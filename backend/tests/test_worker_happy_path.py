"""End-to-end worker chain on REAL PostgreSQL + RabbitMQ (assignment §10).

Covers required tests: the full happy-path chain, history/version progression,
and the terminal payment-failure path (PAYMENT_FAILED with NO retry machinery).
"""

from __future__ import annotations

import asyncio
from collections import Counter

from sqlalchemy import select

from app.core.config import get_settings
from app.db.models.notification import Notification
from app.db.models.order_status_history import OrderStatusHistory
from app.db.session import session_scope
from app.schemas.events import (
    ORDER_CONFIRMED,
    ORDER_CREATED,
    ORDER_DRIVER_ASSIGNED,
    ORDER_PAID,
    ORDER_PAYMENT_FAILED,
)
from scripts.seed_demo import SEED_DRIVERS
from tests.conftest import auth_header
from tests.m3_harness import (
    fetch_outbox_payload,
    get_order_row,
    order_rows,
    place_order,
    wait_for_eq,
    wait_for_status,
)

HAPPY_STATUSES = ("PENDING", "PAID", "CONFIRMED", "DRIVER_ASSIGNED")


async def test_full_happy_path_chain(pipeline, async_client, customer_token, customer_id):
    """checkout -> dispatcher -> payment -> restaurant -> delivery, with the
    notification worker persisting one notice per event — all exactly once."""
    pipeline.start_dispatcher()
    for stage in ("payment", "restaurant", "delivery", "notification"):
        pipeline.start_consumers(stage)

    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "DRIVER_ASSIGNED")
    # Let any duplicate/straggler deliveries land before snapshotting.
    await wait_for_eq(lambda: _notification_count(order_id), 4, timeout=20, message="four notices")
    await asyncio.sleep(0.5)
    pipeline.raise_if_task_failed()
    rows = await order_rows(order_id)
    order = await get_order_row(order_id)

    # Order reached the successful terminal state with the right version.
    assert order is not None
    assert order.status == "DRIVER_ASSIGNED"
    assert order.version == 4
    assert order.failure_code is None and order.failure_reason is None
    assert order.driver_id in {d["driver_id"] for d in SEED_DRIVERS}

    # Exactly one history row per transition, versions 1..4 strictly ordered.
    assert [h.version for h in rows["history"]] == [1, 2, 3, 4]
    assert [h.status for h in rows["history"]] == list(HAPPY_STATUSES)
    assert [h.source for h in rows["history"]] == [
        "checkout",
        "payment",
        "restaurant",
        "delivery",
    ]
    assert all(h.failure_code is None for h in rows["history"])

    # Exactly one payment record and one driver assignment.
    assert len(rows["payments"]) == 1
    assert rows["payments"][0].status == "SUCCEEDED"
    assert rows["payments"][0].payment_reference == f"pay_{order_id}"
    assert rows["payments"][0].amount_minor == order.total_amount_minor
    assert len(rows["assignments"]) == 1
    assert rows["assignments"][0].driver_id == order.driver_id

    # Markers are keyed (consumer, event): the notification worker leaves one
    # per event it renders (4), each stage worker exactly one.
    marker_counts = Counter(m.consumer_name for m in rows["processed"])
    assert marker_counts == Counter(
        {"notification": 4, "payment": 1, "restaurant": 1, "delivery": 1}
    )
    assert all(m.outcome == "PROCESSED" for m in rows["processed"])

    # Child events: four committed, all SENT (confirmed publish + routing).
    assert sorted(o.event_type for o in rows["outbox"]) == sorted(
        [ORDER_CREATED, ORDER_PAID, ORDER_CONFIRMED, ORDER_DRIVER_ASSIGNED]
    )
    assert all(o.state == "SENT" for o in rows["outbox"])
    assert all(o.published_at is not None for o in rows["outbox"])

    # Notifications: one per event, unique event ids, correct customer.
    types = sorted(n.type for n in rows["notifications"])
    assert types == sorted([ORDER_CREATED, ORDER_PAID, ORDER_CONFIRMED, ORDER_DRIVER_ASSIGNED])
    assert len({n.event_id for n in rows["notifications"]}) == 4
    assert all(n.customer_id == customer_id for n in rows["notifications"])
    assert all(n.message for n in rows["notifications"])

    # Idempotency guard: nothing grows after completion (no duplicate work).
    await asyncio.sleep(0.5)
    again = await order_rows(order_id)
    assert len(again["payments"]) == 1
    assert len(again["assignments"]) == 1
    assert len(again["history"]) == 4
    assert len(again["notifications"]) == 4
    assert len(again["processed"]) == 7  # 4 notification + 3 stage markers


