"""Protected deterministic failure-control demonstrations (assignment §12).

Runs ONE scenario at a time against the LIVE stack, driving a production queue
with an in-process consumer whose failure mode comes from the PROCESS
ENVIRONMENT (settings) — never from checkout/API fields (§12: simulation
controls are protected; the API cannot trigger or steer a failure).

    docker compose run --rm api python -m scripts.demo_failures --list
    docker compose run --rm api python -m scripts.demo_failures payment_exhaust
    docker compose run --rm api python -m scripts.demo_failures --all

PREREQUISITES (see scripts/capture_m4_evidence.sh, which orchestrates this):
  - outbox-dispatcher + retry-scheduler running (publishes the API's events
    and activates due retries),
  - the LIVE worker for the driven stage STOPPED (otherwise it competes for
    the same production messages and may consume them first),
  - demo users seeded (`docker compose run --rm seed`).

Scenarios use the DEFAULT retry schedule (2s/10s/30s + 1 initial attempt),
so timing evidence comes from the real configuration, not test values.
"""

from __future__ import annotations

import argparse
import asyncio
import os
import re
import sys
import uuid
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime

import aio_pika
import httpx2
from sqlalchemy import text

from app.core.config import get_settings
from app.db.session import session_scope
from app.messaging.consumer_runtime import consume_forever
from app.messaging.topology import (
    DELIVERY_QUEUE,
    NOTIFICATION_QUEUE,
    PAYMENT_QUEUE,
    RESTAURANT_QUEUE,
)
from app.schemas.events import EVENT_TYPES, ORDER_CONFIRMED, ORDER_CREATED, ORDER_PAID
from app.services.delivery_service import process_delivery
from app.services.notification_service import process_notification
from app.services.payment_service import process_payment
from app.services.restaurant_service import process_restaurant

BASE_URL = os.environ.get("BASE_URL", "http://api:8000")
EMAIL = os.environ.get("DEMO_EMAIL", "alice@quickbite.dev")
PASSWORD = os.environ.get("DEMO_PASSWORD", "quickbite!alice1")
RESTAURANT_BODY = {
    "restaurant_id": "rest_bella_napoli",
    "delivery_address": "12 Lake Road, Bengaluru",
    "items": [
        {"menu_item_id": "item_margherita_pizza", "quantity": 2},
        {"menu_item_id": "item_garlic_bread", "quantity": 1},
    ],
}

ConsumerSpec = tuple[str, str, object, frozenset[str], str]  # name, queue, proc, types, mode env


SCENARIOS: dict[str, tuple[ConsumerSpec, str]] = {
    "payment_baseline": (
        ("payment", PAYMENT_QUEUE, process_payment, frozenset({ORDER_CREATED}), "PAYMENT_MODE"),
        "always_succeed",
    ),
    "payment_fail_twice": (
        ("payment", PAYMENT_QUEUE, process_payment, frozenset({ORDER_CREATED}), "PAYMENT_MODE"),
        "fail_twice",
    ),
    "payment_decline": (
        ("payment", PAYMENT_QUEUE, process_payment, frozenset({ORDER_CREATED}), "PAYMENT_MODE"),
        "always_decline",
    ),
    "payment_exhaust": (
        ("payment", PAYMENT_QUEUE, process_payment, frozenset({ORDER_CREATED}), "PAYMENT_MODE"),
        "always_fail",
    ),
    "restaurant_reject": (
        (
            "restaurant",
            RESTAURANT_QUEUE,
            process_restaurant,
            frozenset({ORDER_PAID}),
            "RESTAURANT_MODE",
        ),
        "always_fail",
    ),
    "delivery_fail": (
        (
            "delivery",
            DELIVERY_QUEUE,
            process_delivery,
            frozenset({ORDER_CONFIRMED}),
            "DELIVERY_MODE",
        ),
        "always_fail",
    ),
    "notification_fail": (
        (
            "notification",
            NOTIFICATION_QUEUE,
            process_notification,
            EVENT_TYPES,
            "NOTIFICATION_MODE",
        ),
        "always_fail",
    ),
}

