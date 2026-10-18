"""Request/response contracts for the administrative management extension."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.schemas.common import Page
from app.schemas.orders import OrderDetail, OrderHistoryEntry


class RestaurantWrite(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str = Field(min_length=2, max_length=160)
    description: str | None = Field(default=None, max_length=4000)
    cuisine: str | None = Field(default=None, max_length=80)
    image_asset: str | None = Field(default=None, max_length=255)
    is_available: bool = True


class RestaurantPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str | None = Field(default=None, min_length=2, max_length=160)
    description: str | None = Field(default=None, max_length=4000)
    cuisine: str | None = Field(default=None, max_length=80)
    image_asset: str | None = Field(default=None, max_length=255)
    is_available: bool | None = None

    @field_validator("name", "is_available")
    @classmethod
    def non_null_required_fields(cls, value):
        if value is None:
            raise ValueError("This field cannot be null.")
        return value


class AdminRestaurant(BaseModel):
    id: str
    name: str
    description: str | None
    cuisine: str | None
    currency: str
    is_available: bool
    image_asset: str | None
    menu_item_count: int
    order_count: int = 0
    customer_count: int = 0
    accepted_order_value_minor: int = 0
    last_order_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class MenuItemWrite(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str = Field(min_length=2, max_length=200)
    description: str | None = Field(default=None, max_length=4000)
    price_amount_minor: int = Field(gt=0, le=100_000_000)
    currency: str = Field(default="INR", pattern="^INR$")
    is_available: bool = True
    image_asset: str | None = Field(default=None, max_length=255)
    sort_order: int = Field(default=0, ge=0, le=1_000_000)


class MenuItemPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str | None = Field(default=None, min_length=2, max_length=200)
    description: str | None = Field(default=None, max_length=4000)
    price_amount_minor: int | None = Field(default=None, gt=0, le=100_000_000)
    currency: str | None = Field(default=None, pattern="^INR$")
    is_available: bool | None = None
    image_asset: str | None = Field(default=None, max_length=255)
    sort_order: int | None = Field(default=None, ge=0, le=1_000_000)

    @field_validator("name", "price_amount_minor", "currency", "is_available", "sort_order")
    @classmethod
    def non_null_required_fields(cls, value):
        if value is None:
            raise ValueError("This field cannot be null.")
        return value


class AdminMenuItem(BaseModel):
    id: str
    restaurant_id: str
    name: str
    description: str | None
    price_amount_minor: int
    currency: str
    is_available: bool
    image_asset: str | None
    sort_order: int
    created_at: datetime
    updated_at: datetime


class CustomerWrite(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: str = Field(min_length=6, max_length=255)
    full_name: str = Field(min_length=1, max_length=120)
    password: str = Field(min_length=12, max_length=128)

    @field_validator("email")
    @classmethod
    def valid_email(cls, value: str) -> str:
        value = value.strip().lower()
        if value.count("@") != 1 or "." not in value.rsplit("@", 1)[-1]:
            raise ValueError("Enter a valid email address.")
        return value


class CustomerPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: str | None = Field(default=None, min_length=6, max_length=255)
    full_name: str | None = Field(default=None, min_length=1, max_length=120)
    is_active: bool | None = None

    @field_validator("email", "full_name", "is_active")
    @classmethod
    def non_null_required_fields(cls, value):
        if value is None:
            raise ValueError("This field cannot be null.")
        return value

    @field_validator("email")
    @classmethod
    def valid_email(cls, value: str | None) -> str | None:
        if value is None:
            return value
        value = value.strip().lower()
        if value.count("@") != 1 or "." not in value.rsplit("@", 1)[-1]:
            raise ValueError("Enter a valid email address.")
        return value


class AdminCustomer(BaseModel):
    id: str
    email: str
    full_name: str
    is_active: bool
    order_count: int
    last_order_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class AdminCustomerPage(Page[AdminCustomer]):
    pass


class AdminRestaurantPage(Page[AdminRestaurant]):
    pass


class AdminMenuPage(Page[AdminMenuItem]):
    pass


class AdminOrderDetail(OrderDetail):
    customer_id: str
    customer_email: str
    customer_name: str
    restaurant_cuisine: str | None
    driver_name: str | None
    history: list[OrderHistoryEntry]


class AdminDriver(BaseModel):
    driver_id: str
    driver_name: str
    assigned_orders: int
    last_assigned_at: datetime | None


class AdminDriverPage(Page[AdminDriver]):
    pass