async def test_full_happy_path_notifications_endpoint(
    pipeline, async_client, customer_token, second_customer_token
):
    """GET /orders/{id}/notifications: owner sees the feed with real
    pagination; a different customer gets 404 (never 403); admin may read it."""
    pipeline.start_dispatcher()
    for stage in ("payment", "restaurant", "delivery", "notification"):
        pipeline.start_consumers(stage)

    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "DRIVER_ASSIGNED")
    await wait_for_eq(
        lambda: _notification_count(order_id),
        4,
        timeout=20,
        message="four notifications persisted",
    )

    # Owner: paginated feed in chronological order.
    response = await async_client.get(
        f"/api/v1/orders/{order_id}/notifications",
        headers=auth_header(customer_token),
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["total"] == 4 and body["page"] == 1 and body["page_size"] == 20
    assert [i["type"] for i in body["items"]] == [
        ORDER_CREATED,
        ORDER_PAID,
        ORDER_CONFIRMED,
        ORDER_DRIVER_ASSIGNED,
    ]
    assert [i["seq"] for i in body["items"]] == sorted(i["seq"] for i in body["items"])
    assert all(i["order_id"] == order_id for i in body["items"])

    # Second page (page_size=2): entries 3..4, chronological order preserved.
    page2 = await async_client.get(
        f"/api/v1/orders/{order_id}/notifications?page=2&page_size=2",
        headers=auth_header(customer_token),
    )
    assert page2.status_code == 200
    page2_body = page2.json()
    assert page2_body["total"] == 4 and page2_body["page"] == 2
    assert [i["type"] for i in page2_body["items"]] == [
        ORDER_CONFIRMED,
        ORDER_DRIVER_ASSIGNED,
    ]

    # Out-of-range page: empty items, total unchanged (well-formed page).
    page9 = await async_client.get(
        f"/api/v1/orders/{order_id}/notifications?page=9&page_size=20",
        headers=auth_header(customer_token),
    )
    assert page9.status_code == 200
    assert page9.json()["items"] == [] and page9.json()["total"] == 4

    # Different customer: 404 (existence never leaks; never 403).
    forbidden_probe = await async_client.get(
        f"/api/v1/orders/{order_id}/notifications",
        headers=auth_header(second_customer_token),
    )
    assert forbidden_probe.status_code == 404

    # Admin: may read any order's feed.
    from scripts.seed_demo import SEED_ACCOUNTS

    admin = next(a for a in SEED_ACCOUNTS if a["role"] == "admin")
    login = await async_client.post(
        "/api/v1/auth/login", json={"email": admin["email"], "password": admin["password"]}
    )
    admin_token = login.json()["access_token"]
    admin_feed = await async_client.get(
        f"/api/v1/orders/{order_id}/notifications",
        headers=auth_header(admin_token),
    )
    assert admin_feed.status_code == 200 and admin_feed.json()["total"] == 4

    # Unknown order: 404 with the standard envelope.
    missing = await async_client.get(
        "/api/v1/orders/order_does_not_exist/notifications",
        headers=auth_header(customer_token),
    )
    assert missing.status_code == 404
    assert missing.json()["code"] == "NOT_FOUND"


async def _notification_count(order_id: str) -> int:
    from sqlalchemy import func

    async with session_scope() as session:
        result = await session.execute(
            select(func.count()).select_from(Notification).where(Notification.order_id == order_id)
        )
        return int(result.scalar_one())


async def test_history_and_version_progression(pipeline, async_client, customer_token):
    """Every transition appends exactly one row: v1..v4 unique, chained
    from_status, no gaps, no rewrites under redelivery."""
    pipeline.start_dispatcher()
    for stage in ("payment", "restaurant", "delivery", "notification"):
        pipeline.start_consumers(stage)

    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "DRIVER_ASSIGNED")

    async with session_scope() as session:
        history = list(
            (
                await session.execute(
                    select(OrderStatusHistory)
                    .where(OrderStatusHistory.order_id == order_id)
                    .order_by(OrderStatusHistory.version)
                )
            ).scalars()
        )

    versions = [h.version for h in history]
    assert versions == [1, 2, 3, 4] and len(set(versions)) == 4
    # from_status chains to the previous row's status (v1 is the initial row).
    assert history[0].from_status is None
    for previous, current in zip(history, history[1:], strict=False):
        assert current.from_status == previous.status
        assert current.version == previous.version + 1

    # The order's live version equals the last history version.
    order = await get_order_row(order_id)
    assert order.version == history[-1].version == 4

    # Duplicate the FIRST event after completion: version/history must not move.
    created = await fetch_outbox_payload(order_id, ORDER_CREATED)
    await pipeline.publish_to_queue(pipeline.names.payment_queue, created)
    await pipeline.assert_queue_empty(pipeline.names.payment_queue, settle=1.0)
    order_after = await get_order_row(order_id)
    assert order_after.version == 4
    async with session_scope() as session:
        count = len(
            list(
                (
                    await session.execute(
                        select(OrderStatusHistory).where(OrderStatusHistory.order_id == order_id)
                    )
                ).scalars()
            )
        )
    assert count == 4


