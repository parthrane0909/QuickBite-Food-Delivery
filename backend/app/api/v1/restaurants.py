"""Catalog routes: paginated restaurants and menus (signed-in users only)."""

from __future__ import annotations

from fastapi import APIRouter, Query

from app.api.deps import CurrentUserDep, SessionDep
from app.core.errors import NotFoundError
from app.db.models.menu_item import MenuItem
from app.repositories import catalog as catalog_repo
from app.schemas.catalog import CuisineList, MenuItemOut, MenuItemPage, RestaurantPage
from app.schemas.common import MAX_PAGE_SIZE
from app.services import catalog_service

router = APIRouter(tags=["catalog"])


@router.get("/restaurants/cuisines", response_model=CuisineList)
async def list_cuisines(session: SessionDep, _user: CurrentUserDep) -> CuisineList:
    """Distinct active restaurant cuisines for the discovery category rail."""
    return CuisineList(items=await catalog_service.list_cuisines(session))


@router.get("/restaurants", response_model=RestaurantPage)
async def list_restaurants(
    session: SessionDep,
    _user: CurrentUserDep,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=MAX_PAGE_SIZE),
    search: str | None = Query(default=None, max_length=160),
    cuisine: str | None = Query(default=None, max_length=80),
) -> RestaurantPage:
    return await catalog_service.list_restaurants(
        session, page=page, page_size=page_size, search=search, cuisine=cuisine
    )


@router.get("/restaurants/{restaurant_id}/menu", response_model=MenuItemPage)
async def get_menu(
    restaurant_id: str,
    session: SessionDep,
    _user: CurrentUserDep,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=MAX_PAGE_SIZE),
) -> MenuItemPage:
    restaurant = await catalog_repo.get_restaurant(session, restaurant_id)
    if restaurant is None:
        raise NotFoundError(f"Restaurant '{restaurant_id}' was not found.")
    return await catalog_service.list_menu(
        session, restaurant_id=restaurant_id, page=page, page_size=page_size
    )


@router.get("/restaurants/{restaurant_id}/menu/{item_id}", response_model=MenuItemOut)
async def get_menu_item(
    restaurant_id: str,
    item_id: str,
    session: SessionDep,
    _user: CurrentUserDep,
) -> MenuItemOut:
    """Resolve a menu-item deep link independently of the current menu page."""
    restaurant = await catalog_repo.get_restaurant(session, restaurant_id)
    if restaurant is None:
        raise NotFoundError(f"Restaurant '{restaurant_id}' was not found.")
    item = await session.get(MenuItem, item_id)
    if item is None or item.restaurant_id != restaurant_id:
        raise NotFoundError(f"Menu item '{item_id}' was not found.")
    return MenuItemOut.model_validate(item, from_attributes=True)
