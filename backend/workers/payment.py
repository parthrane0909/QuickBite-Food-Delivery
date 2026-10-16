"""Payment worker — logical consumer `payment`, queue `payment.queue`.

Consumes order.created and simulates payment (PENDING -> PAID or
PAYMENT_FAILED) starting in Milestone 3. M1: independent process scaffold.
"""

from __future__ import annotations

import asyncio

from app.messaging.consumer_runtime import run_worker


def main() -> None:
    asyncio.run(run_worker(consumer_name="payment", queue_name="payment.queue"))


if __name__ == "__main__":
    main()