async def test_payment_failure_is_terminal_with_no_retry_storm(
    pipeline, async_client, customer_token, monkeypatch
):
    """PAYMENT_MODE=always_decline (PERMANENT business decline) -> exactly one
    FAILED payment, terminal PAYMENT_FAILED status, `order.payment.failed`
    persisted as a notification, and NO retry machinery churns afterwards —
    permanent declines bypass the bounded retry budget by design (§11)."""
    settings = get_settings()
    monkeypatch.setattr(settings, "payment_mode", "always_decline")

    pipeline.start_dispatcher()
    pipeline.start_consumers("payment")
    pipeline.start_consumers("notification")

    order_id = await place_order(async_client, customer_token)
    await wait_for_status(order_id, "PAYMENT_FAILED")
    # The `order.payment.failed` child event is published by the dispatcher
    # (its first attempt may retry); wait until BOTH notifications persisted.
    await wait_for_eq(
        lambda: _notification_count(order_id),
        2,
        timeout=15,
        message="two failure notifications",
    )

    await asyncio.sleep(1.0)  # would reveal any retry/republish churn
    pipeline.raise_if_task_failed()
    rows = await order_rows(order_id)

    order = await get_order_row(order_id)
    assert order.status == "PAYMENT_FAILED" and order.version == 2
    assert order.failure_code == "PAYMENT_DECLINED" and order.failure_reason

    # Terminal transition: history stops at v2 — no retries, no re-decisions.
    assert [h.version for h in rows["history"]] == [1, 2]
    assert [h.status for h in rows["history"]] == ["PENDING", "PAYMENT_FAILED"]
    assert rows["history"][-1].source == "payment"
    assert len(rows["payments"]) == 1
    assert rows["payments"][0].status == "FAILED"

    # `order.payment.failed` reached the notification worker via `order.#`.
    notification_types = sorted(n.type for n in rows["notifications"])
    assert notification_types == sorted([ORDER_CREATED, ORDER_PAYMENT_FAILED])
    assert all(n.order_id == order_id for n in rows["notifications"])

    # The queue drained (ACKed) and nothing requeued for another attempt.
    await pipeline.assert_queue_empty(pipeline.names.payment_queue, settle=0.5)
    # Markers: payment once (order.created) + notification twice
    # (order.created and order.payment.failed) — all committed, none retried.
    marker_counts = Counter(m.consumer_name for m in rows["processed"])
    assert marker_counts == Counter({"notification": 2, "payment": 1})
