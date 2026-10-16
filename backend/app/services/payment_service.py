"""Payment worker logic: `order.created` -> PENDING to PAID / PAYMENT_FAILED.

Deterministic, environment-selected simulation (assignment §12; never
selectable from checkout): `always_succeed` and `always_fail` are supported in
Milestone 3, `crash_after_checkpoint` runs the success path and lets the
consumer crash between commit and ACK (redelivery then no-ops via dedup).
`fail_twice` needs the Milestone 4 retry scheduler and is rejected at worker
startup rather than half-implemented here.

One transaction produces: the simulated payment record (UNIQUE per order),
the transition + exactly one history row, the child `order.paid`/
`order.payment.failed` outbox event, and the processed-event marker (runtime).
"""

from __future__ import annotations

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.db.models.order import Order
from app.db.models.simulated_payment import SimulatedPayment
from app.schemas.events import ORDER_PAID, ORDER_PAYMENT_FAILED, EventEnvelope
from app.services import order_state_machine as sm
from app.services.processing import ProcessOutcome
from app.services.transitions import emit_outbox_event, transition_order

FAILURE_CODE = "PAYMENT_DECLINED"
FAILURE_REASON = (
    "The simulated payment provider declined this payment "
    "(PAYMENT_MODE=always_fail). No real charge was attempted."
)


def simulate_payment(mode: str) -> tuple[str, str | None, str | None]:
    """mode -> (status, failure_code, failure_detail)."""
    if mode == "always_succeed":
        return "SUCCEEDED", None, None
    if mode == "always_fail":
        return "FAILED", FAILURE_CODE, FAILURE_REASON
    if mode == "crash_after_checkpoint":
        # Success path; the consumer crashes AFTER commit, BEFORE ack.
        return "SUCCEEDED", None, None
    # fail_twice and anything else requires Milestone 4 retries (startup-validates).
    raise RuntimeError(
        f"PAYMENT_MODE={mode!r} is not supported before Milestone 4; "
        "use always_succeed, always_fail or crash_after_checkpoint"
    )


async def process_payment(
    session: AsyncSession, envelope: EventEnvelope, order: Order
) -> ProcessOutcome:
    if order.status != sm.PENDING:
        # Payment already resolved (or order further along): safe no-op.
        return ProcessOutcome("stale_noop")

    mode = get_settings().payment_mode
    status, failure_code, failure_detail = simulate_payment(mode)

    session.add(
        SimulatedPayment(
            id=f"pay_rec_{uuid.uuid4().hex}",
            order_id=order.id,
            # Order-derived reference: retries can never charge twice (§10).
            payment_reference=f"pay_{order.id}",
            status=status,
            amount_minor=order.total_amount_minor,
            currency=order.currency,
            failure_code=failure_code,
            failure_detail=failure_detail,
        )
    )

    if status == "SUCCEEDED":
        session.add(transition_order(order, sm.PAID, source="payment"))
        emit_outbox_event(
            session,
            order,
            ORDER_PAID,
            correlation_id=envelope.correlation_id,
            causation_id=envelope.event_id,
        )
    else:
        session.add(
            transition_order(
                order,
                sm.PAYMENT_FAILED,
                source="payment",
                failure_code=failure_code,
                failure_reason=failure_detail,
            )
        )
        emit_outbox_event(
            session,
            order,
            ORDER_PAYMENT_FAILED,
            correlation_id=envelope.correlation_id,
            causation_id=envelope.event_id,
        )
    return ProcessOutcome("applied")
