"""Payment worker — logical consumer `payment`, queue `payment.queue`.

Consumes `order.created` and simulates payment (PENDING -> PAID, or terminal
PAYMENT_FAILED via PAYMENT_MODE=always_fail). Milestone 3: full consume loop
with commit-before-ack, (consumer, event_id) dedup and dead-letter handling.
"""

from __future__ import annotations

import asyncio

from app.messaging.consumer_runtime import run_worker
from app.messaging.topology import PAYMENT_QUEUE
from app.schemas.events import ORDER_CREATED
from app.services.payment_service import process_payment


def main() -> None:
    asyncio.run(
        run_worker(
            consumer_name="payment",
            queue_name=PAYMENT_QUEUE,
            processor=process_payment,
            expected_types=frozenset({ORDER_CREATED}),
        )
    )


if __name__ == "__main__":
    main()
