"""In-process async pipeline harness for Milestone 3 integration tests.

Runs the REAL dispatcher (`outbox_dispatcher.run_forever`) and the REAL
consumer runtime (`consumer_runtime.consume_forever`) as asyncio tasks against
a TEST-NAMESPACED topology (prefix `tst_`): identical exchange/queue/binding
structure and durability, but isolated names — so a running Compose stack
(its own workers consuming `payment.queue` etc.) never competes with test
messages. Production names are identical and are inspected live in
`docs/evidence/m3/`.
"""

from __future__ import annotations

import asyncio
import time
import uuid
from typing import Any

import aio_pika

from app.core.config import get_settings
from app.messaging.consumer_runtime import consume_forever
from app.messaging.outbox_dispatcher import run_forever as dispatcher_run_forever
from app.messaging.retry_scheduler import run_forever as scheduler_run_forever
from app.messaging.topology import (
    DELIVERY_QUEUE,
    NOTIFICATION_QUEUE,
    PAYMENT_QUEUE,
    RESTAURANT_QUEUE,
    TopologyNames,
    declare_topology,
    purge_queues,
)
from app.schemas.events import (
    EVENT_TYPES,
    ORDER_CONFIRMED,
    ORDER_CREATED,
    ORDER_PAID,
)
from app.services.delivery_service import process_delivery
from app.services.notification_service import process_notification
from app.services.payment_service import process_payment
from app.services.restaurant_service import process_restaurant

TEST_PREFIX = "tst_"

RESTAURANT = "rest_bella_napoli"
MARGHERITA = "item_margherita_pizza"
ADDRESS = "12 Lake Road, Bengaluru"

CONSUMER_SPECS: dict[str, tuple[str, Any, frozenset[str]]] = {
    "payment": (PAYMENT_QUEUE, process_payment, frozenset({ORDER_CREATED})),
    "restaurant": (RESTAURANT_QUEUE, process_restaurant, frozenset({ORDER_PAID})),
    "delivery": (DELIVERY_QUEUE, process_delivery, frozenset({ORDER_CONFIRMED})),
    "notification": (NOTIFICATION_QUEUE, process_notification, frozenset(EVENT_TYPES)),
}


async def wait_until(
    predicate,
    *,
    timeout: float = 30.0,
    interval: float = 0.05,
    message: str = "condition not met",
    detail=None,
) -> None:
    """Poll `predicate` (sync or async, truthy = done); raise with context."""
    deadline = time.monotonic() + timeout
    while True:
        result = predicate()
        if asyncio.iscoroutine(result):
            result = await result
        if result:
            return
        if time.monotonic() >= deadline:
            suffix = ""
            if detail is not None:
                info = detail()
                if asyncio.iscoroutine(info):
                    info = await info
                suffix = f"\ncontext: {info}"
            raise AssertionError(f"wait_until timed out after {timeout}s: {message}{suffix}")
        await asyncio.sleep(interval)


async def wait_for_eq(
    factory,
    expected,
    *,
    timeout: float = 30.0,
    message: str = "value never matched",
) -> None:
    """Await `factory()` (an async expression factory) until it EQUALS
    `expected`. Use this instead of `lambda: await_x() == y` — that would
    compare an un-awaited coroutine object and never become true."""

    async def _check() -> bool:
        value = factory()
        if asyncio.iscoroutine(value):
            value = await value
        return value == expected

    await wait_until(_check, timeout=timeout, message=f"{message} (want {expected!r})")


async def get_order_row(order_id: str):
    from sqlalchemy import select

    from app.db.models.order import Order
    from app.db.session import session_scope

    async with session_scope() as session:
        return (
            await session.execute(select(Order).where(Order.id == order_id))
        ).scalar_one_or_none()


async def wait_for_status(order_id: str, *statuses: str, timeout: float = 30.0) -> None:
    """Block until the order reaches one of `statuses` (or fail with context)."""

    async def _check() -> bool:
        order = await get_order_row(order_id)
        return order is not None and order.status in statuses

    async def _context() -> str:
        order = await get_order_row(order_id)
        if order is None:
            return f"order {order_id} missing"
        return f"order {order_id} status={order.status} version={order.version} (want {statuses})"

    await wait_until(
        _check,
        timeout=timeout,
        message=f"order {order_id} -> {statuses}",
        detail=_context,
    )


