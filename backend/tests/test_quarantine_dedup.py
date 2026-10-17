"""Durable quarantine: exactly-once logical records under repetition and races
(assignment §11, M4 §6).

Covers required M4 tests: repeated exhausted deliveries do not duplicate the
logical quarantine record; malformed duplicates deduplicate to one record; the
same event quarantined by two consumers yields independent records but a
single shared dead-letter publication; and competing worker replicas racing on
the same exhausted event stay single (unique identities enforced by
PostgreSQL, not by read-then-write luck).
"""

from __future__ import annotations

import hashlib

import aio_pika
from sqlalchemy import select

from app.core.config import get_settings
from app.db.models.quarantine_record import QuarantineRecord
from app.db.session import session_scope
from app.messaging.topology import DEAD_ROUTING_KEY
from app.schemas.events import ORDER_CREATED
from tests.m3_harness import (
    fetch_outbox_payload,
    get_order_row,
    order_rows,
    outbox_rows_for_event,
    place_order,
    quarantine_rows_for_event,
    retry_job_rows,
    wait_for_status,
    wait_until,
)


async def _dead_rows_for(event_id: str) -> list:
    rows = await outbox_rows_for_event(event_id)
    return [r for r in rows if r.routing_key == DEAD_ROUTING_KEY]


async def test_repeated_exhausted_deliveries_create_one_logical_quarantine(
    pipeline, async_client, customer_token, monkeypatch
):
    """After payment exhausts its ladder into PAYMENT_FAILED, replaying the
    ORIGINAL order.created delivery (a redelivered/late duplicate) changes
    nothing: no second quarantine record, no second retry ladder, no state
    movement — the committed exhaustion marker short-circuits it."""
    settings = get_settings()
    monkeypatch.setattr(settings, "payment_mode", "always_fail")

    pipeline.start_dispatcher()
    pipeline.start_scheduler()
    pipeline.start_consumers("payment")

    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "PAYMENT_FAILED", timeout=30)

    original = await fetch_outbox_payload(order_id, ORDER_CREATED)
    event_id = original["event_id"]

    async def _one_quarantine() -> bool:
        return len(await quarantine_rows_for_event(event_id)) == 1

    await wait_until(_one_quarantine, timeout=10, message="first quarantine recorded")

    # Replay TWO duplicate copies of the very delivery that was exhausted.
    await pipeline.publish_to_queue(pipeline.names.payment_queue, original)
    await pipeline.publish_to_queue(pipeline.names.payment_queue, original)
    await pipeline.assert_queue_empty(pipeline.names.payment_queue, settle=1.0)

    assert len(await quarantine_rows_for_event(event_id)) == 1  # ONE logical record
    jobs = await retry_job_rows("payment", event_id)
    assert [j.attempt for j in jobs] == [2, 3, 4]  # ladder not extended
    rows = await order_rows(order_id)
    assert len(rows["payments"]) == 1  # no double payment
    order = await get_order_row(order_id)
    assert order.status == "PAYMENT_FAILED" and order.version == 2  # no regression
    # The dead-letter publication exists exactly once.
    assert len(await _dead_rows_for(event_id)) == 1
    pipeline.raise_if_task_failed()


async def test_repeated_malformed_copies_create_one_quarantine_record(pipeline):
    """Identical malformed bytes published repeatedly -> one logical
    quarantine record (digest identity), one dead-letter publication, queue
    fully acknowledged."""
    names = pipeline.names
    pipeline.start_consumers("payment")
    pipeline.start_dispatcher()

    raw_body = b"@@@ definitely not a json envelope @@@"
    event_id = f"undecoded_{hashlib.sha256(raw_body).hexdigest()[:32]}"
    channel = await pipeline.connection.channel()
    for _ in range(3):
        # No message_id: identity must come from the deterministic payload
        # digest, which is what makes repeated copies deduplicate.
        await channel.default_exchange.publish(
            aio_pika.Message(body=raw_body),
            routing_key=names.payment_queue,
        )

    async def _one_record() -> bool:
        return len(await quarantine_rows_for_event(event_id)) == 1

    await wait_until(_one_record, timeout=10, message="single malformed quarantine")
    await pipeline.assert_queue_empty(names.payment_queue, settle=1.0)

    # After the copies drained: STILL exactly one record + one publication.
    assert len(await quarantine_rows_for_event(event_id)) == 1
    dead_rows = await _dead_rows_for(event_id)
    assert len(dead_rows) == 1 and dead_rows[0].payload["malformed"] is True


async def test_same_event_quarantined_by_two_consumers_shares_one_publication(pipeline):
    """Two DIFFERENT consumers each record their own logical quarantine for
    the same malformed event (independent identities), while the dead-letter
    outbox publication deduplicates to a single row (publication identity)."""
    names = pipeline.names
    pipeline.start_consumers("payment")
    pipeline.start_consumers("notification")
    pipeline.start_dispatcher()

    raw_body = b'{"definitely": "not an envelope"'
    event_id = f"undecoded_{hashlib.sha256(raw_body).hexdigest()[:32]}"
    channel = await pipeline.connection.channel()
    for queue in (names.payment_queue, names.notification_queue):
        await channel.default_exchange.publish(
            aio_pika.Message(body=raw_body),
            routing_key=queue,
        )

    async def _both_quarantined() -> bool:
        async with session_scope() as session:
            rows = list(
                (
                    await session.execute(
                        select(QuarantineRecord).where(QuarantineRecord.event_id == event_id)
                    )
                ).scalars()
            )
        return sorted(r.consumer_name for r in rows) == ["notification", "payment"]

    await wait_until(_both_quarantined, timeout=10, message="both consumers quarantined the event")
    await pipeline.assert_queue_empty(names.payment_queue, settle=0.5)
    await pipeline.assert_queue_empty(names.notification_queue, settle=0.5)

    # ONE shared dead-letter publication row (identical immutable payload).
    assert len(await _dead_rows_for(event_id)) == 1


async def test_competing_replicas_keep_exhaustion_single(
    pipeline, async_client, customer_token, monkeypatch
):
    """Two payment REPLICA instances racing on duplicate deliveries of the
    same always-failing event: single retry ladder (unique per attempt), one
    PAYMENT_FAILED transition, one payment row, one logical quarantine."""
    settings = get_settings()
    monkeypatch.setattr(settings, "payment_mode", "always_fail")

    pipeline.start_dispatcher()
    pipeline.start_scheduler()
    pipeline.start_consumers("payment", instances=2)

    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "PAYMENT_FAILED", timeout=30)

    original = await fetch_outbox_payload(order_id, ORDER_CREATED)
    event_id = original["event_id"]

    async def _one_quarantine() -> bool:
        return len(await quarantine_rows_for_event(event_id)) == 1

    await wait_until(_one_quarantine, timeout=10, message="single logical quarantine")

    # Amplify the race: duplicate copies while both replicas are live.
    await pipeline.publish_to_queue(pipeline.names.payment_queue, original)
    await pipeline.publish_to_queue(pipeline.names.payment_queue, original)
    await pipeline.assert_queue_empty(pipeline.names.payment_queue, settle=1.0)

    rows = await order_rows(order_id)
    assert len(rows["quarantined"]) == 1
    assert [j.attempt for j in rows["retries"]] == [2, 3, 4]  # no duplicate jobs
    assert len(rows["payments"]) == 1
    order = await get_order_row(order_id)
    assert order.status == "PAYMENT_FAILED" and order.version == 2
    assert sum(1 for m in rows["processed"] if m.consumer_name == "payment") == 1
    pipeline.raise_if_task_failed()
