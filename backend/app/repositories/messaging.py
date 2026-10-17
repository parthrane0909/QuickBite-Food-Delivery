"""Transactional retry-job / quarantine DB operations (assignment §11).

Every function runs inside the CALLER's transaction (session-scoped): a worker
schedules its retry in one commit with its rolled-back business attempt, the
scheduler activates due jobs in one commit, and the quarantine service records
a logical failure exactly once. Uniqueness (enforced by PostgreSQL, not by
read-then-write races) makes repeated failure handling unable to create
duplicate retry jobs or duplicate logical quarantine records:

- retry_jobs        UNIQUE (consumer_name, event_id, attempt)
- quarantine_records UNIQUE (consumer_name, event_id)
- outbox_events     UNIQUE (exchange, routing_key, event_id) — one targeted
  publication row per (target, event), RE-ARMED across attempts.

All due-times are computed with the DATABASE clock (now() + make_interval),
so worker/scheduler/dispatcher clock drift can never claim a job early.
"""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import func, select, text
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.outbox_event import OutboxEvent
from app.db.models.quarantine_record import QuarantineRecord
from app.db.models.retry_job import RetryJob

# Outbox rows for targeted retries use the DEFAULT exchange (empty name):
# routing_key carries the target queue's name (see topology.DEFAULT_EXCHANGE).
RETRY_EXCHANGE = ""

# retry_jobs.state values (CHECK-constrained in 0001).
JOB_PENDING = "PENDING"  # scheduled; waiting for due_at
JOB_PUBLISHED = "PUBLISHED"  # scheduler activated it; retry copy publishable
JOB_EXHAUSTED = "EXHAUSTED"  # final attempt failed; quarantined


@dataclass(frozen=True)
class RetrySchedule:
    """What the runtime logged/committed when scheduling one delayed retry."""

    attempt: int
    due_in_seconds: float
    target_queue: str
    duplicate: bool  # True when this (consumer, event, attempt) already existed


async def current_attempt(session: AsyncSession, consumer_name: str, event_id: str) -> int:
    """The delivery attempt number of the message being processed, read from
    DURABLE retry state (attempts survive worker/broker restarts). Attempt 1 =
    the initial delivery (no retry job exists yet)."""
    row = (
        await session.execute(
            select(func.max(RetryJob.attempt)).where(
                RetryJob.consumer_name == consumer_name, RetryJob.event_id == event_id
            )
        )
    ).scalar_one_or_none()
    return int(row) if row is not None else 1


async def schedule_retry(
    session: AsyncSession,
    *,
    consumer_name: str,
    event_id: str,
    event_type: str,
    order_id: str | None,
    envelope_payload: dict,
    target_queue: str,
    attempt: int,
    delay_seconds: float,
    last_error: str,
) -> RetrySchedule:
    """Atomically persist the NEXT retry attempt (caller's transaction):

    1. one retry_jobs row (unique per consumer/event/attempt — a repeated
       failure handling can never schedule the same attempt twice), and
    2. the scheduled, targeted outbox publication (default exchange,
       routing_key = the failing queue, original envelope/event_id), re-armed
       to become eligible at due time.

    Committing both together before the consumer acks its original message is
    the assignment §11 durability contract.
    """
    job = pg_insert(RetryJob).values(
        id=f"rj_{event_id[:32]}_{attempt}",
        consumer_name=consumer_name,
        event_id=event_id,
        envelope=envelope_payload,
        order_id=order_id,
        target_queue=target_queue,
        attempt=attempt,
        # make_interval with its 7 POSITIONAL parameters (years..secs):
        # SQLAlchemy's generic function factory rejects keyword arguments, and
        # the DB clock (now()) keeps due times immune to app/DB clock skew.
        due_at=func.now() + func.make_interval(0, 0, 0, 0, 0, 0, delay_seconds),
        state=JOB_PENDING,
        last_error=last_error[:2000],
    )
    job = job.on_conflict_do_nothing(constraint="uq_retry_jobs_consumer_name")
    result = await session.execute(job)
    duplicate = result.rowcount == 0

    publication = pg_insert(OutboxEvent).values(
        id=f"out_retry_{event_id[:32]}_{attempt}",
        event_id=event_id,
        event_type=event_type,
        order_id=order_id,
        exchange=RETRY_EXCHANGE,
        routing_key=target_queue,
        payload=envelope_payload,
        state="PENDING",
        available_at=func.now() + func.make_interval(0, 0, 0, 0, 0, 0, delay_seconds),
        attempts=0,
        created_at=func.now(),
    )
    # One publication row per (target queue, event), re-armed per attempt.
    await session.execute(
        publication.on_conflict_do_update(
            constraint="uq_outbox_events_publication_identity",
            set_={
                "state": "PENDING",
                "available_at": publication.excluded.available_at,
                "attempts": 0,
                "claimed_at": None,
                "claimed_by": None,
                "lease_expires_at": None,
                "published_at": None,
                "last_error": None,
                "order_id": publication.excluded.order_id,
                "event_type": publication.excluded.event_type,
                "payload": publication.excluded.payload,
            },
        )
    )
    return RetrySchedule(
        attempt=attempt,
        due_in_seconds=delay_seconds,
        target_queue=target_queue,
        duplicate=duplicate,
    )