# Consumer that must be STOPPED while the scenario drives its queue.
STOP_LIVE_WORKER: dict[str, str] = {
    "payment_baseline": "payment-worker",
    "payment_fail_twice": "payment-worker",
    "payment_decline": "payment-worker",
    "payment_exhaust": "payment-worker",
    "restaurant_reject": "restaurant-worker",
    "delivery_fail": "delivery-worker",
    "notification_fail": "notification-worker",
}


async def login(client: httpx2.AsyncClient) -> str:
    response = await client.post(
        f"{BASE_URL}/api/v1/auth/login",
        json={"email": EMAIL, "password": PASSWORD},
    )
    response.raise_for_status()
    return response.json()["access_token"]


async def place_order(client: httpx2.AsyncClient, token: str) -> str:
    response = await client.post(
        f"{BASE_URL}/api/v1/orders",
        headers={
            "Authorization": f"Bearer {token}",
            "Idempotency-Key": str(uuid.uuid4()),
            "X-Request-ID": f"req_demo_{uuid.uuid4().hex[:16]}",
        },
        json=RESTAURANT_BODY,
    )
    response.raise_for_status()
    found = re.search(r"order_[a-f0-9]{32}", response.headers.get("location", ""))
    if found is None:
        found = re.search(r"order_[a-f0-9]{32}", response.text)
    if found is None:
        raise RuntimeError(f"no order id in response: {response.status_code} {response.text}")
    return found.group(0)


async def _rows(query: str, **params: object) -> list[tuple]:
    async with session_scope() as session:
        result = await session.execute(text(query), params)
        return list(result.all())


async def _order_state(order_id: str) -> tuple[str, int, str | None]:
    rows = await _rows(
        "SELECT status, version, failure_code FROM orders WHERE id = :id",
        id=order_id,
    )
    if not rows:
        return ("", 0, None)
    return (rows[0][0], int(rows[0][1]), rows[0][2])


async def wait_for(
    predicate: Callable[[], Awaitable[bool]],
    *,
    timeout: float,
    context: Callable[[], Awaitable[str]],
    interval: float = 1.0,
) -> None:
    deadline = asyncio.get_running_loop().time() + timeout
    while asyncio.get_running_loop().time() < deadline:
        if await predicate():
            return
        await asyncio.sleep(interval)
    raise TimeoutError(f"scenario did not reach its terminal state: {await context()}")


async def run_scenario(name: str) -> None:
    spec, mode = SCENARIOS[name]
    consumer_name, queue_name, processor, expected_types, mode_env = spec

    # Protected control: PROCESS ENV ONLY (never an API/checkout field).
    os.environ[mode_env] = mode
    get_settings.cache_clear()
    settings = get_settings()
    print(f"\n{'=' * 72}")
    print(f"scenario {name}: {mode_env}={mode} driving production queue {queue_name}")
    print(f"  reminder: the live {STOP_LIVE_WORKER[name]} must be STOPPED for this")
    print(
        f"  retry schedule in effect: {settings.retry_delays}s (max {settings.retry_max_attempts})"
    )
    print(f"{'=' * 72}")

    async with httpx2.AsyncClient(timeout=15) as client:
        token = await login(client)
        order_id = await place_order(client, token)
        print(f"order placed via POST /api/v1/orders -> {order_id}")

        stop_event = asyncio.Event()
        connection = await aio_pika.connect_robust(settings.amqp_url, timeout=10)
        consumer = asyncio.create_task(
            consume_forever(
                connection,
                consumer_name=consumer_name,
                queue_name=queue_name,
                processor=processor,
                expected_types=expected_types,
                stop_event=stop_event,
            )
        )

        try:

            async def _terminal() -> bool:
                status, _, _ = await _order_state(order_id)
                if name == "notification_fail":
                    # Business chain must COMPLETE; failures only quarantine.
                    return status == "DRIVER_ASSIGNED" and await _quarantine_count(order_id) >= 4
                terminal = (
                    "payment_decline",
                    "payment_exhaust",
                    "restaurant_reject",
                    "delivery_fail",
                )
                if name in terminal:
                    return status in ("PAYMENT_FAILED", "FAILED")
                return status == "DRIVER_ASSIGNED"

            timeout = 240.0 if name in ("payment_exhaust", "notification_fail") else 90.0
            await wait_for(
                _terminal,
                timeout=timeout,
                context=lambda: _report_context(order_id),
            )
        finally:
            stop_event.set()
            await asyncio.gather(consumer, return_exceptions=True)
            await connection.close()

        await print_report(name, order_id, consumer_name)


