"""Concurrency and ordering safety (assignment §10/§20).

- Competing replicas of the SAME logical consumer (scale-out pattern) racing
  on duplicate copies must apply each event exactly once — row lock + unique
  marker, no double payments/assignments/transitions.
- Disordered delivery (event arriving BEFORE its prerequisite state) must
  never regress or silently lose a transition: bounded deferred retry, then
  dead-letter, and the pipeline keeps working afterwards.
"""

from __future__ import annotations

from sqlalchemy import select

from app.db.models.processed_event import ProcessedEvent
from app.db.session import session_scope
from app.schemas.events import ORDER_CREATED, ORDER_PAID
from tests.m3_harness import (
    build_envelope,
    fetch_outbox_payload,
    get_order_row,
    order_rows,
    place_order,
    wait_for_status,
)


async def test_competing_consumer_replicas_apply_each_event_once(
    pipeline, async_client, customer_token
):
    """2 payment + 2 restaurant + 2 delivery replicas (the documented
    scale-out mode) receive duplicate copies of the SAME events concurrently:
    the outcome must still be exactly one payment/assignment and one history
    row per version."""
    for stage, instances in (
        ("payment", 2),
        ("restaurant", 2),
        ("delivery", 2),
        ("notification", 1),
    ):
        pipeline.start_consumers(stage, instances=instances)

    order_id = await place_order(async_client, customer_token)
    created = await fetch_outbox_payload(order_id, ORDER_CREATED)

    # Queue a duplicate copy FIRST, then let the dispatcher publish the
    # original: two replicas race on two copies of one logical event.
    await pipeline.publish_to_queue(pipeline.names.payment_queue, created)
    pipeline.start_dispatcher()

    await wait_for_status(order_id, "DRIVER_ASSIGNED")
    await pipeline.assert_queue_empty(pipeline.names.payment_queue, settle=0.75)
    await pipeline.assert_queue_empty(pipeline.names.restaurant_queue, settle=0.75)
    await pipeline.assert_queue_empty(pipeline.names.delivery_queue, settle=0.75)
    pipeline.raise_if_task_failed()

    rows = await order_rows(order_id)
    assert len(rows["payments"]) == 1  # racing duplicate -> one payment
    assert len(rows["assignments"]) == 1
    assert [h.version for h in rows["history"]] == [1, 2, 3, 4]
    order = await get_order_row(order_id)
    assert order.status == "DRIVER_ASSIGNED" and order.version == 4

    # One marker for the shared event_id regardless of which replica won.
    async with session_scope() as session:
        payment_markers = list(
            (
                await session.execute(
                    select(ProcessedEvent).where(
                        ProcessedEvent.order_id == order_id,
                        ProcessedEvent.consumer_name == "payment",
                    )
                )
            ).scalars()
        )
    assert len(payment_markers) == 1


async def test_disordered_event_is_dead_lettered_without_losing_work(
    pipeline, async_client, customer_token
):
    """order.paid arriving while the order is still PENDING (unexpected
    disorder): bounded deferred retry, then dead-letter + ACK — no backward
    transition, no wedge, and the REAL chain still completes afterwards."""
    # Short defer cycles so the bounded retry is observable in test time.
    pipeline.start_consumers("restaurant", precondition_delays=(0.1,))

    order_id = await place_order(async_client, customer_token)  # PENDING
    early_paid = build_envelope(ORDER_PAID, order_id, 2)
    await pipeline.publish_to_queue(pipeline.names.restaurant_queue, early_paid)

    # The event ends up on the dead-letter queue (retry budget exhausted).
    dead = await pipeline.drain_queue(pipeline.names.dead_queue)
    assert len(dead) == 1
    assert dead[0]["event_type"] == ORDER_PAID
    assert dead[0]["event_id"] == early_paid["event_id"]

    # No lost/backward transition: the order never left PENDING, no marker
    # was written for a transaction that did not commit.
    order = await get_order_row(order_id)
    assert order.status == "PENDING" and order.version == 1
    rows = await order_rows(order_id)
    assert [h.version for h in rows["history"]] == [1]
    assert rows["processed"] == []

    # The poison copy is gone (ACKed from the main queue) ...
    await pipeline.assert_queue_empty(pipeline.names.restaurant_queue, settle=0.5)
    # ... and the pipeline is not wedged: run the real chain to completion.
    pipeline.start_dispatcher()
    pipeline.start_consumers("payment")
    pipeline.start_consumers("delivery")
    pipeline.start_consumers("notification")
    await wait_for_status(order_id, "DRIVER_ASSIGNED")
    pipeline.raise_if_task_failed()

    rows = await order_rows(order_id)
    assert [h.version for h in rows["history"]] == [1, 2, 3, 4]
    assert len(rows["payments"]) == 1 and len(rows["assignments"]) == 1
    # We already drained (consumed) the one dead-lettered copy above, and the
    # real chain dead-lettered NOTHING: the queue must still be empty.
    assert await pipeline.queue_depth(pipeline.names.dead_queue) == 0


async def test_precondition_defer_retries_until_state_catches_up(
    pipeline, async_client, customer_token
):
    """A disordered event that RESOLVES itself during the bounded defer window
    is processed (not dead-lettered): order.paid injected while the order is
    PENDING; payment settles during the defer; restaurant then confirms."""
    # Restaurant alone first, with generous defer cycles.
    pipeline.start_consumers("restaurant", precondition_delays=(0.5, 1.0, 2.0))

    order_id = await place_order(async_client, customer_token)  # PENDING, no dispatcher
    early_paid = build_envelope(ORDER_PAID, order_id, 2)
    await pipeline.publish_to_queue(pipeline.names.restaurant_queue, early_paid)

    # During the defer window the real chain settles the prerequisite state.
    pipeline.start_dispatcher()
    pipeline.start_consumers("payment")
    pipeline.start_consumers("delivery")
    pipeline.start_consumers("notification")

    await wait_for_status(order_id, "DRIVER_ASSIGNED")
    await pipeline.assert_queue_empty(pipeline.names.restaurant_queue, settle=0.75)
    await pipeline.assert_queue_empty(pipeline.names.dead_queue, settle=0.75)
    pipeline.raise_if_task_failed()

    rows = await order_rows(order_id)
    assert [h.version for h in rows["history"]] == [1, 2, 3, 4]
    assert len(rows["payments"]) == 1 and len(rows["assignments"]) == 1
    # Dead-letter queue stayed EMPTY: the resolved disorder was processed.
    assert await pipeline.queue_depth(pipeline.names.dead_queue) == 0
    # The deferred event got a committed marker (its transition committed
    # once the prerequisite arrived) — no silent loss.
    async with session_scope() as session:
        restaurant_markers = list(
            (
                await session.execute(
                    select(ProcessedEvent).where(
                        ProcessedEvent.order_id == order_id,
                        ProcessedEvent.consumer_name == "restaurant",
                    )
                )
            ).scalars()
        )
    assert any(m.event_id == early_paid["event_id"] for m in restaurant_markers)
