"""Checkout validation + authoritative pricing (assignment §6/§14).

Every rejected checkout must leave ZERO rows behind in all five tables the
acceptance transaction writes (orders, order_items, order_status_history,
checkout_idempotency, outbox_events) — no partial commits, ever.
"""

from __future__ import annotations

import asyncio
import uuid

import pytest
from sqlalchemy import delete, select, update

from app.db.models.menu_item import MenuItem
from app.db.models.order import Order
from app.db.models.order_item import OrderItem
from app.db.models.restaurant import Restaurant
from app.db.session import session_scope
from tests.conftest import auth_header, checkout_counts

ADDRESS = "12 Lake Road, Bengaluru"
RESTAURANT = "rest_bella_napoli"
MARGHERITA = "item_margherita_pizza"  # 28000 minor units
GARLIC_BREAD = "item_garlic_bread"  # 15000 minor units
UNAVAILABLE = "item_bbq_chicken_pizza"  # seeded unavailable
OTHER_RESTAURANT_ITEM = "item_dal_makhani"  # belongs to rest_spice_route


def _payload(**overrides) -> dict:
    payload = {
        "restaurant_id": RESTAURANT,
        "delivery_address": ADDRESS,
        "items": [{"menu_item_id": MARGHERITA, "quantity": 2}],
    }
    payload.update(overrides)
    return payload


def _checkout(client, token: str, payload: dict | None = None, *, key: str | None = None):
    return client.post(
        "/api/v1/orders",
        json=payload if payload is not None else _payload(),
        headers={
            **auth_header(token),
            "Idempotency-Key": key or str(uuid.uuid4()),
        },
    )


def _assert_rejected_without_writes(
    response,
    before: dict[str, int],
    *,
    status_code: int = 422,
    code: str = "VALIDATION_ERROR",
):
    """`before` MUST be captured before the request: equality afterwards is
    the no-partial-writes proof."""
    assert response.status_code == status_code, response.text
    body = response.json()
    assert body["code"] == code
    assert body["message"]
    assert "details" in body and body["request_id"]
    assert checkout_counts() == before, "rejected checkout must write nothing"


# ------------------------------ request shape ------------------------------


def test_missing_idempotency_key_is_422_and_writes_nothing(client, customer_token):
    before = checkout_counts()
    response = client.post(
        "/api/v1/orders",
        json=_payload(),
        headers=auth_header(customer_token),
    )
    assert response.status_code == 422
    body = response.json()
    assert body["code"] == "IDEMPOTENCY_KEY_REQUIRED"
    assert checkout_counts() == before


def test_blank_idempotency_key_is_rejected(client, customer_token):
    response = _checkout(client, customer_token, key="   ")
    assert response.status_code == 422
    assert response.json()["code"] == "IDEMPOTENCY_KEY_REQUIRED"


def test_client_supplied_prices_totals_and_customer_are_rejected(client, customer_token):
    """Authoritative money/identity NEVER comes from the client (§6/§20.3)."""
    before = checkout_counts()
    payload = _payload()
    payload["total_amount_minor"] = 1
    payload["price_amount_minor"] = 1
    payload["customer_id"] = "user_someone_else"
    response = _checkout(client, customer_token, payload)
    _assert_rejected_without_writes(response, before)


def test_zero_and_excessive_quantities_are_422(client, customer_token):
    before = checkout_counts()
    for bad_quantity in (0, 21, -3):
        response = _checkout(
            client,
            customer_token,
            _payload(items=[{"menu_item_id": MARGHERITA, "quantity": bad_quantity}]),
        )
        assert response.status_code == 422, response.text
        assert response.json()["code"] == "VALIDATION_ERROR"
    assert checkout_counts() == before


def test_empty_items_list_is_422(client, customer_token):
    response = _checkout(client, customer_token, _payload(items=[]))
    assert response.status_code == 422
    assert response.json()["code"] == "VALIDATION_ERROR"


def test_whitespace_only_address_is_422(client, customer_token):
    before = checkout_counts()
    response = _checkout(client, customer_token, _payload(delivery_address="   "))
    _assert_rejected_without_writes(response, before)
    assert response.json()["details"]["reason"] == "invalid_delivery_address"


def test_oversized_address_is_422(client, customer_token):
    response = _checkout(client, customer_token, _payload(delivery_address="A" * 501))
    assert response.status_code == 422
    assert response.json()["code"] == "VALIDATION_ERROR"


# ----------------------------- item validation -----------------------------


