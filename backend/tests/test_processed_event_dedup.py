"""Processed-event deduplication under duplicate/redelivered messages (§10).

The unique (consumer_name, event_id) marker plus the order row lock must make
EVERY redelivery a no-op: exactly one payment, exactly one assignment, no
history growth, no backward movement — even for a full replay of every event
after completion.
"""

from __future__ import annotations

from sqlalchemy import select

from app.db.models.processed_event import ProcessedEvent
from app.db.session import session_scope
from app.schemas.events import (
    ORDER_CONFIRMED,
    ORDER_CREATED,
    ORDER_DRIVER_ASSIGNED,
    ORDER_PAID,
)
from tests.m3_harness import (
    build_envelope,
    fetch_outbox_payload,
    get_order_row,
    order_rows,
    place_order,
    wait_for_eq,
    wait_for_status,
)


async def _markers(order_id: str, consumer: str) -> list[ProcessedEvent]:
    async with session_scope() as session:
        return list(
            (
                await session.execute(
                    select(ProcessedEvent).where(
                        ProcessedEvent.order_id == order_id,
                        ProcessedEvent.consumer_name == consumer,
                    )
                )
            ).scalars()
        )


async def test_duplicate_created_delivers_exactly_one_payment(
    pipeline, async_client, customer_token
):
    """Redelivery of the SAME order.created (same event_id) after PAID must
    not create a second payment, history row or marker."""
    pipeline.start_dispatcher()
    pipeline.start_consumers("payment")

    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "PAID")

    created = await fetch_outbox_payload(order_id, ORDER_CREATED)
    marker_before = await _markers(order_id, "payment")
    assert len(marker_before) == 1

    # Two extra copies (at-least-once dispatcher redelivery + a queue replay).
    await pipeline.publish_to_queue(pipeline.names.payment_queue, created)
    await pipeline.publish_to_queue(pipeline.names.payment_queue, created)
    await pipeline.assert_queue_empty(pipeline.names.payment_queue, settle=1.0)
    pipeline.raise_if_task_failed()

    rows = await order_rows(order_id)
    assert len(rows["payments"]) == 1  # exactly one payment, ever
    assert rows["payments"][0].status == "SUCCEEDED"
    assert [h.version for h in rows["history"]] == [1, 2]
    order = await get_order_row(order_id)
    assert order.status == "PAID" and order.version == 2
    assert len(await _markers(order_id, "payment")) == 1  # one marker for both copies


async def test_duplicate_confirmed_delivers_exactly_one_assignment(
    pipeline, async_client, customer_token
):
    """Redelivery of order.confirmed must not assign a second driver or move
    the version again."""
    pipeline.start_dispatcher()
    for stage in ("payment", "restaurant", "delivery"):
        pipeline.start_consumers(stage)

    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "DRIVER_ASSIGNED")

    confirmed = await fetch_outbox_payload(order_id, ORDER_CONFIRMED)
    await pipeline.publish_to_queue(pipeline.names.delivery_queue, confirmed)
    await pipeline.publish_to_queue(pipeline.names.delivery_queue, confirmed)
    await pipeline.assert_queue_empty(pipeline.names.delivery_queue, settle=1.0)
    pipeline.raise_if_task_failed()

    rows = await order_rows(order_id)
    assert len(rows["assignments"]) == 1
    assert len(rows["payments"]) == 1
    assert [h.version for h in rows["history"]] == [1, 2, 3, 4]
    order = await get_order_row(order_id)
    assert order.status == "DRIVER_ASSIGNED" and order.version == 4
    assert len(await _markers(order_id, "delivery")) == 1