async def _quarantine_count(order_id: str) -> int:
    rows = await _rows("SELECT count(*) FROM quarantine_records WHERE order_id = :id", id=order_id)
    return int(rows[0][0])


async def _report_context(order_id: str) -> str:
    status, version, failure_code = await _order_state(order_id)
    return f"order={order_id} status={status} version={version} failure_code={failure_code}"


async def print_report(name: str, order_id: str, consumer_name: str) -> None:
    status, version, failure_code = await _order_state(order_id)
    print(f"\n-- result: {name} --")
    print(f"order: status={status} version={version} failure_code={failure_code or '-'}")

    history = await _rows(
        "SELECT version, from_status, status FROM order_status_history "
        "WHERE order_id = :id ORDER BY version",
        id=order_id,
    )
    print("history: " + " -> ".join(f"v{v}:{s1}->{s2}" for v, s1, s2 in history))

    payments = await _rows(
        "SELECT status, failure_code FROM simulated_payments WHERE order_id = :id",
        id=order_id,
    )
    print(f"simulated payments: {[(p[0], p[1] or '-') for p in payments]}")

    jobs = await _rows(
        "SELECT attempt, state, created_at, due_at FROM retry_jobs "
        "WHERE order_id = :id AND consumer_name = :consumer ORDER BY attempt",
        id=order_id,
        consumer=consumer_name,
    )
    if jobs:
        print(f"retry ladder ({consumer_name}):")
        for attempt, state, created, due in jobs:
            print(
                f"  attempt #{attempt} state={state} created={created} due={due} "
                f"scheduled_in={_seconds_between(created, due)}s"
            )
    else:
        print("retry ladder: EMPTY (no transient failures in this scenario)")

    quarantined = await _rows(
        "SELECT consumer_name, failure_code, attempts FROM quarantine_records "
        "WHERE order_id = :id ORDER BY created_at",
        id=order_id,
    )
    print(
        "quarantine: "
        + (", ".join(f"{c} code={code} attempts={a}" for c, code, a in quarantined) or "none")
    )

    notifications = await _rows(
        "SELECT seq, type, left(message, 50) FROM notifications WHERE order_id = :id ORDER BY seq",
        id=order_id,
    )
    print(f"customer notifications persisted: {len(notifications)}")
    for seq, kind, message in notifications:
        print(f"  #{seq} {kind}: {message}")


def _seconds_between(created: datetime, due: datetime) -> float:
    if created.tzinfo is None:
        created = created.replace(tzinfo=UTC)
    if due.tzinfo is None:
        due = due.replace(tzinfo=UTC)
    return (due - created).total_seconds()


async def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scenario", nargs="?", choices=sorted(SCENARIOS))
    parser.add_argument("--all", action="store_true", help="run every scenario in order")
    parser.add_argument("--list", action="store_true", help="list scenarios and exit")
    args = parser.parse_args()

    if args.list:
        for name, (spec, mode) in sorted(SCENARIOS.items()):
            print(f"  {name:20} {spec[4]}={mode}  (stop {STOP_LIVE_WORKER[name]})")
        return 0

    names = list(SCENARIOS) if args.all else [args.scenario]
    if not names or names[0] is None:
        parser.print_help()
        return 2

    for name in names:
        await run_scenario(name)
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
