"""Order reads with owner-or-admin authorization (assignment §7).

Ownership rule: another customer's order is always 404 — never 403 — so the
API never confirms that some other customer's order id exists (§14 access
control). Admins may read any order; admin-only LIST endpoints are separate.
"""

from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import NotFoundError
from app.db.models.order import Order
from app.db.models.user import User
from app.repositories import orders as orders_repo
from app.schemas.orders import (
    OrderDetail,
    OrderHistoryEntry,
    OrderHistoryPage,
    OrderItemOut,
    OrderPage,
    OrderSummary,
)

NOT_FOUND_MESSAGE = "Order not found."


def _ensure_visible(order: Order, user: User) -> None:
    if order.customer_id != user.id and user.role != "admin":
        # 404 (not 403): never leak existence of other customers' orders.
        raise NotFoundError(NOT_FOUND_MESSAGE)


def _summary(order: Order, restaurant_name: str) -> OrderSummary:
    return OrderSummary(
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


async def list_orders(
    session: AsyncSession,
    *,
    user: User,
    page: int,
    page_size: int,
    status: str | None = None,
) -> OrderPage:
    """Paginated CURRENT USER'S orders (route enforces the customer role)."""
    total = await orders_repo.count_customer_orders(session, customer_id=user.id, status=status)
    rows = await orders_repo.list_customer_orders(
        session, customer_id=user.id, page=page, page_size=page_size, status=status
    )
    return OrderPage(
        items=[_summary(order, restaurant_name) for order, restaurant_name in rows],
        page=page,
        page_size=page_size,
        total=total,
    )


async def get_order_detail(session: AsyncSession, *, user: User, order_id: str) -> OrderDetail:
    row = await orders_repo.get_order_with_restaurant(session, order_id)
    if row is None:
        raise NotFoundError(NOT_FOUND_MESSAGE)
    order, restaurant_name = row
    _ensure_visible(order, user)

    items = await orders_repo.list_order_items(session, order_id)
    detail = _summary(order, restaurant_name).model_dump()
    detail.update(
        delivery_address=order.delivery_address,
        failure_reason=order.failure_reason,
        driver_id=order.driver_id,
        items=[
            OrderItemOut(
                menu_item_id=item.menu_item_id,
                item_name=item.item_name,
                price_amount_minor=item.price_amount_minor,
                currency=item.currency,
                quantity=item.quantity,
                line_total_minor=item.line_total_minor,
            )
            for item in items
        ],
    )
    return OrderDetail.model_validate(detail)


async def get_order_history(
    session: AsyncSession, *, user: User, order_id: str
) -> OrderHistoryPage:
    row = await orders_repo.get_order_with_restaurant(session, order_id)
    if row is None:
        raise NotFoundError(NOT_FOUND_MESSAGE)
    order, _ = row
    _ensure_visible(order, user)

    entries = await orders_repo.list_history(session, order_id)
    timeline = [
        OrderHistoryEntry(
            version=entry.version,
            status=entry.status,
            from_status=entry.from_status,
            failure_code=entry.failure_code,
            source=entry.source,
            changed_at=entry.changed_at,
        )
        for entry in entries
    ]
    # One full page: the state machine bounds a history at seven entries, so
    # there is never more than one page (page_size >= 1 always holds).
    return OrderHistoryPage(
        items=timeline, page=1, page_size=max(len(timeline), 1), total=len(timeline)
    )
