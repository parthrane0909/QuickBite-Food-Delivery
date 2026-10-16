"""Domain event envelope (assignment §9) — the single wire contract shared by
the outbox dispatcher (M3) and all workers.

Every event carries immutable identity: `event_id` doubles as the AMQP
message_id and the downstream idempotency identifier, and is retained across
redeliveries and retries (retry attempts are delivery metadata, never a new
event identity). `schema_version` lets receivers quarantine unknown versions
instead of guessing. Child events inherit `correlation_id` and set
`causation_id` to the incoming event's `event_id`.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

# Schema version of the v2.0 event contract. Bump ONLY for breaking changes;
# unknown versions are quarantined by consumers rather than retried forever.
SCHEMA_VERSION = 1

# Required event types (assignment §9).
ORDER_CREATED = "order.created"
ORDER_PAID = "order.paid"
ORDER_PAYMENT_FAILED = "order.payment.failed"
ORDER_CONFIRMED = "order.confirmed"
ORDER_DRIVER_ASSIGNED = "order.driver.assigned"
ORDER_FAILED = "order.failed"

EVENT_TYPES = (
    ORDER_CREATED,
    ORDER_PAID,
    ORDER_PAYMENT_FAILED,
    ORDER_CONFIRMED,
    ORDER_DRIVER_ASSIGNED,
    ORDER_FAILED,
)

EventType = Literal[
    ORDER_CREATED,
    ORDER_PAID,
    ORDER_PAYMENT_FAILED,
    ORDER_CONFIRMED,
    ORDER_DRIVER_ASSIGNED,
    ORDER_FAILED,
]


class EventEnvelope(BaseModel):
    """Immutable, PII-free event envelope; `data` is the domain payload."""

    model_config = ConfigDict(frozen=True)

    event_id: str = Field(min_length=1, max_length=64)
    schema_version: int = Field(ge=1)
    event_type: EventType
    order_id: str = Field(min_length=1, max_length=64)
    order_version: int = Field(ge=1)
    occurred_at: datetime  # timezone-aware, always UTC
    correlation_id: str = Field(min_length=1, max_length=64)
    causation_id: str | None = None
    data: dict[str, Any]

    def to_payload(self) -> dict[str, Any]:
        """JSON-safe dict stored verbatim in `outbox_events.payload` and
        published as the AMQP body by the dispatcher."""
        return self.model_dump(mode="json")
