"""Notification worker isolation (assignment §10/§20).

Business processing must proceed WITHOUT the notification consumer (its queue
simply accrues a backlog), notifications must never change order status, and
stopping/restarting the notification consumer later must drain the backlog
exactly once — while the other three workers keep running untouched.
"""

from __future__ import annotations

from sqlalchemy import select

from app.db.models.notification import Notification
from app.db.session import session_scope
from app.schemas.events import (
    ORDER_CONFIRMED,
    ORDER_CREATED,
    ORDER_DRIVER_ASSIGNED,
    ORDER_PAID,
)
from tests.m3_harness import (
    get_order_row,
    order_rows,
    place_order,
    wait_for_eq,
    wait_for_status,
)

BUSINESS_STAGES = ("payment", "restaurant", "delivery")


async def _notification_count(order_id: str) -> int:
    from sqlalchemy import func

    async with session_scope() as session:
        result = await session.execute(
            select(func.count()).select_from(Notification).where(Notification.order_id == order_id)
        )
        return int(result.scalar_one())


async def test_notification_consumer_absence_never_blocks_the_chain(
    pipeline, async_client, customer_token
):
    """With NO notification worker: payment -> restaurant -> delivery complete
    to DRIVER_ASSIGNED, notifications stay at zero (no business side effects),
    the backlog waits in notification.queue — then a (re)started notification
    worker drains it exactly once, still without touching order status."""
    pipeline.start_dispatcher()
    for stage in BUSINESS_STAGES:
        pipeline.start_consumers(stage)

    # --- chain completes with the notification queue untouched ------------
    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "DRIVER_ASSIGNED")

    await wait_for_eq(
        lambda: pipeline.queue_depth(pipeline.names.notification_queue),
        4,
        timeout=15,
        message="notification backlog accrued while no consumer ran",
    )
    backlog_depth = await pipeline.queue_depth(pipeline.names.notification_queue)
    assert backlog_depth == 4  # created + paid + confirmed + driver.assigned

    rows = await order_rows(order_id)
    assert rows["notifications"] == []  # no worker -> no notifications
    order = await get_order_row(order_id)
    assert order.status == "DRIVER_ASSIGNED" and order.version == 4  # unaffected

    # --- restart the notification worker: backlog drains exactly once -----
    pipeline.start_consumers("notification")
    await wait_for_eq(
        lambda: _notification_count(order_id),
        4,
        timeout=20,
        message="backlog drained to four persisted notifications",
    )
    await pipeline.assert_queue_empty(pipeline.names.notification_queue, settle=0.75)
    pipeline.raise_if_task_failed()

    rows = await order_rows(order_id)
    assert sorted(n.type for n in rows["notifications"]) == sorted(
        [ORDER_CREATED, ORDER_PAID, ORDER_CONFIRMED, ORDER_DRIVER_ASSIGNED]
    )
    assert len({n.event_id for n in rows["notifications"]}) == 4  # exactly once
    assert [m.consumer_name for m in rows["processed"]].count("notification") == 4

    # Stopping the notification worker mid-run must not disturb the others:
    # a second order still reaches its business terminal state.
    pipeline.stop_consumer("notification")
    await pipeline.wait_consumer_stopped("notification")
    order_two = await place_order(async_client, customer_token)
    await wait_for_status(order_two, "DRIVER_ASSIGNED")
    rows_two = await order_rows(order_two)
    assert rows_two["notifications"] == []  # stopped worker stays stopped
    assert [h.version for h in rows_two["history"]] == [1, 2, 3, 4]

    # Reinstating it drains the second order's notifications too.
    pipeline.start_consumers("notification")
    await wait_for_eq(
        lambda: _notification_count(order_two),
        4,
        timeout=20,
        message="second order's notifications drained after restart",
    )
