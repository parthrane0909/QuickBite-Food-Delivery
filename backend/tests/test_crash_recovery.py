"""Crash-recovery windows (assignment §11, M4 §8): at-least-once delivery with
a single committed business effect — never exactly-once by claim, always
idempotent by durable state.

Covers required M4 tests: worker death BEFORE commit (no partial effects,
redelivery completes exactly once); redelivery AFTER commit but before ACK
(dedup no-op, no repeated payment/transition); retry-persistence failure
(message kept UNACKED, bounded backoff, ladder continues without duplicates);
dispatcher crash after publish before SENT on a TARGETED RETRY row (republish
never extends the ladder). The PHYSICAL container-kill variants of these
windows run against the real stack in `scripts/capture_m4_evidence.sh`
(captured in docs/evidence/m4/).
"""

from __future__ import annotations

import asyncio

from sqlalchemy import text

from app.core.config import get_settings
from app.db.session import session_scope
from app.schemas.events import ORDER_CREATED
from tests.m3_harness import (
    build_envelope,
    fetch_outbox_payload,
    get_order_row,
    order_rows,
    outbox_rows_for_event,
    place_order,
    retry_job_rows,
    wait_for_status,
    wait_until,
)


async def test_worker_cancelled_before_commit_redelivers_without_partial_effects(
    pipeline, async_client, customer_token
):
    """Worker death BEFORE the business transaction commit: nothing persisted
    (no payment, no history, no marker, no retry job), the unacked copy is
    redelivered, and the restarted worker completes the effect exactly once."""
    consumer_tasks = pipeline.start_consumers("payment", delay_seconds=1.0)

    order_id = await place_order(async_client, customer_token)
    event = build_envelope(ORDER_CREATED, order_id, 1)
    await pipeline.publish_to_queue(pipeline.names.payment_queue, event)

    # Kill the worker mid-flight (inside the stage delay, pre-transaction).
    consumer_tasks[0].cancel()
    await asyncio.gather(consumer_tasks[0], return_exceptions=True)

    # Pre-commit death leaves ZERO partial business state.
    rows = await order_rows(order_id)
    assert rows["payments"] == []
    assert [h.version for h in rows["history"]] == [1]  # PENDING only
    assert rows["processed"] == []
    assert rows["retries"] == []  # a crash is not a classified failure
    assert rows["quarantined"] == []

    # Redelivery after restart: exactly one committed effect.
    pipeline.start_consumers("payment")
    await wait_for_status(order_id, "PAID", timeout=20)
    rows = await order_rows(order_id)
    assert len(rows["payments"]) == 1 and rows["payments"][0].status == "SUCCEEDED"
    assert [h.version for h in rows["history"]] == [1, 2]
    assert [m.outcome for m in rows["processed"]] == ["PROCESSED"]
    assert rows["retries"] == [] and rows["quarantined"] == []
    pipeline.raise_if_task_failed()


async def test_redelivery_after_commit_before_ack_never_repeats_effects(
    pipeline, async_client, customer_token
):
    """Crash between commit and ACK: the broker redelivers the very same
    delivery. The committed marker turns it into a no-op — no second payment,
    no repeated transition, no backward movement."""
    pipeline.start_consumers("payment")

    order_id = await place_order(async_client, customer_token)
    event = build_envelope(ORDER_CREATED, order_id, 1)
    await pipeline.publish_to_queue(pipeline.names.payment_queue, event)
    await wait_for_status(order_id, "PAID", timeout=20)

    # The redelivery (as after a post-commit/pre-ACK crash).
    await pipeline.publish_to_queue(pipeline.names.payment_queue, event)
    await pipeline.assert_queue_empty(pipeline.names.payment_queue, settle=1.0)

    rows = await order_rows(order_id)
    assert len(rows["payments"]) == 1  # single committed business effect
    assert [h.version for h in rows["history"]] == [1, 2]  # no repeated transition
    assert [m.outcome for m in rows["processed"]] == ["PROCESSED"]  # one marker
    assert rows["retries"] == [] and rows["quarantined"] == []
    order = await get_order_row(order_id)
    assert order.status == "PAID" and order.version == 2
    pipeline.raise_if_task_failed()


