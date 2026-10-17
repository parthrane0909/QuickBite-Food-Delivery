"""Notification worker logic: persist one customer notification per event.

Binds `order.#` (multi-segment: also receives `order.payment.failed` and
`order.driver.assigned`). Notifications NEVER touch order business status
(§10) — effects are the `notifications` row (UNIQUE (customer_id, event_id),
belt-and-braces with the runtime's processed-event marker) and the message is
rendered from current PostgreSQL state (no PII in events).

NOTIFICATION_MODE=always_fail (Milestone 4): a deterministic transient
failure on every attempt — rolled back, durably retried with the bounded
delay schedule, and on exhaustion QUARANTINED with the order's business
status deliberately unchanged (assignment §11).
"""

from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.db.models.driver_assignment import DriverAssignment
from app.db.models.notification import Notification
from app.db.models.order import Order
from app.db.models.restaurant import Restaurant
from app.schemas.events import (
    ORDER_CONFIRMED,
    ORDER_CREATED,
    ORDER_DRIVER_ASSIGNED,
    ORDER_FAILED,
    ORDER_PAID,
    ORDER_PAYMENT_FAILED,
    EventEnvelope,
)
from app.services.processing import ProcessOutcome, TransientProcessingError

_EVENT_TITLES = {
    ORDER_CREATED: "Order received",
    ORDER_PAID: "Payment accepted",
    ORDER_PAYMENT_FAILED: "Payment failed",
    ORDER_CONFIRMED: "Restaurant confirmed",
    ORDER_DRIVER_ASSIGNED: "Driver assigned",
    ORDER_FAILED: "Order failed",
}


async def render_message(session: AsyncSession, order: Order, event_type: str) -> str:
    """Readable, PII-light message derived from current DB state."""
    if event_type == ORDER_CREATED:
        restaurant = (
            await session.execute(
                select(Restaurant.name).where(Restaurant.id == order.restaurant_id)
            )
        ).scalar_one_or_none()
        return (
            f"Order {order.id} received — {restaurant or order.restaurant_id} will confirm shortly."
        )
    if event_type == ORDER_PAID:
        amount = f"{order.currency} {order.total_amount_minor / 100:.2f}"
        return f"Payment of {amount} accepted for order {order.id}."
    if event_type == ORDER_PAYMENT_FAILED:
        return f"Payment failed for order {order.id}: {order.failure_reason or 'payment declined.'}"
    if event_type == ORDER_CONFIRMED:
        restaurant = (
            await session.execute(
                select(Restaurant.name).where(Restaurant.id == order.restaurant_id)
            )
        ).scalar_one_or_none()
        return f"{restaurant or 'The restaurant'} confirmed order {order.id}."
    if event_type == ORDER_DRIVER_ASSIGNED:
        driver_name = (
            await session.execute(
                select(DriverAssignment.driver_name).where(DriverAssignment.order_id == order.id)
            )
        ).scalar_one_or_none()
        return f"Driver {driver_name or 'partner'} was assigned to order {order.id}."
    # ORDER_FAILED
    reason = order.failure_reason or "a permanent failure occurred."
    return f"Order {order.id} could not be completed: {reason}"


async def process_notification(
    session: AsyncSession, envelope: EventEnvelope, order: Order, attempt: int
) -> ProcessOutcome:
    del attempt  # notification has no attempt-sensitive simulation in Milestone 4
    if get_settings().notification_mode == "always_fail":
        # Deterministic transient failure BEFORE any write: the whole
        # transaction rolls back and the runtime durably retries; on
        # exhaustion the event is quarantined and the order's business
        # status is deliberately left untouched.
        raise TransientProcessingError(
            "simulated notification delivery error (NOTIFICATION_MODE=always_fail)"
        )
    session.add(
        Notification(
            id=f"notif_{uuid.uuid4().hex}",
            customer_id=order.customer_id,
            order_id=order.id,
            event_id=envelope.event_id,
            type=envelope.event_type,
            message=await render_message(session, order, envelope.event_type),
            order_version=envelope.order_version,
        )
    )
    # Deliberately NO order mutation: notification failures must never change
    # business status, and success never does either.
    return ProcessOutcome("applied")
