"""Checkout idempotency records — scope (customer_id, idempotency_key).

Stores the canonical request hash AND the original acceptance response so a
replayed identical request returns the very same 202 body/Location even after
the order has advanced. A different payload under the same key raises 409.
Records are retained for the assignment lifetime (production retention is
discussed in docs/reliability.md).
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import JSON, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


def _utcnow() -> datetime:
    return datetime.now(UTC)


class CheckoutIdempotency(Base):
    __tablename__ = "checkout_idempotency"
    __table_args__ = (
        # Unique (customer_id, idempotency_key).
        UniqueConstraint("customer_id", "idempotency_key"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    customer_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    idempotency_key: Mapped[str] = mapped_column(String(128), nullable=False)
    request_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    order_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("orders.id", ondelete="RESTRICT"), nullable=False
    )
    response_status: Mapped[int] = mapped_column(Integer, nullable=False, default=202)
    # Original acceptance body, replayed verbatim on duplicate submissions.
    response_body: Mapped[dict] = mapped_column(JSON, nullable=False)
    location: Mapped[str] = mapped_column(String(128), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )
