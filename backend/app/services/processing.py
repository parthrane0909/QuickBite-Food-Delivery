"""Shared processing contract for the four workers (assignment §10).

Processors run INSIDE the consumer's single database transaction, after the
runtime has locked the order row and checked (consumer_name, event_id)
deduplication. They either apply effects (transition + history + records +
child outbox event) or classify why they cannot:

- `TransientProcessingError`: the simulated infrastructure/provider failure —
  the runtime rolls back and durably schedules the next bounded retry
  (retry_jobs + targeted outbox publication), acknowledging the original
  message only after that commit (assignment §11).
- `PreconditionNotMetError`: the event's prerequisite state has not been
  applied YET (unexpected disorder) — also handled through the durable retry
  path; on exhaustion the event is quarantined, never silently lost.
- `ProcessOutcome("stale_noop")`: the order is already at-or-beyond the
  event's target (duplicate/reordered delivery) — handled safely and marked
  processed, no backward movement.

`attempt` is the DURABLE delivery attempt number (1 = initial delivery;
later attempts are retry_jobs rows), letting deterministic simulations such
as `fail_twice` succeed exactly on their configured attempt.
"""

from __future__ import annotations

from dataclasses import dataclass


class PreconditionNotMetError(Exception):
    """Order state is BEHIND what this event requires (disordered delivery)."""


class MissingOrderError(Exception):
    """The event references an order that does not exist (transient disorder
    or a broken event — handled via bounded retries, then quarantine)."""


class TransientProcessingError(Exception):
    """Deterministic simulated infrastructure failure: rolled back, then
    durably retried with the configured bounded delay schedule."""


@dataclass(frozen=True)
class ProcessOutcome:
    """result: 'applied' (effects committed) | 'stale_noop' (already done)."""

    result: str
    crash_before_ack: bool = False