async def order_rows(order_id: str) -> dict[str, list]:
    """All pipeline tables filtered to ONE order — safe under session-shared DB."""
    from sqlalchemy import select

    from app.db.models.driver_assignment import DriverAssignment
    from app.db.models.notification import Notification
    from app.db.models.order_status_history import OrderStatusHistory
    from app.db.models.outbox_event import OutboxEvent
    from app.db.models.processed_event import ProcessedEvent
    from app.db.models.quarantine_record import QuarantineRecord
    from app.db.models.retry_job import RetryJob
    from app.db.models.simulated_payment import SimulatedPayment
    from app.db.session import session_scope

    async with session_scope() as session:

        async def _all(entity, *where_extra):
            return list(
                (
                    await session.execute(
                        select(entity).where(entity.order_id == order_id, *where_extra)
                    )
                ).scalars()
            )

        payments = await _all(SimulatedPayment)
        history = sorted(await _all(OrderStatusHistory), key=lambda h: h.version)
        assignments = await _all(DriverAssignment)
        notifications = await _all(Notification)
        outbox = await _all(OutboxEvent)
        processed = await _all(ProcessedEvent)
        retries = sorted(await _all(RetryJob), key=lambda j: j.attempt)
        quarantined = await _all(QuarantineRecord)
    return {
        "payments": payments,
        "history": history,
        "assignments": assignments,
        "notifications": notifications,
        "outbox": outbox,
        "processed": processed,
        "retries": retries,
        "quarantined": quarantined,
    }


def build_envelope(
    event_type: str,
    order_id: str,
    order_version: int,
    *,
    event_id: str | None = None,
    correlation_id: str | None = None,
    data: dict | None = None,
) -> dict:
    from datetime import UTC, datetime

    from app.schemas.events import SCHEMA_VERSION, EventEnvelope

    envelope = EventEnvelope(
        event_id=event_id or f"evt_test_{uuid.uuid4().hex}",
        schema_version=SCHEMA_VERSION,
        event_type=event_type,  # type: ignore[arg-type]
        order_id=order_id,
        order_version=order_version,
        occurred_at=datetime.now(UTC),
        correlation_id=correlation_id or f"corr_{uuid.uuid4().hex}",
        data=data or {},
    )
    return envelope.to_payload()