async def test_retry_persistence_failure_keeps_message_unacked_then_schedules(
    pipeline, async_client, customer_token, monkeypatch
):
    """If persisting the retry itself fails (DB interruption / crash during
    retry persistence), the message is NEVER acknowledged away: the runtime
    backs off bounded, retries the persistence, and the ladder continues to
    completion with no duplicate jobs and no lost work."""
    settings = get_settings()
    monkeypatch.setattr(settings, "payment_mode", "always_fail")

    from app.repositories import messaging as messaging_repo

    original_schedule = messaging_repo.schedule_retry
    calls = {"n": 0}

    async def _flaky_schedule(session, **kwargs):
        calls["n"] += 1
        if calls["n"] == 1:
            raise RuntimeError("simulated retry persistence outage")
        return await original_schedule(session, **kwargs)

    monkeypatch.setattr(messaging_repo, "schedule_retry", _flaky_schedule)

    pipeline.start_dispatcher()
    pipeline.start_scheduler()
    pipeline.start_consumers("payment")

    # The API-placed order's own order.created event is the failing delivery.
    order_id = await place_order(async_client, customer_token)

    # The first persistence attempt failed; after the bounded backoff the
    # message was still unacked, got redelivered handling, and the retry job
    # now exists — then the WHOLE ladder runs to exhaustion.
    await wait_for_status(order_id, "PAYMENT_FAILED", timeout=30)
    assert calls["n"] >= 2  # outage occurred and was recovered from

    rows = await order_rows(order_id)
    assert [j.attempt for j in rows["retries"]] == [2, 3, 4]  # no duplicates
    assert rows["retries"][-1].state == "EXHAUSTED"
    assert len(rows["quarantined"]) == 1
    assert len(rows["payments"]) == 1
    await pipeline.assert_queue_empty(pipeline.names.payment_queue, settle=0.5)
    pipeline.raise_if_task_failed()


async def test_retry_publication_republish_after_sent_reset_does_not_extend_ladder(
    pipeline, async_client, customer_token, monkeypatch
):
    """Dispatcher crash AFTER publishing a targeted retry but BEFORE marking
    it SENT (row reset to eligible): the copy is published again — a duplicate
    delivery of an already-committed attempt that no-ops through dedup and
    never adds a rung to the ladder or a second payment."""
    settings = get_settings()
    monkeypatch.setattr(settings, "payment_mode", "fail_twice")

    pipeline.start_dispatcher()
    pipeline.start_scheduler()
    pipeline.start_consumers("payment")
    pipeline.start_consumers("notification")

    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "PAID", timeout=20)

    original = await fetch_outbox_payload(order_id, ORDER_CREATED)
    event_id = original["event_id"]
    jobs = await retry_job_rows("payment", event_id)
    assert [j.attempt for j in jobs] == [2, 3]

    # Simulate the crash window: published + consumed, SENT mark lost.
    async with session_scope() as session:
        await session.execute(
            text(
                "UPDATE outbox_events SET state = 'PENDING', available_at = now(), "
                "published_at = NULL WHERE event_id = :event_id AND exchange = ''"
            ),
            {"event_id": event_id},
        )

    # The dispatcher reclaims and republishes; the consumer deduplicates.
    async def _retry_row_republished() -> bool:
        fresh = [r for r in await outbox_rows_for_event(event_id) if r.exchange == ""]
        return len(fresh) == 1 and fresh[0].state == "SENT"

    await wait_until(
        _retry_row_republished,
        timeout=10,
        message="retry publication re-sent after crash-window reset",
    )
    await pipeline.assert_queue_empty(pipeline.names.payment_queue, settle=1.0)

    # Ladder unchanged (still exactly attempts 2 and 3), single payment,
    # no quarantine, no state movement.
    jobs = await retry_job_rows("payment", event_id)
    assert [j.attempt for j in jobs] == [2, 3]
    rows_db = await order_rows(order_id)
    assert len(rows_db["payments"]) == 1
    assert rows_db["quarantined"] == []
    order = await get_order_row(order_id)
    assert order.status == "PAID" and order.version == 2
    pipeline.raise_if_task_failed()
