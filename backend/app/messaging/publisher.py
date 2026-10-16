"""Robust AMQP publish adapter (assignment §10): publisher confirms,
mandatory routing with unroutable-return detection, persistent delivery.

Contract with the dispatcher:
- `publish()` returns normally ONLY after the broker confirmed the message
  AND no mandatory return arrived (RabbitMQ sends basic.return before
  basic.ack, so a confirmed-but-unroutable publish raises `PublishError`
  here and must stay eligible for retry in the outbox).
- `PublishError` carries a stable `reason` for `outbox_events.last_error`.
- Any connection/channel failure invalidates the channel; the caller applies
  bounded backoff and retries (event loss is never an option).
"""

from __future__ import annotations

import logging
from typing import Any

import aio_pika
from aio_pika.exceptions import DeliveryError

from app.messaging.envelope import build_message
from app.messaging.topology import DEAD_EXCHANGE, ORDERS_EXCHANGE

logger = logging.getLogger("quickbite.publisher")

_DEFAULT_PUBLISH_TIMEOUT_S = 10.0


class PublishError(Exception):
    """Publication did not meet the confirm + routing contract."""

    def __init__(self, reason: str, detail: str = "") -> None:
        super().__init__(f"{reason}: {detail}" if detail else reason)
        self.reason = reason
        self.detail = detail


def _exchange_type(exchange_name: str) -> aio_pika.ExchangeType:
    if exchange_name.endswith(DEAD_EXCHANGE):
        return aio_pika.ExchangeType.DIRECT
    # quickbite.orders (and any namespaced variant) is the topic exchange.
    if exchange_name.endswith(ORDERS_EXCHANGE):
        return aio_pika.ExchangeType.TOPIC
    return aio_pika.ExchangeType.TOPIC


class Publisher:
    """One channel per publisher instance; usable with an owned connection
    (dispatcher) or an injected shared connection (consumer dead-lettering)."""

    def __init__(
        self,
        url: str | None = None,
        *,
        connection: aio_pika.abc.AbstractConnection | None = None,
        publish_timeout: float = _DEFAULT_PUBLISH_TIMEOUT_S,
    ) -> None:
        if url is None and connection is None:
            raise ValueError("Publisher needs an amqp url or an existing connection")
        self._url = url
        self._connection = connection
        self._owns_connection = connection is None
        self._channel: aio_pika.abc.AbstractChannel | None = None
        self._exchanges: dict[str, aio_pika.abc.AbstractExchange] = {}
        self._publish_timeout = publish_timeout

    async def _ensure_channel(self) -> aio_pika.abc.AbstractChannel:
        if self._connection is None:
            if self._url is None:
                raise PublishError("connection_lost", "injected connection unavailable")
            self._connection = await aio_pika.connect(self._url, timeout=10)
            self._channel = None
            self._exchanges.clear()
        elif self._connection.is_closed:
            if self._url is None:
                raise PublishError("connection_lost", "injected connection is closed")
            self._connection = None  # owned connection died: redial immediately
            return await self._ensure_channel()
        if self._channel is None or self._channel.is_closed:
            try:
                # on_return_raises: mandatory unroutable publishes raise DeliveryError.
                self._channel = await self._connection.channel(
                    publisher_confirms=True, on_return_raises=True
                )
            except (RuntimeError, ConnectionError, aio_pika.exceptions.ConnectionClosed) as exc:
                # A broker force-close can leave `connection.is_closed` False
                # (observed on 10.1.1 / aiormq after CONNECTION_FORCED): the
                # channel() call then raises on the dead object. Drop the
                # owned connection so the NEXT attempt dials fresh; injected
                # connections belong to their consumer's reconnect loop.
                self._channel = None
                if self._url is not None:
                    self._connection = None
                raise PublishError(
                    "connection_lost", f"channel open failed: {type(exc).__name__}: {exc}"
                ) from exc
            self._exchanges.clear()
        return self._channel

    async def _exchange(self, name: str) -> aio_pika.abc.AbstractExchange:
        channel = await self._ensure_channel()
        # aio-pika's Exchange has NO `is_closed` attribute (verified on
        # 10.1.1); the cache is dropped whenever the channel is replaced or
        # invalidated, so a cached exchange always belongs to the live channel.
        exchange = self._exchanges.get(name)
        if exchange is None:
            exchange = await channel.declare_exchange(name, _exchange_type(name), durable=True)
            self._exchanges[name] = exchange
        return exchange

    def _invalidate(self) -> None:
        self._channel = None
        self._exchanges.clear()

    async def publish(
        self,
        *,
        exchange: str,
        routing_key: str,
        payload: dict[str, Any],
    ) -> str:
        """Confirm+route one event. Returns the immutable event_id on success;
        raises PublishError otherwise (caller keeps the outbox row eligible)."""
        event_id = str(payload.get("event_id", ""))
        try:
            target = await self._exchange(exchange)
            await target.publish(
                build_message(payload),
                routing_key=routing_key,
                mandatory=True,
                timeout=self._publish_timeout,
            )
        except DeliveryError as exc:
            # basic.return arrived: confirmed by transport but NOT routed to
            # any queue. Must never become SENT.
            raise PublishError("unroutable", str(exc)) from exc
        except TimeoutError as exc:
            self._invalidate()
            raise PublishError("confirm_timeout", str(exc)) from exc
        except (ConnectionError, aio_pika.exceptions.ConnectionClosed) as exc:
            self._invalidate()
            raise PublishError("connection_lost", str(exc)) from exc
        except PublishError:
            raise
        except Exception as exc:  # noqa: BLE001 — every failure is retried by design
            self._invalidate()
            raise PublishError("publish_failed", f"{type(exc).__name__}: {exc}") from exc
        return event_id

    async def close(self) -> None:
        try:
            if self._channel is not None and not self._channel.is_closed:
                await self._channel.close()
            if self._owns_connection and self._connection is not None:
                if not self._connection.is_closed:
                    await self._connection.close()
        except Exception as exc:  # closing is best-effort
            logger.debug("publisher close error: %s", exc)
        finally:
            self._invalidate()
