"""Consumer deduplication markers — UNIQUE (consumer_name, event_id).

consumer_name is the LOGICAL worker type (payment/restaurant/delivery/
notification), never a process instance hostname, so competing replicas and
redeliveries share one dedup key. A committed marker means the business
effect is committed; redelivery after a commit-before-ack crash no-ops.
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import DateTime, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


def _utcnow() -> datetime:
    return datetime.now(UTC)


class ProcessedEvent(Base):
    __tablename__ = "processed_events"
    __table_args__ = (
        # Unique (consumer_name, event_id).
        UniqueConstraint("consumer_name", "event_id"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    consumer_name: Mapped[str] = mapped_column(String(32), nullable=False)
    event_id: Mapped[str] = mapped_column(String(64), nullable=False)
    # Raw string on purpose: malformed events may reference unknown orders.
    order_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    outcome: Mapped[str] = mapped_column(String(16), nullable=False, default="PROCESSED")
    processed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )
