"""Shared worker runtime: connection, consume loop, ACK protocol, recovery.

Message protocol (assignment §10, prompt §5) — ACK only after commit:

1. Parse envelope (schema_version + shape). Malformed / unsupported schema ->
   publish to the dead-letter topology + ACK (never retried forever; durable
   `quarantine_records` arrive with Milestone 4). A well-formed FUTURE event
   type is logged + ACKed (assignment §9).
2. Stage simulation delay (deterministic demo control).
3. ONE database transaction: lock the order row (FOR UPDATE), check
   (consumer_name, event_id) dedup -> committed marker means no-op ACK;
   otherwise run the stage processor (effects + history + child outbox event)
   and insert the processed marker in the SAME transaction. Commit.
4. Only after a successful commit: ACK. `crash_after_checkpoint` mode exits
   the PROCESS here (post-commit, pre-ACK) — redelivery then no-ops via dedup.
5. Failure handling, never an immediate nack/requeue loop:
   - DB/processing error -> the message stays UNACKED and the SAME transaction
     is retried IN PLACE with bounded growing backoff (1..30s); shutdown
     requeues it once for redelivery; no false ACK is ever produced.
   - precondition-not-met (disorder) -> bounded deferred retry, then
     dead-letter + ACK (Milestone 4 replaces this stopgap with durable
     retry_jobs/quarantine — documented).
   - connection/channel loss -> the consume stream ends, the caller applies
     bounded reconnect backoff and re-declares topology; unacked messages are
     redelivered by the broker.

Shutdown: stop accepting new messages, finish the in-flight one (bounded
wait), then close the channel so any unacked copy is redelivered elsewhere.
"""

from __future__ import annotations

import asyncio
import logging
import os
import signal
import uuid
from collections.abc import Awaitable, Callable, Sequence

import aio_pika
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.logging import configure_logging
from app.db.models.order import Order
from app.db.models.processed_event import ProcessedEvent
from app.db.session import check_database, dispose_engine, session_scope
from app.messaging.envelope import EnvelopeError, parse_envelope
from app.messaging.publisher import Publisher, PublishError
from app.messaging.topology import TopologyNames, declare_topology
from app.repositories import orders as orders_repo
from app.repositories import processed_events as dedup_repo
from app.schemas.events import EventEnvelope
from app.services.processing import (
    MissingOrderError,
    PreconditionNotMetError,
    ProcessOutcome,
)

logger = logging.getLogger("quickbite.worker")

Processor = Callable[[AsyncSession, EventEnvelope, Order], Awaitable[ProcessOutcome]]

# Bounded startup/database backoff (then exit 1: Compose restarts the worker).
_DB_RETRY_DELAYS_S = (1.0, 2.0, 5.0, 10.0)
# Bounded broker reconnect backoff (delays capped; retries continue while run).
_CONNECT_DELAYS_S = (1.0, 2.0, 5.0, 10.0, 30.0)
# In-place processing-error backoff (capped); the message stays unacked.
_PROCESSING_DELAYS_S = (1.0, 2.0, 5.0, 10.0, 30.0)
# Bounded deferred retry for precondition-not-met disorder (Milestone 4 will
# replace this in-process stopgap with durable retry_jobs + quarantine).
_PRECONDITION_DEFER_DELAYS_S = (1.0, 2.0, 4.0)
# Bounded retries to park a message on the dead-letter exchange before we
# requeue it for a later attempt (never drop, never spin).
_PARK_ATTEMPTS = 3
_PARK_RETRY_DELAY_S = 2.0
_SHUTDOWN_INFLIGHT_TIMEOUT_S = 30.0

_STAGE_MODE_ATTR = {
    "payment": "payment_mode",
    "restaurant": "restaurant_mode",
    "delivery": "delivery_mode",
    "notification": "notification_mode",
}
_STAGE_DELAY_ATTR = {
    "payment": "payment_delay_seconds",
    "restaurant": "restaurant_delay_seconds",
    "delivery": "delivery_delay_seconds",
    "notification": "notification_delay_seconds",
}
# Integrity failures that mean "a concurrent duplicate already committed".
_DUPLICATE_CONSTRAINT_MARKERS = (
    "processed_events",
    "simulated_payments",
    "driver_assignments",
    "notifications",
    "uq_order_status_history",
)


class StreamEndedError(ConnectionError):
    """Consume stream ended WITHOUT a shutdown request: the channel or
    connection died (aio-pika signals this as a clean StopAsyncIteration, so
    the runtime raises this to force the reconnect loop)."""


