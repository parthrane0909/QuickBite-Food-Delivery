"""API contract, access control and order reads (assignment §7/§14).

Covers: 401/403/404 error envelopes with correct codes, owner-or-admin
authorization (other customers -> 404), pagination conventions (max 100,
items/page/page_size/total, stable ordering), optional status filter,
UTC timezone-aware timestamps and the exported OpenAPI document.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from math import ceil

from tests.conftest import auth_header

ADDRESS = "12 Lake Road, Bengaluru"
RESTAURANT = "rest_bella_napoli"
MARGHERITA = "item_margherita_pizza"


def _payload(**overrides) -> dict:
    payload = {
        "restaurant_id": RESTAURANT,
        "delivery_address": ADDRESS,
        "items": [{"menu_item_id": MARGHERITA, "quantity": 1}],
    }
    payload.update(overrides)
    return payload


def _place_order(client, token: str, *, key: str | None = None, payload: dict | None = None):
    response = client.post(
        "/api/v1/orders",
        json=payload if payload is not None else _payload(),
        headers={**auth_header(token), "Idempotency-Key": key or str(uuid.uuid4())},
    )
    assert response.status_code == 202, response.text
    return response


def _assert_envelope(body: dict, *, code: str) -> None:
    assert set(body) >= {"code", "message", "details", "request_id"}
    assert body["code"] == code
    assert isinstance(body["message"], str) and body["message"]
    assert body["request_id"]


# ------------------------------ access control -----------------------------


def test_orders_endpoints_require_authentication(client):
    assert client.get("/api/v1/orders").status_code == 401
    detail = client.get("/api/v1/orders/order_whatever")
    assert detail.status_code == 401
    _assert_envelope(detail.json(), code="UNAUTHENTICATED")


def test_menu_item_deep_link_resolves_item_outside_current_menu_page(client, customer_token):
    response = client.get(
        "/api/v1/restaurants/rest_spice_route/menu/item_mango_lassi",
        headers=auth_header(customer_token),
    )
    assert response.status_code == 200, response.text
    assert response.json()["id"] == "item_mango_lassi"

    wrong_restaurant = client.get(
        "/api/v1/restaurants/rest_bella_napoli/menu/item_mango_lassi",
        headers=auth_header(customer_token),
    )
    assert wrong_restaurant.status_code == 404
    assert (
        client.get("/api/v1/restaurants/rest_spice_route/menu/item_mango_lassi").status_code == 401
    )


def test_restaurant_search_and_cuisine_filters_are_server_side(client, customer_token):
    headers = auth_header(customer_token)
    by_name = client.get(
        "/api/v1/restaurants",
        headers=headers,
        params={"search": "Bella", "page_size": 5},
    )
    assert by_name.status_code == 200, by_name.text
    assert by_name.json()["total"] == 1
    assert by_name.json()["items"][0]["id"] == "rest_bella_napoli"

    by_dish = client.get(
        "/api/v1/restaurants",
        headers=headers,
        params={"search": "Margherita", "page_size": 5},
    )
    assert by_dish.status_code == 200, by_dish.text
    assert any(row["id"] == "rest_bella_napoli" for row in by_dish.json()["items"])

    by_partial_cuisine = client.get(
        "/api/v1/restaurants",
        headers=headers,
        params={"search": "tali", "page_size": 5},
    )
    assert by_partial_cuisine.status_code == 200, by_partial_cuisine.text
    assert any(row["id"] == "rest_bella_napoli" for row in by_partial_cuisine.json()["items"])

    by_cuisine = client.get(
        "/api/v1/restaurants",
        headers=headers,
        params={"cuisine": "Italian", "page_size": 5},
    )
    assert by_cuisine.status_code == 200, by_cuisine.text
    assert by_cuisine.json()["items"]
    assert all(row["cuisine"] == "Italian" for row in by_cuisine.json()["items"])

    cuisines = client.get("/api/v1/restaurants/cuisines", headers=headers)
    assert cuisines.status_code == 200, cuisines.text
    assert "Italian" in cuisines.json()["items"]


def test_admin_can_checkout_as_own_shopping_identity(client, admin_token):
    response = client.post(
        "/api/v1/orders",
        json=_payload(),
        headers={**auth_header(admin_token), "Idempotency-Key": str(uuid.uuid4())},
    )
    assert response.status_code == 202, response.text
    orders = client.get("/api/v1/orders", headers=auth_header(admin_token)).json()["items"]
    assert any(row["id"] == response.json()["order_id"] for row in orders)


def test_admin_order_list_is_owner_scoped_shopping_history(client, admin_token):
    response = client.get("/api/v1/orders", headers=auth_header(admin_token))
    assert response.status_code == 200, response.text
    assert all("customer_email" not in row for row in response.json()["items"])


def test_customer_cannot_read_another_customers_order(
    client, customer_token, second_customer_token
):
    order_id = _place_order(client, customer_token).json()["order_id"]

    detail = client.get(f"/api/v1/orders/{order_id}", headers=auth_header(second_customer_token))
    assert detail.status_code == 404  # 404, never 403: no existence leak
    _assert_envelope(detail.json(), code="NOT_FOUND")

    history = client.get(
        f"/api/v1/orders/{order_id}/history", headers=auth_header(second_customer_token)
    )
    assert history.status_code == 404
    _assert_envelope(history.json(), code="NOT_FOUND")


def test_owner_and_admin_can_read_the_order(client, customer_token, admin_token):
    order_id = _place_order(client, customer_token).json()["order_id"]

    owner = client.get(f"/api/v1/orders/{order_id}", headers=auth_header(customer_token))
    assert owner.status_code == 200

    admin = client.get(f"/api/v1/orders/{order_id}", headers=auth_header(admin_token))
    assert admin.status_code == 200
    assert admin.json()["id"] == order_id

    admin_history = client.get(
        f"/api/v1/orders/{order_id}/history", headers=auth_header(admin_token)
    )
    assert admin_history.status_code == 200


def test_unknown_order_id_is_404_for_its_owner(client, customer_token):
    response = client.get(
        "/api/v1/orders/order_does_not_exist", headers=auth_header(customer_token)
    )
    assert response.status_code == 404
    _assert_envelope(response.json(), code="NOT_FOUND")


# ------------------------------- order reads -------------------------------


def test_order_detail_shape_and_snapshots(client, customer_token):
    order_id = _place_order(client, customer_token).json()["order_id"]
    response = client.get(f"/api/v1/orders/{order_id}", headers=auth_header(customer_token))
    assert response.status_code == 200
    body = response.json()
    assert set(body) == {
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
        "delivery_address",
        "failure_reason",
        "driver_id",
        "items",
    }
    assert body["id"] == order_id
    assert body["restaurant_name"]  # joined for display, not client-inferred
    assert body["status"] == "PENDING"
    assert body["total_amount_minor"] == 28000
    assert body["failure_code"] is None and body["failure_reason"] is None
    assert body["driver_id"] is None
    assert body["delivery_address"] == ADDRESS
    (item,) = body["items"]
    assert item["menu_item_id"] == MARGHERITA
    assert item["price_amount_minor"] == 28000
    assert item["quantity"] == 1
    assert item["line_total_minor"] == 28000

    # UTC ISO-8601 with timezone information (§7).
    created = datetime.fromisoformat(body["created_at"])
    assert created.tzinfo is not None and created.utcoffset().total_seconds() == 0


def test_history_is_version_ordered_append_only_timeline(client, customer_token):
    order_id = _place_order(client, customer_token).json()["order_id"]
    response = client.get(f"/api/v1/orders/{order_id}/history", headers=auth_header(customer_token))
    assert response.status_code == 200
    body = response.json()
    assert set(body) >= {"items", "page", "page_size", "total"}
    assert body["page"] == 1 and body["total"] == 1
    entry = body["items"][0]
    assert entry["version"] == 1
    assert entry["status"] == "PENDING"
    assert entry["from_status"] is None
    assert entry["failure_code"] is None
    assert entry["source"] == "checkout"
    changed = datetime.fromisoformat(entry["changed_at"])
    assert changed.tzinfo is not None


# -------------------------------- pagination -------------------------------


def test_order_list_is_scoped_to_current_customer(client, customer_token, second_customer_token):
    before = client.get("/api/v1/orders", headers=auth_header(customer_token)).json()["total"]

    my_ids = [_place_order(client, customer_token).json()["order_id"] for _ in range(3)]
    foreign_id = _place_order(client, second_customer_token).json()["order_id"]
    assert foreign_id not in my_ids

    page = client.get("/api/v1/orders", headers=auth_header(customer_token)).json()
    assert page["total"] == before + 3
    listed_ids = {item["id"] for item in page["items"]}
    assert set(my_ids) <= listed_ids
    assert foreign_id not in listed_ids


def test_order_list_pagination_walks_pages_stably(client, customer_token):
    before = client.get("/api/v1/orders", headers=auth_header(customer_token)).json()["total"]
    new_ids = {_place_order(client, customer_token).json()["order_id"] for _ in range(3)}
    total = before + 3

    seen: list[str] = []
    for page_number in range(1, ceil(total / 2) + 1):
        page = client.get(
            "/api/v1/orders",
            params={"page": page_number, "page_size": 2},
            headers=auth_header(customer_token),
        ).json()
        assert set(page) == {"items", "page", "page_size", "total"}
        assert page["page"] == page_number
        assert page["page_size"] == 2
        assert page["total"] == total
        assert len(page["items"]) <= 2
        seen.extend(item["id"] for item in page["items"])

    assert len(seen) == len(set(seen)), "pages must not repeat rows"
    assert new_ids <= set(seen), "no created order may be skipped"


def test_order_list_status_filter(client, customer_token):
    for _ in range(2):
        _place_order(client, customer_token)

    pending = client.get(
        "/api/v1/orders",
        params={"status": "PENDING"},
        headers=auth_header(customer_token),
    ).json()
    assert pending["total"] >= 2
    assert {item["status"] for item in pending["items"]} == {"PENDING"}

    paid = client.get(
        "/api/v1/orders",
        params={"status": "PAID"},
        headers=auth_header(customer_token),
    ).json()
    assert paid["total"] == 0 and paid["items"] == []

    invalid = client.get(
        "/api/v1/orders",
        params={"status": "NOT_A_STATUS"},
        headers=auth_header(customer_token),
    )
    assert invalid.status_code == 422
    _assert_envelope(invalid.json(), code="VALIDATION_ERROR")


def test_pagination_bounds_are_validated(client, customer_token):
    too_large = client.get(
        "/api/v1/orders", params={"page_size": 101}, headers=auth_header(customer_token)
    )
    assert too_large.status_code == 422
    _assert_envelope(too_large.json(), code="VALIDATION_ERROR")

    zero_page = client.get(
        "/api/v1/orders", params={"page": 0}, headers=auth_header(customer_token)
    )
    assert zero_page.status_code == 422

    valid = client.get(
        "/api/v1/orders", params={"page_size": 100}, headers=auth_header(customer_token)
    )
    assert valid.status_code == 200


def test_menu_pagination_shape_is_consistent(client, customer_token):
    response = client.get(
        "/api/v1/restaurants",
        params={"page": 1, "page_size": 2},
        headers=auth_header(customer_token),
    )
    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"items", "page", "page_size", "total"}
    assert body["total"] == 4 and len(body["items"]) == 2

    menu = client.get(
        "/api/v1/restaurants/rest_bella_napoli/menu",
        params={"page": 1, "page_size": 100},
        headers=auth_header(customer_token),
    ).json()
    assert set(menu) == {"items", "page", "page_size", "total"}
    assert all(set(item) >= {"id", "price_amount_minor", "currency"} for item in menu["items"])


# -------------------------------- OpenAPI ----------------------------------


def test_openapi_documents_order_routes_and_idempotency_header(client):
    spec = client.get("/openapi.json").json()
    assert "/api/v1/orders" in spec["paths"]
    assert "/api/v1/orders/{order_id}" in spec["paths"]
    assert "/api/v1/orders/{order_id}/history" in spec["paths"]

    checkout = spec["paths"]["/api/v1/orders"]["post"]
    assert "202" in checkout["responses"]
    assert "409" in checkout["responses"]
    parameter_names = {p.get("name") for p in checkout.get("parameters", [])}
    # Header params may also live under the operation's parameters list.
    header_names = set(parameter_names)
    assert "Idempotency-Key" in header_names, checkout.get("parameters")
    assert "Location" in checkout["responses"]["202"].get("headers", {})