class PipelineHarness:
    """Dispatcher + any subset of real consumers, started/stopped per test."""

    def __init__(self, prefix: str = TEST_PREFIX) -> None:
        self.prefix = prefix
        self.names = TopologyNames(prefix)
        self.connection: aio_pika.abc.AbstractConnection | None = None
        self._channel: aio_pika.abc.AbstractChannel | None = None
        self.dispatcher_task: asyncio.Task | None = None
        self._dispatcher_stop: asyncio.Event | None = None
        self.scheduler_task: asyncio.Task | None = None
        self._scheduler_stop: asyncio.Event | None = None
        # (name, task, stop_event) — multiple instances of one name allowed.
        self._consumers: list[tuple[str, asyncio.Task, asyncio.Event]] = []

    # ---- lifecycle -------------------------------------------------------

    async def setup(self) -> None:
        settings = get_settings()
        self.connection = await aio_pika.connect(settings.amqp_url, timeout=10)
        await declare_topology(self.connection, prefix=self.prefix)
        # The session DB is shared across the whole run: rows left PENDING by
        # earlier tests (M2 tests never start a dispatcher; some M3 scenarios
        # stop mid-flight) must not leak into this test's stats or queues.
        # Drive them to SENT first (publishes into this topology), then purge.
        await self.flush_outbox()
        await purge_queues(self.connection, prefix=self.prefix)  # clean slate
        self._channel = await self.connection.channel()

    async def flush_outbox(self) -> None:
        """Drive every pre-existing outbox row to SENT — clearing failure
        backoffs and stale claim leases (time-travel instead of sleeping) —
        so per-test dispatcher stats and queue depths are exact. Raises if
        leftovers cannot be drained (loud, not silent)."""
        from sqlalchemy import text

        from app.db.session import session_scope
        from app.messaging.outbox_dispatcher import run_once
        from app.messaging.publisher import Publisher

        publisher = Publisher(connection=self.connection)
        try:
            for _ in range(60):
                async with session_scope() as session:
                    await session.execute(
                        text(
                            "UPDATE outbox_events SET lease_expires_at = now()"
                            " - interval '1 second' WHERE state = 'CLAIMED'"
                        )
                    )
                    await session.execute(
                        text("UPDATE outbox_events SET available_at = now() WHERE state <> 'SENT'")
                    )
                    remaining = (
                        await session.execute(
                            text("SELECT count(*) FROM outbox_events WHERE state <> 'SENT'")
                        )
                    ).scalar_one()
                if remaining == 0:
                    break
                await run_once(publisher, prefix=self.prefix, worker_id="setup-flush")
            else:
                raise AssertionError("pipeline setup could not flush leftover outbox rows")
        finally:
            await publisher.close()

    async def teardown(self) -> None:
        self.stop_all()
        tasks = [task for _, task, _ in self._consumers]
        if self.dispatcher_task is not None:
            tasks.append(self.dispatcher_task)
        if self.scheduler_task is not None:
            tasks.append(self.scheduler_task)
        results = await asyncio.gather(*tasks, return_exceptions=True)
        if self._channel is not None and not self._channel.is_closed:
            await self._channel.close()
        if self.connection is not None and not self.connection.is_closed:
            await self.connection.close()
        unexpected = [
            r
            for r in results
            if isinstance(r, BaseException)
            and not isinstance(r, (asyncio.CancelledError, GeneratorExit))
        ]
        if unexpected:
            raise AssertionError(f"pipeline task failed: {unexpected[0]!r}") from unexpected[0]

    # ---- components ------------------------------------------------------

    def start_dispatcher(self, *, poll_interval: float = 0.05) -> asyncio.Task:
        settings = get_settings()
        self._dispatcher_stop = asyncio.Event()
        self.dispatcher_task = asyncio.create_task(
            dispatcher_run_forever(
                stop_event=self._dispatcher_stop,
                url=settings.amqp_url,
                prefix=self.prefix,
                poll_interval=poll_interval,
            )
        )
        return self.dispatcher_task

    def start_scheduler(self, *, poll_interval: float = 0.05) -> asyncio.Task:
        """The REAL retry scheduler loop (same code path as the Compose
        `retry-scheduler` service) as an asyncio task."""
        self._scheduler_stop = asyncio.Event()
        self.scheduler_task = asyncio.create_task(
            scheduler_run_forever(stop_event=self._scheduler_stop, poll_interval=poll_interval)
        )
        return self.scheduler_task

    def start_consumers(
        self, name: str, *, instances: int = 1, delay_seconds: float | None = None, **consume_kwargs
    ) -> list[asyncio.Task]:
        queue_name, processor, expected_types = CONSUMER_SPECS[name]
        queue_name = f"{self.prefix}{queue_name}"  # namespaced with the topology
        tasks: list[asyncio.Task] = []
        for _ in range(instances):
            stop = asyncio.Event()
            task = asyncio.create_task(
                consume_forever(
                    self.connection,  # type: ignore[arg-type]
                    consumer_name=name,
                    queue_name=queue_name,
                    processor=processor,
                    expected_types=expected_types,
                    prefix=self.prefix,
                    stop_event=stop,
                    delay_seconds=delay_seconds,
                    **consume_kwargs,
                )
            )
            self._consumers.append((name, task, stop))
            tasks.append(task)
        return tasks

    def stop_consumer(self, name: str) -> None:
        """Graceful stop request for every instance of one logical consumer."""
        stopped = False
        for consumer_name, _task, stop in self._consumers:
            if consumer_name == name:
                stop.set()
                stopped = True
        if not stopped:
            raise AssertionError(f"no {name} consumer instance running")

    async def wait_consumer_stopped(self, name: str, *, timeout: float = 40.0) -> None:
        """Block until every instance of `name` finished its in-flight message
        and returned cleanly (fails on crashed or hung instances)."""
        targets = [task for n, task, _ in self._consumers if n == name]
        assert targets, f"no {name} consumer instance running"
        await asyncio.wait(targets, timeout=timeout)
        for task in targets:
            if not task.done():
                raise AssertionError(f"{name} consumer did not stop within {timeout}s")
            if not task.cancelled() and task.exception() is not None:
                raise AssertionError(
                    f"{name} consumer crashed while stopping: {task.exception()!r}"
                ) from task.exception()

    def stop_all(self) -> None:
        for _, _task, stop in self._consumers:
            stop.set()
        if self._dispatcher_stop is not None:
            self._dispatcher_stop.set()
        if self._scheduler_stop is not None:
            self._scheduler_stop.set()

    def raise_if_task_failed(self) -> None:
        for name, task, _ in self._consumers:
            if task.done() and not task.cancelled() and task.exception() is not None:
                raise AssertionError(
                    f"{name} consumer crashed: {task.exception()!r}"
                ) from task.exception()
        if (
            self.dispatcher_task is not None
            and self.dispatcher_task.done()
            and not self.dispatcher_task.cancelled()
            and self.dispatcher_task.exception() is not None
        ):
            raise AssertionError(
                f"dispatcher crashed: {self.dispatcher_task.exception()!r}"
            ) from self.dispatcher_task.exception()
        if (
            self.scheduler_task is not None
            and self.scheduler_task.done()
            and not self.scheduler_task.cancelled()
            and self.scheduler_task.exception() is not None
        ):
            raise AssertionError(
                f"retry scheduler crashed: {self.scheduler_task.exception()!r}"
            ) from self.scheduler_task.exception()

    # ---- broker actions --------------------------------------------------

    async def publish_to_queue(
        self, queue_name: str, payload: dict, *, message_id: str | None = None
    ) -> None:
        """Direct queue injection (default exchange) — simulates redelivery
        or duplicate copies without depending on bindings."""
        assert self._channel is not None
        await self._channel.default_exchange.publish(
            aio_pika.Message(
                body=_json_body(payload),
                message_id=message_id or str(payload.get("event_id")),
                content_type="application/json",
                delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
            ),
            routing_key=queue_name,
        )

    async def publish_to_orders_exchange(
        self, routing_key: str, payload: dict, *, mandatory: bool = False
    ) -> None:
        """Topic-exchange publish — exercises the real binding topology."""
        assert self._channel is not None
        exchange = await self._channel.declare_exchange(
            self.names.orders_exchange, aio_pika.ExchangeType.TOPIC, durable=True
        )
        await exchange.publish(
            aio_pika.Message(
                body=_json_body(payload),
                message_id=str(payload.get("event_id")),
                content_type="application/json",
                delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
            ),
            routing_key=routing_key,
            mandatory=mandatory,
        )

    async def queue_depth(self, queue_name: str) -> int:
        assert self._channel is not None
        result = await self._channel.declare_queue(queue_name, passive=True)
        # Counts live on the DeclareOk RPC response, not on the Queue object.
        return int(result.declaration_result.message_count)

    async def drain_queue(
        self,
        queue_name: str,
        *,
        first_timeout: float = 5.0,
        quiet: float = 0.4,
        max_total: float = 30.0,
    ) -> list[dict]:
        """Collect messages from a queue that may still be filling.

        `basic.get` on an EMPTY queue returns immediately (the broker never
        waits), so a naive `get(timeout=...)` loop would bail out before
        messages arrive. We therefore POLL: wait up to `first_timeout` for
        the first message, then keep collecting until the queue has been
        quiet for `quiet` seconds (bounded overall by `max_total`).
        """
        assert self._channel is not None
        queue = await self._channel.declare_queue(queue_name, passive=True)
        collected: list[dict] = []
        start = time.monotonic()
        deadline_first = start + first_timeout
        last_arrival = start
        while True:
            if time.monotonic() - start > max_total:
                break
            if await self.queue_depth(queue_name) > 0:
                message = await queue.get(no_ack=True, fail=False)
                if message is not None:
                    import json as _json

                    try:
                        collected.append(_json.loads(message.body))
                    except ValueError:
                        collected.append({"_raw": message.body.decode("utf-8", "replace")})
                    last_arrival = time.monotonic()
                    continue
            if collected:
                if time.monotonic() - last_arrival >= quiet:
                    break
            elif time.monotonic() >= deadline_first:
                break
            await asyncio.sleep(0.05)
        return collected

    async def assert_queue_empty(self, queue_name: str, *, settle: float = 1.0) -> None:
        """Poll until the queue drains within `settle` seconds, then confirm it
        STAYS empty briefly (catches requeues/redeliveries)."""
        deadline = time.monotonic() + settle
        depth = await self.queue_depth(queue_name)
        while depth > 0 and time.monotonic() < deadline:
            await asyncio.sleep(0.05)
            depth = await self.queue_depth(queue_name)
        if depth == 0:
            await asyncio.sleep(0.3)
            depth = await self.queue_depth(queue_name)
        assert depth == 0, f"{queue_name} still holds {depth} message(s)"


