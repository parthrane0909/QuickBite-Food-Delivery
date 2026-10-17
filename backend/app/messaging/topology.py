"""Broker topology: durable exchanges/queues/bindings + idempotent declaration.

Declaration is a deliberate, re-runnable step (assignment §9 / prompt §5):
`scripts/init_topology.py` runs it BEFORE the outbox dispatcher starts (the
Compose topology-init one-shot gates dispatcher and workers), and consumers /
the dispatcher re-declare defensively on startup — all declarations are
idempotent, so duplicate runs are safe.

The `order.#` notification binding is a deliberate correction of the original
`order.*` typo: a star matches exactly ONE segment, so `order.*` would silently
miss `order.payment.failed` and `order.driver.assigned` (assignment §20).

`prefix` namespaces every entity name (exchange/queue). Production uses ""; the
integration-test harness uses a test prefix so a running Compose stack never
competes with test messages. Structure, bindings and durability are identical.
"""

from __future__ import annotations

import logging

import aio_pika

logger = logging.getLogger("quickbite.topology")

# Durable topic exchange carrying every domain event.
ORDERS_EXCHANGE = "quickbite.orders"

# Durable direct exchange + queue for quarantined/failed envelopes.
DEAD_EXCHANGE = "quickbite.dead"
DEAD_QUEUE = "orders.dead-letter.queue"
DEAD_ROUTING_KEY = "failed"

# RabbitMQ's pre-declared default exchange (empty name, direct): every queue is
# automatically bound to it with routing key == queue name. Milestone 4
# targeted retries publish HERE with routing_key equal to the FAILING queue's
# name — only the original consumer ever receives the retry (assignment §11).
# The default exchange must never be declared or bound (RabbitMQ rejects both).
DEFAULT_EXCHANGE = ""

# Main consumer queues (durable, non-exclusive, never auto-delete).
PAYMENT_QUEUE = "payment.queue"
RESTAURANT_QUEUE = "restaurant.queue"
DELIVERY_QUEUE = "delivery.queue"
NOTIFICATION_QUEUE = "notification.queue"

# queue -> binding patterns (notification deliberately uses the multi-segment
# wildcard `order.#` so it receives order.payment.failed/order.driver.assigned).
QUEUE_BINDINGS: dict[str, tuple[str, ...]] = {
    PAYMENT_QUEUE: ("order.created",),
    RESTAURANT_QUEUE: ("order.paid",),
    DELIVERY_QUEUE: ("order.confirmed",),
    NOTIFICATION_QUEUE: ("order.#",),
}


class TopologyNames:
    """Resolved entity names for one prefix (production or test namespace)."""

    def __init__(self, prefix: str = "") -> None:
        self.prefix = prefix
        self.orders_exchange = f"{prefix}{ORDERS_EXCHANGE}"
        self.dead_exchange = f"{prefix}{DEAD_EXCHANGE}"
        self.dead_queue = f"{prefix}{DEAD_QUEUE}"
        self.dead_routing_key = DEAD_ROUTING_KEY
        self.payment_queue = f"{prefix}{PAYMENT_QUEUE}"
        self.restaurant_queue = f"{prefix}{RESTAURANT_QUEUE}"
        self.delivery_queue = f"{prefix}{DELIVERY_QUEUE}"
        self.notification_queue = f"{prefix}{NOTIFICATION_QUEUE}"

    @property
    def consumer_queues(self) -> tuple[str, ...]:
        return (
            self.payment_queue,
            self.restaurant_queue,
            self.delivery_queue,
            self.notification_queue,
        )

    @property
    def all_queues(self) -> tuple[str, ...]:
        return (*self.consumer_queues, self.dead_queue)

    def bindings(self) -> dict[str, tuple[str, ...]]:
        return {
            self.payment_queue: QUEUE_BINDINGS[PAYMENT_QUEUE],
            self.restaurant_queue: QUEUE_BINDINGS[RESTAURANT_QUEUE],
            self.delivery_queue: QUEUE_BINDINGS[DELIVERY_QUEUE],
            self.notification_queue: QUEUE_BINDINGS[NOTIFICATION_QUEUE],
            self.dead_queue: (DEAD_ROUTING_KEY,),
        }


async def declare_topology(
    connection: aio_pika.abc.AbstractConnection, *, prefix: str = ""
) -> TopologyNames:
    """Declare every exchange, queue and binding idempotently (topic/direct
    exchanges first, then queues, then bindings). Safe to call any number of
    times from any process."""
    names = TopologyNames(prefix)
    channel = await connection.channel()

    orders_exchange = await channel.declare_exchange(
        names.orders_exchange, aio_pika.ExchangeType.TOPIC, durable=True
    )
    dead_exchange = await channel.declare_exchange(
        names.dead_exchange, aio_pika.ExchangeType.DIRECT, durable=True
    )

    queues: dict[str, aio_pika.abc.AbstractQueue] = {}
    for queue_name in names.all_queues:
        queues[queue_name] = await channel.declare_queue(
            queue_name, durable=True, exclusive=False, auto_delete=False
        )

    for queue_name, patterns in names.bindings().items():
        target = dead_exchange if queue_name == names.dead_queue else orders_exchange
        for pattern in patterns:
            await queues[queue_name].bind(target, routing_key=pattern)

    await channel.close()
    logger.info(
        "topology declared",
        extra={
            "exchange": names.orders_exchange,
            "result": "declared",
            "queues": ",".join(names.all_queues),
        },
    )
    return names


async def purge_queues(connection: aio_pika.abc.AbstractConnection, *, prefix: str = "") -> None:
    """Test-harness helper: drop any residual messages so each scenario starts
    from an empty broker state (never used by production processes)."""
    names = TopologyNames(prefix)
    channel = await connection.channel()
    for queue_name in names.all_queues:
        queue = await channel.declare_queue(
            queue_name, durable=True, exclusive=False, auto_delete=False
        )
        await queue.purge()
    await channel.close()
