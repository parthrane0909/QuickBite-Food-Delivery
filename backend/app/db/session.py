"""Async SQLAlchemy engine/session lifecycle.

Rules:
- One engine per process (connection pool shared).
- An AsyncSession is created per request/unit-of-work and NEVER shared across
  concurrent tasks.
- Transactions are managed explicitly by services (checkout and workers use
  long-lived, locked transactions; reads use short ones).
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from functools import lru_cache

from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.core.config import get_settings


@lru_cache(maxsize=1)
def get_engine() -> AsyncEngine:
    settings = get_settings()
    kwargs: dict = {"pool_pre_ping": True}
    if settings.environment == "test":
        # TestClient (httpx2/anyio portals) may run requests on different
        # event loops; asyncpg connections are loop-bound, so pooling across
        # requests would fail with "attached to a different loop". Tests get
        # a fresh connection per checkout (NullPool); production keeps pooling.
        from sqlalchemy.pool import NullPool

        kwargs["poolclass"] = NullPool
    else:
        kwargs.update(pool_size=10, max_overflow=20, pool_recycle=1800)
    return create_async_engine(settings.database_url, **kwargs)


@lru_cache(maxsize=1)
def get_sessionmaker() -> async_sessionmaker[AsyncSession]:
    return async_sessionmaker(get_engine(), expire_on_commit=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    """FastAPI dependency: one session per request, commit/rollback on exit."""
    session_factory = get_sessionmaker()
    async with session_factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


@asynccontextmanager
async def session_scope() -> AsyncIterator[AsyncSession]:
    """Programmatic unit-of-work for scripts and background processes."""
    session_factory = get_sessionmaker()
    async with session_factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


async def check_database(timeout: float) -> None:
    """Bounded-time SELECT 1 probe; raises on any failure.

    *timeout* is applied by the caller (readiness endpoint wraps this in
    ``asyncio.wait_for``) so probes never hang past the configured budget.
    """
    del timeout  # enforced by caller; kept for explicit API contract
    async with get_engine().connect() as connection:
        await connection.execute(text("SELECT 1"))


async def dispose_engine() -> None:
    await get_engine().dispose()
