"""Structured JSON logging with an explicit redaction policy.

Only whitelisted, non-sensitive fields are emitted from log extras. Sensitive
material (passwords, tokens, authorization headers, full delivery addresses)
must never be placed into log records; the redact() helper is available for
the rare case where structured data containing such keys must be logged.
"""

from __future__ import annotations

import json
import logging
import sys
from datetime import UTC, datetime
from typing import Any

# Only these extra fields are written to the log output (allowlist).
_EMITTED_EXTRAS = (
    "service",
    "request_id",
    "correlation_id",
    "user_id",
    "order_id",
    "event_id",
    "consumer",
    "attempt",
    "attempts",
    "next_attempt",
    "transition",
    "method",
    "path",
    "http_status",
    "elapsed_ms",
    "duration_ms",
    "result",
    # Transport/publish failure diagnostics (publisher exception text — no
    # payload content, no PII by construction) and retry scheduling.
    "detail",
    "retry_in_s",
    # Milestone 4 observability (§10): failure classification, targeted
    # retry routing, quarantine and backlog inspection counters. All are
    # metadata by construction — no addresses, tokens or payload bodies.
    "classification",
    "quarantine",
    "target_queue",
    "exchange",
    "routing_key",
    "activated",
    "retry_pending",
    "retry_published",
    "retry_exhausted",
    "quarantine_count",
    "oldest_due_age_seconds",
    "pending_outbox_age_s",
)

_SENSITIVE_MARKERS = ("password", "token", "authorization", "secret", "jwt", "address")


def redact(data: dict[str, Any]) -> dict[str, Any]:
    """Return a copy of *data* with sensitive-looking keys masked."""
    masked: dict[str, Any] = {}
    for key, value in data.items():
        if any(marker in key.lower() for marker in _SENSITIVE_MARKERS):
            masked[key] = "[REDACTED]"
        elif isinstance(value, dict):
            masked[key] = redact(value)
        else:
            masked[key] = value
    return masked


class JsonFormatter(logging.Formatter):
    """One JSON object per record, allowlisted extras only."""

    def __init__(self, default_service: str) -> None:
        super().__init__()
        self._default_service = default_service

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "ts": datetime.fromtimestamp(record.created, tz=UTC).isoformat(timespec="milliseconds"),
            "level": record.levelname,
            "logger": record.name,
            "service": getattr(record, "service", self._default_service),
            "message": record.getMessage(),
        }
        for key in _EMITTED_EXTRAS:
            if key == "service":
                continue
            value = getattr(record, key, None)
            if value is not None:
                payload[key] = value
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)


def configure_logging(level: str = "INFO", service: str = "api") -> None:
    """Install the JSON handler on the root logger (idempotent)."""
    root = logging.getLogger()
    if any(getattr(handler, "_quickbite_json", False) for handler in root.handlers):
        return
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter(default_service=service))
    handler._quickbite_json = True  # type: ignore[attr-defined]
    root.addHandler(handler)
    root.setLevel(level.upper())
