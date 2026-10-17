"""Payment worker logic: `order.created` -> PENDING to PAID / PAYMENT_FAILED.

Deterministic, environment-selected simulation (assignment §12; never
selectable from checkout):
- `always_succeed` / `crash_after_checkpoint`: success path (the latter lets
  the consumer crash between commit and ACK; redelivery no-ops via dedup).
- `always_decline`: PERMANENT business decline -> immediate terminal
  PAYMENT_FAILED (failure code PAYMENT_DECLINED) with NO retries — permanent
  declines may bypass the retry budget (assignment §11).
- `always_fail`: simulated provider/transient failure on EVERY attempt ->
  rolled back and durably retried (2s/10s/30s by default) until the bounded
  budget is exhausted -> terminal PAYMENT_FAILED (failure code
  PAYMENT_RETRIES_EXHAUSTED) + quarantine, via the shared runtime path.
- `fail_twice`: transient failures on delivery attempts 1 and 2, success on
  attempt 3 — the attempt number is read from durable retry_jobs state, so
  the outcome is identical across worker/broker restarts.

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
from app.services.processing import ProcessOutcome, TransientProcessingError
from app.services.transitions import emit_outbox_event, transition_order

FAILURE_CODE = "PAYMENT_DECLINED"
FAILURE_REASON = (
    "The simulated payment provider declined this payment "
    "(PAYMENT_MODE=always_decline). No real charge was attempted."
)


def simulate_payment(mode: str, attempt: int) -> str:
    """mode + durable attempt number -> 'succeeded' | 'decline' | raises a
    TransientProcessingError for deterministic provider/infrastructure
    failures (which the runtime durably retries with bounded delays)."""
    if mode in ("always_succeed", "crash_after_checkpoint"):
        return "succeeded"
    if mode == "always_decline":
        return "decline"
    if mode == "always_fail":
        raise TransientProcessingError(
            "simulated payment provider error (PAYMENT_MODE=always_fail)"
        )
    if mode == "fail_twice":
        if attempt <= 2:
            raise TransientProcessingError(
                f"simulated payment provider error (PAYMENT_MODE=fail_twice, attempt {attempt})"
            )
        return "succeeded"
    raise RuntimeError(
        f"PAYMENT_MODE={mode!r} is not supported; use always_succeed, "
        "always_decline, always_fail, fail_twice or crash_after_checkpoint"
    )


async def process_payment(
    session: AsyncSession, envelope: EventEnvelope, order: Order, attempt: int
) -> ProcessOutcome:
    if order.status != sm.PENDING:
        # Payment already resolved (or order further along): safe no-op.
        return ProcessOutcome("stale_noop")

    decision = simulate_payment(get_settings().payment_mode, attempt)
    if decision == "succeeded":
        status, failure_code, failure_detail = "SUCCEEDED", None, None
    else:  # permanent decline — bypasses the retry budget by design
        status, failure_code, failure_detail = "FAILED", FAILURE_CODE, FAILURE_REASON

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
