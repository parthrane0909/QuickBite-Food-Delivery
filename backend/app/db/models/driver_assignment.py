"""Driver assignment — at most one row per order (UNIQUE order_id).

Drivers are fictional, seeded by the demo/seed configuration; there is no
separate drivers table because assignments are the only place driver identity
is needed (documented in docs/data-model.md). No GPS/map data exists.
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


def _utcnow() -> datetime:
    return datetime.now(UTC)


class DriverAssignment(Base):
    __tablename__ = "driver_assignments"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    order_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("orders.id", ondelete="RESTRICT"), nullable=False, unique=True
    )
    driver_id: Mapped[str] = mapped_column(String(64), nullable=False)
    driver_name: Mapped[str] = mapped_column(String(120), nullable=False)
    assigned_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )
