"""Checkout idempotency storage: scope (customer_id, key) under a UNIQUE
constraint, so the database — not application luck — arbitrates concurrent
duplicates (assignment §7/§14).

Reads are always scoped by customer: two customers may legitimately use the
same key value without colliding. Conflict/concurrency resolution (catch the
unique violation, re-read, replay or 409) lives in checkout_service.
"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.checkout_idempotency import CheckoutIdempotency


async def get_for_customer(
    session: AsyncSession, *, customer_id: str, idempotency_key: str
) -> CheckoutIdempotency | None:
    result = await session.execute(
        select(CheckoutIdempotency).where(
            CheckoutIdempotency.customer_id == customer_id,
            CheckoutIdempotency.idempotency_key == idempotency_key,
        )
    )
    return result.scalar_one_or_none()
