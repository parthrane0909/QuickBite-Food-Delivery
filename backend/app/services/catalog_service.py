"""Catalog service — pagination and availability semantics."""

from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from app.repositories import catalog as catalog_repo
from app.schemas.catalog import MenuItemOut, MenuItemPage, RestaurantOut, RestaurantPage


async def list_restaurants(
    session: AsyncSession,
    *,
    page: int,
    page_size: int,
    search: str | None = None,
    cuisine: str | None = None,
) -> RestaurantPage:
    total = await catalog_repo.count_restaurants(session, search=search, cuisine=cuisine)
    rows = await catalog_repo.list_restaurants(
        session, page=page, page_size=page_size, search=search, cuisine=cuisine
    )
    return RestaurantPage(
        items=[
            RestaurantOut(
                id=r.id,
                name=r.name,
                description=r.description,
                cuisine=r.cuisine,
                currency=r.currency,
                is_available=r.is_available,
                image_asset=r.image_asset,
                created_at=r.created_at,
            )
            for r in rows
        ],
        page=page,
        page_size=page_size,
        total=total,
    )


async def list_cuisines(session: AsyncSession) -> list[str]:
    return await catalog_repo.list_cuisines(session)


async def list_menu(
    session: AsyncSession, *, restaurant_id: str, page: int, page_size: int
) -> MenuItemPage:
    """Paginated menu including unavailable items (flagged, so the client can
    disable adding them) with authoritative minor-unit prices."""
    total = await catalog_repo.count_menu_items(session, restaurant_id)
    rows = await catalog_repo.list_menu_items(
        session, restaurant_id=restaurant_id, page=page, page_size=page_size
    )
    return MenuItemPage(
        items=[
            MenuItemOut(
                id=m.id,
                restaurant_id=m.restaurant_id,
                name=m.name,
                description=m.description,
                price_amount_minor=m.price_amount_minor,
                currency=m.currency,
                is_available=m.is_available,
                image_asset=m.image_asset,
                sort_order=m.sort_order,
            )
            for m in rows
        ],
        page=page,
        page_size=page_size,
        total=total,
    )
