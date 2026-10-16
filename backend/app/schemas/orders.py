"""Order/checkout schemas (assignment §7).

Money is ALWAYS integer minor units: `1250` means INR 12.50 with
`currency: "INR"`. The checkout request deliberately accepts no price, total
or customer field (`extra="forbid"`), so a client cannot influence
authoritative money or identity — such payloads are rejected with 422.

Documented input bounds: quantity 1..20 per line, at most 20 DISTINCT items
per order (duplicate lines are merged before the check), delivery address
1..500 characters after trimming, Idempotency-Key 1..128 characters.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.common import Page

OrderStatus = Literal[
    "PENDING",
    "PAID",
    "CONFIRMED",
    "DRIVER_ASSIGNED",
    "PAYMENT_FAILED",
    "FAILED",
]

# Same set as OrderStatus, used for the optional `status` query filter.
ORDER_STATUS_FILTER = OrderStatus

QUANTITY_MIN = 1
QUANTITY_MAX = 20
MAX_DISTINCT_ITEMS = 20
ADDRESS_MAX_LENGTH = 500
IDEMPOTENCY_KEY_MAX_LENGTH = 128

ACCEPTANCE_MESSAGE = "Order accepted for asynchronous processing."


class CheckoutItemIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    menu_item_id: str = Field(min_length=1, max_length=64)
    quantity: int = Field(ge=QUANTITY_MIN, le=QUANTITY_MAX)


class CheckoutRequest(BaseModel):
    """Only identity-independent inputs: prices/totals/customers are NEVER
    accepted here; `extra="forbid"` turns smuggling attempts into 422."""

    model_config = ConfigDict(extra="forbid")

    restaurant_id: str = Field(min_length=1, max_length=64)
    delivery_address: str = Field(min_length=1, max_length=ADDRESS_MAX_LENGTH)
    items: list[CheckoutItemIn] = Field(min_length=1, max_length=100)


class OrderAccepted(BaseModel):
    """202 acceptance body — stored verbatim and replayed on idempotent reuse
    even after the order's real status has advanced."""

    order_id: str
    status: Literal["PENDING"] = "PENDING"
    currency: str
    total_amount_minor: int = Field(ge=0)
    version: int = Field(ge=1)
    message: str = ACCEPTANCE_MESSAGE


class OrderItemOut(BaseModel):
    menu_item_id: str
    item_name: str
    price_amount_minor: int = Field(gt=0)
    currency: str
    quantity: int = Field(ge=QUANTITY_MIN, le=QUANTITY_MAX)
    line_total_minor: int = Field(gt=0)


class OrderSummary(BaseModel):
    id: str
    restaurant_id: str
    restaurant_name: str
    status: str
    currency: str
    total_amount_minor: int = Field(ge=0)
    version: int = Field(ge=1)
    failure_code: str | None = None
    created_at: datetime
    updated_at: datetime


class OrderDetail(OrderSummary):
    delivery_address: str
    failure_reason: str | None = None
    driver_id: str | None = None
    items: list[OrderItemOut]


class OrderHistoryEntry(BaseModel):
    version: int = Field(ge=1)
    status: str
    from_status: str | None = None
    failure_code: str | None = None
    source: str
    changed_at: datetime


class OrderPage(Page[OrderSummary]):
    pass


class OrderHistoryPage(Page[OrderHistoryEntry]):
    """Full timeline as one page — the state machine caps a history at seven
    entries (PENDING..DRIVER_ASSIGNED/failures), far below max page_size."""

    pass


class NotificationEntry(BaseModel):
    """One persisted in-app notification (owner/admin feed)."""

    id: str
    seq: int  # server-assigned monotonic feed order
    order_id: str
    type: str  # event type that produced it (assignment §9)
    message: str
    order_version: int | None = None  # ties the notice to a transition
    created_at: datetime


class NotificationPage(Page[NotificationEntry]):
    pass