def _json_body(payload: dict) -> bytes:
    import json as _json

    return _json.dumps(payload, separators=(",", ":"), ensure_ascii=True).encode("utf-8")


async def place_order(client, token: str, *, quantity: int = 2) -> str:
    """One accepted checkout (202) with a fresh idempotency key."""
    from tests.conftest import auth_header

    response = await client.post(
        "/api/v1/orders",
        json={
            "restaurant_id": RESTAURANT,
            "delivery_address": ADDRESS,
            "items": [{"menu_item_id": MARGHERITA, "quantity": quantity}],
        },
        headers={**auth_header(token), "Idempotency-Key": f"m3-{uuid.uuid4().hex}"},
    )
    assert response.status_code == 202, response.text
    return str(response.json()["order_id"])


async def fetch_outbox_payload(order_id: str, event_type: str) -> dict:
    from sqlalchemy import select

    from app.db.models.outbox_event import OutboxEvent
    from app.db.session import session_scope
    from app.messaging.topology import ORDERS_EXCHANGE

    async with session_scope() as session:
        row = (
            await session.execute(
                select(OutboxEvent).where(
                    OutboxEvent.order_id == order_id,
                    OutboxEvent.event_type == event_type,
                    # Milestone 4: the SAME event id also has a targeted RETRY
                    # publication (default exchange) and possibly a dead-letter
                    # publication (quickbite.dead); the domain event itself is
                    # the quickbite.orders topic row.
                    OutboxEvent.exchange == ORDERS_EXCHANGE,
                )
            )
        ).scalar_one()
        return dict(row.payload)