async def mark_job_exhausted(
    session: AsyncSession, *, consumer_name: str, event_id: str, attempt: int
) -> None:
    """The final attempt failed and the event was quarantined: record it on
    the durable job row (idempotent; leaves other attempts untouched)."""
    await session.execute(
        text(
            "UPDATE retry_jobs SET state = 'EXHAUSTED', updated_at = now() "
            "WHERE consumer_name = :consumer AND event_id = :event AND attempt = :attempt"
        ),
        {"consumer": consumer_name, "event": event_id, "attempt": attempt},
    )


# ---------------------------------------------------------------------------
# Retry scheduler internals (SKIP LOCKED: any number of scheduler instances)
# ---------------------------------------------------------------------------

# Claim due PENDING jobs AND make their targeted outbox publications eligible
# in ONE transaction: a crashed scheduler re-runs the identical claim next
# cycle (idempotent), and a scheduler that never runs cannot lose retries —
# the publication row's own due `available_at` keeps it eligible for the
# dispatcher (belt and braces, documented in docs/reliability.md). Jobs whose
# publication row was already SENT (the dispatcher published it at due time
# regardless) are still returned: they were activated on schedule.
CLAIM_DUE_JOBS_SQL = """
WITH claimed AS (
    UPDATE retry_jobs
    SET state = 'PUBLISHED', updated_at = now()
    WHERE id IN (
        SELECT id FROM retry_jobs
        WHERE state = 'PENDING' AND due_at <= now()
        ORDER BY due_at
        LIMIT :batch
        FOR UPDATE SKIP LOCKED
    )
    RETURNING consumer_name, event_id, target_queue, attempt
),
activated AS (
    UPDATE outbox_events o
    SET state = 'PENDING',
        available_at = now(),
        claimed_at = NULL,
        claimed_by = NULL,
        lease_expires_at = NULL
    FROM claimed c
    WHERE o.exchange = ''
      AND o.routing_key = c.target_queue
      AND o.event_id = c.event_id
      AND o.state = 'PENDING'
    RETURNING c.event_id
)
SELECT consumer_name, event_id, target_queue, attempt FROM claimed
"""


async def claim_due_retry_jobs(
    session: AsyncSession, *, batch_size: int
) -> list[tuple[str, str, str, int]]:
    """Activate due retry jobs (state PENDING -> PUBLISHED) and make their
    scheduled outbox publications eligible NOW. Returns
    (consumer_name, event_id, target_queue, attempt) per activated job."""
    result = await session.execute(text(CLAIM_DUE_JOBS_SQL), {"batch": batch_size})
    return [(r[0], r[1], r[2], int(r[3])) for r in result.all()]


