"""Domain exceptions and the standard error envelope.

Every error response — including validation errors — has the shape:
    {"code": ..., "message": ..., "details": ..., "request_id": ...}
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = logging.getLogger("quickbite.errors")


def error_envelope(
    code: str,
    message: str,
    details: Any,
    request_id: str | None,
) -> dict[str, Any]:
    return {
        "code": code,
        "message": message,
        "details": details,
        "request_id": request_id or "-",
    }


class AppError(Exception):
    """Base for errors that map to a documented API status + code."""

    status_code: int = 500
    code: str = "INTERNAL_ERROR"

    def __init__(self, message: str, *, details: Any = None) -> None:
        super().__init__(message)
        self.message = message
        self.details = details


class InvalidCredentialsError(AppError):
    status_code = 401
    code = "INVALID_CREDENTIALS"


class UnauthenticatedError(AppError):
    status_code = 401
    code = "UNAUTHENTICATED"


class TokenExpiredError(AppError):
    status_code = 401
    code = "TOKEN_EXPIRED"


class TokenInvalidError(AppError):
    status_code = 401
    code = "TOKEN_INVALID"


class ForbiddenError(AppError):
    status_code = 403
    code = "FORBIDDEN"


class NotFoundError(AppError):
    status_code = 404
    code = "NOT_FOUND"


class ConflictError(AppError):
    status_code = 409
    code = "CONFLICT"


class ValidationFailedError(AppError):
    status_code = 422
    code = "VALIDATION_ERROR"


_HTTP_STATUS_CODES = {
    401: "UNAUTHENTICATED",
    403: "FORBIDDEN",
    404: "NOT_FOUND",
    405: "METHOD_NOT_ALLOWED",
    422: "VALIDATION_ERROR",
}


def _request_id(request: Request) -> str | None:
    return getattr(request.state, "request_id", None)


def install_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _handle_app_error(request: Request, exc: AppError) -> JSONResponse:
        rid = _request_id(request)
        if exc.status_code >= 500:
            logger.exception(
                "application error",
                extra={"request_id": rid, "result": exc.code},
            )
        else:
            logger.warning(
                "application error",
                extra={
                    "request_id": rid,
                    "result": exc.code,
                    "method": request.method,
                    "path": request.url.path,
                },
            )
        return JSONResponse(
            status_code=exc.status_code,
            content=error_envelope(exc.code, exc.message, exc.details, rid),
        )

    @app.exception_handler(RequestValidationError)
    async def _handle_request_validation(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        details = [
            {
                "location": ".".join(str(part) for part in error["loc"]),
                "message": error["msg"],
                "type": error["type"],
            }
            for error in exc.errors()
        ]
        return JSONResponse(
            status_code=422,
            content=error_envelope(
                "VALIDATION_ERROR",
                "Request validation failed.",
                details,
                _request_id(request),
            ),
        )

    @app.exception_handler(StarletteHTTPException)
    async def _handle_http_exception(request: Request, exc: StarletteHTTPException) -> JSONResponse:
        code = _HTTP_STATUS_CODES.get(exc.status_code, "HTTP_ERROR")
        detail = exc.detail if isinstance(exc.detail, str) else None
        return JSONResponse(
            status_code=exc.status_code,
            content=error_envelope(
                code, detail or "Request could not be processed.", None, _request_id(request)
            ),
            headers=getattr(exc, "headers", None),
        )

    @app.exception_handler(Exception)
    async def _handle_unexpected(request: Request, exc: Exception) -> JSONResponse:
        rid = _request_id(request)
        logger.exception(
            "unhandled error",
            extra={
                "request_id": rid,
                "method": request.method,
                "path": request.url.path,
                "result": "INTERNAL_ERROR",
            },
        )
        return JSONResponse(
            status_code=500,
            content=error_envelope(
                "INTERNAL_ERROR",
                "An unexpected error occurred.",
                None,
                rid,
            ),
        )
