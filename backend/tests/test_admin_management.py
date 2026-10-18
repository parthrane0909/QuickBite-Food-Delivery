"""Admin extension tests use only the isolated quickbite_test PostgreSQL DB."""

from __future__ import annotations

import uuid

from tests.conftest import auth_header


def test_large_catalogue_seed_is_additive_and_idempotent():
    import asyncio

    from sqlalchemy import delete, func, select

    from app.db.models.menu_item import MenuItem
    from app.db.models.restaurant import Restaurant
    from app.db.session import session_scope
    from scripts.seed_large_catalogue import seed

    async def _exercise():
        try:
            first = await seed(target=20)
            second = await seed(target=20)
            assert first == {
                "restaurants_before": 4,
                "restaurants_added": 16,
                "menu_items_added": 168,
            }
            assert second["restaurants_added"] == 0
            assert second["menu_items_added"] == 0
            async with session_scope() as session:
                total_restaurants = int(
                    (
                        await session.execute(select(func.count()).select_from(Restaurant))
                    ).scalar_one()
                )
                showcase_items = int(
                    (
                        await session.execute(
                            select(func.count())
                            .select_from(MenuItem)
                            .where(MenuItem.restaurant_id.like("showcase_%"))
                        )
                    ).scalar_one()
                )
                assert total_restaurants == 20
                assert showcase_items == 160
                showcase_menu_sizes = (
                    await session.execute(
                        select(func.count(MenuItem.id))
                        .where(MenuItem.restaurant_id.like("showcase_%"))
                        .group_by(MenuItem.restaurant_id)
                    )
                ).scalars()
                assert set(showcase_menu_sizes) == {10}
                for restaurant_id in (
                    "rest_spice_route",
                    "rest_coastal_catch",
                    "rest_bella_napoli",
                    "rest_sweet_crumb",
                ):
                    count = int(
                        (
                            await session.execute(
                                select(func.count())
                                .select_from(MenuItem)
                                .where(MenuItem.restaurant_id == restaurant_id)
                            )
                        ).scalar_one()
                    )
                    assert count == 8
        finally:
            # The isolated test database is shared within this suite; remove
            # only the rows created by this test, which have no orders.
            async with session_scope() as session:
                ids = select(Restaurant.id).where(Restaurant.id.like("showcase_%"))
                await session.execute(
                    delete(MenuItem).where(
                        MenuItem.restaurant_id.in_(ids) | MenuItem.id.like("%_showcase_%")
                    )
                )
                await session.execute(delete(Restaurant).where(Restaurant.id.like("showcase_%")))

    asyncio.run(_exercise())


def test_admin_summary_contains_live_entity_counts(client, admin_token):
    response = client.get("/api/v1/admin/summary", headers=auth_header(admin_token))
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["total_restaurants"] == 4
    assert body["total_customers"] == 3
    assert body["total_orders"] >= 0
    assert body["total_drivers"] == 6


def test_admin_activity_metrics_come_from_orders(client, admin_token, customer_token):
    admin_headers = auth_header(admin_token)
    customer_headers = auth_header(customer_token)
    restaurants_before = client.get(
        "/api/v1/admin/restaurants", headers=admin_headers, params={"search": "Bella"}
    ).json()["items"][0]
    customers_before = client.get(
        "/api/v1/admin/customers",
        headers=admin_headers,
        params={"search": "alice@quickbite.dev"},
    ).json()["items"][0]

    accepted = client.post(
        "/api/v1/orders",
        headers={**customer_headers, "Idempotency-Key": str(uuid.uuid4())},
        json={
            "restaurant_id": "rest_bella_napoli",
            "delivery_address": "12 Lake Road",
            "items": [{"menu_item_id": "item_margherita_pizza", "quantity": 1}],
        },
    )
    assert accepted.status_code == 202, accepted.text

    restaurant = client.get(
        "/api/v1/admin/restaurants", headers=admin_headers, params={"search": "Bella"}
    ).json()["items"][0]
    customer = client.get(
        "/api/v1/admin/customers",
        headers=admin_headers,
        params={"search": "alice@quickbite.dev"},
    ).json()["items"][0]
    assert restaurant["order_count"] == restaurants_before["order_count"] + 1
    assert restaurant["accepted_order_value_minor"] == (
        restaurants_before["accepted_order_value_minor"] + accepted.json()["total_amount_minor"]
    )
    assert restaurant["customer_count"] >= 1
    assert restaurant["last_order_at"] is not None
    assert customer["order_count"] == customers_before["order_count"] + 1
    assert customer["last_order_at"] is not None