def test_unknown_restaurant_is_404_without_writes(client, customer_token):
    before = checkout_counts()
    response = _checkout(client, customer_token, _payload(restaurant_id="rest_does_not_exist"))
    assert response.status_code == 404
    assert response.json()["code"] == "NOT_FOUND"
    assert checkout_counts() == before


def test_item_from_another_restaurant_is_rejected(client, customer_token):
    """Mixed-restaurant orders are impossible: items must belong to the order's
    restaurant (§6)."""
    before = checkout_counts()
    response = _checkout(
        client,
        customer_token,
        _payload(items=[{"menu_item_id": OTHER_RESTAURANT_ITEM, "quantity": 1}]),
    )
    _assert_rejected_without_writes(response, before)
    assert response.json()["details"]["reason"] == "item_not_in_restaurant"


def test_unavailable_item_is_rejected(client, customer_token):
    before = checkout_counts()
    response = _checkout(
        client,
        customer_token,
        _payload(items=[{"menu_item_id": UNAVAILABLE, "quantity": 1}]),
    )
    _assert_rejected_without_writes(response, before)
    assert response.json()["details"]["reason"] == "item_unavailable"


def test_unknown_menu_item_is_rejected(client, customer_token):
    before = checkout_counts()
    response = _checkout(
        client,
        customer_token,
        _payload(items=[{"menu_item_id": "item_nope", "quantity": 1}]),
    )
    _assert_rejected_without_writes(response, before)
    assert response.json()["details"]["reason"] == "unknown_item"


def test_mixed_restaurant_request_is_rejected(client, customer_token):
    """One order per restaurant: valid + foreign item in the same request."""
    before = checkout_counts()
    response = _checkout(
        client,
        customer_token,
        _payload(
            items=[
                {"menu_item_id": MARGHERITA, "quantity": 1},
                {"menu_item_id": OTHER_RESTAURANT_ITEM, "quantity": 1},
            ]
        ),
    )
    _assert_rejected_without_writes(response, before)
    assert response.json()["details"]["reason"] == "item_not_in_restaurant"


def test_more_than_twenty_distinct_items_is_422(client, customer_token):
    """Documented limit: at most 20 distinct items per order (§6). Uses a
    purpose-built restaurant so the seeded catalog is never altered."""
    before = checkout_counts()

    async def _seed_limits_restaurant() -> None:
        async with session_scope() as session:
            session.add(
                Restaurant(
                    id="rest_test_item_limits",
                    name="Test Limits Diner",
                    description="Temporary fixture for limit tests.",
                    currency="INR",
                    is_available=True,
                )
            )
            # Flush the parent row first: without ORM relationships the unit
            # of work does not order these inserts by plain foreign keys.
            await session.flush()
            for index in range(21):
                session.add(
                    MenuItem(
                        id=f"item_test_limit_{index:02d}",
                        restaurant_id="rest_test_item_limits",
                        name=f"Limit Item {index:02d}",
                        price_amount_minor=1000,
                        currency="INR",
                        is_available=True,
                        sort_order=index,
                    )
                )

    async def _cleanup() -> None:
        async with session_scope() as session:
            await session.execute(
                delete(MenuItem).where(MenuItem.restaurant_id == "rest_test_item_limits")
            )
            await session.execute(
                delete(Restaurant).where(Restaurant.id == "rest_test_item_limits")
            )

    try:
        asyncio.run(_seed_limits_restaurant())
        response = _checkout(
            client,
            customer_token,
            _payload(
                restaurant_id="rest_test_item_limits",
                items=[
                    {"menu_item_id": f"item_test_limit_{index:02d}", "quantity": 1}
                    for index in range(21)
                ],
            ),
        )
        _assert_rejected_without_writes(response, before)
        assert response.json()["details"]["reason"] == "too_many_distinct_items"
    finally:
        asyncio.run(_cleanup())


# ---------------------------- merge and pricing ----------------------------


def test_duplicate_lines_are_merged_within_quantity_bounds(client, customer_token):
    """Repeated lines for one item merge; the merged total may not exceed 20."""
    before = checkout_counts()
    response = _checkout(
        client,
        customer_token,
        _payload(
            items=[
                {"menu_item_id": MARGHERITA, "quantity": 12},
                {"menu_item_id": MARGHERITA, "quantity": 12},
            ]
        ),
    )
    assert response.status_code == 422
    assert response.json()["details"]["reason"] == "quantity_out_of_bounds"
    assert checkout_counts() == before


