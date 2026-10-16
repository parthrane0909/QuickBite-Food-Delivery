"""Bounded retry jobs — UNIQUE (consumer_name, event_id, attempt).

The worker's failure path rolls back its business transaction, then in a NEW
transaction inserts one retry row plus a scheduled, targeted outbox
publication before acknowledging the original message. The unique key makes
double-failure handling unable to schedule the same attempt twice. The
scheduler activates due jobs; publication goes ONLY to the failing queue via
the default exchange (routing key = queue name), never to quickbite.orders.
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import (
    JSON,
    CheckConstraint,
    DateTime,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


def _utcnow() -> datetime:
    return datetime.now(UTC)


class RetryJob(Base):
    __tablename__ = "retry_jobs"
    __table_args__ = (
        # Unique (consumer_name, event_id, attempt).
        UniqueConstraint("consumer_name", "event_id", "attempt"),
        CheckConstraint("attempt >= 1", name="attempt_positive"),
        CheckConstraint("state IN ('PENDING','PUBLISHED','EXHAUSTED')", name="state"),
        Index("ix_retry_due", "state", "due_at"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    consumer_name: Mapped[str] = mapped_column(String(32), nullable=False)
    event_id: Mapped[str] = mapped_column(String(64), nullable=False)
    # Original envelope preserved byte-for-byte; event_id never changes
    # across retries (attempt lives here, not in the domain event identity).
    envelope: Mapped[dict] = mapped_column(JSON, nullable=False)
    order_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    target_queue: Mapped[str] = mapped_column(String(64), nullable=False)
    attempt: Mapped[int] = mapped_column(Integer, nullable=False)
    due_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    state: Mapped[str] = mapped_column(String(16), nullable=False, default="PENDING")
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow, onupdate=_utcnow
    )
