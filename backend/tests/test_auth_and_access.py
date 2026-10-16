"""Authentication and access-control acceptance tests (assignment §7/§8/§14).

Covers: valid/invalid login, token expiry, profile reads, catalog
authentication, pagination bounds, seeded menu content and 404 semantics.
Ownership of orders and admin-route denial are exercised here too as soon as
those routes exist (Milestone 2 adds them to this file's coverage scope).
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import jwt as pyjwt

from app.core.config import get_settings
from app.core.security import create_access_token
from scripts.seed_demo import SEED_ACCOUNTS, SEED_RESTAURANTS
from tests.conftest import auth_header

CUSTOMER = next(a for a in SEED_ACCOUNTS if a["role"] == "customer")
ADMIN = next(a for a in SEED_ACCOUNTS if a["role"] == "admin")


# ----------------------------- login --------------------------------------


def test_login_success_returns_token_role_and_user(client):
    response = client.post(
        "/api/v1/auth/login",
        json={"email": CUSTOMER["email"], "password": CUSTOMER["password"]},
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["token_type"] == "bearer"
    assert isinstance(body["access_token"], str) and body["access_token"]
    assert body["role"] == "customer"
    assert body["expires_in"] >= 60
    assert body["user"]["email"] == CUSTOMER["email"]
    assert body["user"]["id"] == CUSTOMER["id"]
    # Expiry must be reported as a timezone-aware ISO-8601 timestamp.
    assert datetime.fromisoformat(body["expires_at"]).tzinfo is not None


def test_login_admin_role(client):
    response = client.post(
        "/api/v1/auth/login",
        json={"email": ADMIN["email"], "password": ADMIN["password"]},
    )
    assert response.status_code == 200, response.text
    assert response.json()["role"] == "admin"


def test_login_wrong_password_is_401_with_envelope(client):
    response = client.post(
        "/api/v1/auth/login",
        json={"email": CUSTOMER["email"], "password": "totally-wrong-password"},
    )
    assert response.status_code == 401
    body = response.json()
    assert body["code"] == "INVALID_CREDENTIALS"
    assert body["message"]
    assert body["request_id"]


def test_login_unknown_email_same_error_as_wrong_password(client):
    response = client.post(
        "/api/v1/auth/login",
        json={"email": "nobody@quickbite.dev", "password": "whatever-123"},
    )
    assert response.status_code == 401
    assert response.json()["code"] == "INVALID_CREDENTIALS"  # no account enumeration


def test_login_invalid_email_format_is_422_envelope(client):
    response = client.post("/api/v1/auth/login", json={"email": "not-an-email", "password": "x"})
    assert response.status_code == 422
    body = response.json()
    assert body["code"] == "VALIDATION_ERROR"
    assert body["details"] and body["request_id"]


def test_login_missing_field_is_422(client):
    response = client.post("/api/v1/auth/login", json={"email": CUSTOMER["email"]})
    assert response.status_code == 422
    assert response.json()["code"] == "VALIDATION_ERROR"


# ----------------------------- /me ----------------------------------------


def test_me_requires_token(client):
    assert client.get("/api/v1/me").status_code == 401


def test_me_returns_profile(client, customer_token):
    response = client.get("/api/v1/me", headers=auth_header(customer_token))
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["email"] == CUSTOMER["email"]
    assert body["role"] == "customer"
    assert body["is_active"] is True


def test_me_rejects_expired_token(client):
    settings = get_settings()
    token, _ = create_access_token(
        settings, user_id=CUSTOMER["id"], role="customer", ttl_seconds=-30
    )
    response = client.get("/api/v1/me", headers=auth_header(token))
    assert response.status_code == 401
    assert response.json()["code"] == "TOKEN_EXPIRED"


def test_me_rejects_garbage_token(client):
    response = client.get("/api/v1/me", headers=auth_header("not.a.jwt"))
    assert response.status_code == 401
    assert response.json()["code"] == "TOKEN_INVALID"


def test_me_rejects_token_signed_with_other_secret(client):
    settings = get_settings()
    now = datetime.now(UTC)
    forged = pyjwt.encode(
        {
            "sub": ADMIN["id"],
            "role": "admin",
            "iat": int(now.timestamp()),
            "exp": int((now + timedelta(minutes=5)).timestamp()),
            "iss": settings.jwt_issuer,
        },
        "a-completely-different-secret-value-32chars!",
        algorithm="HS256",
    )
    response = client.get("/api/v1/me", headers=auth_header(forged))
    assert response.status_code == 401
    assert response.json()["code"] == "TOKEN_INVALID"


# ----------------------------- catalog ------------------------------------


def test_restaurants_requires_auth(client):
    assert client.get("/api/v1/restaurants").status_code == 401


def test_restaurants_pagination_shape(client, customer_token):
    response = client.get(
        "/api/v1/restaurants",
        params={"page": 1, "page_size": 2},
        headers=auth_header(customer_token),
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert set(body) == {"items", "page", "page_size", "total"}
    assert body["total"] == len(SEED_RESTAURANTS)
    assert body["page"] == 1 and body["page_size"] == 2
    assert len(body["items"]) == 2
    names = [r["name"] for r in body["items"]]
    assert names == sorted(names)  # stable ordering
    for restaurant in body["items"]:
        assert restaurant["currency"] == "INR"
        assert isinstance(restaurant["is_available"], bool)
        assert datetime.fromisoformat(restaurant["created_at"]).tzinfo is not None

    page3 = client.get(
        "/api/v1/restaurants",
        params={"page": 3, "page_size": 2},
        headers=auth_header(customer_token),
    ).json()
    assert page3["items"] == []  # beyond the last page, not an error


def test_restaurants_page_size_above_max_is_422(client, customer_token):
    response = client.get(
        "/api/v1/restaurants", params={"page_size": 101}, headers=auth_header(customer_token)
    )
    assert response.status_code == 422
    assert response.json()["code"] == "VALIDATION_ERROR"


def test_menu_returns_authoritative_prices(client, customer_token):
    restaurant_id = SEED_RESTAURANTS[0]["id"]
    response = client.get(
        f"/api/v1/restaurants/{restaurant_id}/menu",
        params={"page_size": 100},
        headers=auth_header(customer_token),
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["total"] == len(SEED_RESTAURANTS[0]["items"])
    first = body["items"][0]
    assert first["id"] == "item_dal_makhani"
    assert first["price_amount_minor"] == 22000  # INR 220.00 in minor units
    assert first["currency"] == "INR"
    assert isinstance(first["is_available"], bool)


def test_menu_flags_unavailable_items(client, customer_token):
    restaurant_id = SEED_RESTAURANTS[0]["id"]
    body = client.get(
        f"/api/v1/restaurants/{restaurant_id}/menu",
        params={"page_size": 100},
        headers=auth_header(customer_token),
    ).json()
    unavailable = [item for item in body["items"] if not item["is_available"]]
    assert [item["id"] for item in unavailable] == ["item_mango_lassi"]


def test_menu_unknown_restaurant_is_404(client, customer_token):
    response = client.get(
        "/api/v1/restaurants/rest_does_not_exist/menu", headers=auth_header(customer_token)
    )
    assert response.status_code == 404
    assert response.json()["code"] == "NOT_FOUND"