async def test_full_redelivery_after_completion_is_a_noop(pipeline, async_client, customer_token):
    """Replay EVERY committed event after the chain finished: zero effects,
    zero history growth, notifications/markers unchanged (idempotency by
    design — duplicates after crash-before-SENT are tolerated downstream)."""
    pipeline.start_dispatcher()
    for stage in ("payment", "restaurant", "delivery", "notification"):
        pipeline.start_consumers(stage)

    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "DRIVER_ASSIGNED")
    await wait_for_eq(
        lambda: _count_notifications(order_id),
        4,
        timeout=20,
        message="four notifications before replay",
    )

    before = await order_rows(order_id)
    assert len(before["notifications"]) == 4

    # Replay all four events into every consumer queue that accepts them.
    created = await fetch_outbox_payload(order_id, ORDER_CREATED)
    paid = await fetch_outbox_payload(order_id, ORDER_PAID)
    confirmed = await fetch_outbox_payload(order_id, ORDER_CONFIRMED)
    driver = await fetch_outbox_payload(order_id, ORDER_DRIVER_ASSIGNED)

    await pipeline.publish_to_queue(pipeline.names.payment_queue, created)
    await pipeline.publish_to_queue(pipeline.names.payment_queue, created)
    await pipeline.publish_to_queue(pipeline.names.restaurant_queue, paid)
    await pipeline.publish_to_queue(pipeline.names.delivery_queue, confirmed)
    for payload in (created, paid, confirmed, driver):
        await pipeline.publish_to_queue(pipeline.names.notification_queue, payload)

    for queue in (
        pipeline.names.payment_queue,
        pipeline.names.restaurant_queue,
        pipeline.names.delivery_queue,
        pipeline.names.notification_queue,
    ):
        await pipeline.assert_queue_empty(queue, settle=0.75)
    pipeline.raise_if_task_failed()

    after = await order_rows(order_id)
    order = await get_order_row(order_id)

    # The order itself did not move.
    assert order.status == "DRIVER_ASSIGNED" and order.version == 4
    assert [h.version for h in after["history"]] == [1, 2, 3, 4]

    # Exactly-one business effects.
    assert len(after["payments"]) == 1
    assert len(after["assignments"]) == 1

    # Replay was ACKed without re-notifying or re-marking: same unique event
    # ids, same marker set (dedup hit before any effect).
    assert len(after["notifications"]) == len(before["notifications"]) == 4
    assert {n.event_id for n in after["notifications"]} == {
        n.event_id for n in before["notifications"]
    }
    # 4 notification + 3 stage markers — unchanged by the replay.
    assert len(after["processed"]) == len(before["processed"]) == 7


async def test_stale_event_is_marked_processed_without_regression(
    pipeline, async_client, customer_token
):
    """A NEW order.created envelope (fresh event_id) for an already-completed
    order: no marker exists, but the order is at-or-beyond payment — the
    processor classifies it as a safe no-op, marks STALE_NOOP and acks."""
    pipeline.start_dispatcher()
    for stage in ("payment", "restaurant", "delivery", "notification"):
        pipeline.start_consumers(stage)

    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "DRIVER_ASSIGNED")

    stale = build_envelope(ORDER_CREATED, order_id, 1)
    await pipeline.publish_to_queue(pipeline.names.payment_queue, stale)
    await pipeline.assert_queue_empty(pipeline.names.payment_queue, settle=1.0)
    pipeline.raise_if_task_failed()

    markers = await _markers(order_id, "payment")
    stale_markers = [m for m in markers if m.event_id == stale["event_id"]]
    assert len(stale_markers) == 1
    assert stale_markers[0].outcome == "STALE_NOOP"

    order = await get_order_row(order_id)
    assert order.status == "DRIVER_ASSIGNED" and order.version == 4
    rows = await order_rows(order_id)
    assert len(rows["payments"]) == 1
    assert [h.version for h in rows["history"]] == [1, 2, 3, 4]


async def _count_notifications(order_id: str) -> int:
    from sqlalchemy import func

    from app.db.models.notification import Notification

    async with session_scope() as session:
        result = await session.execute(
            select(func.count()).select_from(Notification).where(Notification.order_id == order_id)
        )
        return int(result.scalar_one())
