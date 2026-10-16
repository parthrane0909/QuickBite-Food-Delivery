"""One-shot topology initializer (Compose service `topology-init`).

Declares every exchange, queue and binding idempotently BEFORE the outbox
dispatcher or any consumer starts (assignment §9; ordering enforced by
Compose `depends_on: condition: service_completed_successfully`). Re-running
is always safe — declarations are idempotent. Exits non-zero on failure so
the gate actually gates.
"""

from __future__ import annotations

import asyncio
import sys

import aio_pika

from app.core.config import get_settings
from app.core.logging import configure_logging


async def init() -> int:
    settings = get_settings()
    configure_logging(settings.log_level, service="topology-init")
    try:
        connection = await aio_pika.connect(settings.amqp_url, timeout=10)
    except Exception as exc:  # noqa: BLE001 — fail loudly, Compose gates on us
        print(f"topology-init: cannot connect to broker: {exc}", file=sys.stderr)
        return 1
    try:
        from app.messaging.topology import declare_topology

        await declare_topology(connection)
    except Exception as exc:  # noqa: BLE001
        print(f"topology-init: declaration failed: {exc}", file=sys.stderr)
        return 1
    finally:
        await connection.close()
    print("topology-init: exchanges, queues and bindings are in place")
    return 0


def main() -> None:
    raise SystemExit(asyncio.run(init()))


if __name__ == "__main__":
    main()
