"""Delivery worker — logical consumer `delivery`, queue `delivery.queue`.

Consumes order.confirmed and assigns one fictional driver
(CONFIRMED -> DRIVER_ASSIGNED or FAILED) starting in Milestone 3.
M1: independent process scaffold.
"""

from __future__ import annotations

import asyncio

from app.messaging.consumer_runtime import run_worker


def main() -> None:
    asyncio.run(run_worker(consumer_name="delivery", queue_name="delivery.queue"))


if __name__ == "__main__":
    main()
