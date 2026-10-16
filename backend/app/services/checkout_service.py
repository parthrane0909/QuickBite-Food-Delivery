"""Checkout: the SOLE order-acceptance transaction (assignment §7/§14).

One database transaction commits ALL of: `orders` (PENDING, version 1),
`order_items` (server-priced snapshots), `order_status_history` (version 1),
`checkout_idempotency` (canonical request hash + original acceptance
response) and `outbox_events` (`order.created`). If any part fails, nothing
is written and the API returns an error — never a false 202.

Idempotency is arbitrated by the UNIQUE (customer_id, idempotency_key)
constraint, so concurrent identical submissions cannot both win: the loser's
transaction rolls back completely, re-reads the winner's committed record and
replays the original acceptance (or answers 409 for a changed payload).

The transaction performs NO broker I/O: a RabbitMQ outage cannot affect
acceptance — committed outbox rows simply wait for the M3 dispatcher.
"""

from __future__ import annotations

import hashlib
import json
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import (
    IdempotencyConflictError,
    NotFoundError,
    ValidationFailedError,
)
from app.db.models.checkout_idempotency import CheckoutIdempotency
from app.db.models.menu_item import MenuItem
from app.db.models.order import Order
from app.db.models.order_item import OrderItem
from app.db.models.order_status_history import OrderStatusHistory
from app.db.models.outbox_event import OutboxEvent
from app.db.models.restaurant import Restaurant
from app.messaging.topology import ORDERS_EXCHANGE
from app.repositories import catalog as catalog_repo
from app.repositories import idempotency as idempotency_repo
from app.schemas.events import ORDER_CREATED, SCHEMA_VERSION, EventEnvelope
from app.schemas.orders import (
    MAX_DISTINCT_ITEMS,
    CheckoutRequest,
    OrderAccepted,
)
from app.services import order_state_machine as sm


@dataclass(frozen=True)
class CheckoutResult:
    """HTTP outcome for the route: replayed results reuse the STORED body and
    Location verbatim (status may already have advanced server-side)."""

    body: dict[str, Any]
    location: str
    replayed: bool


def new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex}"


def canonical_request(checkout: CheckoutRequest) -> dict[str, Any]:
    """Order-independent, duplicate-merged form of the payload.

    Two requests that describe the same order (different line order, repeated
    lines, padded address) hash identically and therefore replay each other;
    any real difference (restaurant, address, item, quantity) changes the hash.
    """
    merged: dict[str, int] = {}
    for line in checkout.items:
        merged[line.menu_item_id] = merged.get(line.menu_item_id, 0) + line.quantity
    return {
        "restaurant_id": checkout.restaurant_id,
        "delivery_address": checkout.delivery_address.strip(),
        "items": [
            {"menu_item_id": menu_item_id, "quantity": merged[menu_item_id]}
            for menu_item_id in sorted(merged)
        ],
    }


