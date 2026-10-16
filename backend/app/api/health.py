"""Health probes with explicit, documented readiness semantics.

- /health/live  : process liveness only; never fails due to an external outage.
- /health/ready : PostgreSQL is REQUIRED (503 when unavailable or slow).
  RabbitMQ state is reported ('up'/'down') but does NOT fail readiness,
  because a committed order may legally wait in the outbox during a broker
  outage (assignment §7: broker downtime does not invalidate a committed
  order). Degraded broker state is therefore surfaced, not gated.
All probes are bounded by HEALTH_CHECK_TIMEOUT_SECONDS.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import UTC, datetime

import aio_pika
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from app.core.config import get_settings
from app.core.errors import error_envelope
from app.db.session import check_database

logger = logging.getLogger("quickbite.health")

router = APIRouter(tags=["health"])


@router.get("/health/live")
async def live() -> dict[str, str]:
    return {
        "status": "alive",
        "service": "api",
        "time": datetime.now(UTC).isoformat(),
    }


async def _probe_broker(timeout: float) -> str:
    settings = get_settings()
    try:
        connection = await asyncio.wait_for(aio_pika.connect(settings.amqp_url), timeout=timeout)
    except Exception:
        return "down"
    try:
        await connection.close()
    except Exception:  # pragma: no cover - closing an already-dead probe
        pass
    return "up"


@router.get("/health/ready")
async def ready(request: Request) -> JSONResponse:
    settings = get_settings()
    timeout = settings.health_check_timeout_seconds
    request_id = getattr(request.state, "request_id", "-")

    checks: dict[str, str] = {}
    try:
        await asyncio.wait_for(check_database(timeout), timeout=timeout)
        checks["postgres"] = "up"
    except Exception:
        checks["postgres"] = "down"
        logger.warning(
            "readiness check failed",
            extra={"request_id": request_id, "result": "not_ready", "path": "/health/ready"},
        )
        return JSONResponse(
            status_code=503,
            content=error_envelope(
                "SERVICE_NOT_READY",
                "Required dependency unavailable; service is not ready.",
                {"checks": checks},
                request_id,
            ),
        )

    checks["rabbitmq"] = await _probe_broker(timeout)
    status = "ready" if checks["rabbitmq"] == "up" else "degraded"
    return JSONResponse(
        status_code=200,
        content={
            "status": status,
            "checks": checks,
            "request_id": request_id,
            "time": datetime.now(UTC).isoformat(),
        },
    )
