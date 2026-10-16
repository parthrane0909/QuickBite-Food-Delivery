"""Notification worker — logical consumer `notification`, queue `notification.queue`.

Consumes order.# (multi-segment binding: covers order.created, order.paid,
order.payment.failed, order.confirmed, order.driver.assigned, order.failed)
and persists one deduplicated customer notification per logical event,
starting in Milestone 3. Notification failures NEVER change order business
status. M1: independent process scaffold.
"""

from __future__ import annotations

import asyncio

from app.messaging.consumer_runtime import run_worker


def main() -> None:
    asyncio.run(run_worker(consumer_name="notification", queue_name="notification.queue"))


if __name__ == "__main__":
    main()
