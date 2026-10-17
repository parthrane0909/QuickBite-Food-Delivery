"""Transactional outbox dispatcher — separate process loop (assignment §10).

Claim/lease protocol (safe with MULTIPLE concurrent dispatchers):
1. Short transaction: `UPDATE ... WHERE id IN (SELECT ... FOR UPDATE SKIP
   LOCKED)` flips eligible rows (PENDING due now, or CLAIMED with an expired
   lease) to CLAIMED, stamps claimed_by/claimed_at/lease_expires_at and
   increments attempts. Row locks are released at commit — NO database
   transaction is held open across broker I/O.
2. Publish each claimed row with confirms + mandatory routing (publisher).
3. Short transaction: SENT only after a positive confirm AND no return;
   otherwise the row goes back to PENDING with last_error and an exponential
   `available_at` delay — never dropped, attempts never reset.

Crash windows (documented in docs/reliability.md):
- Crash after claim, before publish -> lease expires -> reclaimed. No loss.
- Crash after publish, before SENT -> row reclaimed and published AGAIN:
  at-least-once by design; consumers deduplicate by (consumer, event_id).
"""

from __future__ import annotations

import asyncio
import logging
import os
import signal
import socket
import uuid

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.logging import configure_logging
from app.db.models.outbox_event import OutboxEvent
from app.db.session import dispose_engine, session_scope
from app.messaging.publisher import Publisher, PublishError
from app.repositories import messaging as messaging_repo

logger = logging.getLogger("quickbite.outbox")

# Failure backoff: 2,4,8,... capped at 60s (attempts grow per claim).
_FAILURE_BACKOFF_CAP_S = 60.0
# Bounded reconnect/backoff between dispatcher cycles on DB/broker outages.
_RECONNECT_DELAYS_S = (1.0, 2.0, 5.0, 10.0, 30.0)

CLAIM_SQL = """
UPDATE outbox_events
SET state = 'CLAIMED',
    claimed_by = :worker,
    claimed_at = now(),
    lease_expires_at = now() + make_interval(secs => :lease_seconds),
    attempts = attempts + 1
WHERE id IN (
    SELECT id FROM outbox_events
    WHERE (state = 'PENDING' AND available_at <= now())
       OR (state = 'CLAIMED' AND lease_expires_at < now())
    ORDER BY available_at
    LIMIT :batch
    FOR UPDATE SKIP LOCKED
)
RETURNING id
"""


def dispatcher_worker_id() -> str:
    return f"{socket.gethostname()}-{uuid.uuid4().hex[:8]}"[:64]


def failure_delay_seconds(attempts: int) -> float:
    return min(2.0 ** max(attempts - 1, 0), _FAILURE_BACKOFF_CAP_S)


async def claim_due_rows(
    session: AsyncSession,
    *,
    worker_id: str,
    batch_size: int,
    lease_seconds: float,
) -> list[str]:
    """Lease a batch of eligible rows; returns their ids (locks released at
    the caller's commit)."""
    result = await session.execute(
        text(CLAIM_SQL),
        {"worker": worker_id, "batch": batch_size, "lease_seconds": lease_seconds},
    )
    return [row[0] for row in result.all()]


async def mark_sent(session: AsyncSession, outbox_id: str) -> None:
    await session.execute(
        text(
            "UPDATE outbox_events SET state = 'SENT', published_at = now(), "
            "last_error = NULL, lease_expires_at = NULL WHERE id = :id"
        ),
        {"id": outbox_id},
    )


async def _release_failed(outbox_id: str, attempts: int, error: str) -> None:
    """Back to PENDING with `available_at = now + backoff(attempts)`."""
    async with session_scope() as session:
        await session.execute(
            text(
                "UPDATE outbox_events SET state = 'PENDING', "
                "available_at = now() + make_interval(secs => :delay), "
                "last_error = :error, lease_expires_at = NULL, "
                "claimed_by = NULL, claimed_at = NULL "
                "WHERE id = :id"
            ),
            {"id": outbox_id, "error": error[:2000], "delay": failure_delay_seconds(attempts)},
        )


async def _sent(outbox_id: str) -> None:
    async with session_scope() as session:
        await mark_sent(session, outbox_id)


async def run_once(
    publisher: Publisher,
    *,
    prefix: str = "",
    worker_id: str | None = None,
    batch_size: int | None = None,
    lease_seconds: float | None = None,
) -> dict[str, int]:
    """One claim/publish/mark cycle. Returns {claimed, sent, failed}."""
    settings = get_settings()
    worker = worker_id or dispatcher_worker_id()
    batch = batch_size or settings.outbox_batch_size
    lease = lease_seconds or settings.outbox_lease_seconds

    async with session_scope() as session:
        ids = await claim_due_rows(session, worker_id=worker, batch_size=batch, lease_seconds=lease)
        rows: list[OutboxEvent] = []
        if ids:
            rows = list(
                (
                    await session.execute(select(OutboxEvent).where(OutboxEvent.id.in_(ids)))
                ).scalars()
            )

    stats = {"claimed": len(rows), "sent": 0, "failed": 0}
    for row in rows:
        if row.exchange == "":
            # Targeted retry publication: DEFAULT exchange (empty name) with
            # routing key = the FAILING queue's name — only that queue ever
            # receives the retry (assignment §11). The retry job's target_queue
            # IS the consumer's final queue name (namespaced in tests), so —
            # exactly like topic routing keys — it is never re-prefixed here.
            target_exchange = ""
            routing_key = row.routing_key
        else:
            target_exchange = f"{prefix}{row.exchange}" if prefix else row.exchange
            routing_key = row.routing_key
        try:
            await publisher.publish(
                exchange=target_exchange,
                routing_key=routing_key,
                payload=row.payload,
            )
        except PublishError as exc:
            stats["failed"] += 1
            await _release_failed(row.id, row.attempts, f"{exc.reason}: {exc.detail}")
            logger.warning(
                "outbox publish failed; row remains eligible",
                extra={
                    "event_id": row.event_id,
                    "order_id": row.order_id,
                    "result": f"publish_failed:{exc.reason}",
                    "detail": exc.detail[:500],
                    "attempts": row.attempts,
                },
            )
            continue
        if get_settings().dispatcher_crash_after_publish:
            # Protected crash-recovery demo control (assignment §12/§14):
            # exit AFTER the confirmed publish but BEFORE the SENT mark, to
            # demonstrate the documented at-least-once redelivery window.
            if get_settings().environment == "test":
                logger.critical(
                    "dispatcher crash checkpoint reached (no exit under test)",
                    extra={
                        "event_id": row.event_id,
                        "result": "crash_after_publish_simulated",
                    },
                )
            else:
                logger.critical(
                    "dispatcher crash checkpoint: published but exiting BEFORE SENT",
                    extra={
                        "event_id": row.event_id,
                        "result": "crash_after_publish_before_sent",
                    },
                )
                os._exit(73)
        await _sent(row.id)
        stats["sent"] += 1
        logger.info(
            "outbox published",
            extra={
                "event_id": row.event_id,
                "order_id": row.order_id,
                "result": "sent",
                "exchange": target_exchange or "(default)",
                "routing_key": routing_key,
            },
        )
    if stats["claimed"]:
        logger.info("dispatcher cycle complete", extra=stats)
    async with session_scope() as session:
        pending_age = await messaging_repo.oldest_pending_outbox_age_seconds(session)
    if pending_age is not None and pending_age > 0:
        logger.info(
            "outbox backlog",
            extra={"pending_outbox_age_s": round(pending_age, 2), "result": "backlog"},
        )
    return stats


async def run_forever(
    *,
    stop_event: asyncio.Event,
    url: str,
    prefix: str = "",
    poll_interval: float | None = None,
) -> None:
    """Dispatcher process loop: bounded reconnect/backoff, graceful stop."""
    settings = get_settings()
    poll = poll_interval or settings.outbox_poll_interval_seconds
    worker = dispatcher_worker_id()
    publisher = Publisher(url)
    backoff = list(_RECONNECT_DELAYS_S)  # grows across consecutive failures
    logger.info(
        "outbox dispatcher starting",
        extra={"consumer": "outbox-dispatcher", "result": "starting", "worker_id": worker},
    )
    try:
        while not stop_event.is_set():
            try:
                stats = await run_once(publisher, prefix=prefix, worker_id=worker)
                backoff = list(_RECONNECT_DELAYS_S)  # reset on progress
                if stats["claimed"] == 0:
                    try:
                        await asyncio.wait_for(stop_event.wait(), timeout=poll)
                    except TimeoutError:
                        pass
                continue
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # DB or broker outage: never drop events
                delay = backoff.pop(0) if backoff else _RECONNECT_DELAYS_S[-1]
                logger.warning(
                    "dispatcher cycle failed; backing off",
                    extra={
                        "consumer": "outbox-dispatcher",
                        "result": f"cycle_error:{type(exc).__name__}",
                        "retry_in_s": delay,
                    },
                )
                await publisher.close()
                publisher = Publisher(url)
                try:
                    await asyncio.wait_for(stop_event.wait(), timeout=delay)
                except TimeoutError:
                    pass
    finally:
        await publisher.close()
        logger.info(
            "outbox dispatcher stopped",
            extra={"consumer": "outbox-dispatcher", "result": "stopped"},
        )


async def _amain() -> None:
    settings = get_settings()
    configure_logging(settings.log_level, service="outbox-dispatcher")
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)
    try:
        await run_forever(stop_event=stop, url=settings.amqp_url)
    finally:
        await dispose_engine()


def main() -> None:
    asyncio.run(_amain())


if __name__ == "__main__":
    main()
