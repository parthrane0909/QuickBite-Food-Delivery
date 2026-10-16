"""Order line snapshots: menu id, name, checkout price and quantity frozen
at acceptance time so later menu edits never rewrite history."""

from __future__ import annotations

from sqlalchemy import CheckConstraint, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class OrderItem(Base):
    __tablename__ = "order_items"
    __table_args__ = (
        # Unique (order_id, menu_item_id).
        UniqueConstraint("order_id", "menu_item_id"),
        CheckConstraint("quantity BETWEEN 1 AND 20", name="quantity_bounds"),
        CheckConstraint("price_amount_minor > 0", name="price_positive"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    order_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("orders.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    menu_item_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("menu_items.id", ondelete="RESTRICT"), nullable=False
    )
    # Snapshots (immutable facts as of checkout):
    item_name: Mapped[str] = mapped_column(String(200), nullable=False)
    price_amount_minor: Mapped[int] = mapped_column(Integer, nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    quantity: Mapped[int] = mapped_column(Integer, nullable=False)
    line_total_minor: Mapped[int] = mapped_column(Integer, nullable=False)
