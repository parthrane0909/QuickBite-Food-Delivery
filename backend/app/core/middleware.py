"""Request/correlation-ID middleware with timing and structured access logs.

Tokens, authorization headers, query strings and bodies are deliberately never
logged. The request ID is exposed back to clients via the X-Request-ID header
so a client-side failure can be correlated with server logs.
"""

from __future__ import annotations

import logging
import time
import uuid

from fastapi import FastAPI
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

logger = logging.getLogger("quickbite.request")

REQUEST_ID_HEADER = "X-Request-ID"
_MAX_REQUEST_ID_LENGTH = 64


class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        incoming = (request.headers.get(REQUEST_ID_HEADER) or "").strip()
        request_id = incoming[:_MAX_REQUEST_ID_LENGTH] or uuid.uuid4().hex
        request.state.request_id = request_id

        started = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
            logger.exception(
                "request failed",
                extra={
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "elapsed_ms": elapsed_ms,
                    "result": "error",
                },
            )
            raise

        elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
        response.headers[REQUEST_ID_HEADER] = request_id
        logger.info(
            "request completed",
            extra={
                "request_id": request_id,
                "method": request.method,
                "path": request.url.path,
                "http_status": response.status_code,
                "elapsed_ms": elapsed_ms,
                "result": "ok" if response.status_code < 400 else "error",
            },
        )
        return response


def install_middlewares(app: FastAPI) -> None:
    # Added first => runs closest to the app; CORS is added later (outermost)
    # so preflights never reach this layer.
    app.add_middleware(RequestContextMiddleware)
