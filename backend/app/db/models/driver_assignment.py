"""Driver assignment — at most one row per order (UNIQUE order_id).

Drivers are fictional, seeded into a small persistent roster; assignments
retain a name snapshot for historical display. No GPS/map data exists.
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
    driver_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("drivers.id", ondelete="RESTRICT"), nullable=False
    )
    driver_name: Mapped[str] = mapped_column(String(120), nullable=False)
    assigned_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )
