"""Central order state machine (assignment §6).

This module DEFINES the legal transitions; the checkout service (M2) and the
workers (M3+) apply them through atomic compare-and-set/row-lock transactions
that append one history row per version. No component may transition outside
this map, and no transition ever moves backwards.
"""

from __future__ import annotations

PENDING = "PENDING"
PAID = "PAID"
CONFIRMED = "CONFIRMED"
DRIVER_ASSIGNED = "DRIVER_ASSIGNED"
PAYMENT_FAILED = "PAYMENT_FAILED"
FAILED = "FAILED"

ALL_STATES = frozenset({PENDING, PAID, CONFIRMED, DRIVER_ASSIGNED, PAYMENT_FAILED, FAILED})

# Successful completion for THIS assignment is DRIVER_ASSIGNED; physical
# delivery (DELIVERED) does not exist.
TERMINAL_STATES = frozenset({DRIVER_ASSIGNED, PAYMENT_FAILED, FAILED})

# Assignment §6, verbatim:
#   PENDING -> PAID -> CONFIRMED -> DRIVER_ASSIGNED
#   PENDING -> PAYMENT_FAILED
#   PAID -> FAILED        (unrecoverable restaurant failure)
#   CONFIRMED -> FAILED   (unrecoverable delivery failure)
ALLOWED_TRANSITIONS: dict[str, frozenset[str]] = {
    PENDING: frozenset({PAID, PAYMENT_FAILED}),
    PAID: frozenset({CONFIRMED, FAILED}),
    CONFIRMED: frozenset({DRIVER_ASSIGNED, FAILED}),
    DRIVER_ASSIGNED: frozenset(),
    PAYMENT_FAILED: frozenset(),
    FAILED: frozenset(),
}


class IllegalTransitionError(Exception):
    """Raised when a component attempts a transition outside the map."""


def is_terminal(state: str) -> bool:
    return state in TERMINAL_STATES


def can_transition(current: str, target: str) -> bool:
    if current not in ALLOWED_TRANSITIONS:
        raise ValueError(f"unknown order state: {current}")
    return target in ALLOWED_TRANSITIONS[current]


def ensure_transition(current: str, target: str) -> None:
    if not can_transition(current, target):
        raise IllegalTransitionError(f"illegal transition {current} -> {target}")


def next_version(version: int) -> int:
    if version < 1:
        raise ValueError("order version must be >= 1")
    return version + 1