async def outbox_rows_for_event(event_id: str) -> list:
    """Every outbox publication row for ONE immutable event id (original
    topic publication and/or its targeted retry copies)."""
    from sqlalchemy import select

    from app.db.models.outbox_event import OutboxEvent
    from app.db.session import session_scope

    async with session_scope() as session:
        return list(
            (
                await session.execute(select(OutboxEvent).where(OutboxEvent.event_id == event_id))
            ).scalars()
        )


async def retry_job_rows(consumer_name: str, event_id: str) -> list:
    """All durable retry jobs for one (consumer, event) pair, by attempt."""
    from sqlalchemy import select

    from app.db.models.retry_job import RetryJob
    from app.db.session import session_scope

    async with session_scope() as session:
        rows = list(
            (
                await session.execute(
                    select(RetryJob).where(
                        RetryJob.consumer_name == consumer_name,
                        RetryJob.event_id == event_id,
                    )
                )
            ).scalars()
        )
    return sorted(rows, key=lambda j: j.attempt)


async def quarantine_rows_for_event(event_id: str) -> list:
    from sqlalchemy import select

    from app.db.models.quarantine_record import QuarantineRecord
    from app.db.session import session_scope

    async with session_scope() as session:
        return list(
            (
                await session.execute(
                    select(QuarantineRecord).where(QuarantineRecord.event_id == event_id)
                )
            ).scalars()
        )


async def set_outbox_available_now(order_id: str) -> None:
    """Time-skip a failure backoff window (no event is ever dropped)."""
    from sqlalchemy import text

    from app.db.session import session_scope

    async with session_scope() as session:
        await session.execute(
            text(
                "UPDATE outbox_events SET available_at = now() "
                "WHERE order_id = :order_id AND state <> 'SENT'"
            ),
            {"order_id": order_id},
        )
