"""Checkout idempotency, atomic acceptance and broker independence
(assignment §7/§14, prompt M2 gate).

Proves on REAL PostgreSQL:
- one transaction commits order + items + history + idempotency + outbox,
- same key/payload replays the ORIGINAL response (even after advancement),
- same key/different payload -> 409, keys scoped per customer,
- concurrent identical submissions -> exactly ONE order/event,
- a broker outage (or a mid-transaction failure) cannot lose or half-write
  an accepted order.
"""

from __future__ import annotations

import asyncio
import uuid
from datetime import UTC, datetime

from fastapi.testclient import TestClient
from sqlalchemy import select, update

from app.db.models.checkout_idempotency import CheckoutIdempotency
from app.db.models.order import Order
from app.db.models.order_item import OrderItem
from app.db.models.order_status_history import OrderStatusHistory
from app.db.models.outbox_event import OutboxEvent
from app.db.session import session_scope
from tests.conftest import auth_header, checkout_counts, checkout_counts_async

ADDRESS = "12 Lake Road, Bengaluru"
RESTAURANT = "rest_bella_napoli"
MARGHERITA = "item_margherita_pizza"  # 28000 minor units
GARLIC_BREAD = "item_garlic_bread"  # 15000 minor units


def _payload(**overrides) -> dict:
    payload = {
        "restaurant_id": RESTAURANT,
        "delivery_address": ADDRESS,
        "items": [{"menu_item_id": MARGHERITA, "quantity": 2}],
    }
    payload.update(overrides)
    return payload


def _checkout(
    client, token: str, payload: dict | None = None, *, key: str, request_id: str | None = None
):
    headers = {**auth_header(token), "Idempotency-Key": key}
    if request_id:
        headers["X-Request-ID"] = request_id
    return client.post(
        "/api/v1/orders",
        json=payload if payload is not None else _payload(),
        headers=headers,
    )


async def _fetch_acceptance_rows(order_id: str, customer_id: str, key: str):
    async with session_scope() as session:
        order = (await session.execute(select(Order).where(Order.id == order_id))).scalar_one()
        items = list(
            (
                await session.execute(select(OrderItem).where(OrderItem.order_id == order_id))
            ).scalars()
        )
        history = list(
            (
                await session.execute(
                    select(OrderStatusHistory)
                    .where(OrderStatusHistory.order_id == order_id)
                    .order_by(OrderStatusHistory.version)
                )
            ).scalars()
        )
        idempotency = (
            await session.execute(
                select(CheckoutIdempotency).where(
                    CheckoutIdempotency.customer_id == customer_id,
                    CheckoutIdempotency.idempotency_key == key,
                )
            )
        ).scalar_one()
        outbox = (
            (await session.execute(select(OutboxEvent).where(OutboxEvent.order_id == order_id)))
            .scalars()
            .all()
        )
        return order, items, history, idempotency, list(outbox)


# ------------------------------ happy path --------------------------------


def test_happy_path_checkout_commits_all_five_records(client, customer_token, customer_id):
    key = str(uuid.uuid4())
    correlation = f"req_checkout_{key[:8]}"

    response = _checkout(client, customer_token, key=key, request_id=correlation)

    # --- HTTP contract: 202 + Location + exact acceptance body ---
    assert response.status_code == 202, response.text
    body = response.json()
    assert set(body) == {
        "order_id",
        "status",
        "currency",
        "total_amount_minor",
        "version",
        "message",
    }
    assert body["status"] == "PENDING"
    assert body["currency"] == "INR"
    assert body["total_amount_minor"] == 2 * 28000  # server-priced: 56000
    assert body["version"] == 1
    assert body["message"] == "Order accepted for asynchronous processing."
    assert response.headers["location"] == f"/api/v1/orders/{body['order_id']}"

    # --- one atomic transaction wrote all five record types ---
    order, items, history, idempotency, outbox = asyncio.run(
        _fetch_acceptance_rows(body["order_id"], customer_id, key)
    )
    assert order.status == "PENDING" and order.version == 1
    assert order.customer_id == customer_id
    assert order.delivery_address == ADDRESS
    assert order.total_amount_minor == 56000
    assert len(items) == 1 and items[0].price_amount_minor == 28000

    assert len(history) == 1
    assert history[0].version == 1
    assert history[0].status == "PENDING"
    assert history[0].from_status is None
    assert history[0].source == "checkout"

    assert idempotency.order_id == body["order_id"]
    assert idempotency.response_status == 202
    assert idempotency.response_body == body
    assert idempotency.location == response.headers["location"]
    assert len(idempotency.request_hash) == 64  # sha-256 hex

    # --- documented order.created envelope (assignment §9) ---
    assert len(outbox) == 1
    row = outbox[0]
    assert row.state == "PENDING"
    assert row.exchange == "quickbite.orders"
    assert row.routing_key == "order.created"
    envelope = row.payload
    assert envelope["event_id"] == row.event_id
    assert envelope["event_id"].startswith("evt_created_")
    assert envelope["schema_version"] == 1
    assert envelope["event_type"] == "order.created"
    assert envelope["order_id"] == body["order_id"]
    assert envelope["order_version"] == 1
    occurred = datetime.fromisoformat(envelope["occurred_at"])
    assert occurred.tzinfo is not None and occurred.utcoffset() == UTC.utcoffset(None)
    assert envelope["correlation_id"] == correlation
    assert envelope["causation_id"] is None
    assert envelope["data"] == {
        "customer_id": customer_id,
        "restaurant_id": RESTAURANT,
    }


