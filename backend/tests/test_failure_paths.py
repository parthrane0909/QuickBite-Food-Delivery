"""Terminal failure paths and notification isolation (assignment §11, §5/§10).

Covers required M4 tests: always-failing payment exhausting its finite retry
budget into a terminal PAYMENT_FAILED with a persisted failure code; permanent
restaurant/delivery rejections terminating without churn; notification
exhaustion quarantined WITHOUT ever changing order business status; and
missing-order events exhausting to quarantine without creating or mutating
any unrelated order.
"""

from __future__ import annotations

from collections import Counter

from app.core.config import get_settings
from app.schemas.events import ORDER_CREATED, ORDER_PAID
from tests.m3_harness import (
    build_envelope,
    fetch_outbox_payload,
    get_order_row,
    order_rows,
    place_order,
    wait_for_status,
    wait_until,
)


async def test_always_failing_payment_exhausts_retries_then_terminal_failure(
    pipeline, async_client, customer_token, monkeypatch
):
    """PAYMENT_MODE=always_fail is a TRANSIENT failure every attempt: attempts
    1..4 (retries due +0.2/0.4/0.8s in tests), then terminal PAYMENT_FAILED
    with failure code, history, order.payment.failed event and a durable
    quarantine record — never an immediate termination, never an unbounded
    retry loop."""
    settings = get_settings()
    monkeypatch.setattr(settings, "payment_mode", "always_fail")

    pipeline.start_dispatcher()
    pipeline.start_scheduler()
    pipeline.start_consumers("payment")
    pipeline.start_consumers("notification")

    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "PAYMENT_FAILED", timeout=30)

    order = await get_order_row(order_id)
    assert order.failure_code == "PAYMENT_RETRIES_EXHAUSTED"
    assert order.version == 2

    rows = await order_rows(order_id)
    # Exactly one committed transition PENDING -> PAYMENT_FAILED.
    assert [h.version for h in rows["history"]] == [1, 2]
    # Exactly one simulated payment record, marked failed with the SAME code.
    assert len(rows["payments"]) == 1
    assert rows["payments"][0].status == "FAILED"
    assert rows["payments"][0].failure_code == "PAYMENT_RETRIES_EXHAUSTED"
    # The durable retry ladder ran exactly 3 times and is now exhausted.
    assert [j.attempt for j in rows["retries"]] == [2, 3, 4]
    assert rows["retries"][-1].state == "EXHAUSTED"
    # ONE logical quarantine record for the exhausted event.
    assert len(rows["quarantined"]) == 1
    quarantine = rows["quarantined"][0]
    assert quarantine.consumer_name == "payment"
    assert quarantine.failure_code == "PAYMENT_RETRIES_EXHAUSTED"
    assert quarantine.attempts == 4
    assert quarantine.order_id == order_id
    # Markers: payment exhausted exactly once; notification unaffected twice.
    outcomes = sorted(m.outcome for m in rows["processed"] if m.consumer_name == "payment")
    assert outcomes == ["QUARANTINED"]

    # order.payment.failed flowed on as a normal business event.
    async def _two_notifications() -> bool:
        return len((await order_rows(order_id))["notifications"]) == 2

    await wait_until(_two_notifications, timeout=10, message="created + payment.failed")

    # The quarantine is dead-lettered to the DLQ with the original identity.
    original = await fetch_outbox_payload(order_id, ORDER_CREATED)
    dead = await pipeline.drain_queue(pipeline.names.dead_queue, first_timeout=10)
    assert len(dead) == 1
    assert dead[0]["event_type"] == ORDER_CREATED
    assert dead[0]["event_id"] == original["event_id"]
    pipeline.raise_if_task_failed()


async def test_permanent_restaurant_rejection_bypasses_retries(
    pipeline, async_client, customer_token, monkeypatch
):
    """A permanent business rejection (RESTAURANT_MODE=always_fail) is a
    deliberate bypass of the retry budget: immediate PAID -> FAILED with
    RESTAURANT_REJECTED, zero retry jobs, zero quarantines."""
    settings = get_settings()
    monkeypatch.setattr(settings, "restaurant_mode", "always_fail")

    pipeline.start_dispatcher()
    pipeline.start_scheduler()
    pipeline.start_consumers("payment")
    pipeline.start_consumers("restaurant")
    pipeline.start_consumers("notification")

    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "FAILED", timeout=30)

    order = await get_order_row(order_id)
    assert order.failure_code == "RESTAURANT_REJECTED"

    rows = await order_rows(order_id)
    assert [h.version for h in rows["history"]] == [1, 2, 3]  # PENDING,PAID,FAILED
    assert len(rows["payments"]) == 1 and rows["payments"][0].status == "SUCCEEDED"
    assert rows["retries"] == []  # permanent decline never enters the ladder
    assert rows["quarantined"] == []

    async def _three_notifications() -> bool:
        return len((await order_rows(order_id))["notifications"]) == 3

    await wait_until(_three_notifications, timeout=10, message="created+paid+failed")
    assert await pipeline.queue_depth(pipeline.names.dead_queue) == 0
    pipeline.raise_if_task_failed()