def validate_stage_modes(consumer_name: str) -> None:
    """Fail fast at startup on controls that require Milestone 4 machinery —
    never a half-implemented retry path (assignment §16 milestone gates)."""
    settings = get_settings()
    mode = getattr(settings, _STAGE_MODE_ATTR[consumer_name])
    if mode == "fail_twice":
        raise SystemExit(
            f"{_STAGE_MODE_ATTR[consumer_name].upper()}=fail_twice requires the "
            "Milestone 4 retry scheduler; use always_succeed/always_fail until then"
        )
    if consumer_name == "notification" and mode != "always_succeed":
        raise SystemExit(
            f"NOTIFICATION_MODE={mode} failure/quarantine handling arrives with "
            "Milestone 4; use always_succeed until then"
        )


async def _wait_for_database(consumer_name: str) -> bool:
    for attempt, delay in enumerate(_DB_RETRY_DELAYS_S, start=1):
        try:
            await check_database(2.0)
            return True
        except Exception as exc:
            logger.warning(
                "database not reachable yet",
                extra={
                    "consumer": consumer_name,
                    "attempt": attempt,
                    "result": f"db_probe_failed: {type(exc).__name__}",
                },
            )
            await asyncio.sleep(delay)
    return False


def _is_duplicate_race(exc: IntegrityError) -> bool:
    return any(marker in str(exc) for marker in _DUPLICATE_CONSTRAINT_MARKERS)


async def _run_transaction(
    consumer_name: str,
    envelope: EventEnvelope,
    processor: Processor,
) -> ProcessOutcome:
    """The single business transaction: lock -> dedup -> effects -> marker."""
    async with session_scope() as session:
        order = await orders_repo.get_order_for_update(session, envelope.order_id)
        if order is None:
            raise MissingOrderError(f"order {envelope.order_id!r} does not exist")
        marker = await dedup_repo.get_marker(
            session, consumer_name=consumer_name, event_id=envelope.event_id
        )
        if marker is not None:
            return ProcessOutcome("duplicate")
        outcome = await processor(session, envelope, order)
        session.add(
            ProcessedEvent(
                id=f"pe_{uuid.uuid4().hex}",
                consumer_name=consumer_name,  # logical type, never a replica id
                event_id=envelope.event_id,
                order_id=order.id,
                outcome="PROCESSED" if outcome.result == "applied" else "STALE_NOOP",
            )
        )
        return outcome


async def _sleep_or_stopping(seconds: float, stop_event: asyncio.Event) -> bool:
    """Interruptible bounded sleep. Returns True when shutdown won the race."""
    try:
        await asyncio.wait_for(stop_event.wait(), timeout=seconds)
        return True
    except TimeoutError:
        return False


async def _dead_letter(
    message: aio_pika.abc.AbstractIncomingMessage,
    publisher: Publisher,
    names: TopologyNames,
    *,
    payload: dict,
    consumer_name: str,
    reason: str,
) -> bool:
    """Route to the dead exchange (routing `failed`) then ACK.

    False -> the caller retries/requeues; we never ACK work we failed to park.
    """
    try:
        await publisher.publish(
            exchange=names.dead_exchange,
            routing_key=names.dead_routing_key,
            payload=payload,
        )
    except PublishError as exc:
        logger.error(
            "dead-letter publish failed",
            extra={
                "consumer": consumer_name,
                "event_id": message.message_id,
                "result": f"dead_letter_failed:{exc.reason}",
                "detail": exc.detail[:500],
            },
        )
        return False
    await message.ack()
    logger.warning(
        "message dead-lettered",
        extra={
            "consumer": consumer_name,
            "event_id": message.message_id,
            "order_id": payload.get("order_id"),
            "result": f"dead_letter:{reason}",
        },
    )
    return True


