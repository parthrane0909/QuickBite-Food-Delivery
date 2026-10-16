"""Outbox dispatcher: no loss under broker failure, claim/lease recovery (§10).

Covers required tests: committed outbox events survive broker unavailability
without loss or identity change, and dispatcher crash recovery (expired
lease + crash-after-publish-before-SENT) preserves exactly-once business
effects downstream. The PHYSICAL broker-restart variant runs against the real
stack in `scripts/capture_m3_evidence.sh` (captured in docs/evidence/m3/).
"""

from __future__ import annotations

import aio_pika
from sqlalchemy import text

from app.core.config import get_settings
from app.db.session import session_scope
from app.messaging.outbox_dispatcher import claim_due_rows, run_once
from app.messaging.publisher import Publisher
from app.schemas.events import ORDER_CREATED
from tests.m3_harness import (
    TEST_PREFIX,
    fetch_outbox_payload,
    get_order_row,
    order_rows,
    place_order,
    set_outbox_available_now,
    wait_for_status,
    wait_until,
)

# Leftover outbox rows from earlier tests are neutralized by
# `PipelineHarness.setup()` (`flush_outbox`): every test starts with zero
# non-SENT outbox rows and empty queues.


async def test_committed_outbox_events_survive_broker_connection_loss(
    pipeline, async_client, customer_token
):
    """Checkout commits WITHOUT a broker (already proven in M2); then the
    dispatcher faces a dead connection: the row stays eligible with its
    identity intact, and publication succeeds once connectivity returns —
    followed by a full exactly-once chain."""
    live = Publisher(connection=pipeline.connection)

    # 1. Commit an event while the broker (for the dispatcher) is unusable.
    order_id = await place_order(async_client, customer_token)
    rows = await order_rows(order_id)
    assert len(rows["outbox"]) == 1
    original = rows["outbox"][0]
    assert original.state == "PENDING" and original.event_type == ORDER_CREATED

    # 2. Dispatcher cycle against a DEAD connection: claimed, failed, released.
    dead_connection = await aio_pika.connect(get_settings().amqp_url, timeout=5)
    await dead_connection.close()
    broken = Publisher(connection=dead_connection)
    stats = await run_once(broken, prefix=TEST_PREFIX, worker_id="instance-broken")
    assert stats == {"claimed": 1, "sent": 0, "failed": 1}

    rows = await order_rows(order_id)
    row = rows["outbox"][0]
    # No loss, no identity change, visible failure, still retry-eligible.
    assert row.id == original.id and row.event_id == original.event_id
    assert row.state == "PENDING"
    assert row.attempts == 1
    assert row.last_error is not None and "connection_lost" in row.last_error
    assert row.available_at is not None

    # 3. Connectivity returns (backoff window elapsed): publish confirms.
    await set_outbox_available_now(order_id)
    stats = await run_once(live, prefix=TEST_PREFIX, worker_id="instance-healthy")
    assert stats == {"claimed": 1, "sent": 1, "failed": 0}
    row = (await order_rows(order_id))["outbox"][0]
    assert row.state == "SENT" and row.event_id == original.event_id
    assert row.last_error is None and row.published_at is not None

    # 4. The recovered event still drives the chain exactly once.
    pipeline.start_dispatcher()
    for stage in ("payment", "restaurant", "delivery", "notification"):
        pipeline.start_consumers(stage)
    await wait_for_status(order_id, "DRIVER_ASSIGNED")
    await wait_until(
        lambda: _all_sent(order_id),
        timeout=15,
        message="every outbox row SENT after recovery",
    )
    pipeline.raise_if_task_failed()

    rows = await order_rows(order_id)
    assert len(rows["payments"]) == 1 and len(rows["assignments"]) == 1
    assert [h.version for h in rows["history"]] == [1, 2, 3, 4]


async def test_dispatcher_recovery_reclaims_lease_and_tolerates_duplicate(
    pipeline, async_client, customer_token
):
    """A dispatcher that claims and CRASHES must not strand events: the lease
    expires, another instance reclaims (SKIP LOCKED), and even if the crashed
    instance had already published (crash before the SENT update), the second
    publish produces a duplicate message that downstream dedup absorbs —
    exactly-once effects throughout."""
    live = Publisher(connection=pipeline.connection)

    order_id = await place_order(async_client, customer_token)
    created = await fetch_outbox_payload(order_id, ORDER_CREATED)

    # --- instance A claims, then "crashes" before publishing ---------------
    async with session_scope() as session:
        claimed = await claim_due_rows(
            session, worker_id="crashed-A", batch_size=10, lease_seconds=30
        )
    assert len(claimed) == 1

    # While A's lease is LIVE, no other instance may touch the row.
    stats = await run_once(live, prefix=TEST_PREFIX, worker_id="instance-B-early")
    assert stats["claimed"] == 0

    # --- simulate A's crash AFTER publishing but BEFORE the SENT update ----
    await pipeline.publish_to_queue(pipeline.names.payment_queue, created)
    async with session_scope() as session:
        await session.execute(
            text(
                "UPDATE outbox_events SET lease_expires_at = now() - interval '10 seconds' "
                "WHERE order_id = :order_id"
            ),
            {"order_id": order_id},
        )

    # --- instance B reclaims the expired lease and publishes (duplicate) ---
    stats = await run_once(live, prefix=TEST_PREFIX, worker_id="instance-B")
    assert stats == {"claimed": 1, "sent": 1, "failed": 0}
    rows = await order_rows(order_id)
    assert rows["outbox"][0].state == "SENT"
    assert rows["outbox"][0].event_id == created["event_id"]  # identity kept
    assert rows["outbox"][0].attempts == 2  # claim counted for both instances

    # Two copies of one logical event are now queued.
    depth = await pipeline.queue_depth(pipeline.names.payment_queue)
    assert depth == 2

    # Downstream: exactly one payment; the duplicate is absorbed.
    pipeline.start_consumers("payment")
    await pipeline.assert_queue_empty(pipeline.names.payment_queue, settle=1.0)
    pipeline.raise_if_task_failed()
    rows = await order_rows(order_id)
    assert len(rows["payments"]) == 1 and rows["payments"][0].status == "SUCCEEDED"
    order = await get_order_row(order_id)
    assert order.status == "PAID" and order.version == 2
    payment_markers = [m for m in rows["processed"] if m.consumer_name == "payment"]
    assert len(payment_markers) == 1  # dedup absorbed the duplicate copy

    # Recovery preserved full correctness: the chain still completes.
    pipeline.start_dispatcher()
    for stage in ("restaurant", "delivery", "notification"):
        pipeline.start_consumers(stage)
    await wait_for_status(order_id, "DRIVER_ASSIGNED")
    pipeline.raise_if_task_failed()
    rows = await order_rows(order_id)
    assert len(rows["assignments"]) == 1
    assert [h.version for h in rows["history"]] == [1, 2, 3, 4]


async def _all_sent(order_id: str) -> bool:
    rows = await order_rows(order_id)
    return bool(rows["outbox"]) and all(r.state == "SENT" for r in rows["outbox"])
