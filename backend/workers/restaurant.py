"""Restaurant worker — logical consumer `restaurant`, queue `restaurant.queue`.

Consumes `order.paid` and deterministically confirms (PAID -> CONFIRMED) or,
with RESTAURANT_MODE=always_fail, applies the terminal restaurant rejection
(PAID -> FAILED + `order.failed`).
"""

from __future__ import annotations

import asyncio

from app.messaging.consumer_runtime import run_worker
from app.messaging.topology import RESTAURANT_QUEUE
from app.schemas.events import ORDER_PAID
from app.services.restaurant_service import process_restaurant


def main() -> None:
    asyncio.run(
        run_worker(
            consumer_name="restaurant",
            queue_name=RESTAURANT_QUEUE,
            processor=process_restaurant,
            expected_types=frozenset({ORDER_PAID}),
        )
    )


if __name__ == "__main__":
    main()