async def _park_or_requeue(
    message: aio_pika.abc.AbstractIncomingMessage,
    publisher: Publisher,
    names: TopologyNames,
    *,
    payload: dict,
    consumer_name: str,
    reason: str,
    stop_event: asyncio.Event,
) -> None:
    """Bounded park attempts; never an unbounded spin, never a false ACK."""
    for _ in range(_PARK_ATTEMPTS):
        if await _dead_letter(
            message,
            publisher,
            names,
            payload=payload,
            consumer_name=consumer_name,
            reason=reason,
        ):
            return  # acked
        if await _sleep_or_stopping(_PARK_RETRY_DELAY_S, stop_event):
            try:
                await message.nack(requeue=True)
            except Exception:  # noqa: BLE001 — channel may already be gone;
                pass  # the broker requeues unacked copies on channel loss anyway
            logger.info(
                "message requeued during shutdown",
                extra={
                    "consumer": consumer_name,
                    "event_id": message.message_id,
                    "result": "requeued_on_shutdown",
                },
            )
            return
    # Broker accepted connections but refused the dead exchange repeatedly:
    # requeue so the copy survives; redelivery retries the park with bounded
    # 2s spacing and a loud log (durable quarantine recording: Milestone 4).
    logger.error(
        "dead-letter parking failed repeatedly; requeueing for a later attempt",
        extra={
            "consumer": consumer_name,
            "event_id": message.message_id,
            "result": f"dead_letter_exhausted:{reason}",
        },
    )
    try:
        await message.nack(requeue=True)
    except Exception:  # noqa: BLE001 — unacked copies survive channel loss
        pass


async def _handle_message(
    message: aio_pika.abc.AbstractIncomingMessage,
    *,
    consumer_name: str,
    processor: Processor,
    expected_types: frozenset[str],
    delay_seconds: float,
    names: TopologyNames,
    publisher: Publisher,
    stop_event: asyncio.Event,
    precondition_delays: Sequence[float],
    processing_delays: Sequence[float],
) -> None:
    # ---- 1. envelope validation -----------------------------------------
    try:
        envelope = parse_envelope(message.body)
    except EnvelopeError as exc:
        if exc.reason == "unknown_event_type":
            logger.info(
                "ignoring well-formed future event type",
                extra={
                    "consumer": consumer_name,
                    "event_id": message.message_id,
                    "result": "ack_unknown_event_type",
                },
            )
            await message.ack()
            return
        logger.error(
            "malformed message",
            extra={
                "consumer": consumer_name,
                "event_id": message.message_id,
                "result": f"rejected:{exc.reason}",
            },
        )
        await _park_or_requeue(
            message,
            publisher,
            names,
            payload={
                "event_id": message.message_id or f"malformed_{uuid.uuid4().hex}",
                "reason": exc.reason,
                "detail": exc.detail[:1000],
                "body": message.body.decode("utf-8", errors="replace")[:2000],
                "consumer": consumer_name,
            },
            consumer_name=consumer_name,
            reason=exc.reason,
            stop_event=stop_event,
        )
        return

    if envelope.event_type not in expected_types:
        logger.info(
            "event type not served by this consumer; acknowledged",
            extra={
                "consumer": consumer_name,
                "event_id": envelope.event_id,
                "order_id": envelope.order_id,
                "correlation_id": envelope.correlation_id,
                "result": "ack_unexpected_type",
            },
        )
        await message.ack()
        return

    # ---- 2. deterministic stage latency ---------------------------------
    if delay_seconds > 0:
        await asyncio.sleep(delay_seconds)

    # ---- 3. transactional processing with classified failure handling ----
    precondition_attempts = 0
    processing_attempts = 0
    while True:
        try:
            outcome = await _run_transaction(consumer_name, envelope, processor)
            break
        except PreconditionNotMetError:
            precondition_attempts += 1
            if precondition_attempts > len(precondition_delays):
                logger.warning(
                    "precondition never met; dead-lettering (durable quarantine "
                    "arrives with Milestone 4)",
                    extra={
                        "consumer": consumer_name,
                        "event_id": envelope.event_id,
                        "order_id": envelope.order_id,
                        "correlation_id": envelope.correlation_id,
                        "result": "precondition_exhausted",
                    },
                )
                await _park_or_requeue(
                    message,
                    publisher,
                    names,
                    payload=envelope.to_payload(),
                    consumer_name=consumer_name,
                    reason="precondition_not_met",
                    stop_event=stop_event,
                )
                return  # acked (or requeued after bounded park attempts)
            wait_s = precondition_delays[precondition_attempts - 1]
            logger.info(
                "precondition not met; bounded deferred retry",
                extra={
                    "consumer": consumer_name,
                    "event_id": envelope.event_id,
                    "order_id": envelope.order_id,
                    "correlation_id": envelope.correlation_id,
                    "result": "precondition_defer",
                    "retry_in_s": wait_s,
                },
            )
            if await _sleep_or_stopping(wait_s, stop_event):
                try:
                    await message.nack(requeue=True)
                except Exception:  # noqa: BLE001 — best effort on shutdown
                    pass
                return
        except MissingOrderError:
            logger.error(
                "unknown order reference; dead-lettering",
                extra={
                    "consumer": consumer_name,
                    "event_id": envelope.event_id,
                    "correlation_id": envelope.correlation_id,
                    "result": "missing_order",
                },
            )
            await _park_or_requeue(
                message,
                publisher,
                names,
                payload=envelope.to_payload(),
                consumer_name=consumer_name,
                reason="missing_order",
                stop_event=stop_event,
            )
            return
        except Exception as exc:  # noqa: BLE001 — classified below, never acked
            if isinstance(exc, IntegrityError) and _is_duplicate_race(exc):
                outcome = ProcessOutcome("duplicate")
                break
            # DB/processing failure: keep the message UNACKED and retry the
            # SAME transaction in place with bounded growing backoff.
            processing_attempts += 1
            delay = processing_delays[min(processing_attempts - 1, len(processing_delays) - 1)]
            logger.error(
                "processing failed; message kept unacked, retrying in place",
                extra={
                    "consumer": consumer_name,
                    "event_id": envelope.event_id,
                    "order_id": envelope.order_id,
                    "correlation_id": envelope.correlation_id,
                    "result": f"processing_error:{type(exc).__name__}",
                    "retry_in_s": delay,
                    "attempt": processing_attempts,
                },
            )
            if await _sleep_or_stopping(delay, stop_event):
                try:
                    await message.nack(requeue=True)
                except Exception:  # noqa: BLE001 — best effort on shutdown
                    pass
                logger.info(
                    "message requeued for redelivery during shutdown",
                    extra={
                        "consumer": consumer_name,
                        "event_id": envelope.event_id,
                        "result": "requeued_on_shutdown",
                    },
                )
                return

    # ---- 4. post-commit: checkpoint crash, then ACK ----------------------
    settings = get_settings()
    if getattr(settings, _STAGE_MODE_ATTR[consumer_name]) == "crash_after_checkpoint":
        if settings.environment == "test":
            logger.critical(
                "crash checkpoint reached (no process exit under test)",
                extra={
                    "consumer": consumer_name,
                    "event_id": envelope.event_id,
                    "order_id": envelope.order_id,
                    "result": "crash_checkpoint_simulated",
                },
            )
        else:
            logger.critical(
                "crash checkpoint: committed but exiting BEFORE ack",
                extra={
                    "consumer": consumer_name,
                    "event_id": envelope.event_id,
                    "order_id": envelope.order_id,
                    "result": "crash_before_ack",
                },
            )
            os._exit(70)

    await message.ack()  # strictly after the database commit
    logger.info(
        "message processed",
        extra={
            "consumer": consumer_name,
            "event_id": envelope.event_id,
            "order_id": envelope.order_id,
            "correlation_id": envelope.correlation_id,
            "result": outcome.result,
        },
    )


