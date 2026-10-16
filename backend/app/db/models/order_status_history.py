"""Append-only order status history, one row per (order, version).

History rows are never updated or deleted. `order_version` gives every
timeline a stable, total ordering even when events arrive out of order.
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


def _utcnow() -> datetime:
    return datetime.now(UTC)


class OrderStatusHistory(Base):
    __tablename__ = "order_status_history"
    __table_args__ = (
        # Unique (order_id, version): history is append-only, one row per version.
        UniqueConstraint("order_id", "version"),
        CheckConstraint("version >= 1", name="version_positive"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    order_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("orders.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[str] = mapped_column(String(24), nullable=False)
    from_status: Mapped[str | None] = mapped_column(String(24), nullable=True)
    failure_code: Mapped[str | None] = mapped_column(String(64), nullable=True)
    # Which component produced the transition (checkout, payment, restaurant,
    # delivery, quarantine). Never an instance hostname.
    source: Mapped[str] = mapped_column(String(32), nullable=False)
    changed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )
