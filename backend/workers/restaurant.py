"""Restaurant worker — logical consumer `restaurant`, queue `restaurant.queue`.

Consumes order.paid and simulates restaurant acceptance (PAID -> CONFIRMED or
FAILED) starting in Milestone 3. M1: independent process scaffold.
"""

from __future__ import annotations

import asyncio

from app.messaging.consumer_runtime import run_worker


def main() -> None:
    asyncio.run(run_worker(consumer_name="restaurant", queue_name="restaurant.queue"))


if __name__ == "__main__":
    main()
