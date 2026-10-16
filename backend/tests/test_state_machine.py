"""Order state machine definition tests (assignment §6, defined in M1,
applied by checkout/workers from Milestone 2/3)."""

from __future__ import annotations

import pytest

from app.services import order_state_machine as sm


def test_happy_path_transitions_are_legal():
    sm.ensure_transition(sm.PENDING, sm.PAID)
    sm.ensure_transition(sm.PAID, sm.CONFIRMED)
    sm.ensure_transition(sm.CONFIRMED, sm.DRIVER_ASSIGNED)


def test_failure_transitions_match_assignment():
    sm.ensure_transition(sm.PENDING, sm.PAYMENT_FAILED)
    sm.ensure_transition(sm.PAID, sm.FAILED)
    sm.ensure_transition(sm.CONFIRMED, sm.FAILED)


def test_terminal_states_allow_nothing_further():
    for terminal in sm.TERMINAL_STATES:
        assert sm.is_terminal(terminal)
        for target in sm.ALL_STATES:
            assert not sm.can_transition(terminal, target)


def test_no_backward_or_skipping_transitions():
    illegal = [
        (sm.PAID, sm.PENDING),
        (sm.CONFIRMED, sm.PAID),
        (sm.PENDING, sm.CONFIRMED),
        (sm.PENDING, sm.DRIVER_ASSIGNED),
        (sm.DRIVER_ASSIGNED, sm.PAID),
        (sm.FAILED, sm.PENDING),
        (sm.PAYMENT_FAILED, sm.PAID),
    ]
    for current, target in illegal:
        with pytest.raises(sm.IllegalTransitionError):
            sm.ensure_transition(current, target)


def test_unknown_state_raises():
    with pytest.raises(ValueError):
        sm.can_transition("BOGUS", sm.PAID)


def test_version_is_strictly_monotonic():
    assert sm.next_version(1) == 2
    assert sm.next_version(41) == 42
    with pytest.raises(ValueError):
        sm.next_version(0)


def test_success_terminal_is_driver_assigned():
    # DRIVER_ASSIGNED is successful completion for this assignment; physical
    # delivery (DELIVERED) deliberately does not exist.
    assert sm.DRIVER_ASSIGNED in sm.TERMINAL_STATES
    assert "DELIVERED" not in sm.ALL_STATES
