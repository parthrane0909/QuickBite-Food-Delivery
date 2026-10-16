"""Order state application: the ONLY way workers move an order.

Every transition goes through the state machine (assignment §6), increments
`version`, and appends exactly one history row per (order_id, version) inside
the caller's transaction. Child events are emitted through the transactional
outbox here — never published inline.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.order import Order
from app.db.models.order_status_history import OrderStatusHistory
from app.db.models.outbox_event import OutboxEvent
from app.messaging.topology import ORDERS_EXCHANGE
from app.schemas.events import SCHEMA_VERSION, EventEnvelope, EventType
from app.services import order_state_machine as sm


def _new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex}"


def transition_order(
    order: Order,
    target: str,
    *,
    source: str,
    failure_code: str | None = None,
    failure_reason: str | None = None,
) -> OrderStatusHistory:
    """Illegal transitions raise IllegalTransitionError; the caller's whole
    transaction then rolls back (no partial effects)."""
    sm.ensure_transition(order.status, target)
    previous = order.status
    new_version = sm.next_version(order.version)

    order.status = target
    order.version = new_version
    order.failure_code = failure_code
    order.failure_reason = failure_reason

    return OrderStatusHistory(
        id=_new_id("hist"),
        order_id=order.id,
        version=new_version,
        status=target,
        from_status=previous,
        failure_code=failure_code,
        source=source,
    )


def emit_outbox_event(
    session: AsyncSession,
    order: Order,
    event_type: EventType,
    *,
    correlation_id: str,
    causation_id: str,
) -> OutboxEvent:
    """Queue a child domain event in `outbox_events` (same transaction as the
    transition). `data` carries identity only — workers query PostgreSQL for
    current state; no addresses or other personal data (§9)."""
    envelope = EventEnvelope(
        event_id=_new_id(f"evt_{event_type.split('.', 1)[1].replace('.', '_')}"),
        schema_version=SCHEMA_VERSION,
        event_type=event_type,
        order_id=order.id,
        order_version=order.version,
        occurred_at=datetime.now(UTC),
        correlation_id=correlation_id,
        causation_id=causation_id,
        data={"customer_id": order.customer_id, "restaurant_id": order.restaurant_id},
    )
    row = OutboxEvent(
        id=_new_id("out"),
        event_id=envelope.event_id,
        event_type=envelope.event_type,
        order_id=order.id,
        exchange=ORDERS_EXCHANGE,
        routing_key=event_type,
        payload=envelope.to_payload(),
        state="PENDING",
    )
    session.add(row)
    return row
