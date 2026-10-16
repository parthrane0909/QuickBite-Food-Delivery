"""Simulated payment effect — at most one row per order (UNIQUE order_id).

The payment reference is derived from the order id, so retries of the same
logical payment can never create a second charge record (assignment §10:
payment simulation uses an order-based idempotency identifier).
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


def _utcnow() -> datetime:
    return datetime.now(UTC)


class SimulatedPayment(Base):
    __tablename__ = "simulated_payments"
    __table_args__ = (
        CheckConstraint("status IN ('SUCCEEDED','FAILED')", name="status"),
        CheckConstraint("amount_minor >= 0", name="amount_non_negative"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    order_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("orders.id", ondelete="RESTRICT"), nullable=False, unique=True
    )
    payment_reference: Mapped[str] = mapped_column(String(80), nullable=False, unique=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    # Amount of the order total this payment attempt was for (attempted even
    # when the simulated charge failed, for auditability).
    amount_minor: Mapped[int] = mapped_column(Integer, nullable=False)
    currency: Mapped[str | None] = mapped_column(String(3), nullable=True)
    failure_code: Mapped[str | None] = mapped_column(String(64), nullable=True)
    failure_detail: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )
