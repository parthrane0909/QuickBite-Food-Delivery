"""Delivery worker logic: `order.confirmed` -> CONFIRMED to DRIVER_ASSIGNED.

DRIVER_ASSIGNED is successful completion for this assignment (§6 — no physical
delivery). Exactly one `driver_assignments` row per order is enforced by the
UNIQUE(order_id) constraint; the driver comes deterministically from the
fictional seeded roster (stable hash of order id) so demos reproduce. Failure
mode DELIVERY_MODE=always_fail -> FAILED + order.failed with no assignment.
"""

from __future__ import annotations

import hashlib
import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.db.models.driver_assignment import DriverAssignment
from app.db.models.order import Order
from app.schemas.events import ORDER_DRIVER_ASSIGNED, ORDER_FAILED, EventEnvelope
from app.services import order_state_machine as sm
from app.services.processing import PreconditionNotMetError, ProcessOutcome
from app.services.transitions import emit_outbox_event, transition_order
from scripts.seed_demo import SEED_DRIVERS

FAILURE_CODE = "DRIVER_UNAVAILABLE"
FAILURE_REASON = (
    "No simulated driver could be assigned to this order "
    "(DELIVERY_MODE=always_fail). This is a permanent failure."
)


def select_driver(order_id: str) -> dict[str, str]:
    """Deterministic fictional driver for this order (no GPS/maps/real drivers)."""
    digest = hashlib.sha256(order_id.encode("utf-8")).hexdigest()
    return SEED_DRIVERS[int(digest[:12], 16) % len(SEED_DRIVERS)]


def simulate_delivery(mode: str) -> str:
    if mode in ("always_succeed", "crash_after_checkpoint"):
        return "assign"
    if mode == "always_fail":
        return "fail"
    raise RuntimeError(
        f"DELIVERY_MODE={mode!r} is not supported before Milestone 4; "
        "use always_succeed, always_fail or crash_after_checkpoint"
    )


async def process_delivery(
    session: AsyncSession, envelope: EventEnvelope, order: Order
) -> ProcessOutcome:
    if order.status in (sm.PENDING, sm.PAID):
        # order.confirmed arriving before the restaurant confirmed: disorder.
        raise PreconditionNotMetError(
            f"order {order.id} is {order.status}; order.confirmed requires CONFIRMED"
        )
    if order.status != sm.CONFIRMED:
        return ProcessOutcome("stale_noop")  # already assigned/terminal

    decision = simulate_delivery(get_settings().delivery_mode)
    if decision == "assign":
        driver = select_driver(order.id)
        session.add(
            DriverAssignment(
                id=f"assign_{uuid.uuid4().hex}",
                order_id=order.id,
                driver_id=driver["driver_id"],
                driver_name=driver["driver_name"],
            )
        )
        order.driver_id = driver["driver_id"]  # denormalized for owner/admin reads
        session.add(transition_order(order, sm.DRIVER_ASSIGNED, source="delivery"))
        emit_outbox_event(
            session,
            order,
            ORDER_DRIVER_ASSIGNED,
            correlation_id=envelope.correlation_id,
            causation_id=envelope.event_id,
        )
    else:
        session.add(
            transition_order(
                order,
                sm.FAILED,
                source="delivery",
                failure_code=FAILURE_CODE,
                failure_reason=FAILURE_REASON,
            )
        )
        emit_outbox_event(
            session,
            order,
            ORDER_FAILED,
            correlation_id=envelope.correlation_id,
            causation_id=envelope.event_id,
        )
    return ProcessOutcome("applied")