async def retry_backlog(session: AsyncSession) -> dict[str, float | int]:
    """Inspection data for scheduler logs and scripts/inspect_state.py:
    per-state job counts, oldest due age (s) and quarantine count."""
    count_result = await session.execute(
        text("SELECT state, count(*) FROM retry_jobs GROUP BY state")
    )
    counts = {row[0]: int(row[1]) for row in count_result.all()}
    oldest = (
        await session.execute(
            text(
                "SELECT extract(epoch FROM (now() - min(due_at))) "
                "FROM retry_jobs WHERE state = 'PENDING'"
            )
        )
    ).scalar_one_or_none()
    quarantined = (
        await session.execute(text("SELECT count(*) FROM quarantine_records"))
    ).scalar_one()
    return {
        "pending": counts.get(JOB_PENDING, 0),
        "published": counts.get(JOB_PUBLISHED, 0),
        "exhausted": counts.get(JOB_EXHAUSTED, 0),
        "oldest_due_age_seconds": float(oldest) if oldest is not None else 0.0,
        "quarantine_count": int(quarantined),
    }


# ---------------------------------------------------------------------------
# Quarantine persistence (unique logical record per consumer + event)
# ---------------------------------------------------------------------------


async def insert_quarantine(
    session: AsyncSession,
    *,
    record_id: str,
    event_id: str,
    consumer_name: str,
    queue_name: str,
    attempts: int,
    failure_code: str,
    reason: str,
    envelope_payload: dict,
    order_id: str | None,
    outbox_event_id: str | None,
) -> bool:
    """INSERT one quarantine record; ON CONFLICT DO NOTHING on the logical
    identity (consumer_name, event_id). Returns False when the event was
    ALREADY quarantined by this consumer (a duplicate delivery can never
    create a second logical record)."""
    stmt = (
        pg_insert(QuarantineRecord)
        .values(
            id=record_id,
            event_id=event_id,
            consumer_name=consumer_name,
            queue_name=queue_name,
            attempts=attempts,
            failure_code=failure_code,
            reason=reason[:2000],
            envelope=envelope_payload,
            order_id=order_id,
            outbox_event_id=outbox_event_id,
        )
        .on_conflict_do_nothing(constraint="uq_quarantine_records_consumer_name")
    )
    result = await session.execute(stmt)
    return result.rowcount > 0


async def insert_dead_publication(
    session: AsyncSession,
    *,
    outbox_id: str,
    event_id: str,
    event_type: str,
    order_id: str | None,
    exchange: str,
    routing_key: str,
    payload: dict,
) -> bool:
    """Insert the dead-exchange outbox publication for a quarantine. ON
    CONFLICT DO NOTHING on the publication identity: if another consumer
    already queued the same event for the dead queue, the single row suffices
    (identical immutable payload)."""
    stmt = (
        pg_insert(OutboxEvent)
        .values(
            id=outbox_id,
            event_id=event_id,
            event_type=event_type,
            order_id=order_id,
            exchange=exchange,
            routing_key=routing_key,
            payload=payload,
            state="PENDING",
            available_at=func.now(),
            attempts=0,
            created_at=func.now(),
        )
        .on_conflict_do_nothing(constraint="uq_outbox_events_publication_identity")
    )
    result = await session.execute(stmt)
    return result.rowcount > 0


async def get_outbox_row(
    session: AsyncSession, *, exchange: str, routing_key: str, event_id: str
) -> OutboxEvent | None:
    return (
        await session.execute(
            select(OutboxEvent).where(
                OutboxEvent.exchange == exchange,
                OutboxEvent.routing_key == routing_key,
                OutboxEvent.event_id == event_id,
            )
        )
    ).scalar_one_or_none()


async def oldest_pending_outbox_age_seconds(session: AsyncSession) -> float | None:
    """Age of the oldest non-SENT outbox row (observability, M4 §10)."""
    value = (
        await session.execute(
            text(
                "SELECT extract(epoch FROM (now() - min(created_at))) "
                "FROM outbox_events WHERE state <> 'SENT'"
            )
        )
    ).scalar_one_or_none()
    return float(value) if value is not None else None
