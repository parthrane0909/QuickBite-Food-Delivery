"""Admin overview API (assignment §7/§14; admin endpoints delivered in M5).

Covers: 401 unauthenticated, 403 for customers (envelope), admin
cross-customer pagination with stable ordering, page_size maximum (422),
optional exact-status filter, customer identification via customer_email,
and summary counts that match authoritative PostgreSQL state exactly.
"""

from __future__ import annotations

import asyncio
import uuid
from datetime import datetime

from tests.conftest import auth_header

ADDRESS = "42 Admin Avenue, Bengaluru"
RESTAURANT = "rest_bella_napoli"
MARGHERITA = "item_margherita_pizza"

ALL_STATUSES = (
    "PENDING",
    "PAID",
    "CONFIRMED",
    "DRIVER_ASSIGNED",
    "PAYMENT_FAILED",
    "FAILED",
)


def _payload(**overrides) -> dict:
    payload = {
        "restaurant_id": RESTAURANT,
        "delivery_address": ADDRESS,
        "items": [{"menu_item_id": MARGHERITA, "quantity": 1}],
    }
    payload.update(overrides)
    return payload


def _place_order(client, token: str, *, key: str | None = None) -> dict:
    response = client.post(
        "/api/v1/orders",
        json=_payload(),
        headers={**auth_header(token), "Idempotency-Key": key or str(uuid.uuid4())},
    )
    assert response.status_code == 202, response.text
    return response.json()


def _assert_envelope(body: dict, *, code: str) -> None:
    assert set(body) >= {"code", "message", "details", "request_id"}
    assert body["code"] == code
    assert isinstance(body["message"], str) and body["message"]
    assert body["request_id"]


def _db_counts() -> dict:
    """Authoritative table counts, read directly from PostgreSQL."""
    from sqlalchemy import func, select

    from app.db.models.order import Order
    from app.db.models.outbox_event import OutboxEvent
    from app.db.models.quarantine_record import QuarantineRecord
    from app.db.models.retry_job import RetryJob
    from app.db.session import session_scope

    async def _read() -> dict:
        async with session_scope() as session:
            orders = dict(
                (
                    await session.execute(select(Order.status, func.count()).group_by(Order.status))
                ).all()
            )
            outbox = (
                await session.execute(
                    select(func.count())
                    .select_from(OutboxEvent)
                    .where(OutboxEvent.state.in_(("PENDING", "CLAIMED")))
                )
            ).scalar_one()
            retries = (
                await session.execute(
                    select(func.count()).select_from(RetryJob).where(RetryJob.state == "PENDING")
                )
            ).scalar_one()
            quarantines = (
                await session.execute(select(func.count()).select_from(QuarantineRecord))
            ).scalar_one()
        return {
            "orders_by_status": {s: int(orders.get(s, 0)) for s in ALL_STATUSES},
            "pending_outbox_events": int(outbox),
            "retry_backlog": int(retries),
            "quarantine_records": int(quarantines),
        }

    return asyncio.run(_read())


# ------------------------------ access control -----------------------------


def test_admin_endpoints_require_authentication(client):
    for path in ("/api/v1/admin/orders", "/api/v1/admin/summary"):
        response = client.get(path)
        assert response.status_code == 401, response.text
        _assert_envelope(response.json(), code="UNAUTHENTICATED")


def test_admin_endpoints_forbid_customers(client, customer_token):
    for path in ("/api/v1/admin/orders", "/api/v1/admin/summary"):
        response = client.get(path, headers=auth_header(customer_token))
        assert response.status_code == 403, response.text
        _assert_envelope(response.json(), code="FORBIDDEN")


def test_customer_authorization_is_unchanged_by_admin_endpoints(
    client, customer_token, second_customer_token
):
    """The admin surface adds no new customer-visible data: bob still cannot
    see alice's orders (404, never 403)."""
    order = _place_order(client, second_customer_token)
    response = client.get(
        f"/api/v1/orders/{order['order_id']}", headers=auth_header(customer_token)
    )
    assert response.status_code == 404, response.text
    _assert_envelope(response.json(), code="NOT_FOUND")


# ------------------------------ order listing ------------------------------


