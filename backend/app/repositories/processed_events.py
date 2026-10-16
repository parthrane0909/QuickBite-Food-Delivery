"""Consumer deduplication lookups: UNIQUE (consumer_name, event_id).

The runtime checks the marker AFTER locking the order row, so a competing
copy of the same event waits on the lock, then observes the committed marker
and no-ops (assignment §10: unique logical consumer + event identity).
"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.processed_event import ProcessedEvent


async def get_marker(
    session: AsyncSession, *, consumer_name: str, event_id: str
) -> ProcessedEvent | None:
    result = await session.execute(
        select(ProcessedEvent).where(
            ProcessedEvent.consumer_name == consumer_name,
            ProcessedEvent.event_id == event_id,
        )
    )
    return result.scalar_one_or_none()
