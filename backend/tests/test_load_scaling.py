"""Opt-in M7 load/scaling run against disposable PostgreSQL + tst_ RabbitMQ.

Run with QUICKBITE_RUN_LOAD_BENCHMARK=1 pytest -q tests/test_load_scaling.py.
The test DB is recreated and dropped by conftest; no development orders or
production queues are used. Each worker configuration is repeated twice.
"""

from __future__ import annotations

import asyncio
import json
import os
import resource
import statistics
import time
from pathlib import Path

import pytest
from sqlalchemy import func, select

from app.db.models.notification import Notification
from app.db.models.order import Order
from app.db.session import session_scope
from scripts.seed_large_catalogue import seed
from tests.conftest import auth_header
from tests.m3_harness import ADDRESS, MARGHERITA, RESTAURANT, wait_until

pytestmark = pytest.mark.skipif(
    os.getenv("QUICKBITE_RUN_LOAD_BENCHMARK") != "1",
    reason="opt-in 400-order M7 benchmark; recreates only quickbite_test",
)


def _percentile(values: list[float], quantile: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, round((len(ordered) - 1) * quantile))]


@pytest.mark.asyncio
async def test_one_vs_three_payment_consumers_repeated_twice(
    pipeline, async_client, customer_token, admin_token
):
    await seed(2_000)
    pipeline.start_dispatcher(poll_interval=0.01)
    results: list[dict] = []

    for workers in (1, 3):
        for repetition in (1, 2):
            for stage in ("payment", "restaurant", "delivery", "notification"):
                pipeline.start_consumers(stage, instances=workers if stage == "payment" else 1)

            request_latencies: list[float] = []
            request_semaphore = asyncio.Semaphore(20)

            async def submit(
                index: int,
                workers: int = workers,
                repetition: int = repetition,
                request_latencies: list[float] = request_latencies,
                request_semaphore: asyncio.Semaphore = request_semaphore,
            ) -> tuple[str | None, int]:
                async with request_semaphore:
                    started = time.perf_counter()
                    response = await async_client.post(
                        "/api/v1/orders",
                        json={
                            "restaurant_id": RESTAURANT,
                            "delivery_address": ADDRESS,
                            "items": [{"menu_item_id": MARGHERITA, "quantity": 1}],
                        },
                        headers={
                            **auth_header(customer_token),
                            "Idempotency-Key": f"m7-w{workers}-r{repetition}-{index}",
                        },
                    )
                    request_latencies.append((time.perf_counter() - started) * 1000)
                if response.status_code != 202:
                    return None, response.status_code
                return str(response.json()["order_id"]), response.status_code

            started = time.perf_counter()
            submissions = await asyncio.gather(*(submit(i) for i in range(100)))
            accepted_ids = [order_id for order_id, code in submissions if code == 202 and order_id]
            assert len(accepted_ids) == 100, submissions

            await wait_until(
                lambda accepted_ids=accepted_ids: _completed(accepted_ids),
                timeout=120,
                interval=0.1,
                message=f"{len(accepted_ids)} orders complete with {workers} payment worker(s)",
            )
            await wait_until(
                lambda accepted_ids=accepted_ids: _notifications(accepted_ids),
                timeout=60,
                interval=0.1,
                message="all four persisted notifications per order",
            )
            duration = time.perf_counter() - started
            pipeline.raise_if_task_failed()

            summary = {
                "payment_workers": workers,
                "repetition": repetition,
                "attempted": 100,
                "accepted": len(accepted_ids),
                "failed": len(submissions) - len(accepted_ids),
                "completed": 100,
                "duration_seconds": round(duration, 4),
                "orders_per_second": round(100 / duration, 3),
                "api_checkout_p50_ms": round(statistics.median(request_latencies), 3),
                "api_checkout_p95_ms": round(_percentile(request_latencies, 0.95), 3),
                "rabbit_ready_messages_after_completion": {
                    name: await pipeline.queue_depth(name)
                    for name in pipeline.names.consumer_queues
                },
            }
            results.append(summary)

            for stage in ("payment", "restaurant", "delivery", "notification"):
                pipeline.stop_consumer(stage)
                await pipeline.wait_consumer_stopped(stage, timeout=30)

    # Measure representative search, paginated restaurant/menu, and admin list
    # requests against the same disposable database. They stay read-only.
    async def latency(path: str, token: str) -> float:
        samples = []
        for _ in range(20):
            start = time.perf_counter()
            response = await async_client.get(path, headers=auth_header(token))
            assert response.status_code == 200, response.text
            samples.append((time.perf_counter() - start) * 1000)
        return round(_percentile(samples, 0.95), 3)

    catalog_latency = {
        "restaurant_page_1_p95_ms": await latency(
            "/api/v1/restaurants?page_size=20", customer_token
        ),
        "restaurant_name_search_p95_ms": await latency(
            "/api/v1/restaurants?page_size=20&search=Kitchens", customer_token
        ),
        "restaurant_cuisine_search_p95_ms": await latency(
            "/api/v1/restaurants?page_size=20&cuisine=Italian", customer_token
        ),
        "admin_restaurant_page_p95_ms": await latency(
            "/api/v1/admin/restaurants?page_size=20", admin_token
        ),
        "fixture_menu_page_p95_ms": await latency(
            f"/api/v1/restaurants/{RESTAURANT}/menu?page_size=20", customer_token
        ),
    }
    report = {
        "environment": "isolated quickbite_test PostgreSQL + tst_ RabbitMQ topology",
        "request_model": (
            "100 checkout requests per run, bounded to 20 simultaneous ASGI calls; "
            "test-mode stage delays are 0 seconds"
        ),
        "runs": results,
        "read_only_catalogue_endpoint_p95_ms": catalog_latency,
        "test_process_max_rss_kib": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
        "host_load_average_1_5_15": os.getloadavg(),
        "notes": [
            "Checkout latency uses in-process FastAPI ASGI transport, "
            "not nginx or a remote network.",
            "Only payment worker count changes; all other stage counts stay at one.",
            "The pytest session drops quickbite_test; the Compose development database is unused.",
        ],
    }
    destination = Path(__file__).resolve().parents[2] / "docs/evidence/final/load-test.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, indent=2) + "\n")


async def _completed(order_ids: list[str]) -> bool:
    async with session_scope() as session:
        count = await session.scalar(
            select(func.count(Order.id)).where(
                Order.id.in_(order_ids), Order.status == "DRIVER_ASSIGNED"
            )
        )
    return int(count or 0) == len(order_ids)


async def _notifications(order_ids: list[str]) -> bool:
    async with session_scope() as session:
        count = await session.scalar(
            select(func.count(Notification.id)).where(Notification.order_id.in_(order_ids))
        )
    return int(count or 0) == len(order_ids) * 4
