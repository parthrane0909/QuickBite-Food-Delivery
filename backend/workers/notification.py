"""Notification worker — logical consumer `notification`, queue `notification.queue`.

Binds `order.#` (MULTI-segment wildcard, so it also receives
`order.payment.failed` and `order.driver.assigned`) and persists exactly one
customer notification per event. Notifications never change order status.
"""

from __future__ import annotations

import asyncio

from app.messaging.consumer_runtime import run_worker
from app.messaging.topology import NOTIFICATION_QUEUE
from app.schemas.events import EVENT_TYPES
from app.services.notification_service import process_notification


def main() -> None:
    asyncio.run(
        run_worker(
            consumer_name="notification",
            queue_name=NOTIFICATION_QUEUE,
            processor=process_notification,
            expected_types=frozenset(EVENT_TYPES),
        )
    )


if __name__ == "__main__":
    main()
