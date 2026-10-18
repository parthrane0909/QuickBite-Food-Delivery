"""Catalog schemas. All money is integer minor units (assignment §6)."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.common import Page


class RestaurantOut(BaseModel):
    id: str
    name: str
    description: str | None = None
    cuisine: str | None = None
    currency: str
    is_available: bool
    image_asset: str | None = None
    created_at: datetime


class MenuItemOut(BaseModel):
    id: str
    restaurant_id: str
    name: str
    description: str | None = None
    price_amount_minor: int = Field(gt=0)
    currency: str
    is_available: bool
    image_asset: str | None = None
    sort_order: int


class RestaurantPage(Page[RestaurantOut]):
    pass


class MenuItemPage(Page[MenuItemOut]):
    pass


class CuisineList(BaseModel):
    items: list[str]
