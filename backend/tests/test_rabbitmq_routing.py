"""RabbitMQ topology and binding behavior on the real broker (§9/§20).

Proves: durable entities + idempotent declaration, exact queue/binding routing
(including the multi-segment `order.#` correction for `order.payment.failed`
and `order.driver.assigned`), and that malformed/unsupported envelopes reach
the dead-letter topology instead of being retried forever.
"""

from __future__ import annotations

import copy

import aio_pika

from app.messaging.topology import declare_topology
from app.schemas.events import (
    ORDER_CONFIRMED,
    ORDER_CREATED,
    ORDER_DRIVER_ASSIGNED,
    ORDER_FAILED,
    ORDER_PAID,
    ORDER_PAYMENT_FAILED,
)
from tests.m3_harness import build_envelope, order_rows

ALL_SIX = [
    ORDER_CREATED,
    ORDER_PAID,
    ORDER_PAYMENT_FAILED,
    ORDER_CONFIRMED,
    ORDER_DRIVER_ASSIGNED,
    ORDER_FAILED,
]


async def test_topology_is_durable_and_declaration_is_idempotent(pipeline):
    """Every entity exists (passive declares) and re-declaring changes nothing."""
    names = pipeline.names
    for queue_name in names.all_queues:  # includes the dead-letter queue
        assert await pipeline.queue_depth(queue_name) == 0
    # Idempotent: a second full declaration (as done by every worker reconnect)
    # must succeed without error.
    await declare_topology(pipeline.connection, prefix=pipeline.prefix)
    await declare_topology(pipeline.connection, prefix=pipeline.prefix)
    # And messages survive having no consumers (durability, not just names).
    payload = build_envelope(ORDER_CREATED, "order_topology_probe", 1)
    await pipeline.publish_to_queue(names.payment_queue, payload)
    assert await pipeline.queue_depth(names.payment_queue) == 1
    await pipeline.drain_queue(names.payment_queue, first_timeout=1.0, quiet=0.2)


async def test_bindings_route_each_event_type_to_exactly_the_right_queues(pipeline):
    """One publish per required event type with mandatory=True: an unbound
    routing key would RAISE (basic.return), so success proves the bindings —
    and drains prove the exact per-queue membership."""
    names = pipeline.names
    order_id = "order_route_probe"
    for index, event_type in enumerate(ALL_SIX, start=1):
        payload = build_envelope(event_type, order_id, index)
        await pipeline.publish_to_orders_exchange(event_type, payload, mandatory=True)

    payment = await pipeline.drain_queue(names.payment_queue)
    restaurant = await pipeline.drain_queue(names.restaurant_queue)
    delivery = await pipeline.drain_queue(names.delivery_queue)
    notification = await pipeline.drain_queue(names.notification_queue)
    # Nothing should fail to route; keep the empty-wait short.
    dead = await pipeline.drain_queue(names.dead_queue, first_timeout=0.5)

    # payment -> order.created only
    assert [m["event_type"] for m in payment] == [ORDER_CREATED]
    # restaurant -> order.paid only
    assert [m["event_type"] for m in restaurant] == [ORDER_PAID]
    # delivery -> order.confirmed only
    assert [m["event_type"] for m in delivery] == [ORDER_CONFIRMED]
    # notification -> order.# (multi-segment: ALL SIX, both dotted names included)
    assert sorted(m["event_type"] for m in notification) == sorted(ALL_SIX)
    # nothing failed to route
    assert dead == []


async def test_multi_segment_wildcard_reaches_dotted_event_names(pipeline):
    """Regression guard for the `order.*` -> `order.#` correction: publishing
    ONLY the dotted names via mandatory routing must succeed (a one-segment
    star would return the message and raise)."""
    order_id = "order_dotted_probe"
    await pipeline.publish_to_orders_exchange(
        ORDER_PAYMENT_FAILED,
        build_envelope(ORDER_PAYMENT_FAILED, order_id, 2),
        mandatory=True,
    )
    await pipeline.publish_to_orders_exchange(
        ORDER_DRIVER_ASSIGNED,
        build_envelope(ORDER_DRIVER_ASSIGNED, order_id, 4),
        mandatory=True,
    )
    notification = await pipeline.drain_queue(pipeline.names.notification_queue)
    assert sorted(m["event_type"] for m in notification) == sorted(
        [ORDER_PAYMENT_FAILED, ORDER_DRIVER_ASSIGNED]
    )
    # The single-segment queues correctly did NOT get them.
    assert await pipeline.queue_depth(pipeline.names.payment_queue) == 0
    assert await pipeline.queue_depth(pipeline.names.restaurant_queue) == 0
    assert await pipeline.queue_depth(pipeline.names.delivery_queue) == 0


async def test_malformed_and_unsupported_envelopes_are_dead_lettered(pipeline):
    """Malformed/unknown-schema -> dead-letter + ACK (never infinite retry);
    a well-formed FUTURE event type -> logged + ACK without side effects."""
    names = pipeline.names
    pipeline.start_consumers("payment")
    pipeline.start_consumers("notification")

    channel = await pipeline.connection.channel()

    # 1. Not JSON at all.
    await channel.default_exchange.publish(
        aio_pika.Message(body=b"this-is-not-json{{{", message_id="malformed_raw_1"),
        routing_key=names.payment_queue,
    )

    # 2. Well-formed JSON, unsupported schema_version.
    unsupported = build_envelope(ORDER_CREATED, "order_dead_probe", 1)
    unsupported = {**unsupported, "schema_version": 2}
    await pipeline.publish_to_queue(
        names.payment_queue, unsupported, message_id="unsupported_schema_1"
    )

    # 3. Well-formed envelope with a FUTURE event type.
    future = build_envelope(ORDER_CREATED, "order_dead_probe", 1)
    future = {**copy.deepcopy(future), "event_type": "order.tracked_in_future"}
    await pipeline.publish_to_queue(names.notification_queue, future, message_id="future_type_1")

    dead = await pipeline.drain_queue(names.dead_queue)
    reasons = sorted(m.get("reason", "") for m in dead)
    assert reasons == ["invalid_json", "unsupported_schema_version"]
    assert len(dead) == 2  # exactly the two rejected copies

    # Both malformed copies were ACKED (queues drained), and the future type
    # was acknowledged WITHOUT dead-lettering it or writing anything.
    await pipeline.assert_queue_empty(names.payment_queue, settle=1.0)
    await pipeline.assert_queue_empty(names.notification_queue, settle=1.0)

    rows = await order_rows("order_dead_probe")
    assert rows["processed"] == [] and rows["notifications"] == []