async def consume_forever(
    connection: aio_pika.abc.AbstractConnection,
    *,
    consumer_name: str,
    queue_name: str,
    processor: Processor,
    expected_types: frozenset[str],
    prefix: str = "",
    stop_event: asyncio.Event,
    precondition_delays: Sequence[float] = _PRECONDITION_DEFER_DELAYS_S,
    processing_delays: Sequence[float] = _PROCESSING_DELAYS_S,
    delay_seconds: float | None = None,
) -> None:
    """Consume one queue until `stop_event`.

    Returns after the in-flight message finishes (bounded shutdown budget).
    Raises `StreamEndedError` when the stream ends WITHOUT a shutdown request
    (channel/connection loss — aio-pika reports that as a clean iterator end),
    so callers reconnect with bounded backoff instead of exiting.
    `delay_seconds` overrides the configured stage delay (tests).
    """
    settings = get_settings()
    names = TopologyNames(prefix)
    if delay_seconds is None:
        delay_seconds = getattr(settings, _STAGE_DELAY_ATTR[consumer_name])
    publisher = Publisher(connection=connection)

    channel = await connection.channel()
    await channel.set_qos(prefetch_count=settings.worker_prefetch_count)
    queue = await channel.declare_queue(queue_name, durable=True, exclusive=False)

    stream_context = queue.iterator(no_ack=False)
    stream = await stream_context.__aenter__()

    async def _consume_stream() -> None:
        async for message in stream:
            if stop_event.is_set():
                # Stop accepting: this just-delivered copy goes back to ready.
                await message.nack(requeue=True)
                break
            await _handle_message(
                message,
                consumer_name=consumer_name,
                processor=processor,
                expected_types=expected_types,
                delay_seconds=delay_seconds,
                names=names,
                publisher=publisher,
                stop_event=stop_event,
                precondition_delays=precondition_delays,
                processing_delays=processing_delays,
            )

    consume_task = asyncio.create_task(_consume_stream())
    stop_task = asyncio.create_task(stop_event.wait())
    try:
        done, _ = await asyncio.wait({consume_task, stop_task}, return_when=asyncio.FIRST_COMPLETED)
        if consume_task in done:
            stop_task.cancel()
            consume_task.result()  # propagate real consume/processing errors
            if not stop_event.is_set():
                # Iterator ended by itself: the channel/connection is gone.
                raise StreamEndedError(f"{consumer_name}: consume stream ended without shutdown")
            return
        # Graceful stop: stop accepting, then finish the in-flight message.
        logger.info(
            "shutdown requested; finishing in-flight message",
            extra={"consumer": consumer_name, "result": "stopping"},
        )
        try:
            await stream_context.__aexit__(None, None, None)
        except Exception as exc:  # noqa: BLE001 — iterator cleanup is best effort
            logger.debug("iterator close error: %s", exc)
        try:
            await asyncio.wait_for(consume_task, timeout=_SHUTDOWN_INFLIGHT_TIMEOUT_S)
        except TimeoutError:
            logger.warning(
                "in-flight message did not finish within the shutdown budget; "
                "closing the channel so its copy is redelivered",
                extra={"consumer": consumer_name, "result": "inflight_abandoned"},
            )
            consume_task.cancel()
        except Exception as exc:  # noqa: BLE001 — we are closing anyway
            logger.info(
                "consume task ended with an error during shutdown",
                extra={"consumer": consumer_name, "result": f"stop_error:{type(exc).__name__}"},
            )
    finally:
        if not stop_task.done():
            stop_task.cancel()
        if not consume_task.done():
            consume_task.cancel()
        await asyncio.gather(consume_task, stop_task, return_exceptions=True)
        if not channel.is_closed:
            await channel.close()
        await publisher.close()


