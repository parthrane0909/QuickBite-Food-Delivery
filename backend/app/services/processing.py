"""Shared processing contract for the four workers (assignment §10).

Processors run INSIDE the consumer's single database transaction, after the
runtime has locked the order row and checked (consumer_name, event_id)
deduplication. They either apply effects (transition + history + records +
child outbox event) or classify why they cannot:

- `PreconditionNotMetError`: the event's prerequisite state has not been
  applied YET (unexpected disorder) — the runtime performs a bounded deferred
  retry and finally dead-letters; never a silent lost transition.
- `ProcessOutcome("stale_noop")`: the order is already at-or-beyond the
  event's target (duplicate/reordered delivery) — handled safely and marked
  processed, no backward movement.
"""

from __future__ import annotations

from dataclasses import dataclass


class PreconditionNotMetError(Exception):
    """Order state is BEHIND what this event requires (disordered delivery)."""


class MissingOrderError(Exception):
    """Permanent: the event references an order that does not exist."""


@dataclass(frozen=True)
class ProcessOutcome:
    """result: 'applied' (effects committed) | 'stale_noop' (already done)."""

    result: str
    crash_before_ack: bool = False
