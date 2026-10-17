"""Admin read-only schemas (assignment §7/§14 admin overview; milestone
agreement: admin endpoints delivered in Milestone 5).

Both responses reuse the standard pagination envelope and the ORDER VIEW
contract so clients share one order shape. The cross-customer list adds
exactly one field, `customer_email` — the minimum needed to identify whose
order an admin is inspecting. No payment details, no secrets, no mutations:
these endpoints are GET-only by design.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.common import Page
from app.schemas.orders import (
    OrderSummary,
)

# The complete status set. Summary responses always include every key with a
# count (zero included) so dashboards never have to guess missing states.
ALL_ORDER_STATUSES: tuple[str, ...] = (
    "PENDING",
    "PAID",
    "CONFIRMED",
    "DRIVER_ASSIGNED",
    "PAYMENT_FAILED",
    "FAILED",
)


class AdminOrderItem(OrderSummary):
    """One cross-customer order row: the standard order summary plus the
    ordering customer's email (admin-only field; never exposed to customers)."""

    customer_email: str


class AdminOrderPage(Page[AdminOrderItem]):
    pass


class AdminSummary(BaseModel):
    """Aggregate operational counts from authoritative PostgreSQL state.

    Counting semantics (documented in docs/api.md):
    - orders_by_status: COUNT(*) of the orders table grouped by status; every
      status appears (0 included).
    - pending_outbox_events: outbox rows not yet confirmed published
      (state IN ('PENDING','CLAIMED')) — includes leased in-flight rows and
      crash-orphaned leases still awaiting redelivery.
    - retry_backlog: retry_jobs rows still scheduled (state='PENDING') —
      attempts neither published nor exhausted.
    - quarantine_records: total terminally failed deliveries on record.
    """

    orders_by_status: dict[str, int] = Field(
        description="Order counts keyed by every order status (0 included)."
    )
    pending_outbox_events: int = Field(ge=0)
    retry_backlog: int = Field(ge=0)
    quarantine_records: int = Field(ge=0)
    generated_at: datetime
