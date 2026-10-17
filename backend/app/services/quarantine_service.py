"""Durable quarantine + terminal failure paths (assignment §11, M4 §5/§6).

Everything here runs inside the CALLER's transaction and commits BEFORE the
source message is acknowledged:

- `quarantine_event` / `quarantine_malformed` persist ONE logical
  quarantine record (UNIQUE consumer_name, event_id — duplicates are no-ops)
  together with its transactional outbox publication to the dead exchange
  (`quickbite.dead`, routing key `failed` -> orders.dead-letter.queue).
  The dispatcher publishes it with confirms + mandatory routing like every
  other outbox row — RabbitMQ's built-in dead-letter behaviour is never the
  only copy of a failed message.
- `apply_exhaustion_terminal` applies the consumer's terminal order state on
  retry exhaustion, STATE-GUARDED so a stale event can never move an order
  backwards: payment PENDING->PAYMENT_FAILED (+ order.payment.failed),
  restaurant PAID->FAILED, delivery CONFIRMED->FAILED (+ order.failed).
  Notifications NEVER touch order business state (§10) — their exhaustion is
  recorded and quarantined only.
"""

from __future__ import annotations

import hashlib
import json
import uuid
from dataclasses import dataclass

from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.order import Order
from app.db.models.simulated_payment import SimulatedPayment
from app.messaging.topology import DEAD_EXCHANGE, DEAD_ROUTING_KEY
from app.repositories import messaging as messaging_repo
from app.schemas.events import ORDER_FAILED, ORDER_PAYMENT_FAILED, EventEnvelope
from app.services import order_state_machine as sm
from app.services.transitions import emit_outbox_event, transition_order

# Terminal failure codes persisted on exhaustion (per consumer).
EXHAUSTION_CODES = {
    "payment": "PAYMENT_RETRIES_EXHAUSTED",
    "restaurant": "RESTAURANT_RETRIES_EXHAUSTED",
    "delivery": "DELIVERY_RETRIES_EXHAUSTED",
    "notification": "NOTIFICATION_RETRIES_EXHAUSTED",
}

# consumer -> (required current status, terminal target, terminal event)
_TERMINAL_TARGETS = {
    "payment": (sm.PENDING, sm.PAYMENT_FAILED, ORDER_PAYMENT_FAILED),
    "restaurant": (sm.PAID, sm.FAILED, ORDER_FAILED),
    "delivery": (sm.CONFIRMED, sm.FAILED, ORDER_FAILED),
}


@dataclass(frozen=True)
class QuarantineOutcome:
    quarantine_id: str | None  # None -> already quarantined (duplicate copy)
    published: bool  # the dead-exchange outbox row exists after this call
    duplicate: bool


@dataclass(frozen=True)
class ExhaustionOutcome:
    transitioned: bool
    failure_code: str
    failure_reason: str


def _dead_outbox_id(event_id: str) -> str:
    # Deterministic so repeated/racing quarantines reference the SAME row.
    return f"out_qtn_{event_id[:40]}"


async def _record_quarantine(
    session: AsyncSession,
    *,
    consumer_name: str,
    queue_name: str,
    event_id: str,
    event_type: str,
    order_id: str | None,
    attempts: int,
    failure_code: str,
    reason: str,
    envelope_payload: dict,
) -> QuarantineOutcome:
    outbox_id = _dead_outbox_id(event_id)
    published = await messaging_repo.insert_dead_publication(
        session,
        outbox_id=outbox_id,
        event_id=event_id,
        event_type=event_type,
        order_id=order_id,
        exchange=DEAD_EXCHANGE,
        routing_key=DEAD_ROUTING_KEY,
        payload=envelope_payload,
    )
    inserted = await messaging_repo.insert_quarantine(
        session,
        record_id=f"qtn_{uuid.uuid4().hex}",
        event_id=event_id,
        consumer_name=consumer_name,
        queue_name=queue_name,
        attempts=attempts,
        failure_code=failure_code,
        reason=reason,
        envelope_payload=envelope_payload,
        order_id=order_id,
        outbox_event_id=outbox_id,
    )
    return QuarantineOutcome(
        quarantine_id=None if not inserted else outbox_id,
        published=published,
        duplicate=not inserted,
    )


async def quarantine_event(
    session: AsyncSession,
    *,
    consumer_name: str,
    queue_name: str,
    envelope: EventEnvelope,
    envelope_payload: dict,
    attempts: int,
    failure_code: str,
    reason: str,
) -> QuarantineOutcome:
    """Quarantine a PARSEABLE event (retry exhaustion, unknown future event
    type at a business consumer, ...). Never mutates any order row."""
    return await _record_quarantine(
        session,
        consumer_name=consumer_name,
        queue_name=queue_name,
        event_id=envelope.event_id,
        event_type=envelope.event_type,
        order_id=envelope.order_id,
        attempts=attempts,
        failure_code=failure_code,
        reason=reason,
        envelope_payload=envelope_payload,
    )


