"""FastAPI application factory.

The HTTP success boundary for checkout is the committed PostgreSQL
transaction (Milestone 2). This process never publishes to RabbitMQ inline
and never waits on background workers; the outbox dispatcher does that
asynchronously (Milestone 3).
"""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.health import router as health_router
from app.api.v1.router import api_router
from app.core.config import get_settings
from app.core.errors import install_exception_handlers
from app.core.logging import configure_logging
from app.core.middleware import REQUEST_ID_HEADER, install_middlewares

API_VERSION = "2.0.0"


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings.log_level, service="api")

    app = FastAPI(
        title="QuickBite API",
        version=API_VERSION,
        description=(
            "QuickBite Revised Full-Stack Assignment v2.0 — food ordering with "
            "server-priced idempotent checkout and asynchronous RabbitMQ processing."
        ),
        docs_url="/docs",
        redoc_url="/redoc",
        openapi_url="/openapi.json",
    )

    # Innermost first; CORS added last so it becomes the outermost layer.
    install_middlewares(app)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PATCH", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "Idempotency-Key", REQUEST_ID_HEADER],
        expose_headers=["Location", REQUEST_ID_HEADER],
        max_age=600,
    )
    install_exception_handlers(app)

    app.include_router(health_router)
    app.include_router(api_router, prefix="/api/v1")
    return app


app = create_app()
