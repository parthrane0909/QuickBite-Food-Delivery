"""Catalog repository — paginated, stably ordered reads and authoritative
menu lookups used by checkout (Milestone 2)."""

from __future__ import annotations

from collections.abc import Iterable

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.menu_item import MenuItem
from app.db.models.restaurant import Restaurant


async def count_restaurants(session: AsyncSession) -> int:
    result = await session.execute(select(func.count()).select_from(Restaurant))
    return int(result.scalar_one())


async def list_restaurants(session: AsyncSession, *, page: int, page_size: int) -> list[Restaurant]:
    # Stable sort: name then id, so pagination never skips/duplicates rows.
    result = await session.execute(
        select(Restaurant)
        .order_by(Restaurant.name.asc(), Restaurant.id.asc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    return list(result.scalars())


async def get_restaurant(session: AsyncSession, restaurant_id: str) -> Restaurant | None:
    result = await session.execute(select(Restaurant).where(Restaurant.id == restaurant_id))
    return result.scalar_one_or_none()


async def get_menu_items_by_ids(
    session: AsyncSession, menu_item_ids: Iterable[str]
) -> dict[str, MenuItem]:
    """Authoritative checkout lookup: current price/availability for exactly
    the requested items, keyed by id (missing ids are simply absent)."""
    ids = list(menu_item_ids)
    if not ids:
        return {}
    result = await session.execute(select(MenuItem).where(MenuItem.id.in_(ids)))
    return {item.id: item for item in result.scalars()}


async def count_menu_items(session: AsyncSession, restaurant_id: str) -> int:
    result = await session.execute(
        select(func.count()).select_from(MenuItem).where(MenuItem.restaurant_id == restaurant_id)
    )
    return int(result.scalar_one())


async def list_menu_items(
    session: AsyncSession, *, restaurant_id: str, page: int, page_size: int
) -> list[MenuItem]:
    result = await session.execute(
        select(MenuItem)
        .where(MenuItem.restaurant_id == restaurant_id)
        .order_by(MenuItem.sort_order.asc(), MenuItem.name.asc(), MenuItem.id.asc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    return list(result.scalars())
