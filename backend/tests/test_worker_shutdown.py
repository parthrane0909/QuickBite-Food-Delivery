"""Worker lifecycle: backlog drain, graceful shutdown, redelivery safety (§10).

Covers required tests: backlog drains after consumer (re)start, and a message
whose transaction COMMITTED but was never ACKed (crash-before-ack) must
redeliver into a pure no-op — never repeated effects.
"""

from __future__ import annotations

from app.messaging.consumer_runtime import _run_transaction
from app.messaging.envelope import parse_envelope
from app.schemas.events import ORDER_CREATED
from app.services.payment_service import process_payment
from tests.m3_harness import (
    build_envelope,
    fetch_outbox_payload,
    get_order_row,
    order_rows,
    place_order,
    wait_for_eq,
    wait_for_status,
    wait_until,
)

ALL_STAGES = ("payment", "restaurant", "delivery", "notification")


async def test_backlog_drains_after_consumer_restart(pipeline, async_client, customer_token):
    """Messages committed while NO workers run are never lost: they wait in
    durable queues, and (re)started consumers drain them to completion —
    twice in a row (stop-all, new backlog, restart again)."""
    pipeline.start_dispatcher()  # dispatcher alone: no consumer progress yet

    order_one = await place_order(async_client, customer_token)
    await wait_for_eq(
        lambda: pipeline.queue_depth(pipeline.names.payment_queue),
        1,
        timeout=15,
        message="order.created waited in payment.queue with no consumer",
    )
    assert await pipeline.queue_depth(pipeline.names.notification_queue) == 1
    assert (await get_order_row(order_one)).status == "PENDING"

    # --- workers start (restart #1): backlog drains to completion ---------
    for stage in ALL_STAGES:
        pipeline.start_consumers(stage)
    await wait_for_status(order_one, "DRIVER_ASSIGNED")
    for queue in (
        pipeline.names.payment_queue,
        pipeline.names.restaurant_queue,
        pipeline.names.delivery_queue,
        pipeline.names.notification_queue,
    ):
        await pipeline.assert_queue_empty(queue, settle=0.75)
    pipeline.raise_if_task_failed()

    rows = await order_rows(order_one)
    assert len(rows["payments"]) == 1 and len(rows["assignments"]) == 1
    assert [h.version for h in rows["history"]] == [1, 2, 3, 4]

    # --- stop every worker (new backlog forms), restart (restart #2) ------
    for stage in ALL_STAGES:
        pipeline.stop_consumer(stage)
        await pipeline.wait_consumer_stopped(stage)

    order_two = await place_order(async_client, customer_token)
    await wait_for_eq(
        lambda: pipeline.queue_depth(pipeline.names.payment_queue),
        1,
        timeout=15,
        message="second backlog waited while workers were stopped",
    )

    for stage in ALL_STAGES:
        pipeline.start_consumers(stage)
    await wait_for_status(order_two, "DRIVER_ASSIGNED")
    await pipeline.assert_queue_empty(pipeline.names.payment_queue, settle=0.75)
    pipeline.raise_if_task_failed()

    rows_two = await order_rows(order_two)
    assert len(rows_two["payments"]) == 1
    assert [h.version for h in rows_two["history"]] == [1, 2, 3, 4]
    # First order untouched by the second cycle.
    rows_one = await order_rows(order_one)
    assert len(rows_one["payments"]) == 1 and rows_one["history"][-1].version == 4


