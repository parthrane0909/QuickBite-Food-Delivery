"""Operational backlog inspection for the Milestone 4 reliability components.

Run inside the stack (no host Python needed):

    docker compose exec api python -m scripts.inspect_state
    docker compose exec api python -m scripts.inspect_state --jobs 20 --quarantine 20
    docker compose exec api python -m scripts.inspect_state --no-broker

Prints (assignment §11/§13 inspection requirement):
  - outbox backlog per state + oldest eligible age (dispatcher view)
  - retry_jobs per state + oldest DUE age (scheduler view) + recent jobs
  - quarantine_records total + the most recent records
  - production RabbitMQ queue depths (skipped with --no-broker, or when the
    broker is unreachable — reported, never fatal: an outage is itself
    inspectable evidence)

Read-only: never mutates any row or queue.
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from datetime import UTC, datetime

from sqlalchemy import text

from app.core.config import get_settings
from app.db.session import session_scope

# Production names only — tst_* belongs to the isolated test namespace.
PROD_QUEUES = (
    "payment.queue",
    "restaurant.queue",
    "delivery.queue",
    "notification.queue",
    "orders.dead-letter.queue",
)


def _print_section(title: str) -> None:
    print(f"\n=== {title} " + "=" * max(1, 66 - len(title)))


async def _outbox_backlog() -> None:
    _print_section("outbox backlog (dispatcher)")
    async with session_scope() as session:
        counts = {
            row[0]: int(row[1])
            for row in (
                await session.execute(
                    text("SELECT state, count(*) FROM outbox_events GROUP BY state")
                )
            ).all()
        }
        for state in ("PENDING", "CLAIMED", "SENT"):
            print(f"  {state:8} {counts.get(state, 0)}")
        oldest = (
            await session.execute(
                text(
                    "SELECT now() - min(available_at) FROM outbox_events "
                    "WHERE state = 'PENDING' AND available_at <= now()"
                )
            )
        ).scalar_one()
        print(f"  oldest ELIGIBLE pending row age: {oldest or 'none'}")


async def _retry_backlog(jobs_limit: int) -> None:
    _print_section("retry jobs (scheduler)")
    async with session_scope() as session:
        counts = {
            row[0]: int(row[1])
            for row in (
                await session.execute(text("SELECT state, count(*) FROM retry_jobs GROUP BY state"))
            ).all()
        }
        for state in ("PENDING", "PUBLISHED", "EXHAUSTED"):
            print(f"  {state:10} {counts.get(state, 0)}")
        oldest_due = (
            await session.execute(
                text(
                    "SELECT now() - min(due_at) FROM retry_jobs "
                    "WHERE state = 'PENDING' AND due_at <= now()"
                )
            )
        ).scalar_one()
        print(f"  oldest DUE unactivated age: {oldest_due or 'none'}")

        rows = (
            await session.execute(
                text(
                    "SELECT consumer_name, event_id, attempt, state, created_at, "
                    "due_at, left(coalesce(last_error, ''), 60) "
                    "FROM retry_jobs ORDER BY id DESC LIMIT :limit"
                ),
                {"limit": jobs_limit},
            )
        ).all()
        print(f"  most recent {len(rows)} job(s):")
        for consumer, event_id, attempt, state, created, due, err in rows:
            print(
                f"    {consumer:12} {event_id[:28]:28} #{attempt} {state:9} "
                f"due_in={_due_delta(due)} created={created} err={err!r}"
            )


def _due_delta(due: datetime) -> str:
    if due.tzinfo is None:
        due = due.replace(tzinfo=UTC)
    delta = (due - datetime.now(UTC)).total_seconds()
    return f"{delta:+.1f}s"


async def _quarantine(limit: int) -> None:
    _print_section("quarantine records")
    async with session_scope() as session:
        total = (
            await session.execute(text("SELECT count(*) FROM quarantine_records"))
        ).scalar_one()
        print(f"  total: {total}")
        rows = (
            await session.execute(
                text(
                    "SELECT consumer_name, failure_code, attempts, "
                    "order_id, event_id, created_at "
                    "FROM quarantine_records ORDER BY created_at DESC LIMIT :limit"
                ),
                {"limit": limit},
            )
        ).all()
        for consumer, code, attempts, order_id, event_id, created in rows:
            print(f"    {consumer:12} {code:30} attempts={attempts} order={order_id or '-'}")
            print(f"      event_id={event_id} at={created}")


async def _queue_depths() -> None:
    _print_section("production queue depths (broker management API)")
    try:
        from urllib.parse import urlparse

        import httpx2

        settings = get_settings()
        parsed = urlparse(settings.amqp_url)
        host = parsed.hostname or "rabbitmq"
        # Management API shares the broker host, HTTPS-port offset from AMQP.
        mgmt_port = 15672 if parsed.port in (None, 5672) else parsed.port
        base = f"http://{host}:{mgmt_port}"
        response = httpx2.get(
            f"{base}/api/queues",
            auth=(parsed.username or "", parsed.password or ""),
            timeout=5,
        )
        response.raise_for_status()
        wanted = set(PROD_QUEUES)
        for queue in sorted(response.json(), key=lambda q: q["name"]):
            if queue["name"] in wanted:
                print(
                    f"  {queue['name']:26} messages={queue.get('messages', 0)} "
                    f"consumers={queue.get('consumers', 0)}"
                )
    except Exception as exc:  # noqa: BLE001 - outage must be reportable, not fatal
        print(f"  broker unreachable (management API): {exc!r}")


async def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=10, help="recent retry jobs")
    parser.add_argument("--quarantine", type=int, default=10, help="recent quarantine records")
    parser.add_argument("--no-broker", action="store_true", help="skip RabbitMQ depth check")
    args = parser.parse_args()

    await _outbox_backlog()
    await _retry_backlog(args.jobs)
    await _quarantine(args.quarantine)
    if not args.no_broker:
        await _queue_depths()
    print()
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
