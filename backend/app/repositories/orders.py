"""Order reads scoped by ownership, plus append-only history access.

Authorization decisions live in the query SERVICE (owner-or-admin, with 404
for other customers' orders); this layer only executes explicitly scoped
queries with stable ordering for pagination.
"""

from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.order import Order
from app.db.models.order_item import OrderItem
from app.db.models.order_status_history import OrderStatusHistory
from app.db.models.restaurant import Restaurant


async def get_order_with_restaurant(
    session: AsyncSession, order_id: str
) -> tuple[Order, str] | None:
    result = await session.execute(
        select(Order, Restaurant.name)
        .join(Restaurant, Order.restaurant_id == Restaurant.id)
        .where(Order.id == order_id)
    )
    row = result.first()
    return (row[0], row[1]) if row is not None else None


async def count_customer_orders(
    session: AsyncSession, *, customer_id: str, status: str | None = None
) -> int:
    stmt = select(func.count()).select_from(Order).where(Order.customer_id == customer_id)
    if status is not None:
        stmt = stmt.where(Order.status == status)
    result = await session.execute(stmt)
    return int(result.scalar_one())


async def list_customer_orders(
    session: AsyncSession,
    *,
    customer_id: str,
    page: int,
    page_size: int,
    status: str | None = None,
) -> list[tuple[Order, str]]:
    """Newest first with `id` as a tie-break so pages never skip/duplicate."""
    stmt = (
        select(Order, Restaurant.name)
        .join(Restaurant, Order.restaurant_id == Restaurant.id)
        .where(Order.customer_id == customer_id)
        .order_by(Order.created_at.desc(), Order.id.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    if status is not None:
        stmt = stmt.where(Order.status == status)
    result = await session.execute(stmt)
    return [(row[0], row[1]) for row in result.all()]


async def list_order_items(session: AsyncSession, order_id: str) -> list[OrderItem]:
    result = await session.execute(
        select(OrderItem)
        .where(OrderItem.order_id == order_id)
        .order_by(OrderItem.menu_item_id.asc())
    )
    return list(result.scalars())


async def list_history(session: AsyncSession, order_id: str) -> list[OrderStatusHistory]:
    result = await session.execute(
        select(OrderStatusHistory)
        .where(OrderStatusHistory.order_id == order_id)
        .order_by(OrderStatusHistory.version.asc())
    )
    return list(result.scalars())
