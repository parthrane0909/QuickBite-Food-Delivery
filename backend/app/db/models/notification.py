"""Persisted customer notifications — durable, deduplicated per (customer, event).

Notifications NEVER change order business status. `seq` provides a stable
total order for display; `order_version` ties a notification to the state
transition it describes so timelines stay consistent under redelivery.
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import BigInteger, DateTime, ForeignKey, Identity, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


def _utcnow() -> datetime:
    return datetime.now(UTC)


class Notification(Base):
    __tablename__ = "notifications"
    __table_args__ = (
        # Unique (customer_id, event_id); convention names it uq_notifications_customer_id.
        UniqueConstraint("customer_id", "event_id"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    # Server-generated monotonic value for stable feed ordering.
    seq: Mapped[int] = mapped_column(BigInteger, Identity(), nullable=False)
    customer_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    order_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("orders.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    event_id: Mapped[str] = mapped_column(String(64), nullable=False)
    type: Mapped[str] = mapped_column(String(64), nullable=False)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    order_version: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )
