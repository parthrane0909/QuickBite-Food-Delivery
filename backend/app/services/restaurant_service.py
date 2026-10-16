"""Restaurant worker logic: `order.paid` -> PAID to CONFIRMED / FAILED.

Deterministic simulation via RESTAURANT_MODE (always_succeed,
always_fail = unrecoverable restaurant rejection -> FAILED + order.failed,
crash_after_checkpoint = success path with a commit-before-ack crash).
`fail_twice` is rejected at startup until Milestone 4.
"""

from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.db.models.order import Order
from app.schemas.events import ORDER_CONFIRMED, ORDER_FAILED, EventEnvelope
from app.services import order_state_machine as sm
from app.services.processing import PreconditionNotMetError, ProcessOutcome
from app.services.transitions import emit_outbox_event, transition_order

FAILURE_CODE = "RESTAURANT_REJECTED"
FAILURE_REASON = (
    "The restaurant could not accept this order "
    "(RESTAURANT_MODE=always_fail). This is a permanent failure."
)


def simulate_restaurant(mode: str) -> str:
    if mode in ("always_succeed", "crash_after_checkpoint"):
        return "accept"
    if mode == "always_fail":
        return "reject"
    raise RuntimeError(
        f"RESTAURANT_MODE={mode!r} is not supported before Milestone 4; "
        "use always_succeed, always_fail or crash_after_checkpoint"
    )


async def process_restaurant(
    session: AsyncSession, envelope: EventEnvelope, order: Order
) -> ProcessOutcome:
    if order.status == sm.PENDING:
        # order.paid arriving before payment settled: unexpected disorder.
        raise PreconditionNotMetError(
            f"order {order.id} is {order.status}; order.paid requires PAID"
        )
    if order.status != sm.PAID:
        return ProcessOutcome("stale_noop")  # already confirmed/further/terminal

    decision = simulate_restaurant(get_settings().restaurant_mode)
    if decision == "accept":
        session.add(transition_order(order, sm.CONFIRMED, source="restaurant"))
        emit_outbox_event(
            session,
            order,
            ORDER_CONFIRMED,
            correlation_id=envelope.correlation_id,
            causation_id=envelope.event_id,
        )
    else:
        session.add(
            transition_order(
                order,
                sm.FAILED,
                source="restaurant",
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
