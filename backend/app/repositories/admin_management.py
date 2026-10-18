"""Database access for admin management and observational order detail."""

from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.driver import Driver
from app.db.models.driver_assignment import DriverAssignment
from app.db.models.menu_item import MenuItem
from app.db.models.order import Order
from app.db.models.order_item import OrderItem
from app.db.models.order_status_history import OrderStatusHistory
from app.db.models.restaurant import Restaurant
from app.db.models.user import User


async def restaurant_page(
    session: AsyncSession, *, page: int, size: int, search: str | None, active: bool | None
) -> tuple[list[tuple[Restaurant, int, int, int, int, object]], int]:
    menus = (
        select(MenuItem.restaurant_id, func.count().label("menu_item_count"))
        .group_by(MenuItem.restaurant_id)
        .subquery()
    )
    activity = (
        select(
            Order.restaurant_id,
            func.count(Order.id).label("order_count"),
            func.count(func.distinct(Order.customer_id)).label("customer_count"),
            func.coalesce(func.sum(Order.total_amount_minor), 0).label(
                "accepted_order_value_minor"
            ),
            func.max(Order.created_at).label("last_order_at"),
        )
        .group_by(Order.restaurant_id)
        .subquery()
    )
    stmt = (
        select(
            Restaurant,
            func.coalesce(menus.c.menu_item_count, 0),
            func.coalesce(activity.c.order_count, 0),
            func.coalesce(activity.c.customer_count, 0),
            func.coalesce(activity.c.accepted_order_value_minor, 0),
            activity.c.last_order_at,
        )
        .outerjoin(menus, menus.c.restaurant_id == Restaurant.id)
        .outerjoin(activity, activity.c.restaurant_id == Restaurant.id)
    )
    count_stmt = select(func.count()).select_from(Restaurant)
    if search:
        pattern = f"%{search.strip()}%"
        stmt = stmt.where(Restaurant.name.ilike(pattern))
        count_stmt = count_stmt.where(Restaurant.name.ilike(pattern))
    if active is not None:
        stmt = stmt.where(Restaurant.is_available.is_(active))
        count_stmt = count_stmt.where(Restaurant.is_available.is_(active))
    total = int((await session.execute(count_stmt)).scalar_one())
    rows = (
        await session.execute(
            stmt.order_by(Restaurant.name, Restaurant.id).offset((page - 1) * size).limit(size)
        )
    ).all()
    return [
        (row[0], int(row[1]), int(row[2]), int(row[3]), int(row[4]), row[5]) for row in rows
    ], total


async def restaurant_stats(session: AsyncSession, restaurant_id: str):
    menu_count = (
        select(func.count()).select_from(MenuItem).where(MenuItem.restaurant_id == restaurant_id)
    ).scalar_subquery()
    result = await session.execute(
        select(
            menu_count,
            func.count(Order.id),
            func.count(func.distinct(Order.customer_id)),
            func.coalesce(func.sum(Order.total_amount_minor), 0),
            func.max(Order.created_at),
        ).where(Order.restaurant_id == restaurant_id)
    )
    row = result.one()
    return int(row[0]), int(row[1]), int(row[2]), int(row[3]), row[4]


async def menu_page(
    session: AsyncSession,
    *,
    restaurant_id: str,
    page: int,
    size: int,
    search: str | None,
    active: bool | None,
) -> tuple[list[MenuItem], int]:
    stmt = select(MenuItem).where(MenuItem.restaurant_id == restaurant_id)
    count_stmt = (
        select(func.count()).select_from(MenuItem).where(MenuItem.restaurant_id == restaurant_id)
    )
    if search:
        pattern = f"%{search.strip()}%"
        stmt = stmt.where(MenuItem.name.ilike(pattern))
        count_stmt = count_stmt.where(MenuItem.name.ilike(pattern))
    if active is not None:
        stmt = stmt.where(MenuItem.is_available.is_(active))
        count_stmt = count_stmt.where(MenuItem.is_available.is_(active))
    total = int((await session.execute(count_stmt)).scalar_one())
    rows = (
        (
            await session.execute(
                stmt.order_by(MenuItem.sort_order, MenuItem.name, MenuItem.id)
                .offset((page - 1) * size)
                .limit(size)
            )
        )
        .scalars()
        .all()
    )
    return list(rows), total


async def customer_page(
    session: AsyncSession, *, page: int, size: int, search: str | None
) -> tuple[list[tuple[User, int, object]], int]:
    counts = (
        select(
            Order.customer_id,
            func.count().label("order_count"),
            func.max(Order.created_at).label("last_order_at"),
        )
        .group_by(Order.customer_id)
        .subquery()
    )
    stmt = (
        select(
            User,
            func.coalesce(counts.c.order_count, 0),
            counts.c.last_order_at,
        )
        .outerjoin(counts, counts.c.customer_id == User.id)
        .where(User.role == "customer")
    )
    count_stmt = select(func.count()).select_from(User).where(User.role == "customer")
    if search:
        pattern = f"%{search.strip()}%"
        criterion = User.email.ilike(pattern) | User.full_name.ilike(pattern)
        stmt = stmt.where(criterion)
        count_stmt = count_stmt.where(criterion)
    total = int((await session.execute(count_stmt)).scalar_one())
    rows = (
        await session.execute(
            stmt.order_by(User.full_name, User.id).offset((page - 1) * size).limit(size)
        )
    ).all()
    return [(row[0], int(row[1]), row[2]) for row in rows], total


async def count_entity(session: AsyncSession, model: type, *criteria) -> int:
    stmt = select(func.count()).select_from(model)
    if criteria:
        stmt = stmt.where(*criteria)
    return int((await session.execute(stmt)).scalar_one())


async def latest_customer_order(session: AsyncSession, customer_id: str):
    return (
        await session.execute(
            select(func.max(Order.created_at)).where(Order.customer_id == customer_id)
        )
    ).scalar_one()


async def order_detail(session: AsyncSession, order_id: str):
    result = await session.execute(
        select(Order, Restaurant, User, DriverAssignment)
        .join(Restaurant, Restaurant.id == Order.restaurant_id)
        .join(User, User.id == Order.customer_id)
        .outerjoin(DriverAssignment, DriverAssignment.order_id == Order.id)
        .where(Order.id == order_id)
    )
    row = result.one_or_none()
    if row is None:
        return None
    order, restaurant, customer, driver = row
    items = list(
        (
            await session.execute(
                select(OrderItem).where(OrderItem.order_id == order_id).order_by(OrderItem.id)
            )
        )
        .scalars()
        .all()
    )
    history = list(
        (
            await session.execute(
                select(OrderStatusHistory)
                .where(OrderStatusHistory.order_id == order_id)
                .order_by(OrderStatusHistory.version)
            )
        )
        .scalars()
        .all()
    )
    return order, restaurant, customer, driver, items, history


async def driver_page(session: AsyncSession, *, page: int, size: int):
    stmt = select(
        Driver.id,
        Driver.full_name,
        func.count(DriverAssignment.id).label("assigned_orders"),
        func.max(DriverAssignment.assigned_at).label("last_assigned_at"),
    )
    rows = (
        await session.execute(
            stmt.outerjoin(DriverAssignment, DriverAssignment.driver_id == Driver.id)
            .group_by(Driver.id, Driver.full_name)
            .order_by(Driver.full_name, Driver.id)
            .offset((page - 1) * size)
            .limit(size)
        )
    ).all()
    count = select(func.count()).select_from(Driver)
    total = int((await session.execute(count)).scalar_one())
    return rows, total
