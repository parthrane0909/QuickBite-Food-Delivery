"""Shared process runtime for all worker entrypoints.

Milestone 1 scope (process scaffold, per assignment §15): validated
configuration, structured logging, database connectivity verification with
bounded backoff, periodic heartbeat and graceful SIGTERM/SIGINT shutdown.

Milestone 3 replaces the idle loop with the RabbitMQ consume loop:
topology declared before consumption, bounded prefetch, manual ACK strictly
after the PostgreSQL transaction commits, reconnect on channel loss, and
deduplication by (logical consumer, event_id) so redeliveries are safe.
"""

from __future__ import annotations

import asyncio
import logging
import signal

from app.core.config import get_settings
from app.core.logging import configure_logging
from app.db.session import check_database, dispose_engine

logger = logging.getLogger("quickbite.worker")

# Bounded connectivity backoff: retry a few times, then fail loudly rather
# than pretending to run without its authoritative dependency.
_DB_RETRY_DELAYS_S = (1.0, 2.0, 5.0, 10.0)
_DB_PROBE_TIMEOUT_S = 2.0
_HEARTBEAT_SECONDS = 30.0


async def _wait_for_database(consumer_name: str) -> bool:
    for attempt, delay in enumerate(_DB_RETRY_DELAYS_S, start=1):
        try:
            await check_database(_DB_PROBE_TIMEOUT_S)
            return True
        except Exception as exc:
            logger.warning(
                "database not reachable yet",
                extra={
                    "consumer": consumer_name,
                    "attempt": attempt,
                    "result": f"db_probe_failed: {type(exc).__name__}",
                },
            )
            await asyncio.sleep(delay)
    return False


async def run_worker(*, consumer_name: str, queue_name: str) -> None:
    settings = get_settings()
    configure_logging(settings.log_level, service=f"{consumer_name}-worker")

    logger.info(
        "worker starting",
        extra={"consumer": consumer_name, "result": f"queue={queue_name}"},
    )

    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)

    if not await _wait_for_database(consumer_name):
        logger.error(
            "database unavailable after bounded retries; exiting",
            extra={"consumer": consumer_name, "result": "startup_failed"},
        )
        raise SystemExit(1)

    logger.info(
        "worker ready (M1 scaffold: database verified; message consumption "
        "arrives with Milestone 3)",
        extra={"consumer": consumer_name, "result": "ready"},
    )

    try:
        while not stop.is_set():
            try:
                await asyncio.wait_for(stop.wait(), timeout=_HEARTBEAT_SECONDS)
            except TimeoutError:
                logger.debug("heartbeat", extra={"consumer": consumer_name, "result": "alive"})
    finally:
        await dispose_engine()
        logger.info(
            "worker stopped gracefully",
            extra={"consumer": consumer_name, "result": "stopped"},
        )
