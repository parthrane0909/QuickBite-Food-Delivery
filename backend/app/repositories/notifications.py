"""Persisted notification reads (owner/admin feed, cursorless pagination)."""

from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.notification import Notification


async def count_for_order(session: AsyncSession, *, order_id: str) -> int:
    result = await session.execute(
        select(func.count()).select_from(Notification).where(Notification.order_id == order_id)
    )
    return int(result.scalar_one())


async def list_for_order(
    session: AsyncSession, *, order_id: str, page: int, page_size: int
) -> list[Notification]:
    """Chronological (`seq` ascending): one page holds every notification a
    single order can produce (at most one per domain event)."""
    result = await session.execute(
        select(Notification)
        .where(Notification.order_id == order_id)
        .order_by(Notification.seq.asc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    return list(result.scalars())
