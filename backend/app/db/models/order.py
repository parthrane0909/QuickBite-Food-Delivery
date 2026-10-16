"""Orders: authoritative state, money in integer minor units, monotonic version.

Status machine (assignment §6):
    PENDING -> PAID -> CONFIRMED -> DRIVER_ASSIGNED   (success terminal)
    PENDING -> PAYMENT_FAILED                         (terminal)
    PAID -> FAILED | CONFIRMED -> FAILED              (terminal)
Applied transitions always increment `version` inside a locked transaction.
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base

ORDER_STATUSES = (
    "PENDING",
    "PAID",
    "CONFIRMED",
    "DRIVER_ASSIGNED",
    "PAYMENT_FAILED",
    "FAILED",
)


def _utcnow() -> datetime:
    return datetime.now(UTC)


class Order(Base):
    __tablename__ = "orders"
    __table_args__ = (
        CheckConstraint(
            "status IN ('PENDING','PAID','CONFIRMED','DRIVER_ASSIGNED','PAYMENT_FAILED','FAILED')",
            name="status",
        ),
        CheckConstraint("total_amount_minor >= 0", name="total_non_negative"),
        CheckConstraint("version >= 1", name="version_positive"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    customer_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    restaurant_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("restaurants.id", ondelete="RESTRICT"), nullable=False
    )
    delivery_address: Mapped[str] = mapped_column(Text, nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    total_amount_minor: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[str] = mapped_column(String(24), nullable=False, default="PENDING")
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    failure_code: Mapped[str | None] = mapped_column(String(64), nullable=True)
    failure_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Denormalized from driver_assignments for fast owner/admin reads.
    driver_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow, index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow, onupdate=_utcnow
    )
