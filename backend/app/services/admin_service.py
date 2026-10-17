"""Admin read-only service (assignment §7 admin overview).

Thin assembly layer: executes admin-scoped repository queries and maps them
into the documented response contracts. Timestamps come from the database
clock (`func.now()` in the same query) so `generated_at` is consistent with
the counts it accompanies.
"""

from __future__ import annotations

from sqlalchemy import func
from sqlalchemy.ext.asyncio import AsyncSession

from app.repositories import admin as admin_repo
from app.schemas.admin import (
    ALL_ORDER_STATUSES,
    AdminOrderItem,
    AdminOrderPage,
    AdminSummary,
)


async def list_orders(
    session: AsyncSession,
    *,
    page: int,
    page_size: int,
    status: str | None = None,
) -> AdminOrderPage:
    """Paginated cross-customer order listing, newest first."""
    total = await admin_repo.count_all_orders(session, status=status)
    rows = await admin_repo.list_all_orders(session, page=page, page_size=page_size, status=status)
    items = [
        AdminOrderItem(
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
            customer_email=customer_email,
        )
        for order, restaurant_name, customer_email in rows
    ]
    return AdminOrderPage(items=items, page=page, page_size=page_size, total=total)


async def get_summary(session: AsyncSession) -> AdminSummary:
    """Aggregate counts from authoritative PostgreSQL state (see
    `AdminSummary` for the exact counting semantics of each field)."""
    by_status = await admin_repo.count_orders_by_status(session)
    orders_by_status = {status: by_status.get(status, 0) for status in ALL_ORDER_STATUSES}

    generated_at = (await session.execute(func.now())).scalar_one()
    return AdminSummary(
        orders_by_status=orders_by_status,
        pending_outbox_events=await admin_repo.count_unpublished_outbox(session),
        retry_backlog=await admin_repo.count_retry_backlog(session),
        quarantine_records=await admin_repo.count_quarantine(session),
        generated_at=generated_at,
    )


__all__ = ["get_summary", "list_orders"]
