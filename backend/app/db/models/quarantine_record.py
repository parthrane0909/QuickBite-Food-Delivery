"""Quarantine records — inspectable history of terminally failed deliveries.

UNIQUE (consumer_name, event_id): a logically exhausted event is quarantined
exactly once no matter how many duplicates arrive. The original envelope,
failing queue/consumer, attempt count, failure code/reason and timestamps are
preserved. Notification quarantine leaves order business state untouched.
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import JSON, DateTime, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


def _utcnow() -> datetime:
    return datetime.now(UTC)


class QuarantineRecord(Base):
    __tablename__ = "quarantine_records"
    __table_args__ = (
        # Unique (consumer_name, event_id): quarantined exactly once logically.
        UniqueConstraint("consumer_name", "event_id"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    event_id: Mapped[str] = mapped_column(String(64), nullable=False)
    consumer_name: Mapped[str] = mapped_column(String(32), nullable=False)
    queue_name: Mapped[str] = mapped_column(String(64), nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False)
    failure_code: Mapped[str] = mapped_column(String(64), nullable=False)
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    envelope: Mapped[dict] = mapped_column(JSON, nullable=False)
    order_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    # The outbox row that published this quarantine to quickbite.dead.
    outbox_event_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )
