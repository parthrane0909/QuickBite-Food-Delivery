"""Delivery worker — logical consumer `delivery`, queue `delivery.queue`.

Consumes `order.confirmed` and assigns exactly one fictional seeded driver
(CONFIRMED -> DRIVER_ASSIGNED — successful completion for this assignment),
or with DELIVERY_MODE=always_fail applies the terminal failure.
"""

from __future__ import annotations

import asyncio

from app.messaging.consumer_runtime import run_worker
from app.messaging.topology import DELIVERY_QUEUE
from app.schemas.events import ORDER_CONFIRMED
from app.services.delivery_service import process_delivery


def main() -> None:
    asyncio.run(
        run_worker(
            consumer_name="delivery",
            queue_name=DELIVERY_QUEUE,
            processor=process_delivery,
            expected_types=frozenset({ORDER_CONFIRMED}),
        )
    )


if __name__ == "__main__":
    main()