async def run_worker(
    *,
    consumer_name: str,
    queue_name: str,
    processor: Processor,
    expected_types: frozenset[str],
    prefix: str = "",
) -> None:
    """Worker process entry: config/logging, mode validation, DB probe,
    idempotent topology declaration, consume loop with bounded reconnects,
    graceful SIGTERM/SIGINT shutdown."""
    settings = get_settings()
    configure_logging(settings.log_level, service=f"{consumer_name}-worker")
    validate_stage_modes(consumer_name)

    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)

    logger.info(
        "worker starting",
        extra={"consumer": consumer_name, "result": f"queue={queue_name}"},
    )
    if not await _wait_for_database(consumer_name):
        logger.error(
            "database unavailable after bounded retries; exiting",
            extra={"consumer": consumer_name, "result": "startup_failed"},
        )
        raise SystemExit(1)

    backoff = list(_CONNECT_DELAYS_S)
    try:
        while not stop.is_set():
            connection: aio_pika.abc.AbstractConnection | None = None
            try:
                connection = await aio_pika.connect(settings.amqp_url, timeout=10)
                # Idempotent declarations on every (re)connect: publishes can
                # never race ahead of queues/bindings, and a broker restart
                # that lost state is healed on reconnect.
                await declare_topology(connection, prefix=prefix)
                logger.info(
                    "worker connected; consuming",
                    extra={"consumer": consumer_name, "result": "consuming"},
                )
                backoff = list(_CONNECT_DELAYS_S)
                await consume_forever(
                    connection,
                    consumer_name=consumer_name,
                    queue_name=queue_name,
                    processor=processor,
                    expected_types=expected_types,
                    prefix=prefix,
                    stop_event=stop,
                )
                break  # graceful stop
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # broker/channel loss: bounded backoff
                delay = backoff.pop(0) if backoff else _CONNECT_DELAYS_S[-1]
                logger.warning(
                    "connection/consume failure; reconnecting with bounded backoff",
                    extra={
                        "consumer": consumer_name,
                        "result": f"reconnect:{type(exc).__name__}",
                        "retry_in_s": delay,
                    },
                )
                if connection is not None and not connection.is_closed:
                    try:
                        await connection.close()
                    except Exception:  # noqa: BLE001 — closing is best-effort
                        pass
                if await _sleep_or_stopping(delay, stop):
                    break
    finally:
        await dispose_engine()
        logger.info(
            "worker stopped gracefully",
            extra={"consumer": consumer_name, "result": "stopped"},
        )
