"""Admin-scoped aggregate and cross-customer reads.

All queries here are intentionally READ-ONLY and unscoped by customer: they
are only ever reached through routes guarded by `require_admin`. Ordering
mirrors the customer list (created_at DESC, id tie-break) so pagination is
stable. Summary counts are single aggregate queries against authoritative
tables — never broker state — so the numbers always reflect committed
database truth.
"""

from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.driver import Driver
from app.db.models.order import Order
from app.db.models.outbox_event import OutboxEvent
from app.db.models.quarantine_record import QuarantineRecord
from app.db.models.restaurant import Restaurant
from app.db.models.retry_job import RetryJob
from app.db.models.user import User


async def count_all_orders(session: AsyncSession, *, status: str | None = None) -> int:
    stmt = select(func.count()).select_from(Order)
    if status is not None:
        stmt = stmt.where(Order.status == status)
    result = await session.execute(stmt)
    return int(result.scalar_one())


async def list_all_orders(
    session: AsyncSession,
    *,
    page: int,
    page_size: int,
    status: str | None = None,
) -> list[tuple[Order, str, str]]:
    """(order, restaurant_name, customer_email) — newest first, id tie-break."""
    stmt = (
        select(Order, Restaurant.name, User.email)
        .join(Restaurant, Order.restaurant_id == Restaurant.id)
        .join(User, Order.customer_id == User.id)
        .order_by(Order.created_at.desc(), Order.id.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    if status is not None:
        stmt = stmt.where(Order.status == status)
    result = await session.execute(stmt)
    return [(row[0], row[1], row[2]) for row in result.all()]


async def count_orders_by_status(session: AsyncSession) -> dict[str, int]:
    result = await session.execute(select(Order.status, func.count()).group_by(Order.status))
    return {status: int(count) for status, count in result.all()}


async def count_unpublished_outbox(session: AsyncSession) -> int:
    """Rows not yet CONFIRMED published: eligible (PENDING) plus leased
    in-flight rows (CLAIMED), including crash-orphaned leases."""
    result = await session.execute(
        select(func.count())
        .select_from(OutboxEvent)
        .where(OutboxEvent.state.in_(("PENDING", "CLAIMED")))
    )
    return int(result.scalar_one())


async def count_retry_backlog(session: AsyncSession) -> int:
    """Scheduled retries neither yet published nor exhausted."""
    result = await session.execute(
        select(func.count()).select_from(RetryJob).where(RetryJob.state == "PENDING")
    )
    return int(result.scalar_one())


async def count_quarantine(session: AsyncSession) -> int:
    result = await session.execute(select(func.count()).select_from(QuarantineRecord))
    return int(result.scalar_one())


async def count_distinct_drivers(session: AsyncSession) -> int:
    result = await session.execute(select(func.count()).select_from(Driver))
    return int(result.scalar_one())