async def quarantine_raw_event(
    session: AsyncSession,
    *,
    consumer_name: str,
    queue_name: str,
    raw_payload: dict,
    attempts: int,
    failure_code: str,
    reason: str,
) -> QuarantineOutcome:
    """Quarantine PARSEABLE JSON whose `event_type` is not part of schema v1
    (an unknown future business event at a non-notification consumer). The
    payload is preserved verbatim; identity falls back to a payload digest
    when the envelope is missing one, and NO order row is ever touched."""
    canonical = json.dumps(raw_payload, sort_keys=True, default=str).encode()
    event_id_raw = raw_payload.get("event_id")
    event_id = (
        event_id_raw
        if isinstance(event_id_raw, str) and event_id_raw
        else f"undecoded_{hashlib.sha256(canonical).hexdigest()[:32]}"
    )
    order_id_raw = raw_payload.get("order_id")
    order_id = order_id_raw if isinstance(order_id_raw, str) and order_id_raw else None
    event_type_raw = raw_payload.get("event_type")
    event_type = event_type_raw if isinstance(event_type_raw, str) and event_type_raw else "unknown"
    return await _record_quarantine(
        session,
        consumer_name=consumer_name,
        queue_name=queue_name,
        event_id=event_id,
        event_type=event_type,
        order_id=order_id,
        attempts=attempts,
        failure_code=failure_code,
        reason=reason,
        envelope_payload=raw_payload,
    )


async def quarantine_malformed(
    session: AsyncSession,
    *,
    consumer_name: str,
    queue_name: str,
    raw_body: bytes,
    failure_code: str,
    reason: str,
) -> QuarantineOutcome:
    """Quarantine a MALFORMED message. No valid order reference is required
    and NO order row is ever read or modified. The logical identity is a
    deterministic digest of the raw bytes — the AMQP message_id can never be
    one: aiormq (and RabbitMQ itself when the publisher omits it) generates a
    UNIQUE message_id per delivery, so repeated copies of the same malformed
    bytes would each become their own quarantine record instead of one."""
    decoded = raw_body.decode("utf-8", errors="replace")[:2000]
    event_id = f"undecoded_{hashlib.sha256(raw_body).hexdigest()[:32]}"
    return await _record_quarantine(
        session,
        consumer_name=consumer_name,
        queue_name=queue_name,
        event_id=event_id,
        event_type="malformed",
        order_id=None,
        attempts=1,
        failure_code=failure_code,
        reason=reason,
        # The dead-lettered copy is self-describing: classification + reason
        # travel WITH the payload (assignment §6 inspection requirement).
        envelope_payload={
            "event_id": event_id,
            "malformed": True,
            "failure_code": failure_code,
            "reason": reason[:1000],
            "body": decoded,
        },
    )


async def apply_exhaustion_terminal(
    session: AsyncSession,
    *,
    consumer_name: str,
    envelope: EventEnvelope,
    order: Order | None,
) -> ExhaustionOutcome:
    """Terminal order state for a consumer that exhausted its bounded retries
    (assignment §11). The transition only applies when the CURRENT status
    permits it — a stale/exhausted event can never regress an order; then it
    is quarantined without a transition instead."""
    code = EXHAUSTION_CODES[consumer_name]
    if consumer_name == "notification":
        return ExhaustionOutcome(
            transitioned=False,
            failure_code=code,
            failure_reason=(
                "Notification delivery failed through every configured retry "
                "attempt and was quarantined. Order business status is "
                "deliberately unaffected."
            ),
        )
    required, target, event_type = _TERMINAL_TARGETS[consumer_name]
    if order is None:
        return ExhaustionOutcome(
            transitioned=False,
            failure_code=code,
            failure_reason="Event references an order that does not exist; quarantined only.",
        )
    if order.status != required:
        return ExhaustionOutcome(
            transitioned=False,
            failure_code=code,
            failure_reason=(
                f"Order is {order.status}; the {required}->{target} terminal "
                "transition no longer applies. Quarantined without a transition."
            ),
        )
    reason = (
        f"{consumer_name.capitalize()} processing failed through every configured "
        f"retry attempt (RETRY_DELAYS_SECONDS); the order is terminally {target} "
        f"and the event is quarantined. ({code})"
    )
    if consumer_name == "payment":
        # Exactly one durable simulated-payment record for this order (UNIQUE
        # per order): the payment never succeeded and never will.
        session.add(
            SimulatedPayment(
                id=f"pay_rec_{uuid.uuid4().hex}",
                order_id=order.id,
                payment_reference=f"pay_{order.id}",
                status="FAILED",
                amount_minor=order.total_amount_minor,
                currency=order.currency,
                failure_code=code,
                failure_detail=reason,
            )
        )
    session.add(
        transition_order(
            order,
            target,
            source=consumer_name,
            failure_code=code,
            failure_reason=reason,
        )
    )
    emit_outbox_event(
        session,
        order,
        event_type,
        correlation_id=envelope.correlation_id,
        causation_id=envelope.event_id,
    )
    return ExhaustionOutcome(transitioned=True, failure_code=code, failure_reason=reason)