# ----------------------------- replay / 409 --------------------------------


def test_same_key_and_payload_replays_without_new_writes(client, customer_token, customer_id):
    key = str(uuid.uuid4())

    first = _checkout(client, customer_token, key=key)
    assert first.status_code == 202
    before = checkout_counts()

    second = _checkout(client, customer_token, key=key)
    assert second.status_code == 202
    assert second.json() == first.json()  # original acceptance, verbatim
    assert second.headers["location"] == first.headers["location"]
    assert checkout_counts() == before  # no new order, item, history, key or event


def test_replay_returns_original_even_after_status_advanced(client, customer_token):
    """Even if processing has advanced, the replay serves the STORED 202 body;
    the client then reads current state from GET /orders/{id} (§7)."""
    key = str(uuid.uuid4())
    accepted = _checkout(client, customer_token, key=key)
    order_id = accepted.json()["order_id"]

    # Simulate an advanced order (M3 workers would do this via CAS).
    async def _advance() -> None:
        async with session_scope() as session:
            await session.execute(
                update(Order).where(Order.id == order_id).values(status="PAID", version=2)
            )
            session.add(
                OrderStatusHistory(
                    id=f"hist_{uuid.uuid4().hex}",
                    order_id=order_id,
                    version=2,
                    status="PAID",
                    from_status="PENDING",
                    source="payment",
                )
            )

    asyncio.run(_advance())

    replay = _checkout(client, customer_token, key=key)
    assert replay.status_code == 202
    assert replay.json()["status"] == "PENDING"  # ORIGINAL acceptance
    assert replay.json()["version"] == 1
    assert replay.headers["location"] == f"/api/v1/orders/{order_id}"

    current = client.get(f"/api/v1/orders/{order_id}", headers=auth_header(customer_token))
    assert current.status_code == 200
    assert current.json()["status"] == "PAID"  # authority is the database
    assert current.json()["version"] == 2


def test_same_key_different_quantity_is_409(client, customer_token):
    key = str(uuid.uuid4())
    assert _checkout(client, customer_token, key=key).status_code == 202
    before = checkout_counts()

    changed = _checkout(
        client,
        customer_token,
        _payload(items=[{"menu_item_id": MARGHERITA, "quantity": 3}]),
        key=key,
    )
    assert changed.status_code == 409
    body = changed.json()
    assert body["code"] == "IDEMPOTENCY_CONFLICT"
    assert body["details"]["reason"] == "payload_mismatch"
    assert body["request_id"]
    assert checkout_counts() == before  # conflict writes nothing


def test_same_key_different_address_or_restaurant_is_409(client, customer_token):
    key = str(uuid.uuid4())
    assert _checkout(client, customer_token, key=key).status_code == 202
    before = checkout_counts()

    for changed_payload in (
        _payload(delivery_address="42 Totally Different Street"),
        _payload(
            restaurant_id="rest_spice_route",
            items=[{"menu_item_id": "item_dal_makhani", "quantity": 1}],
        ),
    ):
        response = _checkout(client, customer_token, changed_payload, key=key)
        assert response.status_code == 409
        assert response.json()["code"] == "IDEMPOTENCY_CONFLICT"
    assert checkout_counts() == before


def test_reordered_and_duplicate_lines_replay_the_same_order(client, customer_token):
    """Canonicalization: line order and duplicate rows describe the same
    request, so they must REPLAY rather than 409 or duplicate."""
    key = str(uuid.uuid4())
    original = _checkout(
        client,
        customer_token,
        _payload(
            items=[
                {"menu_item_id": MARGHERITA, "quantity": 1},
                {"menu_item_id": GARLIC_BREAD, "quantity": 2},
            ]
        ),
        key=key,
    )
    assert original.status_code == 202

    equivalent = _checkout(
        client,
        customer_token,
        _payload(
            items=[
                {"menu_item_id": GARLIC_BREAD, "quantity": 1},
                {"menu_item_id": GARLIC_BREAD, "quantity": 1},
                {"menu_item_id": MARGHERITA, "quantity": 1},
            ]
        ),
        key=key,
    )
    assert equivalent.status_code == 202
    assert equivalent.json() == original.json()
    assert equivalent.headers["location"] == original.headers["location"]