async def test_permanent_delivery_failure_bypasses_retries(
    pipeline, async_client, customer_token, monkeypatch
):
    """DELIVERY_MODE=always_fail: CONFIRMED -> FAILED with DRIVER_UNAVAILABLE,
    no driver assignment, no retry churn, no quarantine."""
    settings = get_settings()
    monkeypatch.setattr(settings, "delivery_mode", "always_fail")

    pipeline.start_dispatcher()
    pipeline.start_scheduler()
    pipeline.start_consumers("payment")
    pipeline.start_consumers("restaurant")
    pipeline.start_consumers("delivery")
    pipeline.start_consumers("notification")

    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "FAILED", timeout=30)

    order = await get_order_row(order_id)
    assert order.failure_code == "DRIVER_UNAVAILABLE"

    rows = await order_rows(order_id)
    assert [h.version for h in rows["history"]] == [1, 2, 3, 4]  # through CONFIRMED
    assert rows["assignments"] == []  # permanent failure assigns nobody
    assert rows["retries"] == [] and rows["quarantined"] == []

    async def _four_notifications() -> bool:
        return len((await order_rows(order_id))["notifications"]) == 4

    await wait_until(_four_notifications, timeout=10, message="created..failed")
    pipeline.raise_if_task_failed()


async def test_notification_exhaustion_never_changes_order_status(
    pipeline, async_client, customer_token, monkeypatch
):
    """Notification failures exhaust INDEPENDENTLY: every chain event is
    quarantined after the bounded ladder while the order's business status,
    version and history stay those of the successful chain — notifications
    can never move an order (§10), forward or backward."""
    settings = get_settings()
    monkeypatch.setattr(settings, "notification_mode", "always_fail")

    pipeline.start_dispatcher()
    pipeline.start_scheduler()
    pipeline.start_consumers("payment")
    pipeline.start_consumers("restaurant")
    pipeline.start_consumers("delivery")
    pipeline.start_consumers("notification")

    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "DRIVER_ASSIGNED", timeout=30)

    async def _all_four_quarantined() -> bool:
        rows = await order_rows(order_id)
        return len(rows["quarantined"]) == 4 and all(
            q.consumer_name == "notification" for q in rows["quarantined"]
        )

    await wait_until(
        _all_four_quarantined,
        timeout=30,
        message="4 notification quarantines (one per chain event)",
    )

    rows = await order_rows(order_id)
    # Business outcome is the successful chain — untouched by the failures.
    order = await get_order_row(order_id)
    assert order.status == "DRIVER_ASSIGNED" and order.version == 4
    assert [h.version for h in rows["history"]] == [1, 2, 3, 4]
    assert len(rows["payments"]) == 1 and rows["payments"][0].status == "SUCCEEDED"
    assert len(rows["assignments"]) == 1
    # Zero customer notifications were persisted; all four events exhausted.
    assert rows["notifications"] == []
    assert all(q.failure_code == "NOTIFICATION_RETRIES_EXHAUSTED" for q in rows["quarantined"])
    assert Counter(q.failure_code for q in rows["quarantined"]) == {
        "NOTIFICATION_RETRIES_EXHAUSTED": 4
    }
    # Exactly one QUARANTINED marker per event for the notification consumer,
    # and normal PROCESSED markers for the three business consumers.
    notification_outcomes = sorted(
        m.outcome for m in rows["processed"] if m.consumer_name == "notification"
    )
    assert notification_outcomes == ["QUARANTINED"] * 4
    for consumer in ("payment", "restaurant", "delivery"):
        assert [m.outcome for m in rows["processed"] if m.consumer_name == consumer] == [
            "PROCESSED"
        ]
    # The retry ladder: 4 events x attempts 2,3,4, last attempt exhausted.
    assert Counter(j.attempt for j in rows["retries"]) == {2: 4, 3: 4, 4: 4}
    assert sum(1 for j in rows["retries"] if j.state == "EXHAUSTED") == 4

    # All four quarantined copies reached the dead-letter queue.
    dead = await pipeline.drain_queue(pipeline.names.dead_queue, first_timeout=10)
    assert len(dead) == 4
    pipeline.raise_if_task_failed()


async def test_missing_order_exhausts_to_quarantine_without_touching_orders(pipeline):
    """An event referencing a non-existent order goes through the bounded
    durable ladder and ends quarantined — it never creates an order, never
    mutates an unrelated one, and never silently disappears."""
    pipeline.start_dispatcher()
    pipeline.start_scheduler()
    pipeline.start_consumers("restaurant")

    ghost_id = "order_ghost_404"
    ghost_event = build_envelope(ORDER_PAID, ghost_id, 2)
    await pipeline.publish_to_queue(pipeline.names.restaurant_queue, ghost_event)

    async def _quarantined() -> bool:
        rows = await order_rows(ghost_id)
        return len(rows["quarantined"]) == 1

    await wait_until(_quarantined, timeout=20, message="missing order quarantined")

    assert await get_order_row(ghost_id) is None  # no order row was created
    rows = await order_rows(ghost_id)
    assert [j.attempt for j in rows["retries"]] == [2, 3, 4]
    assert rows["retries"][-1].state == "EXHAUSTED"
    quarantine = rows["quarantined"][0]
    assert quarantine.failure_code == "RESTAURANT_RETRIES_EXHAUSTED"
    assert "missing_order" in quarantine.reason
    assert quarantine.event_id == ghost_event["event_id"]  # immutable identity
    assert [m.outcome for m in rows["processed"]] == ["QUARANTINED"]

    dead = await pipeline.drain_queue(pipeline.names.dead_queue, first_timeout=10)
    assert len(dead) == 1 and dead[0]["event_id"] == ghost_event["event_id"]
    pipeline.raise_if_task_failed()
