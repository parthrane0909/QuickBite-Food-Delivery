"""Durable retry policy + independent retry scheduler (assignment §11, §13).

Covers required M4 tests: configured delay schedule and attempt ceiling;
targeted retry routing (default exchange, routing key = only the failing
queue, never `quickbite.orders`); immutable event id/payload across retries;
duplicate failure handling creating no duplicate retry jobs; scheduler claim
concurrency safety (SKIP LOCKED); scheduler restart/late start never losing
due work; and unknown-business-event quarantine vs the assignment-permitted
notification acknowledgement of a valid future event type.
"""

from __future__ import annotations

import asyncio
import json

import aio_pika
import pytest
from pydantic import ValidationError
from sqlalchemy import select

from app.core.config import Settings, get_settings
from app.db.models.quarantine_record import QuarantineRecord
from app.db.session import session_scope
from app.messaging import retry_scheduler
from app.repositories import messaging as messaging_repo
from app.schemas.events import ORDER_CREATED, ORDER_PAID
from tests.m3_harness import (
    build_envelope,
    fetch_outbox_payload,
    order_rows,
    outbox_rows_for_event,
    place_order,
    retry_job_rows,
    wait_for_status,
    wait_until,
)

# ---- configuration contract ----------------------------------------------


def test_retry_policy_defaults_match_documented_contract(monkeypatch):
    """1 initial attempt + 3 delayed retries at ~2s, ~10s, ~30s — the defaults
    documented in README/.env.example are the ones Settings actually ships
    (the test environment's fast delays are cleared first)."""
    monkeypatch.delenv("RETRY_DELAYS_SECONDS", raising=False)
    monkeypatch.delenv("RETRY_MAX_ATTEMPTS", raising=False)
    settings = Settings(
        database_url="postgresql+asyncpg://user:pass@localhost/quickbite",
        amqp_url="amqp://user:pass@localhost:5672/",
        jwt_secret="x" * 40,
    )
    assert settings.retry_delays == (2.0, 10.0, 30.0)
    assert settings.retry_max_attempts == 4  # 1 initial + 3 retries


def test_retry_max_attempts_must_match_the_delay_schedule(monkeypatch):
    monkeypatch.delenv("RETRY_DELAYS_SECONDS", raising=False)
    monkeypatch.delenv("RETRY_MAX_ATTEMPTS", raising=False)
    with pytest.raises(ValidationError):
        Settings(
            database_url="postgresql+asyncpg://user:pass@localhost/quickbite",
            amqp_url="amqp://user:pass@localhost:5672/",
            jwt_secret="x" * 40,
            retry_delays_seconds="2,10,30",
            retry_max_attempts=3,
        )


# ---- scheduler mechanics --------------------------------------------------


async def _wait_for_retry_attempts(
    consumer_name: str, event_id: str, attempts: set[int], *, timeout: float
) -> None:
    async def _check() -> bool:
        jobs = await retry_job_rows(consumer_name, event_id)
        return {j.attempt for j in jobs} >= attempts

    await wait_until(_check, timeout=timeout, message=f"retry attempts {attempts}")


async def test_due_retry_activation_makes_targeted_publication_eligible():
    """Scheduler claim: due PENDING job -> PUBLISHED, its scheduled outbox
    publication made eligible in the same transaction, targeting ONLY the
    failing queue through the default exchange (routing key = queue name)."""
    event_id = "evt_scheduler_probe_1"
    async with session_scope() as session:
        await messaging_repo.schedule_retry(
            session,
            consumer_name="payment",
            event_id=event_id,
            event_type=ORDER_CREATED,
            order_id=None,
            envelope_payload={"event_id": event_id, "event_type": ORDER_CREATED},
            target_queue="tst_payment.queue",
            attempt=2,
            delay_seconds=0.0,
            last_error="probe",
        )

    stats = await retry_scheduler.run_once()
    assert stats["activated"] >= 1  # our due job was claimed this cycle

    jobs = await retry_job_rows("payment", event_id)
    assert [j.attempt for j in jobs] == [2]
    assert jobs[0].state == "PUBLISHED"  # claimed exactly once

    rows = await outbox_rows_for_event(event_id)
    assert len(rows) == 1
    assert rows[0].exchange == "" and rows[0].routing_key == "tst_payment.queue"

    # Idempotence: a re-run re-claims nothing for this job.
    await retry_scheduler.run_once()
    jobs_after = await retry_job_rows("payment", event_id)
    assert [j.state for j in jobs_after] == ["PUBLISHED"]