async def test_graceful_shutdown_finishes_inflight_and_preserves_backlog(
    pipeline, async_client, customer_token
):
    """SIGTERM-equivalent stop: the in-flight message COMMITS and ACKs, every
    not-yet-handled prefetched copy returns to the queue, and a restarted
    consumer finishes the rest exactly once."""
    order_id = await place_order(async_client, customer_token)  # dispatcher off

    # Five distinct events (unique ids) queued for the notification worker.
    for index in range(5):
        payload = build_envelope(ORDER_CREATED, order_id, 1, event_id=f"evt_shutdown_{index}")
        await pipeline.publish_to_queue(pipeline.names.notification_queue, payload)

    # Stage delay keeps the first message in flight long enough to stop
    # DURING it — deterministically exercising the in-flight completion path.
    pipeline.start_consumers("notification", delay_seconds=2.0)
    await wait_for_eq(
        lambda: pipeline.queue_depth(pipeline.names.notification_queue),
        0,
        timeout=10,
        message="consumer took the backlog (prefetch) before shutdown",
    )

    pipeline.stop_consumer("notification")
    await pipeline.wait_consumer_stopped("notification")

    rows = await order_rows(order_id)
    # The in-flight message committed + acked exactly once...
    assert len(rows["notifications"]) == 1
    notification_markers = [m for m in rows["processed"] if m.consumer_name == "notification"]
    assert len(notification_markers) == 1
    # ...and the other four were NOT acked/lost: back in the queue.
    remaining = await pipeline.queue_depth(pipeline.names.notification_queue)
    assert remaining == 4
    # Notification work never touches business status.
    order = await get_order_row(order_id)
    assert order.status == "PENDING" and order.version == 1

    # Restart: the remaining backlog drains, still exactly once each.
    pipeline.start_consumers("notification")

    async def _five_persisted() -> bool:
        return len(await notification_event_ids(order_id)) == 5

    await wait_until(
        _five_persisted,
        timeout=20,
        message="all five notifications persisted after restart",
    )
    await pipeline.assert_queue_empty(pipeline.names.notification_queue, settle=0.75)
    pipeline.raise_if_task_failed()

    event_ids = await notification_event_ids(order_id)
    assert len(set(event_ids)) == 5  # no repeated effects for any copy
    assert {f"evt_shutdown_{i}" for i in range(5)} <= set(event_ids)


async def test_commit_without_ack_redelivery_produces_no_repeated_effects(
    pipeline, async_client, customer_token
):
    """The exact crash window 'transaction committed, ACK never sent': the
    broker requeues the copy, the restarted worker sees the committed marker
    and no-ops — one payment, no extra history, no crash loop."""
    order_id = await place_order(async_client, customer_token)  # dispatcher off

    created = await fetch_outbox_payload(order_id, ORDER_CREATED)
    await pipeline.publish_to_queue(pipeline.names.payment_queue, created)

    # Act as the crashed worker: receive WITHOUT acking, commit the effects.
    channel = await pipeline.connection.channel()
    queue = await channel.declare_queue(pipeline.names.payment_queue, durable=True)
    message = await queue.get(no_ack=False, timeout=10)
    assert message is not None
    envelope = parse_envelope(message.body)
    assert envelope.event_id == created["event_id"]

    outcome = await _run_transaction("payment", envelope, process_payment)
    assert outcome.result == "applied"

    # Crash: no ACK. Closing the channel makes the broker requeue the copy.
    await channel.close()

    # Effects are committed already: PAID exactly once, marker present.
    order = await get_order_row(order_id)
    assert order.status == "PAID" and order.version == 2
    rows = await order_rows(order_id)
    assert len(rows["payments"]) == 1
    payment_markers = [m for m in rows["processed"] if m.consumer_name == "payment"]
    assert len(payment_markers) == 1

    # "Restart": a real consumer consumes the redelivered copy -> no-op + ack.
    pipeline.start_consumers("payment")
    await pipeline.assert_queue_empty(pipeline.names.payment_queue, settle=1.0)
    pipeline.raise_if_task_failed()

    rows = await order_rows(order_id)
    assert len(rows["payments"]) == 1  # STILL one payment after redelivery
    assert [h.version for h in rows["history"]] == [1, 2]  # no repeat, no advance
    payment_markers = [m for m in rows["processed"] if m.consumer_name == "payment"]
    assert len(payment_markers) == 1  # dedup marker untouched
    order = await get_order_row(order_id)
    assert order.status == "PAID" and order.version == 2

    # And the rest of the pipeline still runs from this state.
    pipeline.start_dispatcher()
    pipeline.start_consumers("restaurant")
    pipeline.start_consumers("delivery")
    pipeline.start_consumers("notification")
    await wait_for_status(order_id, "DRIVER_ASSIGNED")


async def notification_event_ids(order_id: str) -> list[str]:
    from sqlalchemy import select

    from app.db.models.notification import Notification
    from app.db.session import session_scope

    async with session_scope() as session:
        return [
            str(row)
            for row in (
                (
                    await session.execute(
                        select(Notification.event_id).where(Notification.order_id == order_id)
                    )
                ).scalars()
            )
        ]
