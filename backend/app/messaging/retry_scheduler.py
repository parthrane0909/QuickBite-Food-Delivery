"""Retry scheduler — independent process (assignment §13, §11).

Responsibilities:
1. Find DUE retry jobs safely (`state='PENDING' AND due_at <= now()`,
   FOR UPDATE SKIP LOCKED — any number of scheduler instances may run).
2. Make their scheduled, targeted outbox publications eligible NOW, in the
   SAME transaction as the claim (crash between claim and activation is
   therefore impossible; a crashed scheduler simply re-claims next cycle).
3. Expose the retry/quarantine backlog through structured logs
   (scripts/inspect_state.py reads the same tables for inspection).

The scheduler touches ONLY PostgreSQL — no broker connection — so it can
never lose or duplicate a message. Durability never depends on it: retry
outbox rows are committed atomically with their retry job and carry their
own due `available_at`, so even a scheduler that is down for a long time
cannot lose retries; the outbox dispatcher publishes any due row on its own.
The scheduler's activation is the assignment-mandated, inspectable step that
makes due retries publishable immediately, independent of dispatcher polling.
"""

from __future__ import annotations

import asyncio
import logging
import signal

from app.core.config import get_settings
from app.core.logging import configure_logging
from app.db.session import dispose_engine, session_scope
from app.repositories import messaging as messaging_repo

logger = logging.getLogger("quickbite.retry_scheduler")

# Bounded backoff between cycles on database interruptions.
_RECONNECT_DELAYS_S = (1.0, 2.0, 5.0, 10.0, 30.0)


async def run_once(*, batch_size: int | None = None) -> dict[str, float | int]:
    """One claim/activate cycle. Returns activation + backlog stats."""
    settings = get_settings()
    batch = batch_size or settings.retry_scheduler_batch_size
    async with session_scope() as session:
        activated = await messaging_repo.claim_due_retry_jobs(session, batch_size=batch)
        backlog = await messaging_repo.retry_backlog(session)
    for consumer_name, event_id, target_queue, attempt in activated:
        logger.info(
            "due retry activated for publication",
            extra={
                "consumer": consumer_name,
                "event_id": event_id,
                "target_queue": target_queue,
                "attempt": attempt,
                "result": "retry_activated",
            },
        )
    if activated or backlog["pending"] or backlog["quarantine_count"]:
        logger.info(
            "retry scheduler cycle complete",
            extra={
                "activated": len(activated),
                "retry_pending": backlog["pending"],
                "retry_published": backlog["published"],
                "retry_exhausted": backlog["exhausted"],
                "quarantine_count": backlog["quarantine_count"],
                "oldest_due_age_seconds": round(backlog["oldest_due_age_seconds"], 2),
                "result": "scheduler_cycle",
            },
        )
    return {"activated": len(activated), **backlog}


async def run_forever(*, stop_event: asyncio.Event, poll_interval: float | None = None) -> None:
    """Scheduler process loop: bounded backoff on DB outages, graceful stop."""
    settings = get_settings()
    poll = poll_interval or settings.retry_scheduler_poll_interval_seconds
    backoff = list(_RECONNECT_DELAYS_S)
    logger.info("retry scheduler starting", extra={"consumer": "retry-scheduler"})
    try:
        while not stop_event.is_set():
            try:
                await run_once()
                backoff = list(_RECONNECT_DELAYS_S)  # reset on progress
                try:
                    await asyncio.wait_for(stop_event.wait(), timeout=poll)
                except TimeoutError:
                    pass
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # noqa: BLE001 — DB interruption: never drop jobs
                delay = backoff.pop(0) if backoff else _RECONNECT_DELAYS_S[-1]
                logger.warning(
                    "scheduler cycle failed; backing off",
                    extra={
                        "consumer": "retry-scheduler",
                        "result": f"cycle_error:{type(exc).__name__}",
                        "retry_in_s": delay,
                        "detail": str(exc)[:500],
                    },
                )
                try:
                    await asyncio.wait_for(stop_event.wait(), timeout=delay)
                except TimeoutError:
                    pass
    finally:
        logger.info("retry scheduler stopped", extra={"consumer": "retry-scheduler"})


async def _amain() -> None:
    settings = get_settings()
    configure_logging(settings.log_level, service="retry-scheduler")
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)
    try:
        await run_forever(stop_event=stop)
    finally:
        await dispose_engine()


def main() -> None:
    asyncio.run(_amain())


if __name__ == "__main__":
    main()