async def test_concurrent_scheduler_claims_never_double_activate():
    """Two scheduler instances racing over due jobs (FOR UPDATE SKIP LOCKED):
    each job is activated exactly once across both racers."""
    own_ids = [f"evt_concurrent_claim_{i}" for i in range(4)]
    async with session_scope() as session:
        for event_id in own_ids:
            await messaging_repo.schedule_retry(
                session,
                consumer_name="payment",
                event_id=event_id,
                event_type=ORDER_CREATED,
                order_id=None,
                envelope_payload={"event_id": event_id},
                target_queue="tst_payment.queue",
                attempt=2,
                delay_seconds=0.0,
                last_error="probe",
            )

    async def _claim() -> list[tuple[str, str, str, int]]:
        async with session_scope() as session:
            return await messaging_repo.claim_due_retry_jobs(session, batch_size=10)

    results = await asyncio.gather(_claim(), _claim())
    claimed = [entry for batch in results for entry in batch]
    own_claims = [entry for entry in claimed if entry[1] in own_ids]
    # Every one of OUR jobs was activated, and by exactly ONE of the racers
    # (a double activation would make this count exceed 4).
    assert sorted(entry[1] for entry in own_claims) == own_ids
    assert len(own_claims) == 4

    for event_id in own_ids:
        jobs = await retry_job_rows("payment", event_id)
        assert [j.state for j in jobs] == ["PUBLISHED"]


async def test_due_retry_survives_dispatcher_downtime_then_processes(
    pipeline, async_client, customer_token, monkeypatch
):
    """Due work is never lost while the dispatcher is down: the retry job and
    its scheduled publication wait untouched past their due time, then flow
    to completion once the dispatcher (and scheduler) come back."""
    settings = get_settings()
    monkeypatch.setattr(settings, "payment_mode", "fail_twice")

    pipeline.start_consumers("payment")  # consumer up, DISPATCHER DOWN
    order_id = await place_order(async_client, customer_token)
    event = build_envelope(ORDER_CREATED, order_id, 1)
    await pipeline.publish_to_queue(pipeline.names.payment_queue, event)

    # Attempt 1 failed -> durable retry job scheduled (dispatcher still down).
    await _wait_for_retry_attempts("payment", event["event_id"], {2}, timeout=10)

    # Long past due (test delay 0.2s) with NO dispatcher: still unpublished,
    # still fully intact — exactly-once scheduling, zero loss.
    await asyncio.sleep(0.5)
    jobs = await retry_job_rows("payment", event["event_id"])
    assert [j.attempt for j in jobs] == [2]
    rows = [r for r in await outbox_rows_for_event(event["event_id"]) if r.exchange == ""]
    assert len(rows) == 1 and rows[0].state == "PENDING"  # due but not lost
    assert rows[0].routing_key == pipeline.names.payment_queue

    # Dispatcher + scheduler come back: the due work flows to completion.
    pipeline.start_dispatcher()
    pipeline.start_scheduler()
    await wait_for_status(order_id, "PAID")

    async def _targeted_publication_confirmed() -> bool:
        rows = [r for r in await outbox_rows_for_event(event["event_id"]) if r.exchange == ""]
        return bool(rows and rows[0].state == "SENT")

    # The worker can consume an acknowledged Rabbit message before the
    # dispatcher finishes committing its SENT bookkeeping transaction.
    await wait_until(
        _targeted_publication_confirmed,
        timeout=5,
        message="retry publication SENT after broker confirmation",
    )
    rows = [r for r in await outbox_rows_for_event(event["event_id"]) if r.exchange == ""]
    assert rows[0].state == "SENT"
    jobs = await retry_job_rows("payment", event["event_id"])
    assert [j.attempt for j in jobs] == [2, 3]  # attempt 2 failed, 3 succeeded