def test_idempotency_key_is_scoped_per_customer(client, customer_token, second_customer_token):
    """Same key VALUE from a different customer is a different scope."""
    key = str(uuid.uuid4())
    first = _checkout(client, customer_token, key=key)
    assert first.status_code == 202

    second = _checkout(client, second_customer_token, key=key)
    assert second.status_code == 202
    assert second.json()["order_id"] != first.json()["order_id"]


# ------------------------------ concurrency -------------------------------


async def test_concurrent_identical_checkouts_create_exactly_one_order(
    async_client, customer_token
):
    """8 simultaneous submissions of the same key/payload: the unique
    (customer_id, key) constraint lets exactly one transaction commit; every
    loser rolls back completely and replays the winner's response."""
    key = str(uuid.uuid4())
    headers = {**auth_header(customer_token), "Idempotency-Key": key}
    before = await checkout_counts_async()

    responses = await asyncio.gather(
        *(async_client.post("/api/v1/orders", json=_payload(), headers=headers) for _ in range(8))
    )

    assert [r.status_code for r in responses] == [202] * 8, [r.text for r in responses]
    order_ids = {r.json()["order_id"] for r in responses}
    assert len(order_ids) == 1, "concurrent duplicates must converge on one order"
    assert len({r.headers["location"] for r in responses}) == 1
    assert len({r.json()["total_amount_minor"] for r in responses}) == 1

    after = await checkout_counts_async()
    assert after["orders"] == before["orders"] + 1
    assert after["order_items"] == before["order_items"] + 1
    assert after["order_status_history"] == before["order_status_history"] + 1
    assert after["checkout_idempotency"] == before["checkout_idempotency"] + 1
    assert after["outbox_events"] == before["outbox_events"] + 1


async def test_concurrent_conflicting_payloads_commit_one_order_and_reject_the_other(
    async_client, customer_token
):
    """Different payloads racing on one key: one commits, the other receives
    409 (not 500, not a second order)."""
    key = str(uuid.uuid4())
    headers = {**auth_header(customer_token), "Idempotency-Key": key}
    before = await checkout_counts_async()

    responses = await asyncio.gather(
        async_client.post("/api/v1/orders", json=_payload(), headers=headers),
        async_client.post(
            "/api/v1/orders",
            json=_payload(items=[{"menu_item_id": MARGHERITA, "quantity": 3}]),
            headers=headers,
        ),
    )

    statuses = sorted(r.status_code for r in responses)
    assert statuses == [202, 409], [r.text for r in responses]
    conflict = next(r for r in responses if r.status_code == 409)
    assert conflict.json()["code"] == "IDEMPOTENCY_CONFLICT"

    after = await checkout_counts_async()
    assert after["orders"] == before["orders"] + 1
    assert after["outbox_events"] == before["outbox_events"] + 1
    assert after["checkout_idempotency"] == before["checkout_idempotency"] + 1


# ------------------------ atomicity / broker safety ------------------------


def test_broker_outage_cannot_lose_an_accepted_order(client, customer_token, monkeypatch):
    """Acceptance performs NO broker I/O (§7): even a dead RabbitMQ leaves the
    committed order and its PENDING outbox row intact for the M3 dispatcher."""
    import aio_pika

    async def _broker_down(*_args, **_kwargs):
        raise ConnectionError("broker is down (simulated)")

    monkeypatch.setattr(aio_pika, "connect", _broker_down)

    before = checkout_counts()
    key = str(uuid.uuid4())
    response = _checkout(client, customer_token, key=key)

    assert response.status_code == 202, response.text
    after = checkout_counts()
    assert after["orders"] == before["orders"] + 1
    assert after["outbox_events"] == before["outbox_events"] + 1

    order_id = response.json()["order_id"]

    async def _outbox_state() -> str:
        async with session_scope() as session:
            row = (
                await session.execute(select(OutboxEvent).where(OutboxEvent.order_id == order_id))
            ).scalar_one()
            return row.state

    assert asyncio.run(_outbox_state()) == "PENDING"  # waits for recovery


def test_mid_transaction_failure_rolls_back_the_entire_acceptance(customer_token, monkeypatch):
    """If the acceptance transaction cannot finish (simulated outbox write
    failure), NOTHING is persisted and NO 202 is ever returned."""
    import app.services.checkout_service as checkout_service_module
    from app.main import create_app

    def _boom(*_args, **_kwargs):
        raise RuntimeError("simulated acceptance transaction failure")

    monkeypatch.setattr(checkout_service_module, "_persist_outbox_event", _boom)

    before = checkout_counts()
    with TestClient(create_app(), raise_server_exceptions=False) as failing_client:
        response = _checkout(failing_client, customer_token, key=str(uuid.uuid4()))

    assert response.status_code == 500
    body = response.json()
    assert body["code"] == "INTERNAL_ERROR"
    assert body["request_id"]
    assert checkout_counts() == before, "failed acceptance must leave ZERO rows"
