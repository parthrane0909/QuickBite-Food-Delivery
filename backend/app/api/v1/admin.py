"""Original read-only admin overview plus additive management operations.

Cross-customer order inspection and operational counters remain read-only.
New restaurant, menu and customer management routes are admin-gated, audited,
soft-deactivation based, and preserve historical order snapshots.
"""

from __future__ import annotations

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Query

from app.api.deps import AdminDep, SessionDep
from app.schemas.admin import AdminOrderPage, AdminSummary
from app.schemas.admin_management import (
    AdminCustomer,
    AdminCustomerPage,
    AdminDriverPage,
    AdminMenuItem,
    AdminMenuPage,
    AdminOrderDetail,
    AdminRestaurant,
    AdminRestaurantPage,
    CustomerPatch,
    CustomerWrite,
    MenuItemPatch,
    MenuItemWrite,
    RestaurantPatch,
    RestaurantWrite,
)
from app.schemas.common import MAX_PAGE_SIZE
from app.schemas.orders import ORDER_STATUS_FILTER, OrderPage
from app.services import admin_management_service as management
from app.services import admin_service

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/orders", response_model=AdminOrderPage)
async def list_all_orders(
    session: SessionDep,
    _admin: AdminDep,
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)] = 20,
    status: ORDER_STATUS_FILTER | None = None,
) -> AdminOrderPage:
    """Paginated cross-customer order listing (newest first); optional exact
    status filter. Read-only: no order mutation is exposed anywhere."""
    return await admin_service.list_orders(session, page=page, page_size=page_size, status=status)


@router.get("/summary", response_model=AdminSummary)
async def get_summary(session: SessionDep, _admin: AdminDep) -> AdminSummary:
    """Aggregate counts from authoritative PostgreSQL state: orders grouped
    by status, unpublished outbox rows, scheduled retry backlog and
    quarantine records (exact semantics documented in docs/api.md)."""
    return await admin_service.get_summary(session)


@router.get("/orders/{order_id}", response_model=AdminOrderDetail)
async def get_order_detail(order_id: str, session: SessionDep, _admin: AdminDep):
    return await management.order_detail(session, order_id)


@router.get("/restaurants", response_model=AdminRestaurantPage)
async def list_restaurants(
    session: SessionDep,
    _admin: AdminDep,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=MAX_PAGE_SIZE),
    search: str | None = Query(None, max_length=160),
    active: bool | None = None,
):
    return await management.restaurants(
        session, page=page, size=page_size, search=search, active=active
    )


@router.post("/restaurants", response_model=AdminRestaurant, status_code=201)
async def create_restaurant(body: RestaurantWrite, session: SessionDep, admin: AdminDep):
    return await management.create_restaurant(session, admin, body)


@router.get("/restaurants/{restaurant_id}", response_model=AdminRestaurant)
async def get_restaurant(restaurant_id: str, session: SessionDep, _admin: AdminDep):
    from app.db.models.restaurant import Restaurant

    row = await session.get(Restaurant, restaurant_id)
    if row is None:
        from app.core.errors import NotFoundError

        raise NotFoundError("Restaurant was not found.")
    metrics = await management.restaurant_metrics(session, row.id)
    return AdminRestaurant(
        id=row.id,
        name=row.name,
        description=row.description,
        cuisine=row.cuisine,
        currency=row.currency,
        is_available=row.is_available,
        image_asset=row.image_asset,
        **metrics,
        created_at=row.created_at,
        updated_at=row.updated_at,
    )


@router.patch("/restaurants/{restaurant_id}", response_model=AdminRestaurant)
async def patch_restaurant(
    restaurant_id: str,
    body: RestaurantPatch,
    session: SessionDep,
    admin: AdminDep,
    expected_updated_at: datetime | None = None,
):
    return await management.update_restaurant(
        session, admin, restaurant_id, body, expected_updated_at
    )


