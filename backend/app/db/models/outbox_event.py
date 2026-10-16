"""Transactional outbox — every outgoing event is committed here atomically
with its domain change, then published by the separate dispatcher process.

States: PENDING (eligible), CLAIMED (leased by a dispatcher), SENT (confirmed
publish AND no mandatory return). Publication failures leave rows PENDING and
re-eligible; a crash after publish but before SENT may duplicate the message,
which is why consumers must be idempotent (at-least-once by design).
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import JSON, CheckConstraint, DateTime, Index, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


def _utcnow() -> datetime:
    return datetime.now(UTC)


class OutboxEvent(Base):
    __tablename__ = "outbox_events"
    __table_args__ = (
        CheckConstraint("state IN ('PENDING','CLAIMED','SENT')", name="state"),
        CheckConstraint("attempts >= 0", name="attempts_non_negative"),
        Index("ix_outbox_claim", "state", "available_at"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    # Immutable publication identity — equal to the AMQP message_id; unique so
    # the same domain event is never stored twice.
    event_id: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    event_type: Mapped[str] = mapped_column(String(64), nullable=False)
    order_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    exchange: Mapped[str] = mapped_column(String(64), nullable=False)
    routing_key: Mapped[str] = mapped_column(String(64), nullable=False)
    payload: Mapped[dict] = mapped_column(JSON, nullable=False)
    state: Mapped[str] = mapped_column(String(16), nullable=False, default="PENDING")
    available_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )
    claimed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    claimed_by: Mapped[str | None] = mapped_column(String(64), nullable=True)
    lease_expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )
