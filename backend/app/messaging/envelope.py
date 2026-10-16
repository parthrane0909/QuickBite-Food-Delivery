"""Envelope parsing/building at the messaging boundary (assignment §9/§10).

One wire contract: the Pydantic `EventEnvelope` in `app.schemas.events`.
This module owns the runtime concerns around it — strict JSON/schema-version
checking (unknown versions are rejected to dead-letter handling, never
retried forever), structured rejection reasons, and AMQP message properties
(`message_id = event_id`, JSON content type, persistent delivery).
"""

from __future__ import annotations

import json
import logging
from datetime import UTC, datetime
from typing import Any

import aio_pika
from pydantic import ValidationError

from app.schemas.events import EVENT_TYPES, SCHEMA_VERSION, EventEnvelope

logger = logging.getLogger("quickbite.envelope")


class EnvelopeError(Exception):
    """Malformed or unsupported message. Carries a stable machine reason so
    the runtime can dead-letter + log instead of retrying forever."""

    def __init__(self, reason: str, *, detail: str = "") -> None:
        super().__init__(f"{reason}: {detail}" if detail else reason)
        self.reason = reason
        self.detail = detail


def parse_envelope(body: bytes | str) -> EventEnvelope:
    """bytes -> validated envelope, or EnvelopeError with a stable reason:
    invalid_json | invalid_envelope | unknown_event_type |
    unsupported_schema_version."""
    if isinstance(body, bytes):
        try:
            body = body.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise EnvelopeError("invalid_json", detail=str(exc)) from exc
    try:
        raw: Any = json.loads(body)
    except json.JSONDecodeError as exc:
        raise EnvelopeError("invalid_json", detail=str(exc)) from exc
    if not isinstance(raw, dict):
        raise EnvelopeError("invalid_envelope", detail="body must be a JSON object")

    version = raw.get("schema_version")
    if not isinstance(version, int) or version < 1:
        raise EnvelopeError("invalid_envelope", detail="missing/invalid schema_version")
    if version != SCHEMA_VERSION:
        # Unknown schema versions are quarantined (Milestone 4 records them in
        # quarantine_records); Milestone 3 routes them to the dead-letter queue.
        raise EnvelopeError("unsupported_schema_version", detail=f"schema_version={version}")

    event_type = raw.get("event_type")
    if isinstance(event_type, str) and event_type not in EVENT_TYPES:
        # Well-formed envelope with a FUTURE event type: consumers may
        # acknowledge-and-log it instead of retrying forever (assignment §9).
        raise EnvelopeError("unknown_event_type", detail=event_type)

    try:
        return EventEnvelope.model_validate(raw)
    except ValidationError as exc:
        raise EnvelopeError("invalid_envelope", detail=str(exc)) from exc


def build_message(payload: dict[str, Any]) -> aio_pika.Message:
    """Outbox payload dict -> persistent AMQP message. Immutable identity:
    `message_id` IS `event_id` across every publication attempt."""
    event_id = str(payload["event_id"])
    return aio_pika.Message(
        body=json.dumps(payload, separators=(",", ":"), ensure_ascii=True).encode("utf-8"),
        message_id=event_id,
        content_type="application/json",
        delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
        type=str(payload.get("event_type", "")),
        correlation_id=str(payload.get("correlation_id", "")) or None,
        timestamp=datetime.now(UTC),
    )


def supported_event_types() -> frozenset[str]:
    return frozenset(EVENT_TYPES)
