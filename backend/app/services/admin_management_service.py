"""Transactional admin management operations and append-only audit entries."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import ConflictError, NotFoundError
from app.core.security import hash_password
from app.db.base import generate_id
from app.db.models.admin_audit_log import AdminAuditLog
from app.db.models.menu_item import MenuItem
from app.db.models.order import Order
from app.db.models.restaurant import Restaurant
from app.db.models.user import User
from app.repositories import admin_management as repo
from app.schemas.admin_management import (
    AdminCustomer,
    AdminCustomerPage,
    AdminDriver,
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
from app.schemas.orders import OrderHistoryEntry, OrderItemOut


def _audit(
    session: AsyncSession, admin_id: str, action: str, kind: str, target: str, changed: list[str]
) -> None:
    session.add(
        AdminAuditLog(
            id=generate_id("audit"),
            admin_id=admin_id,
            action=action,
            target_type=kind,
            target_id=target,
            changed_fields=sorted(changed),
        )
    )


async def restaurants(
    session: AsyncSession, *, page: int, size: int, search: str | None, active: bool | None
) -> AdminRestaurantPage:
    rows, total = await repo.restaurant_page(
        session, page=page, size=size, search=search, active=active
    )
    return AdminRestaurantPage(
        items=[
            AdminRestaurant(
                id=r.id,
                name=r.name,
                description=r.description,
                cuisine=r.cuisine,
                currency=r.currency,
                is_available=r.is_available,
                image_asset=r.image_asset,
                menu_item_count=count,
                order_count=order_count,
                customer_count=customer_count,
                accepted_order_value_minor=accepted_value,
                last_order_at=last_order_at,
                created_at=r.created_at,
                updated_at=r.updated_at,
            )
            for r, count, order_count, customer_count, accepted_value, last_order_at in rows
        ],
        page=page,
        page_size=size,
        total=total,
    )


async def restaurant_metrics(session: AsyncSession, restaurant_id: str) -> dict[str, object]:
    (
        menu_count,
        order_count,
        customer_count,
        accepted_value,
        last_order_at,
    ) = await repo.restaurant_stats(session, restaurant_id)
    return {
        "menu_item_count": menu_count,
        "order_count": order_count,
        "customer_count": customer_count,
        "accepted_order_value_minor": accepted_value,
        "last_order_at": last_order_at,
    }


async def create_restaurant(
    session: AsyncSession, admin: User, body: RestaurantWrite
) -> AdminRestaurant:
    if (await session.execute(select(Restaurant.id).where(Restaurant.name == body.name))).first():
        raise ConflictError("A restaurant with this name already exists.")
    row = Restaurant(
        id=generate_id("rest"),
        name=body.name.strip(),
        description=body.description,
        cuisine=body.cuisine,
        image_asset=body.image_asset,
        is_available=body.is_available,
        currency="INR",
    )
    session.add(row)
    await session.flush()
    _audit(session, admin.id, "create", "restaurant", row.id, list(body.model_fields_set))
    return AdminRestaurant(
        id=row.id,
        name=row.name,
        description=row.description,
        cuisine=row.cuisine,
        currency=row.currency,
        is_available=row.is_available,
        image_asset=row.image_asset,
        menu_item_count=0,
        created_at=row.created_at,
        updated_at=row.updated_at,
    )


async def update_restaurant(
    session: AsyncSession,
    admin: User,
    restaurant_id: str,
    body: RestaurantPatch,
    expected: datetime | None = None,
) -> AdminRestaurant:
    row = await session.get(Restaurant, restaurant_id, with_for_update=True)
    if row is None:
        raise NotFoundError("Restaurant was not found.")
    if expected is not None and row.updated_at != expected:
        raise ConflictError("Restaurant changed since it was loaded; refresh and try again.")
    changes = body.model_dump(exclude_unset=True)
    if "name" in changes and changes["name"] != row.name:
        duplicate = await session.execute(
            select(Restaurant.id).where(Restaurant.name == changes["name"], Restaurant.id != row.id)
        )
        if duplicate.first():
            raise ConflictError("A restaurant with this name already exists.")
    for key, value in changes.items():
        setattr(row, key, value.strip() if key == "name" and value else value)
    await session.flush()
    _audit(session, admin.id, "update", "restaurant", row.id, list(changes))
    metrics = await restaurant_metrics(session, row.id)
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


async def menu(
    session: AsyncSession,
    *,
    restaurant_id: str,
    page: int,
    size: int,
    search: str | None,
    active: bool | None,
) -> AdminMenuPage:
    if await session.get(Restaurant, restaurant_id) is None:
        raise NotFoundError("Restaurant was not found.")
    rows, total = await repo.menu_page(
        session, restaurant_id=restaurant_id, page=page, size=size, search=search, active=active
    )
    return AdminMenuPage(
        items=[AdminMenuItem.model_validate(r, from_attributes=True) for r in rows],
        page=page,
        page_size=size,
        total=total,
    )


async def create_menu_item(
    session: AsyncSession, admin: User, restaurant_id: str, body: MenuItemWrite
) -> AdminMenuItem:
    if await session.get(Restaurant, restaurant_id) is None:
        raise NotFoundError("Restaurant was not found.")
    row = MenuItem(id=generate_id("item"), restaurant_id=restaurant_id, **body.model_dump())
    session.add(row)
    await session.flush()
    _audit(session, admin.id, "create", "menu_item", row.id, list(body.model_fields_set))
    return AdminMenuItem.model_validate(row, from_attributes=True)


async def update_menu_item(
    session: AsyncSession,
    admin: User,
    item_id: str,
    body: MenuItemPatch,
    expected: datetime | None = None,
) -> AdminMenuItem:
    row = await session.get(MenuItem, item_id, with_for_update=True)
    if row is None:
        raise NotFoundError("Menu item was not found.")
    if expected is not None and row.updated_at != expected:
        raise ConflictError("Menu item changed since it was loaded; refresh and try again.")
    changes = body.model_dump(exclude_unset=True)
    for key, value in changes.items():
        setattr(row, key, value.strip() if key == "name" and value else value)
    await session.flush()
    _audit(session, admin.id, "update", "menu_item", row.id, list(changes))
    return AdminMenuItem.model_validate(row, from_attributes=True)


async def customers(session: AsyncSession, *, page: int, size: int, search: str | None):
    rows, total = await repo.customer_page(session, page=page, size=size, search=search)
    items = [
        AdminCustomer(
            id=u.id,
            email=u.email,
            full_name=u.full_name,
            is_active=u.is_active,
            order_count=count,
            last_order_at=last_order_at,
            created_at=u.created_at,
            updated_at=u.updated_at,
        )
        for u, count, last_order_at in rows
    ]
    return AdminCustomerPage(items=items, page=page, page_size=size, total=total)


async def latest_customer_order(session: AsyncSession, customer_id: str):
    return await repo.latest_customer_order(session, customer_id)


async def create_customer(session: AsyncSession, admin: User, body: CustomerWrite) -> AdminCustomer:
    if (await session.execute(select(User.id).where(User.email == body.email))).first():
        raise ConflictError("An account with this email already exists.")
    row = User(
        id=generate_id("user"),
        email=body.email,
        full_name=body.full_name.strip(),
        password_hash=hash_password(body.password),
        role="customer",
        is_active=True,
    )
    session.add(row)
    await session.flush()
    _audit(session, admin.id, "create", "customer", row.id, ["email", "full_name"])
    return AdminCustomer(
        id=row.id,
        email=row.email,
        full_name=row.full_name,
        is_active=True,
        order_count=0,
        last_order_at=None,
        created_at=row.created_at,
        updated_at=row.updated_at,
    )


async def update_customer(
    session: AsyncSession,
    admin: User,
    customer_id: str,
    body: CustomerPatch,
    expected: datetime | None = None,
) -> AdminCustomer:
    row = await session.get(User, customer_id, with_for_update=True)
    if row is None or row.role != "customer":
        raise NotFoundError("Customer was not found.")
    if expected is not None and row.updated_at != expected:
        raise ConflictError("Customer changed since it was loaded; refresh and try again.")
    changes = body.model_dump(exclude_unset=True)
    if "email" in changes and changes["email"] != row.email:
        if (
            await session.execute(
                select(User.id).where(User.email == changes["email"], User.id != row.id)
            )
        ).first():
            raise ConflictError("An account with this email already exists.")
    for key, value in changes.items():
        setattr(row, key, value.strip() if key in {"email", "full_name"} and value else value)
    await session.flush()
    _audit(session, admin.id, "update", "customer", row.id, list(changes))
    count = await repo.count_entity(session, Order, Order.customer_id == row.id)
    return AdminCustomer(
        id=row.id,
        email=row.email,
        full_name=row.full_name,
        is_active=row.is_active,
        order_count=count,
        last_order_at=await repo.latest_customer_order(session, row.id),
        created_at=row.created_at,
        updated_at=row.updated_at,
    )


async def customer_orders(session: AsyncSession, customer_id: str, *, page: int, size: int):
    customer = await session.get(User, customer_id)
    if customer is None or customer.role != "customer":
        raise NotFoundError("Customer was not found.")
    count = await repo.count_entity(session, Order, Order.customer_id == customer_id)
    from app.db.models.restaurant import Restaurant
    from app.schemas.orders import OrderPage, OrderSummary

    result = await session.execute(
        select(Order, Restaurant.name)
        .join(Restaurant, Restaurant.id == Order.restaurant_id)
        .where(Order.customer_id == customer_id)
        .order_by(Order.created_at.desc(), Order.id.desc())
        .offset((page - 1) * size)
        .limit(size)
    )
    items = [
        OrderSummary(
            id=order.id,
            restaurant_id=order.restaurant_id,
            restaurant_name=restaurant_name,
            status=order.status,
            currency=order.currency,
            total_amount_minor=order.total_amount_minor,
            version=order.version,
            failure_code=order.failure_code,
            created_at=order.created_at,
            updated_at=order.updated_at,
        )
        for order, restaurant_name in result.all()
    ]
    return OrderPage(items=items, page=page, page_size=size, total=count)


async def order_detail(session: AsyncSession, order_id: str) -> AdminOrderDetail:
    found = await repo.order_detail(session, order_id)
    if found is None:
        raise NotFoundError("Order was not found.")
    order, restaurant, customer, driver, items, history = found
    return AdminOrderDetail(
        id=order.id,
        restaurant_id=order.restaurant_id,
        restaurant_name=restaurant.name,
        restaurant_cuisine=restaurant.cuisine,
        status=order.status,
        currency=order.currency,
        total_amount_minor=order.total_amount_minor,
        version=order.version,
        failure_code=order.failure_code,
        created_at=order.created_at,
        updated_at=order.updated_at,
        delivery_address=order.delivery_address,
        failure_reason=order.failure_reason,
        driver_id=order.driver_id,
        customer_id=customer.id,
        customer_email=customer.email,
        customer_name=customer.full_name,
        driver_name=driver.driver_name if driver else None,
        items=[
            OrderItemOut(
                menu_item_id=i.menu_item_id,
                item_name=i.item_name,
                price_amount_minor=i.price_amount_minor,
                currency=i.currency,
                quantity=i.quantity,
                line_total_minor=i.line_total_minor,
            )
            for i in items
        ],
        history=[
            OrderHistoryEntry(
                version=h.version,
                status=h.status,
                from_status=h.from_status,
                failure_code=h.failure_code,
                source=h.source,
                changed_at=h.changed_at,
            )
            for h in history
        ],
    )


async def drivers(session: AsyncSession, *, page: int, size: int) -> AdminDriverPage:
    rows, total = await repo.driver_page(session, page=page, size=size)
    return AdminDriverPage(
        items=[
            AdminDriver(
                driver_id=r[0], driver_name=r[1], assigned_orders=int(r[2]), last_assigned_at=r[3]
            )
            for r in rows
        ],
        page=page,
        page_size=size,
        total=total,
    )