async def test_scheduler_late_start_is_belt_and_braces(
    pipeline, async_client, customer_token, monkeypatch
):
    """Retries must never depend on scheduler uptime: with the dispatcher
    alone (NO scheduler), a fail_twice order still completes — the retry
    publication's own due `available_at` drives delivery. Starting the
    scheduler afterwards performs the bookkeeping activation."""
    settings = get_settings()
    monkeypatch.setattr(settings, "payment_mode", "fail_twice")

    pipeline.start_dispatcher()  # no scheduler yet
    pipeline.start_consumers("payment")
    pipeline.start_consumers("notification")

    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "PAID")  # restaurant/delivery not running

    original = await fetch_outbox_payload(order_id, ORDER_CREATED)
    jobs = await retry_job_rows("payment", original["event_id"])
    assert [j.attempt for j in jobs] == [2, 3]

    pipeline.start_scheduler()

    async def _both_activated() -> bool:
        current = await retry_job_rows("payment", original["event_id"])
        return len(current) == 2 and all(j.state == "PUBLISHED" for j in current)

    await wait_until(
        _both_activated,
        timeout=10,
        message="late scheduler activates both lingering retry jobs",
    )
    pipeline.raise_if_task_failed()


# ---- targeted retry routing (end to end) ---------------------------------


async def test_fail_twice_succeeds_after_durable_retries_with_immutable_event(
    pipeline, async_client, customer_token, monkeypatch
):
    """Payment fails on delivery attempts 1 and 2, succeeds on attempt 3.
    Both failures become durable retry jobs with the ORIGINAL event id and
    payload, targeted only at the payment queue through the default exchange
    (never republished to quickbite.orders)."""
    settings = get_settings()
    monkeypatch.setattr(settings, "payment_mode", "fail_twice")

    pipeline.start_dispatcher()
    pipeline.start_scheduler()
    pipeline.start_consumers("payment")
    pipeline.start_consumers("notification")

    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "PAID")

    original = await fetch_outbox_payload(order_id, ORDER_CREATED)
    event_id = original["event_id"]

    async def _two_jobs_activated() -> bool:
        current = await retry_job_rows("payment", event_id)
        return [j.attempt for j in current] == [2, 3] and all(
            j.state == "PUBLISHED" for j in current
        )

    await wait_until(
        _two_jobs_activated,
        timeout=10,
        message="retry attempts 2 and 3 scheduled and activated",
    )

    jobs = await retry_job_rows("payment", event_id)
    for job in jobs:
        assert job.target_queue == pipeline.names.payment_queue
        assert job.event_id == event_id  # immutable identity
        assert job.envelope["event_id"] == event_id  # immutable payload
        assert job.envelope["data"] == original["data"]

    # Publication rows: exactly one topic publication + one TARGETED retry
    # publication — the retry never rides the topic exchange.
    rows = await outbox_rows_for_event(event_id)
    topic_rows = [r for r in rows if r.exchange != ""]
    retry_rows = [r for r in rows if r.exchange == ""]
    assert len(topic_rows) == 1 and len(retry_rows) == 1
    assert retry_rows[0].routing_key == pipeline.names.payment_queue
    assert retry_rows[0].payload["event_id"] == event_id
    assert retry_rows[0].state == "SENT"

    # Business outcome: exactly one payment, no quarantine, ordered history.
    rows_db = await order_rows(order_id)
    assert len(rows_db["payments"]) == 1 and rows_db["payments"][0].status == "SUCCEEDED"
    assert [h.version for h in rows_db["history"]] == [1, 2]
    assert rows_db["quarantined"] == []