def test_management_is_admin_only(client, customer_token):
    for method, path in (
        ("get", "/api/v1/admin/restaurants"),
        ("post", "/api/v1/admin/restaurants"),
        ("get", "/api/v1/admin/customers"),
        ("get", "/api/v1/admin/drivers"),
    ):
        response = getattr(client, method)(path, headers=auth_header(customer_token))
        assert response.status_code == 403, (path, response.text)


def test_admin_can_shop_as_own_identity_but_list_is_owner_scoped(
    client, admin_token, customer_token
):
    response = client.get("/api/v1/orders", headers=auth_header(admin_token))
    assert response.status_code == 200, response.text
    assert response.json()["items"] == []
    assert (
        client.get("/api/v1/admin/orders", headers=auth_header(customer_token)).status_code == 403
    )


def test_restaurant_menu_mutations_are_audited_and_keep_order_snapshots(
    client, admin_token, customer_token
):
    key = str(uuid.uuid4())
    accepted = client.post(
        "/api/v1/orders",
        headers={
            **auth_header(customer_token),
            "Idempotency-Key": key,
        },
        json={
            "restaurant_id": "rest_bella_napoli",
            "delivery_address": "12 Lake Road",
            "items": [{"menu_item_id": "item_margherita_pizza", "quantity": 1}],
        },
    )
    assert accepted.status_code == 202, accepted.text
    order_id = accepted.json()["order_id"]

    patched = client.patch(
        "/api/v1/admin/menu-items/item_margherita_pizza",
        headers=auth_header(admin_token),
        json={"price_amount_minor": 51000},
    )
    assert patched.status_code == 200, patched.text
    assert patched.json()["price_amount_minor"] == 51000

    detail = client.get(f"/api/v1/orders/{order_id}", headers=auth_header(customer_token))
    assert detail.status_code == 200, detail.text
    assert detail.json()["items"][0]["price_amount_minor"] == 28000

    from sqlalchemy import select

    from app.db.models.admin_audit_log import AdminAuditLog
    from app.db.session import session_scope

    async def _read_audit():
        async with session_scope() as session:
            row = (
                await session.execute(
                    select(AdminAuditLog).where(AdminAuditLog.target_id == "item_margherita_pizza")
                )
            ).scalar_one()
            return row.action, row.changed_fields

    import asyncio

    assert asyncio.run(_read_audit()) == ("update", ["price_amount_minor"])
    reset = client.patch(
        "/api/v1/admin/menu-items/item_margherita_pizza",
        headers=auth_header(admin_token),
        json={"price_amount_minor": 28000},
    )
    assert reset.status_code == 200, reset.text


def test_menu_create_deactivate_and_customer_creation_do_not_leak_secrets(client, admin_token):
    created = client.post(
        "/api/v1/admin/restaurants/rest_bella_napoli/menu",
        headers=auth_header(admin_token),
        json={
            "name": "Lemon Ricotta Gnocchi",
            "description": "Pillowy potato gnocchi with lemon.",
            "price_amount_minor": 32000,
            "currency": "INR",
            "is_available": True,
            "sort_order": 99,
        },
    )
    assert created.status_code == 201, created.text
    item_id = created.json()["id"]
    unavailable = client.post(
        f"/api/v1/admin/menu-items/{item_id}/deactivate", headers=auth_header(admin_token)
    )
    assert unavailable.status_code == 200 and unavailable.json()["is_available"] is False

    customer = client.post(
        "/api/v1/admin/customers",
        headers=auth_header(admin_token),
        json={
            "email": "demo-new@quickbite.dev",
            "full_name": "Morgan Lee",
            "password": "a-secure-demo-passphrase",
        },
    )
    assert customer.status_code == 201, customer.text
    assert "password" not in customer.text and "password_hash" not in customer.text
    disabled = client.post(
        f"/api/v1/admin/customers/{customer.json()['id']}/deactivate",
        headers=auth_header(admin_token),
    )
    assert disabled.status_code == 200 and disabled.json()["is_active"] is False
