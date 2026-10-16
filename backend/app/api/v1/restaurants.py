"""Catalog routes: paginated restaurants and menus (signed-in users only)."""

from __future__ import annotations

from fastapi import APIRouter, Query

from app.api.deps import CurrentUserDep, SessionDep
from app.core.errors import NotFoundError
from app.repositories import catalog as catalog_repo
from app.schemas.catalog import MenuItemPage, RestaurantPage
from app.schemas.common import MAX_PAGE_SIZE
from app.services import catalog_service

router = APIRouter(tags=["catalog"])


@router.get("/restaurants", response_model=RestaurantPage)
async def list_restaurants(
    session: SessionDep,
    _user: CurrentUserDep,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=MAX_PAGE_SIZE),
) -> RestaurantPage:
    return await catalog_service.list_restaurants(session, page=page, page_size=page_size)


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