def request_hash(canonical: dict[str, Any]) -> str:
    blob = json.dumps(canonical, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def _replay_or_conflict(existing: CheckoutIdempotency, payload_hash: str) -> CheckoutResult:
    if existing.request_hash != payload_hash:
        raise IdempotencyConflictError(
            "This Idempotency-Key was already used with a different request payload.",
            details={"reason": "payload_mismatch"},
        )
    return CheckoutResult(body=existing.response_body, location=existing.location, replayed=True)


async def _load_restaurant(session: AsyncSession, restaurant_id: str) -> Restaurant:
    # Validation reads happen INSIDE the acceptance transaction so pricing and
    # availability are as authoritative as the rows being written (prompt M2.2).
    restaurant = await catalog_repo.get_restaurant(session, restaurant_id)
    if restaurant is None:
        raise NotFoundError(f"Restaurant '{restaurant_id}' was not found.")
    if not restaurant.is_available:
        raise ValidationFailedError(
            "This restaurant is not accepting orders right now.",
            details={"reason": "restaurant_unavailable"},
        )
    return restaurant


def _merge_and_validate_lines(
    checkout: CheckoutRequest,
) -> dict[str, int]:
    merged: dict[str, int] = {}
    for line in checkout.items:
        merged[line.menu_item_id] = merged.get(line.menu_item_id, 0) + line.quantity
    if len(merged) > MAX_DISTINCT_ITEMS:
        raise ValidationFailedError(
            f"An order may contain at most {MAX_DISTINCT_ITEMS} distinct menu items.",
            details={"reason": "too_many_distinct_items", "limit": MAX_DISTINCT_ITEMS},
        )
    for menu_item_id, quantity in merged.items():
        if not (1 <= quantity <= 20):  # merged duplicates can exceed a single line's cap
            raise ValidationFailedError(
                "Quantity per menu item must be between 1 and 20.",
                details={
                    "reason": "quantity_out_of_bounds",
                    "menu_item_id": menu_item_id,
                    "quantity": quantity,
                },
            )
    return merged


def _validate_address(checkout: CheckoutRequest) -> str:
    address = checkout.delivery_address.strip()
    if not address:
        raise ValidationFailedError(
            "A delivery address is required.",
            details={"reason": "invalid_delivery_address"},
        )
    return address


async def _price_lines(
    session: AsyncSession,
    restaurant: Restaurant,
    merged: dict[str, int],
) -> list[tuple[MenuItem, int]]:
    """Authoritative pricing: current menu rows, inside this transaction."""
    menu_items = await catalog_repo.get_menu_items_by_ids(session, merged.keys())
    lines: list[tuple[MenuItem, int]] = []
    for menu_item_id in sorted(merged):
        item = menu_items.get(menu_item_id)
        if item is None:
            raise ValidationFailedError(
                f"Menu item '{menu_item_id}' does not exist.",
                details={"reason": "unknown_item", "menu_item_id": menu_item_id},
            )
        if item.restaurant_id != restaurant.id:
            raise ValidationFailedError(
                "All items must belong to the selected restaurant.",
                details={
                    "reason": "item_not_in_restaurant",
                    "menu_item_id": menu_item_id,
                    "expected_restaurant_id": restaurant.id,
                },
            )
        if not item.is_available:
            raise ValidationFailedError(
                f"Menu item '{item.name}' is currently unavailable.",
                details={"reason": "item_unavailable", "menu_item_id": menu_item_id},
            )
        if item.currency != restaurant.currency:
            # Defensive integrity check: a mismatched seed would corrupt totals.
            raise ValidationFailedError(
                "Menu item currency does not match the restaurant currency.",
                details={"reason": "currency_mismatch", "menu_item_id": menu_item_id},
            )
        lines.append((item, merged[menu_item_id]))
    return lines


def _build_created_event(order: Order, *, request_id: str) -> EventEnvelope:
    """Documented `order.created` envelope (assignment §9). Carries identity
    only — no delivery address or other personal data."""
    return EventEnvelope(
        event_id=new_id("evt_created"),
        schema_version=SCHEMA_VERSION,
        event_type=ORDER_CREATED,
        order_id=order.id,
        order_version=order.version,
        occurred_at=datetime.now(UTC),
        correlation_id=request_id or "-",
        causation_id=None,
        data={
            "customer_id": order.customer_id,
            "restaurant_id": order.restaurant_id,
        },
    )


def _persist_outbox_event(
    session: AsyncSession, envelope: EventEnvelope, order: Order
) -> OutboxEvent:
    """Seam kept explicit (and tested): the outbox row commits with the order
    or not at all. Replacing this with a direct publish would break the
    broker-outage guarantee."""
    outbox_row = OutboxEvent(
        id=new_id("out"),
        event_id=envelope.event_id,
        event_type=envelope.event_type,
        order_id=order.id,
        exchange=ORDERS_EXCHANGE,
        routing_key=ORDER_CREATED,
        payload=envelope.to_payload(),
        state="PENDING",
    )
    session.add(outbox_row)
    return outbox_row


async def _accept(
    session: AsyncSession,
    *,
    customer_id: str,
    idempotency_key: str,
    checkout: CheckoutRequest,
    payload_hash: str,
    request_id: str,
) -> tuple[Order, OrderAccepted]:
    address = _validate_address(checkout)
    restaurant = await _load_restaurant(session, checkout.restaurant_id)
    merged = _merge_and_validate_lines(checkout)
    lines = await _price_lines(session, restaurant, merged)

    total_amount_minor = sum(item.price_amount_minor * qty for item, qty in lines)

    order = Order(
        id=new_id("order"),
        customer_id=customer_id,
        restaurant_id=restaurant.id,
        delivery_address=address,
        currency=restaurant.currency,
        total_amount_minor=total_amount_minor,
        status=sm.PENDING,
        version=1,
    )
    session.add(order)
    # Explicit flush: `orders.id` must exist before the FK-dependent rows
    # below (checkout_idempotency.order_id, order_items.order_id) — plain
    # foreign keys without ORM relationships do not order the flush for us.
    await session.flush()

    for item, quantity in lines:
        session.add(
            OrderItem(
                id=new_id("oi"),
                order_id=order.id,
                menu_item_id=item.id,
                item_name=item.name,
                price_amount_minor=item.price_amount_minor,
                currency=item.currency,
                quantity=quantity,
                line_total_minor=item.price_amount_minor * quantity,
            )
        )

    session.add(
        OrderStatusHistory(
            id=new_id("hist"),
            order_id=order.id,
            version=1,
            status=sm.PENDING,
            from_status=None,
            failure_code=None,
            source="checkout",
        )
    )

    envelope = _build_created_event(order, request_id=request_id)
    _persist_outbox_event(session, envelope, order)

    acceptance = OrderAccepted(
        order_id=order.id,
        status="PENDING",
        currency=order.currency,
        total_amount_minor=order.total_amount_minor,
        version=1,
    )
    session.add(
        CheckoutIdempotency(
            id=new_id("idem"),
            customer_id=customer_id,
            idempotency_key=idempotency_key,
            request_hash=payload_hash,
            order_id=order.id,
            response_status=202,
            response_body=acceptance.model_dump(mode="json"),
            location=f"/api/v1/orders/{order.id}",
        )
    )
    return order, acceptance


async def create_order(
    session: AsyncSession,
    *,
    customer_id: str,
    idempotency_key: str,
    checkout: CheckoutRequest,
    request_id: str,
) -> CheckoutResult:
    """Accept (or idempotently replay) a checkout — never publishes to the
    broker and never returns 202 unless the transaction committed.

    Uses the request's implicit transaction (opened by the auth dependency's
    reads) and COMMITS it here only after all five record types are staged;
    any failure path rolls the whole thing back."""
    key = idempotency_key.strip()
    canonical = canonical_request(checkout)
    payload_hash = request_hash(canonical)

    try:
        existing = await idempotency_repo.get_for_customer(
            session, customer_id=customer_id, idempotency_key=key
        )
        if existing is not None:
            return _replay_or_conflict(existing, payload_hash)

        order, acceptance = await _accept(
            session,
            customer_id=customer_id,
            idempotency_key=key,
            checkout=checkout,
            payload_hash=payload_hash,
            request_id=request_id,
        )
        # THE acceptance commit: order + items + history + idempotency + outbox.
        await session.commit()
    except IntegrityError:
        # Lost a concurrent duplicate race: our whole transaction rolled back
        # (no partial rows); the winner's committed record is now visible.
        await session.rollback()
        existing = await idempotency_repo.get_for_customer(
            session, customer_id=customer_id, idempotency_key=key
        )
        if existing is None:
            raise  # unrelated integrity failure — surface as 500
        return _replay_or_conflict(existing, payload_hash)

    return CheckoutResult(
        body=acceptance.model_dump(mode="json"),
        location=f"/api/v1/orders/{order.id}",
        replayed=False,
    )
