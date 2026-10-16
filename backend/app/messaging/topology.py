"""Broker topology NAME constants (assignment §9/§10).

Milestone 2 only needs the destination identity so the checkout transaction
can write outbox rows. Milestone 3 adds the idempotent declaration functions
(exchanges/queues/bindings) used by topology-init and the dispatcher; keeping
the names here from the start guarantees producers and topology cannot drift.
"""

from __future__ import annotations

# Durable topic exchange carrying every domain event.
ORDERS_EXCHANGE = "quickbite.orders"

# Durable direct exchange + queue for quarantined/failed envelopes.
DEAD_EXCHANGE = "quickbite.dead"
DEAD_QUEUE = "orders.dead-letter.queue"
DEAD_ROUTING_KEY = "failed"

# Main consumer queues (durable, non-exclusive, never auto-delete).
PAYMENT_QUEUE = "payment.queue"
RESTAURANT_QUEUE = "restaurant.queue"
DELIVERY_QUEUE = "delivery.queue"
NOTIFICATION_QUEUE = "notification.queue"