@router.post("/restaurants/{restaurant_id}/deactivate", response_model=AdminRestaurant)
async def deactivate_restaurant(restaurant_id: str, session: SessionDep, admin: AdminDep):
    return await management.update_restaurant(
        session, admin, restaurant_id, RestaurantPatch(is_available=False)
    )


@router.get("/restaurants/{restaurant_id}/menu", response_model=AdminMenuPage)
async def list_menu(
    restaurant_id: str,
    session: SessionDep,
    _admin: AdminDep,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=MAX_PAGE_SIZE),
    search: str | None = Query(None, max_length=200),
    active: bool | None = None,
):
    return await management.menu(
        session,
        restaurant_id=restaurant_id,
        page=page,
        size=page_size,
        search=search,
        active=active,
    )


@router.post("/restaurants/{restaurant_id}/menu", response_model=AdminMenuItem, status_code=201)
async def create_menu(
    restaurant_id: str, body: MenuItemWrite, session: SessionDep, admin: AdminDep
):
    return await management.create_menu_item(session, admin, restaurant_id, body)


@router.patch("/menu-items/{item_id}", response_model=AdminMenuItem)
async def patch_menu(
    item_id: str,
    body: MenuItemPatch,
    session: SessionDep,
    admin: AdminDep,
    expected_updated_at: datetime | None = None,
):
    return await management.update_menu_item(session, admin, item_id, body, expected_updated_at)


@router.post("/menu-items/{item_id}/deactivate", response_model=AdminMenuItem)
async def deactivate_menu(item_id: str, session: SessionDep, admin: AdminDep):
    return await management.update_menu_item(
        session, admin, item_id, MenuItemPatch(is_available=False)
    )


@router.get("/customers", response_model=AdminCustomerPage)
async def list_customers(
    session: SessionDep,
    _admin: AdminDep,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=MAX_PAGE_SIZE),
    search: str | None = Query(None, max_length=255),
):
    return await management.customers(session, page=page, size=page_size, search=search)


@router.post("/customers", response_model=AdminCustomer, status_code=201)
async def create_customer(body: CustomerWrite, session: SessionDep, admin: AdminDep):
    return await management.create_customer(session, admin, body)


@router.patch("/customers/{customer_id}", response_model=AdminCustomer)
async def patch_customer(
    customer_id: str,
    body: CustomerPatch,
    session: SessionDep,
    admin: AdminDep,
    expected_updated_at: datetime | None = None,
):
    return await management.update_customer(session, admin, customer_id, body, expected_updated_at)


@router.post("/customers/{customer_id}/deactivate", response_model=AdminCustomer)
async def deactivate_customer(customer_id: str, session: SessionDep, admin: AdminDep):
    return await management.update_customer(
        session, admin, customer_id, CustomerPatch(is_active=False)
    )


@router.get("/customers/{customer_id}/orders", response_model=OrderPage)
async def customer_orders(
    customer_id: str,
    session: SessionDep,
    _admin: AdminDep,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=MAX_PAGE_SIZE),
):
    return await management.customer_orders(session, customer_id, page=page, size=page_size)


@router.get("/customers/{customer_id}", response_model=AdminCustomer)
async def get_customer(customer_id: str, session: SessionDep, _admin: AdminDep):
    from app.core.errors import NotFoundError
    from app.db.models.order import Order
    from app.db.models.user import User
    from app.repositories.admin_management import count_entity

    row = await session.get(User, customer_id)
    if row is None or row.role != "customer":
        raise NotFoundError("Customer was not found.")
    return AdminCustomer(
        id=row.id,
        email=row.email,
        full_name=row.full_name,
        is_active=row.is_active,
        order_count=await count_entity(session, Order, Order.customer_id == row.id),
        last_order_at=await management.latest_customer_order(session, row.id),
        created_at=row.created_at,
        updated_at=row.updated_at,
    )


@router.get("/drivers", response_model=AdminDriverPage)
async def list_drivers(
    session: SessionDep,
    _admin: AdminDep,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=MAX_PAGE_SIZE),
):
    return await management.drivers(session, page=page, size=page_size)