def test_admin_orders_pagination_contract(client, admin_token, customer_token):
    placed = [_place_order(client, customer_token)["order_id"] for _ in range(3)]

    response = client.get(
        "/api/v1/admin/orders", params={"page_size": 2}, headers=auth_header(admin_token)
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert set(body) == {"items", "page", "page_size", "total"}
    assert body["page"] == 1 and body["page_size"] == 2
    assert body["total"] >= 3
    assert len(body["items"]) == 2

    page2 = client.get(
        "/api/v1/admin/orders",
        params={"page": 2, "page_size": 2},
        headers=auth_header(admin_token),
    ).json()
    seen = [item["id"] for item in body["items"] + page2["items"]]
    # Newest first: the three just-placed ids lead the listing in reverse.
    assert seen[:3] == list(reversed(placed))
    assert len(seen) == len(set(seen)), "pages must not duplicate orders"


def test_admin_orders_page_size_maximum(client, admin_token):
    assert (
        client.get(
            "/api/v1/admin/orders", params={"page_size": 100}, headers=auth_header(admin_token)
        ).status_code
        == 200
    )
    assert (
        client.get(
            "/api/v1/admin/orders", params={"page_size": 101}, headers=auth_header(admin_token)
        ).status_code
        == 422
    )
    assert (
        client.get(
            "/api/v1/admin/orders", params={"page": 0}, headers=auth_header(admin_token)
        ).status_code
        == 422
    )


def test_admin_orders_status_filter(client, admin_token, customer_token):
    order = _place_order(client, customer_token)  # stays PENDING (no workers in tests)

    filtered = client.get(
        "/api/v1/admin/orders",
        params={"status": "PENDING"},
        headers=auth_header(admin_token),
    ).json()
    assert any(item["id"] == order["order_id"] for item in filtered["items"])
    assert all(item["status"] == "PENDING" for item in filtered["items"])

    empty = client.get(
        "/api/v1/admin/orders",
        params={"status": "DRIVER_ASSIGNED"},
        headers=auth_header(admin_token),
    ).json()
    assert all(item["status"] == "DRIVER_ASSIGNED" for item in empty["items"])

    invalid = client.get(
        "/api/v1/admin/orders",
        params={"status": "DELIVERED"},
        headers=auth_header(admin_token),
    )
    assert invalid.status_code == 422, invalid.text


def test_admin_orders_identify_the_customer(client, admin_token, customer_token):
    from scripts.seed_demo import SEED_ACCOUNTS

    account = next(a for a in SEED_ACCOUNTS if a["role"] == "customer")
    order = _place_order(client, customer_token)

    body = client.get(
        "/api/v1/admin/orders", params={"page_size": 100}, headers=auth_header(admin_token)
    ).json()
    item = next(i for i in body["items"] if i["id"] == order["order_id"])
    assert item["customer_email"] == account["email"]
    assert item["restaurant_name"]  # joined restaurant name, per the contract
    assert set(item) >= {
        "id",
        "restaurant_id",
        "restaurant_name",
        "status",
        "currency",
        "total_amount_minor",
        "version",
        "failure_code",
        "created_at",
        "updated_at",
        "customer_email",
    }


def test_admin_orders_created_at_is_timezone_aware(client, admin_token, customer_token):
    _place_order(client, customer_token)
    item = client.get("/api/v1/admin/orders", headers=auth_header(admin_token)).json()["items"][0]
    created = datetime.fromisoformat(item["created_at"])
    assert created.tzinfo is not None


# --------------------------------- summary ---------------------------------


def test_admin_summary_matches_database_exactly(client, admin_token, customer_token):
    before = _db_counts()
    order = _place_order(client, customer_token)
    after = _db_counts()

    response = client.get("/api/v1/admin/summary", headers=auth_header(admin_token))
    assert response.status_code == 200, response.text
    body = response.json()

    # The checkout committed one PENDING order and one PENDING outbox row.
    assert after["orders_by_status"]["PENDING"] == before["orders_by_status"]["PENDING"] + 1
    assert after["pending_outbox_events"] == before["pending_outbox_events"] + 1

    # API counts equal authoritative table counts field-for-field.
    assert body["orders_by_status"] == after["orders_by_status"]
    assert body["pending_outbox_events"] == after["pending_outbox_events"]
    assert body["retry_backlog"] == after["retry_backlog"]
    assert body["quarantine_records"] == after["quarantine_records"]

    # Every status key is present (zero included), non-negative counts.
    assert set(body["orders_by_status"]) == set(ALL_STATUSES)
    assert all(count >= 0 for count in body["orders_by_status"].values())
    assert all(
        body[field] >= 0
        for field in ("pending_outbox_events", "retry_backlog", "quarantine_records")
    )
    assert datetime.fromisoformat(body["generated_at"]).tzinfo is not None

    # The placed order is visible in the cross-customer listing too.
    ids = {
        item["id"]
        for item in client.get(
            "/api/v1/admin/orders",
            params={"page_size": 100},
            headers=auth_header(admin_token),
        ).json()["items"]
    }
    assert order["order_id"] in ids