def test_server_prices_and_snapshots_drive_the_total(client, customer_token):
    """Total = sum(current menu price x qty) in integer minor units, and each
    order item snapshots the server price it used (§6/§14)."""
    response = _checkout(
        client,
        customer_token,
        _payload(
            items=[
                {"menu_item_id": MARGHERITA, "quantity": 2},  # 2 * 28000
                {"menu_item_id": GARLIC_BREAD, "quantity": 1},  # 1 * 15000
            ]
        ),
    )
    assert response.status_code == 202, response.text
    body = response.json()
    assert body["total_amount_minor"] == 2 * 28000 + 15000  # 71000
    assert body["currency"] == "INR"

    order_id = body["order_id"]

    async def _verify():
        async with session_scope() as session:
            order = (await session.execute(select(Order).where(Order.id == order_id))).scalar_one()
            items = list(
                (
                    await session.execute(select(OrderItem).where(OrderItem.order_id == order_id))
                ).scalars()
            )
            return order, items

    order, items = asyncio.run(_verify())
    assert order.total_amount_minor == 71000
    by_id = {item.menu_item_id: item for item in items}
    assert by_id[MARGHERITA].price_amount_minor == 28000  # snapshot, not client input
    assert by_id[MARGHERITA].line_total_minor == 56000
    assert by_id[GARLIC_BREAD].price_amount_minor == 15000
    assert len(items) == 2


def test_total_follows_current_menu_price_change(client, customer_token):
    """Authoritative pricing: a menu edit between seeding and checkout changes
    what the customer pays (and what gets snapshotted)."""
    new_price = 30500

    async def _reprice(restore: bool) -> None:
        async with session_scope() as session:
            if restore:
                await session.execute(
                    update(MenuItem)
                    .where(MenuItem.id == MARGHERITA)
                    .values(price_amount_minor=28000)
                )
            else:
                await session.execute(
                    update(MenuItem)
                    .where(MenuItem.id == MARGHERITA)
                    .values(price_amount_minor=new_price)
                )

    try:
        asyncio.run(_reprice(restore=False))
        response = _checkout(
            client,
            customer_token,
            _payload(items=[{"menu_item_id": MARGHERITA, "quantity": 2}]),
        )
        assert response.status_code == 202, response.text
        assert response.json()["total_amount_minor"] == new_price * 2
    finally:
        asyncio.run(_reprice(restore=True))


def test_batch_of_invalid_checkouts_changes_nothing(client, customer_token):
    """Aggregate guarantee: however the client misbehaves, the five tables are
    untouched until ONE fully valid checkout commits them all together."""
    before = checkout_counts()

    invalid_requests = [
        (_payload(restaurant_id="rest_missing"), 404),
        (_payload(delivery_address=""), 422),
        (
            _payload(items=[{"menu_item_id": UNAVAILABLE, "quantity": 1}]),
            422,
        ),
        (
            _payload(items=[{"menu_item_id": OTHER_RESTAURANT_ITEM, "quantity": 1}]),
            422,
        ),
        (_payload(items=[]), 422),
    ]
    for payload, expected in invalid_requests:
        response = _checkout(client, customer_token, payload)
        assert response.status_code == expected, response.text

    assert checkout_counts() == before

    # One valid request afterwards commits exactly its own rows.
    accepted = _checkout(client, customer_token)
    assert accepted.status_code == 202
    after = checkout_counts()
    assert after["orders"] == before["orders"] + 1
    assert after["order_items"] == before["order_items"] + 1  # margherita only
    assert after["order_status_history"] == before["order_status_history"] + 1
    assert after["checkout_idempotency"] == before["checkout_idempotency"] + 1
    assert after["outbox_events"] == before["outbox_events"] + 1


@pytest.mark.parametrize("key_length", [1, 128])
def test_idempotency_key_length_bounds(client, customer_token, key_length):
    key = "k" * key_length
    response = _checkout(client, customer_token, key=key)
    assert response.status_code == 202, response.text


def test_oversized_idempotency_key_is_422(client, customer_token):
    before = checkout_counts()
    response = _checkout(client, customer_token, key="k" * 129)
    assert response.status_code == 422
    assert response.json()["details"]["reason"] == "idempotency_key_too_long"
    assert checkout_counts() == before


def test_unauthenticated_checkout_is_401(client):
    response = client.post(
        "/api/v1/orders",
        json=_payload(),
        headers={"Idempotency-Key": str(uuid.uuid4())},
    )
    assert response.status_code == 401
    assert response.json()["code"] == "UNAUTHENTICATED"