async def test_targeted_retries_do_not_trigger_unrelated_workers(
    pipeline, async_client, customer_token, monkeypatch
):
    """While payment retries, no extra copy ever reaches the restaurant or
    delivery queues: their depths hold only the genuine chain events (and the
    payment queue ends empty). Notification markers stay exactly-once."""
    settings = get_settings()
    monkeypatch.setattr(settings, "payment_mode", "fail_twice")

    pipeline.start_dispatcher()
    pipeline.start_scheduler()
    pipeline.start_consumers("payment")
    pipeline.start_consumers("notification")

    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "PAID")

    # Restaurant queue: only the GENUINE order.paid (restaurant not running,
    # so depth is observable). Delivery queue must stay completely empty.
    async def _restaurant_got_exactly_one() -> bool:
        return await pipeline.queue_depth(pipeline.names.restaurant_queue) == 1

    await wait_until(
        _restaurant_got_exactly_one,
        timeout=10,
        message="restaurant queue holds exactly the genuine order.paid",
    )
    assert await pipeline.queue_depth(pipeline.names.delivery_queue) == 0
    await pipeline.assert_queue_empty(pipeline.names.payment_queue, settle=0.5)

    # The notification consumer saw order.created exactly once despite the
    # payment retries of that same event id.
    original = await fetch_outbox_payload(order_id, ORDER_CREATED)

    async def _two_notifications() -> bool:
        rows = await order_rows(order_id)
        return len(rows["notifications"]) == 2

    await wait_until(_two_notifications, timeout=10, message="created + paid notifications only")
    rows = await order_rows(order_id)
    created_markers = [
        m
        for m in rows["processed"]
        if m.consumer_name == "notification" and m.event_id == original["event_id"]
    ]
    assert len(created_markers) == 1
    # Notification effects: order.created + order.paid, nothing more.
    assert len(rows["notifications"]) == 2
    assert rows["quarantined"] == []


# ---- classification: unknown future event types --------------------------


def _future_message(payload: dict, *, message_id: str) -> aio_pika.Message:
    return aio_pika.Message(
        body=json.dumps(payload).encode(),
        content_type="application/json",
        delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
        message_id=message_id,
    )


async def test_unknown_business_event_quarantined_notification_future_type_acked(
    pipeline,
):
    """A valid FUTURE event type is acknowledged by the notification worker
    (assignment §9 permission) but QUARANTINED at a business consumer — never
    silently acked (§11)."""
    names = pipeline.names
    pipeline.start_consumers("payment")
    pipeline.start_consumers("notification")
    pipeline.start_dispatcher()  # publishes the quarantine dead-letter rows

    channel = await pipeline.connection.channel()
    future_type = "order.autonomous_dispatch"
    payment_copy = build_envelope(ORDER_PAID, "order_future_probe_1", 2)
    payment_copy = {**payment_copy, "event_type": future_type, "event_id": "evt_future_payment"}
    notification_copy = build_envelope(ORDER_PAID, "order_future_probe_1", 2)
    notification_copy = {
        **notification_copy,
        "event_type": future_type,
        "event_id": "evt_future_notification",
    }

    await channel.default_exchange.publish(
        _future_message(payment_copy, message_id="evt_future_payment"),
        routing_key=names.payment_queue,
    )
    await channel.default_exchange.publish(
        _future_message(notification_copy, message_id="evt_future_notification"),
        routing_key=names.notification_queue,
    )

    # Notification copy: acknowledged, NOTHING written (no quarantine, no marker).
    await pipeline.assert_queue_empty(names.notification_queue, settle=1.0)
    async with session_scope() as session:
        notification_quarantine = list(
            (
                await session.execute(
                    select(QuarantineRecord).where(
                        QuarantineRecord.consumer_name == "notification",
                        QuarantineRecord.event_id == "evt_future_notification",
                    )
                )
            ).scalars()
        )
    assert notification_quarantine == []

    # Payment copy: durable quarantine record + dead publication.
    async def _payment_quarantined() -> bool:
        async with session_scope() as session:
            rows = list(
                (
                    await session.execute(
                        select(QuarantineRecord).where(
                            QuarantineRecord.consumer_name == "payment",
                            QuarantineRecord.event_id == "evt_future_payment",
                        )
                    )
                ).scalars()
            )
        return len(rows) == 1 and rows[0].failure_code == "unknown_event_type"

    await wait_until(
        _payment_quarantined,
        timeout=10,
        message="future business event quarantined at payment consumer",
    )
    await pipeline.assert_queue_empty(names.payment_queue, settle=0.5)
    pipeline.raise_if_task_failed()
