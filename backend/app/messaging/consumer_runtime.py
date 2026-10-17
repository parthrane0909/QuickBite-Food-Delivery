"""Shared worker runtime: connection, consume loop, ACK protocol, recovery.

Message protocol (assignment §9-§11; Milestone 4 durable retries):

1. Parse envelope (schema_version + shape):
   - MALFORMED or unsupported schema version -> durable quarantine (record +
     transactional dead-exchange publication) in one commit, then ACK.
     Retries are bypassed: a broken message never becomes valid by waiting.
   - Well-formed FUTURE event type -> the notification worker ACKs it with a
     structured log (explicitly permitted by assignment §9); any OTHER
     consumer quarantines it (never a silent ack of an unknown business event).
2. Read the DURABLE delivery attempt number from retry_jobs (attempt 1 =
   initial delivery; attempts survive worker and broker restarts).
3. Stage simulation delay (deterministic demo control).
4. ONE database transaction: lock the order row (FOR UPDATE), check
   (consumer_name, event_id) dedup -> committed marker means no-op ACK;
   otherwise run the stage processor (effects + history + child outbox event)
   and insert the processed marker in the SAME transaction. Commit.
5. Only after a successful commit: ACK. `crash_after_checkpoint` mode exits
   the PROCESS here (post-commit, pre-ACK) — redelivery then no-ops via dedup.
6. Classified failure handling (never an immediate nack/requeue loop):
   - transient processing error / precondition-behind / missing order ->
     the business transaction is ROLLED BACK, then ONE transaction persists
     the next bounded retry (retry_jobs row, unique per consumer/event/
     attempt, plus its scheduled TARGETED outbox publication to only this
     queue via the default exchange) — and only then is the original message
     acknowledged. Durably scheduled retries use the configured delays
     (default 2s, 10s, 30s after attempts 1..3; attempt 4 is the last).
   - retry exhaustion -> terminal order transition where the current state
     permits it (payment PENDING->PAYMENT_FAILED, restaurant PAID->FAILED,
     delivery CONFIRMED->FAILED; notifications never touch order state) +
     failure event + durable quarantine record + dead-exchange publication,
     all in one commit, then ACK.
   - if RETRY/QUARANTINE PERSISTENCE itself fails, the message is never
     acknowledged: bounded in-place backoff, then redelivery on reconnect.
7. Connection/channel loss ends the consume stream; the caller applies
   bounded reconnect backoff and re-declares topology; unacked messages are
   redelivered by the broker.

Shutdown: stop accepting new messages, finish the in-flight one (bounded
wait), then close the channel so any unacked copy is redelivered elsewhere.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import signal
import time
import uuid
from collections.abc import Awaitable, Callable

import aio_pika
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.logging import configure_logging
from app.db.models.order import Order
from app.db.models.processed_event import ProcessedEvent
from app.db.session import check_database, dispose_engine, session_scope
from app.messaging.envelope import EnvelopeError, parse_envelope
from app.messaging.topology import declare_topology
from app.repositories import messaging as messaging_repo
from app.repositories import orders as orders_repo
from app.repositories import processed_events as dedup_repo
from app.schemas.events import EventEnvelope
from app.services import quarantine_service
from app.services.processing import (
    MissingOrderError,
    PreconditionNotMetError,
    ProcessOutcome,
    TransientProcessingError,
)

logger = logging.getLogger("quickbite.worker")

Processor = Callable[[AsyncSession, EventEnvelope, Order, int], Awaitable[ProcessOutcome]]

# Bounded startup/database backoff (then exit 1: Compose restarts the worker).
_DB_RETRY_DELAYS_S = (1.0, 2.0, 5.0, 10.0)
# Bounded broker reconnect backoff (delays capped; retries continue while run).
_CONNECT_DELAYS_S = (1.0, 2.0, 5.0, 10.0, 30.0)
# Bounded backoff while RETRY/QUARANTINE PERSISTENCE fails — the message stays
# UNACKED throughout (assignment §11: never ack away work we failed to park).
_RETRY_PERSIST_DELAYS_S = (1.0, 2.0, 5.0, 10.0, 30.0)
_SHUTDOWN_INFLIGHT_TIMEOUT_S = 30.0

# Physical crash checkpoints (protected demo control: CRASH_POINT env var,
# honoured outside the test environment only; assignment §12/§14).
_CRASH_EXIT_CODES = {"before_commit": 71, "during_retry_persistence": 72}

_STAGE_MODE_ATTR = {
    "payment": "payment_mode",
    "restaurant": "restaurant_mode",
    "delivery": "delivery_mode",
    "notification": "notification_mode",
}
_STAGE_DELAY_ATTR = {
    "payment": "payment_delay_seconds",
    "restaurant": "restaurant_delay_seconds",
    "delivery": "delivery_delay_seconds",
    "notification": "notification_delay_seconds",
}
# Integrity failures that mean "a concurrent duplicate already committed".
_DUPLICATE_CONSTRAINT_MARKERS = (
    "processed_events",
    "simulated_payments",
    "driver_assignments",
    "notifications",
    "uq_order_status_history",
)

# Failure classifications emitted in structured logs (M4 §10).
CLASS_TRANSIENT = "transient_processing_error"
CLASS_PRECONDITION = "precondition_not_met"
CLASS_MISSING_ORDER = "missing_order"
CLASS_MALFORMED = "malformed_envelope"
CLASS_UNSUPPORTED_SCHEMA = "unsupported_schema_version"
CLASS_UNKNOWN_TYPE = "unknown_event_type"

_ALLOWED_MODES = {
    "payment": frozenset(
        {"always_succeed", "fail_twice", "always_fail", "always_decline", "crash_after_checkpoint"}
    ),
    "restaurant": frozenset({"always_succeed", "always_fail", "crash_after_checkpoint"}),
    "delivery": frozenset({"always_succeed", "always_fail", "crash_after_checkpoint"}),
    "notification": frozenset({"always_succeed", "always_fail", "crash_after_checkpoint"}),
}


class StreamEndedError(ConnectionError):
    """Consume stream ended WITHOUT a shutdown request: the channel or
    connection died (aio-pika signals this as a clean StopAsyncIteration, so
    the runtime raises this to force the reconnect loop)."""


def validate_stage_modes(consumer_name: str) -> None:
    """Fail fast at startup on demo controls this consumer does not support —
    deterministic simulation only ever comes from environment configuration
    (assignment §12), never from checkout request fields."""
    settings = get_settings()
    attr = _STAGE_MODE_ATTR[consumer_name]
    mode = getattr(settings, attr)
    if mode not in _ALLOWED_MODES[consumer_name]:
        raise SystemExit(
            f"{attr.upper()}={mode!r} is not supported for the {consumer_name} "
            f"worker; allowed: {sorted(_ALLOWED_MODES[consumer_name])}"
        )


async def _wait_for_database(consumer_name: str) -> bool:
    for attempt, delay in enumerate(_DB_RETRY_DELAYS_S, start=1):
        try:
            await check_database(2.0)
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


def _is_duplicate_race(exc: IntegrityError) -> bool:
    return any(marker in str(exc) for marker in _DUPLICATE_CONSTRAINT_MARKERS)


def _maybe_crash(checkpoint: str, *, consumer_name: str, event_id: str | None) -> None:
    """Protected crash-recovery demo control (CRASH_POINT): exits the process
    at a chosen failure boundary OUTSIDE the test environment; under test it
    only logs, so the suite can never be killed by a demo control."""
    settings = get_settings()
    if settings.crash_point != checkpoint:
        return
    if settings.environment == "test":
        logger.critical(
            "crash checkpoint reached (no process exit under test)",
            extra={
                "consumer": consumer_name,
                "event_id": event_id,
                "result": f"crash_{checkpoint}_simulated",
            },
        )
        return
    logger.critical(
        "crash checkpoint: exiting the process on purpose",
        extra={
            "consumer": consumer_name,
            "event_id": event_id,
            "result": f"crash_{checkpoint}",
        },
    )
    os._exit(_CRASH_EXIT_CODES[checkpoint])


async def _attempt_number(consumer_name: str, event_id: str) -> int:
    async with session_scope() as session:
        return await messaging_repo.current_attempt(session, consumer_name, event_id)


async def _run_transaction(
    consumer_name: str,
    envelope: EventEnvelope,
    processor: Processor,
    attempt: int,
) -> ProcessOutcome:
    """The single business transaction: lock -> dedup -> effects -> marker."""
    async with session_scope() as session:
        order = await orders_repo.get_order_for_update(session, envelope.order_id)
        if order is None:
            raise MissingOrderError(f"order {envelope.order_id!r} does not exist")
        marker = await dedup_repo.get_marker(
            session, consumer_name=consumer_name, event_id=envelope.event_id
        )
        if marker is not None:
            return ProcessOutcome("duplicate")
        outcome = await processor(session, envelope, order, attempt)
        session.add(
            ProcessedEvent(
                id=f"pe_{uuid.uuid4().hex}",
                consumer_name=consumer_name,  # logical type, never a replica id
                event_id=envelope.event_id,
                order_id=order.id,
                outcome="PROCESSED" if outcome.result == "applied" else "STALE_NOOP",
            )
        )
        return outcome


async def _sleep_or_stopping(seconds: float, stop_event: asyncio.Event) -> bool:
    """Interruptible bounded sleep. Returns True when shutdown won the race."""
    try:
        await asyncio.wait_for(stop_event.wait(), timeout=seconds)
        return True
    except TimeoutError:
        return False


async def _requeue_on_shutdown(message: aio_pika.abc.AbstractIncomingMessage) -> None:
    try:
        await message.nack(requeue=True)
    except Exception:  # noqa: BLE001 — channel may already be gone; unacked
        pass  # copies survive channel/connection loss and are redelivered


async def _persist_failure(
    message: aio_pika.abc.AbstractIncomingMessage,
    *,
    consumer_name: str,
    queue_name: str,
    envelope: EventEnvelope,
    attempt: int,
    classification: str,
    error_text: str,
    stop_event: asyncio.Event,
) -> bool:
    """Durably schedule the next bounded retry, or exhaust to quarantine.

    Runs AFTER the failed business transaction rolled back. One transaction
    persists everything (retry job + scheduled targeted publication, or
    terminal transition + failure event + quarantine record + dead
    publication); the caller acks the original message only on success. If
    persistence itself keeps failing, the message stays UNACKED with bounded
    backoff — never acknowledged away, never an unbounded spin.
    """
    settings = get_settings()
    delays = settings.retry_delays
    exhausted = attempt >= len(delays) + 1
    backoff = list(_RETRY_PERSIST_DELAYS_S)
    while True:
        try:
            quarantine = None
            async with session_scope() as session:
                if exhausted:
                    order = await orders_repo.get_order_for_update(session, envelope.order_id)
                    terminal = await quarantine_service.apply_exhaustion_terminal(
                        session, consumer_name=consumer_name, envelope=envelope, order=order
                    )
                    quarantine = await quarantine_service.quarantine_event(
                        session,
                        consumer_name=consumer_name,
                        queue_name=queue_name,
                        envelope=envelope,
                        envelope_payload=envelope.to_payload(),
                        attempts=attempt,
                        failure_code=terminal.failure_code,
                        reason=(
                            f"{classification} on final attempt {attempt}: "
                            f"{error_text[:500]} — {terminal.failure_reason}"
                        ),
                    )
                    await messaging_repo.mark_job_exhausted(
                        session,
                        consumer_name=consumer_name,
                        event_id=envelope.event_id,
                        attempt=attempt,
                    )
                    session.add(
                        ProcessedEvent(
                            id=f"pe_{uuid.uuid4().hex}",
                            consumer_name=consumer_name,
                            event_id=envelope.event_id,
                            order_id=envelope.order_id,
                            outcome="QUARANTINED",
                        )
                    )
                    _maybe_crash(
                        "during_retry_persistence",
                        consumer_name=consumer_name,
                        event_id=envelope.event_id,
                    )
                else:
                    schedule = await messaging_repo.schedule_retry(
                        session,
                        consumer_name=consumer_name,
                        event_id=envelope.event_id,
                        event_type=envelope.event_type,
                        order_id=envelope.order_id,
                        envelope_payload=envelope.to_payload(),
                        target_queue=queue_name,
                        attempt=attempt + 1,
                        delay_seconds=delays[attempt - 1],
                        last_error=f"{classification}: {error_text}",
                    )
                    _maybe_crash(
                        "during_retry_persistence",
                        consumer_name=consumer_name,
                        event_id=envelope.event_id,
                    )
                    logger.warning(
                        "transient failure; durable retry scheduled",
                        extra={
                            "consumer": consumer_name,
                            "event_id": envelope.event_id,
                            "order_id": envelope.order_id,
                            "correlation_id": envelope.correlation_id,
                            "classification": classification,
                            "attempt": attempt,
                            "next_attempt": schedule.attempt,
                            "retry_in_s": schedule.due_in_seconds,
                            "target_queue": schedule.target_queue,
                            "result": "retry_scheduled",
                        },
                    )
                    return True
            if exhausted:
                quarantine_state = (
                    "duplicate" if quarantine and quarantine.duplicate else "recorded"
                )
                logger.critical(
                    "retry attempts exhausted; event quarantined",
                    extra={
                        "consumer": consumer_name,
                        "event_id": envelope.event_id,
                        "order_id": envelope.order_id,
                        "correlation_id": envelope.correlation_id,
                        "classification": classification,
                        "attempt": attempt,
                        "quarantine": quarantine_state,
                        "result": "retries_exhausted",
                    },
                )
            return True
        except Exception as exc:  # noqa: BLE001 — persistence failure, classified
            delay = backoff.pop(0) if backoff else _RETRY_PERSIST_DELAYS_S[-1]
            logger.error(
                "retry persistence failed; message kept unacked",
                extra={
                    "consumer": consumer_name,
                    "event_id": envelope.event_id,
                    "order_id": envelope.order_id,
                    "classification": classification,
                    "attempt": attempt,
                    "retry_in_s": delay,
                    "result": f"persist_failed:{type(exc).__name__}",
                    "detail": str(exc)[:500],
                },
            )
            if await _sleep_or_stopping(delay, stop_event):
                await _requeue_on_shutdown(message)
                logger.info(
                    "message requeued for redelivery during shutdown",
                    extra={
                        "consumer": consumer_name,
                        "event_id": envelope.event_id,
                        "result": "requeued_on_shutdown",
                    },
                )
                return False


async def _quarantine_invalid(
    message: aio_pika.abc.AbstractIncomingMessage,
    *,
    consumer_name: str,
    queue_name: str,
    stop_event: asyncio.Event,
    envelope: EventEnvelope | None = None,
    raw_payload: dict | None = None,
    failure_code: str = CLASS_MALFORMED,
    reason: str = "",
    envelope_payload: dict | None = None,
) -> bool:
    """Durable quarantine for a message that must NOT be retried (malformed,
    unsupported schema version, unknown business event type). Returns True
    when the quarantine committed (caller ACKs); False only on shutdown
    (message requeued, never acknowledged away)."""
    backoff = list(_RETRY_PERSIST_DELAYS_S)
    while True:
        try:
            async with session_scope() as session:
                if envelope is not None:
                    outcome = await quarantine_service.quarantine_event(
                        session,
                        consumer_name=consumer_name,
                        queue_name=queue_name,
                        envelope=envelope,
                        envelope_payload=envelope_payload or envelope.to_payload(),
                        attempts=1,
                        failure_code=failure_code,
                        reason=reason,
                    )
                elif raw_payload is not None:
                    outcome = await quarantine_service.quarantine_raw_event(
                        session,
                        consumer_name=consumer_name,
                        queue_name=queue_name,
                        raw_payload=raw_payload,
                        attempts=1,
                        failure_code=failure_code,
                        reason=reason,
                    )
                else:
                    outcome = await quarantine_service.quarantine_malformed(
                        session,
                        consumer_name=consumer_name,
                        queue_name=queue_name,
                        raw_body=message.body,
                        failure_code=failure_code,
                        reason=reason,
                    )
            logger.warning(
                "message quarantined",
                extra={
                    "consumer": consumer_name,
                    "event_id": message.message_id,
                    "classification": failure_code,
                    "quarantine": "duplicate" if outcome.duplicate else "recorded",
                    "result": "quarantined",
                },
            )
            return True
        except Exception as exc:  # noqa: BLE001 — persistence failure, classified
            delay = backoff.pop(0) if backoff else _RETRY_PERSIST_DELAYS_S[-1]
            logger.error(
                "quarantine persistence failed; message kept unacked",
                extra={
                    "consumer": consumer_name,
                    "event_id": message.message_id,
                    "classification": failure_code,
                    "retry_in_s": delay,
                    "result": f"quarantine_failed:{type(exc).__name__}",
                    "detail": str(exc)[:500],
                },
            )
            if await _sleep_or_stopping(delay, stop_event):
                await _requeue_on_shutdown(message)
                return False


async def _handle_message(
    message: aio_pika.abc.AbstractIncomingMessage,
    *,
    consumer_name: str,
    queue_name: str,
    processor: Processor,
    expected_types: frozenset[str],
    delay_seconds: float,
    stop_event: asyncio.Event,
) -> None:
    # ---- 1. envelope validation -----------------------------------------
    try:
        envelope = parse_envelope(message.body)
    except EnvelopeError as exc:
        if exc.reason == "unknown_event_type" and consumer_name == "notification":
            # Assignment §9: a valid FUTURE event type the notification worker
            # intentionally ignores is acknowledged with a structured log.
            logger.info(
                "ignoring well-formed future event type (assignment §9)",
                extra={
                    "consumer": consumer_name,
                    "event_id": message.message_id,
                    "result": "ack_unknown_event_type",
                },
            )
            await message.ack()
            return
        if exc.reason == "unknown_event_type":
            logger.error(
                "unknown business event type; quarantining",
                extra={
                    "consumer": consumer_name,
                    "event_id": message.message_id,
                    "classification": CLASS_UNKNOWN_TYPE,
                    "result": "quarantine_unknown_event_type",
                },
            )
            try:
                parsed_raw = json.loads(message.body)
            except (ValueError, UnicodeDecodeError):
                parsed_raw = None
            if await _quarantine_invalid(
                message,
                consumer_name=consumer_name,
                queue_name=queue_name,
                stop_event=stop_event,
                raw_payload=parsed_raw if isinstance(parsed_raw, dict) else None,
                failure_code=CLASS_UNKNOWN_TYPE,
                reason=f"event type {exc.detail!r} is not part of schema v1",
            ):
                await message.ack()
            return
        classification = (
            CLASS_UNSUPPORTED_SCHEMA
            if exc.reason == "unsupported_schema_version"
            else CLASS_MALFORMED
        )
        logger.error(
            "malformed message; quarantining without retries",
            extra={
                "consumer": consumer_name,
                "event_id": message.message_id,
                "classification": classification,
                "result": f"quarantine:{exc.reason}",
            },
        )
        if await _quarantine_invalid(
            message,
            consumer_name=consumer_name,
            queue_name=queue_name,
            stop_event=stop_event,
            failure_code=classification,
            reason=f"{exc.reason}: {exc.detail[:500]}",
        ):
            await message.ack()
        return

    if envelope.event_type not in expected_types:
        logger.info(
            "event type not served by this consumer; acknowledged",
            extra={
                "consumer": consumer_name,
                "event_id": envelope.event_id,
                "order_id": envelope.order_id,
                "correlation_id": envelope.correlation_id,
                "result": "ack_unexpected_type",
            },
        )
        await message.ack()
        return

    # ---- 2. durable attempt number + deterministic latency ---------------
    attempt = await _attempt_number(consumer_name, envelope.event_id)
    if delay_seconds > 0:
        await asyncio.sleep(delay_seconds)

    # ---- 3. transactional processing with classified failure handling ----
    started = time.monotonic()
    _maybe_crash("before_commit", consumer_name=consumer_name, event_id=envelope.event_id)
    try:
        outcome = await _run_transaction(consumer_name, envelope, processor, attempt)
    except PreconditionNotMetError as exc:
        handled = await _persist_failure(
            message,
            consumer_name=consumer_name,
            queue_name=queue_name,
            envelope=envelope,
            attempt=attempt,
            classification=CLASS_PRECONDITION,
            error_text=str(exc),
            stop_event=stop_event,
        )
        if handled:
            await message.ack()
        return
    except MissingOrderError as exc:
        handled = await _persist_failure(
            message,
            consumer_name=consumer_name,
            queue_name=queue_name,
            envelope=envelope,
            attempt=attempt,
            classification=CLASS_MISSING_ORDER,
            error_text=str(exc),
            stop_event=stop_event,
        )
        if handled:
            await message.ack()
        return
    except TransientProcessingError as exc:
        handled = await _persist_failure(
            message,
            consumer_name=consumer_name,
            queue_name=queue_name,
            envelope=envelope,
            attempt=attempt,
            classification=CLASS_TRANSIENT,
            error_text=str(exc),
            stop_event=stop_event,
        )
        if handled:
            await message.ack()
        return
    except Exception as exc:  # noqa: BLE001 — classified, never silently acked
        if isinstance(exc, IntegrityError) and _is_duplicate_race(exc):
            outcome = ProcessOutcome("duplicate")
        else:
            handled = await _persist_failure(
                message,
                consumer_name=consumer_name,
                queue_name=queue_name,
                envelope=envelope,
                attempt=attempt,
                classification=CLASS_TRANSIENT,
                error_text=f"{type(exc).__name__}: {exc}",
                stop_event=stop_event,
            )
            if handled:
                await message.ack()
            return

    # ---- 4. post-commit: checkpoint crash, then ACK ----------------------
    settings = get_settings()
    if getattr(settings, _STAGE_MODE_ATTR[consumer_name]) == "crash_after_checkpoint":
        if settings.environment == "test":
            logger.critical(
                "crash checkpoint reached (no process exit under test)",
                extra={
                    "consumer": consumer_name,
                    "event_id": envelope.event_id,
                    "order_id": envelope.order_id,
                    "result": "crash_checkpoint_simulated",
                },
            )
        else:
            logger.critical(
                "crash checkpoint: committed but exiting BEFORE ack",
                extra={
                    "consumer": consumer_name,
                    "event_id": envelope.event_id,
                    "order_id": envelope.order_id,
                    "result": "crash_before_ack",
                },
            )
            os._exit(70)

    await message.ack()  # strictly after the database commit
    logger.info(
        "message processed",
        extra={
            "consumer": consumer_name,
            "event_id": envelope.event_id,
            "order_id": envelope.order_id,
            "correlation_id": envelope.correlation_id,
            "attempt": attempt,
            "duration_ms": round((time.monotonic() - started) * 1000, 1),
            "result": outcome.result,
        },
    )


async def consume_forever(
    connection: aio_pika.abc.AbstractConnection,
    *,
    consumer_name: str,
    queue_name: str,
    processor: Processor,
    expected_types: frozenset[str],
    prefix: str = "",
    stop_event: asyncio.Event,
    delay_seconds: float | None = None,
) -> None:
    """Consume one queue until `stop_event`.

    Returns after the in-flight message finishes (bounded shutdown budget).
    Raises `StreamEndedError` when the stream ends WITHOUT a shutdown request
    (channel/connection loss — aio-pika reports that as a clean iterator end),
    so callers reconnect with bounded backoff instead of exiting.
    `delay_seconds` overrides the configured stage delay (tests).
    """
    settings = get_settings()
    if delay_seconds is None:
        delay_seconds = getattr(settings, _STAGE_DELAY_ATTR[consumer_name])

    channel = await connection.channel()
    await channel.set_qos(prefetch_count=settings.worker_prefetch_count)
    queue = await channel.declare_queue(queue_name, durable=True, exclusive=False)

    stream_context = queue.iterator(no_ack=False)
    stream = await stream_context.__aenter__()

    async def _consume_stream() -> None:
        async for message in stream:
            if stop_event.is_set():
                # Stop accepting: this just-delivered copy goes back to ready.
                await message.nack(requeue=True)
                break
            await _handle_message(
                message,
                consumer_name=consumer_name,
                queue_name=queue_name,
                processor=processor,
                expected_types=expected_types,
                delay_seconds=delay_seconds,
                stop_event=stop_event,
            )

    consume_task = asyncio.create_task(_consume_stream())
    stop_task = asyncio.create_task(stop_event.wait())
    try:
        done, _ = await asyncio.wait({consume_task, stop_task}, return_when=asyncio.FIRST_COMPLETED)
        if consume_task in done:
            stop_task.cancel()
            consume_task.result()  # propagate real consume/processing errors
            if not stop_event.is_set():
                # Iterator ended by itself: the channel/connection is gone.
                raise StreamEndedError(f"{consumer_name}: consume stream ended without shutdown")
            return
        # Graceful stop: stop accepting, then finish the in-flight message.
        logger.info(
            "shutdown requested; finishing in-flight message",
            extra={"consumer": consumer_name, "result": "stopping"},
        )
        try:
            await stream_context.__aexit__(None, None, None)
        except Exception as exc:  # noqa: BLE001 — iterator cleanup is best effort
            logger.debug("iterator close error: %s", exc)
        try:
            await asyncio.wait_for(consume_task, timeout=_SHUTDOWN_INFLIGHT_TIMEOUT_S)
        except TimeoutError:
            logger.warning(
                "in-flight message did not finish within the shutdown budget; "
                "closing the channel so its copy is redelivered",
                extra={"consumer": consumer_name, "result": "inflight_abandoned"},
            )
            consume_task.cancel()
        except Exception as exc:  # noqa: BLE001 — we are closing anyway
            logger.info(
                "consume task ended with an error during shutdown",
                extra={"consumer": consumer_name, "result": f"stop_error:{type(exc).__name__}"},
            )
    finally:
        if not stop_task.done():
            stop_task.cancel()
        if not consume_task.done():
            consume_task.cancel()
        await asyncio.gather(consume_task, stop_task, return_exceptions=True)
        if not channel.is_closed:
            await channel.close()


async def run_worker(
    *,
    consumer_name: str,
    queue_name: str,
    processor: Processor,
    expected_types: frozenset[str],
    prefix: str = "",
) -> None:
    """Worker process entry: config/logging, mode validation, DB probe,
    idempotent topology declaration, consume loop with bounded reconnects,
    graceful SIGTERM/SIGINT shutdown."""
    settings = get_settings()
    configure_logging(settings.log_level, service=f"{consumer_name}-worker")
    validate_stage_modes(consumer_name)

    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)

    logger.info(
        "worker starting",
        extra={"consumer": consumer_name, "result": f"queue={queue_name}"},
    )
    if not await _wait_for_database(consumer_name):
        logger.error(
            "database unavailable after bounded retries; exiting",
            extra={"consumer": consumer_name, "result": "startup_failed"},
        )
        raise SystemExit(1)

    backoff = list(_CONNECT_DELAYS_S)
    try:
        while not stop.is_set():
            connection: aio_pika.abc.AbstractConnection | None = None
            try:
                connection = await aio_pika.connect(settings.amqp_url, timeout=10)
                # Idempotent declarations on every (re)connect: publishes can
                # never race ahead of queues/bindings, and a broker restart
                # that lost state is healed on reconnect.
                await declare_topology(connection, prefix=prefix)
                logger.info(
                    "worker connected; consuming",
                    extra={"consumer": consumer_name, "result": "consuming"},
                )
                backoff = list(_CONNECT_DELAYS_S)
                await consume_forever(
                    connection,
                    consumer_name=consumer_name,
                    queue_name=queue_name,
                    processor=processor,
                    expected_types=expected_types,
                    prefix=prefix,
                    stop_event=stop,
                )
                break  # graceful stop
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # broker/channel loss: bounded backoff
                delay = backoff.pop(0) if backoff else _CONNECT_DELAYS_S[-1]
                logger.warning(
                    "connection/consume failure; reconnecting with bounded backoff",
                    extra={
                        "consumer": consumer_name,
                        "result": f"reconnect:{type(exc).__name__}",
                        "retry_in_s": delay,
                    },
                )
                if connection is not None and not connection.is_closed:
                    try:
                        await connection.close()
                    except Exception:  # noqa: BLE001 — closing is best-effort
                        pass
                if await _sleep_or_stopping(delay, stop):
                    break
    finally:
        await dispose_engine()
        logger.info(
            "worker stopped gracefully",
            extra={"consumer": consumer_name, "result": "stopped"},
        )


# Re-exported for tests that build classification assertions.
__all__ = [
    "CLASS_MALFORMED",
    "CLASS_MISSING_ORDER",
    "CLASS_PRECONDITION",
    "CLASS_TRANSIENT",
    "CLASS_UNKNOWN_TYPE",
    "CLASS_UNSUPPORTED_SCHEMA",
    "StreamEndedError",
    "consume_forever",
    "run_worker",
    "validate_stage_modes",
]
