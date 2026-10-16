"""Pytest bootstrap: an isolated, migrated and seeded PostgreSQL database
per test session (REAL PostgreSQL — assignment §14 forbids mock-only
evidence for anything transactional).

Canonical invocation, inside the backend image against Compose services:

    docker compose up -d postgres rabbitmq
    docker compose run --rm api pytest

The database URL is captured from the environment, redirected to
`quickbite_test`, migrations are applied via Alembic and the standard demo
seed runs, so tests never touch the development database. The test database
is dropped afterwards.
"""

from __future__ import annotations

import asyncio
import os
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
TEST_DB_NAME = "quickbite_test"


def _with_database(url: str, dbname: str) -> str:
    parts = urlsplit(url)
    return urlunsplit((parts.scheme, parts.netloc, f"/{dbname}", parts.query, parts.fragment))


def _ensure_env_defaults() -> None:
    """Provide test-safe values when the environment doesn't define them."""
    # ENVIRONMENT is FORCED (not defaulted): tests require test-mode behavior
    # such as the NullPool engine, regardless of a development .env.
    os.environ["ENVIRONMENT"] = "test"
    os.environ.setdefault("LOG_LEVEL", "WARNING")
    os.environ.setdefault("JWT_SECRET", "quickbite-test-secret-0123456789abcdef")
    os.environ.setdefault("AMQP_URL", "amqp://quickbite:change-me-rabbit@127.0.0.1:5672/")
    os.environ.setdefault("CORS_ORIGINS", "http://localhost:5000,http://localhost:8080")


def _bootstrap_test_database() -> None:
    """(Re)create the test DB, migrate it and seed it. Runs at import time so
    every app import inside test modules already targets the test database."""
    _ensure_env_defaults()

    base_url = os.environ.get("DATABASE_URL", "").strip()
    if not base_url:
        raise RuntimeError(
            "DATABASE_URL must be set before running tests. "
            "Use: docker compose run --rm api pytest  (or export the host URL from .env)."
        )

    maintenance_url = _with_database(base_url, "postgres")
    test_url = _with_database(base_url, TEST_DB_NAME)

    async def _recreate() -> None:
        from sqlalchemy import text
        from sqlalchemy.ext.asyncio import create_async_engine

        engine = create_async_engine(maintenance_url)
        try:
            async with engine.connect() as conn:
                await conn.execute(text("COMMIT"))  # leave autocommit-ish state for DDL
                await conn.execute(text(f"DROP DATABASE IF EXISTS {TEST_DB_NAME} WITH (FORCE)"))
                await conn.execute(text(f"CREATE DATABASE {TEST_DB_NAME}"))
        finally:
            await engine.dispose()

    asyncio.run(_recreate())

    # Point the app AND Alembic at the test database before any app import.
    os.environ["DATABASE_URL"] = test_url

    subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=BACKEND_DIR,
        check=True,
        env={**os.environ},
    )

    async def _seed() -> None:
        from app.db.session import session_scope
        from scripts.seed_demo import seed_all

        async with session_scope() as session:
            await seed_all(session)

    asyncio.run(_seed())


def _drop_test_database() -> None:
    async def _drop() -> None:
        from sqlalchemy import text
        from sqlalchemy.ext.asyncio import create_async_engine

        base_url = os.environ["DATABASE_URL"]
        engine = create_async_engine(_with_database(base_url, "postgres"))
        try:
            async with engine.connect() as conn:
                await conn.execute(text("COMMIT"))
                await conn.execute(text(f"DROP DATABASE IF EXISTS {TEST_DB_NAME} WITH (FORCE)"))
        finally:
            await engine.dispose()

    asyncio.run(_drop())


_bootstrap_test_database()


def pytest_sessionfinish(session, exitstatus):  # noqa: ANN001, ANN201
    _drop_test_database()


@pytest.fixture()
def client():
    from fastapi.testclient import TestClient

    from app.main import create_app

    with TestClient(create_app()) as test_client:
        yield test_client


@pytest.fixture()
def login(client):
    def _login(email: str, password: str) -> dict:
        response = client.post("/api/v1/auth/login", json={"email": email, "password": password})
        assert response.status_code == 200, response.text
        return response.json()

    return _login


@pytest.fixture()
def customer_token(login) -> str:
    from scripts.seed_demo import SEED_ACCOUNTS

    account = next(a for a in SEED_ACCOUNTS if a["role"] == "customer")
    return login(account["email"], account["password"])["access_token"]


@pytest.fixture()
def customer_id() -> str:
    """The seeded primary customer's stable user id."""
    from scripts.seed_demo import SEED_ACCOUNTS

    return next(a for a in SEED_ACCOUNTS if a["role"] == "customer")["id"]


@pytest.fixture()
def second_customer_token(login) -> str:
    """A DIFFERENT seeded customer (bob) — used for ownership isolation."""
    from scripts.seed_demo import SEED_ACCOUNTS

    customers = [a for a in SEED_ACCOUNTS if a["role"] == "customer"]
    assert len(customers) >= 2, "seed must provide a second customer"
    return login(customers[1]["email"], customers[1]["password"])["access_token"]


@pytest.fixture()
def admin_token(login) -> str:
    from scripts.seed_demo import SEED_ACCOUNTS

    account = next(a for a in SEED_ACCOUNTS if a["role"] == "admin")
    return login(account["email"], account["password"])["access_token"]


@pytest.fixture()
async def async_client():
    """ASGI client on the SAME app — several of these run concurrently in one
    event loop, with NullPool giving every request its own PostgreSQL
    connection: real concurrent transactions for idempotency tests."""
    import httpx2

    from app.main import create_app

    transport = httpx2.ASGITransport(app=create_app())
    async with httpx2.AsyncClient(transport=transport, base_url="http://testserver") as client:
        yield client


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def count_rows_async(*entities) -> dict[str, int]:
    """Row counts keyed by table name — proves 'no partial writes' and
    'exactly one order/event' claims directly against PostgreSQL."""
    from sqlalchemy import func, select

    from app.db.session import session_scope

    counts: dict[str, int] = {}
    async with session_scope() as session:
        for entity in entities:
            table = entity.__tablename__
            result = await session.execute(select(func.count()).select_from(entity))
            counts[table] = int(result.scalar_one())
    return counts


def count_rows(*entities) -> dict[str, int]:
    """Sync wrapper for tests that are not async."""
    return asyncio.run(count_rows_async(*entities))


async def checkout_counts_async() -> dict[str, int]:
    """Counts of every table the acceptance transaction must (or must not)
    write: order, items, history, idempotency record and outbox event."""
    from app.db.models.checkout_idempotency import CheckoutIdempotency
    from app.db.models.order import Order
    from app.db.models.order_item import OrderItem
    from app.db.models.order_status_history import OrderStatusHistory
    from app.db.models.outbox_event import OutboxEvent

    return await count_rows_async(
        Order, OrderItem, OrderStatusHistory, OutboxEvent, CheckoutIdempotency
    )


def checkout_counts() -> dict[str, int]:
    return asyncio.run(checkout_counts_async())
