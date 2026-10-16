"""Health, readiness semantics, CORS and configuration-validation tests."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.core.config import Settings
from tests.conftest import auth_header


def _base_settings_kwargs() -> dict:
    return {
        "database_url": "postgresql+asyncpg://user:pass@localhost:5432/quickbite",
        "amqp_url": "amqp://user:pass@localhost:5672/",
        "jwt_secret": "a-sufficiently-long-test-secret-value-1234",
    }


def test_live_endpoint_reports_process_liveness(client):
    response = client.get("/health/live")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "alive"
    assert body["service"] == "api"


def test_ready_reports_dependency_status(client):
    response = client.get("/health/ready")
    assert response.status_code in (200, 503)
    body = response.json()
    if response.status_code == 200:
        assert body["checks"]["postgres"] == "up"
        # Broker state is REPORTED but never gates readiness (committed
        # orders may legally wait for broker recovery — assignment §7).
        assert body["status"] in ("ready", "degraded")
        assert body["checks"]["rabbitmq"] in ("up", "down")
    else:
        # Error responses use the standard envelope: checks live in details.
        assert body["code"] == "SERVICE_NOT_READY"
        assert body["details"]["checks"]["postgres"] == "down"


def test_ready_returns_503_envelope_when_database_unavailable(client, monkeypatch):
    async def _boom(timeout: float) -> None:
        raise ConnectionError("database unreachable")

    monkeypatch.setattr("app.api.health.check_database", _boom)
    response = client.get("/health/ready")
    assert response.status_code == 503
    body = response.json()
    assert body["code"] == "SERVICE_NOT_READY"
    assert body["details"]["checks"]["postgres"] == "down"
    assert body["request_id"]


def test_cors_allows_configured_origin_and_exposes_headers(client):
    response = client.get(
        "/health/live",
        headers={"Origin": "http://localhost:5000"},
    )
    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "http://localhost:5000"
    # Location + X-Request-ID must be readable by the browser client.
    expose = response.headers.get("access-control-expose-headers", "")
    assert "Location" in expose and "X-Request-ID" in expose


def test_cors_rejects_unknown_origin(client):
    response = client.get("/health/live", headers={"Origin": "http://evil.example"})
    assert response.status_code == 200
    assert "access-control-allow-origin" not in response.headers


def test_request_id_is_echoed_and_reused(client):
    response = client.get("/health/live", headers={"X-Request-ID": "trace-abc-123"})
    assert response.headers.get("x-request-id") == "trace-abc-123"


def test_settings_reject_short_jwt_secret():
    with pytest.raises(ValidationError):
        Settings(**{**_base_settings_kwargs(), "jwt_secret": "short"})


def test_settings_reject_non_postgres_database():
    with pytest.raises(ValidationError):
        Settings(**{**_base_settings_kwargs(), "database_url": "sqlite:///./dev.db"})


def test_settings_reject_unknown_worker_mode():
    with pytest.raises(ValidationError):
        Settings(**{**_base_settings_kwargs(), "payment_mode": "sometimes"})


def test_settings_reject_inconsistent_retry_policy():
    with pytest.raises(ValidationError):
        Settings(
            **{**_base_settings_kwargs(), "retry_delays_seconds": "2,10", "retry_max_attempts": 4}
        )


def test_settings_reject_placeholder_secret_in_production():
    with pytest.raises(ValidationError):
        Settings(
            **{
                **_base_settings_kwargs(),
                "environment": "production",
                "jwt_secret": "change-me-change-me-change-me-change-me",
            }
        )


def test_password_never_appears_in_logs(client, caplog):
    import logging

    with caplog.at_level(logging.INFO):
        client.post(
            "/api/v1/auth/login",
            json={"email": "alice@quickbite.dev", "password": "super-secret-pw-xyz"},
        )
        ok = client.post(
            "/api/v1/auth/login",
            json={"email": "alice@quickbite.dev", "password": "quickbite!alice1"},
        )
    assert ok.status_code == 200
    assert "super-secret-pw-xyz" not in caplog.text
    assert "quickbite!alice1" not in caplog.text
    # Tokens are also never logged.
    token = ok.json()["access_token"]
    assert token not in caplog.text


def test_openapi_document_is_versioned(client):
    response = client.get("/openapi.json")
    assert response.status_code == 200
    spec = response.json()
    assert spec["info"]["title"] == "QuickBite API"
    assert "/api/v1/auth/login" in spec["paths"]
    assert "/api/v1/me" in spec["paths"]


def test_customer_cannot_use_admin_routes_yet_or_is_forbidden(client, customer_token):
    response = client.get("/api/v1/admin/orders", headers=auth_header(customer_token))
    # Until Milestone 2 mounts admin routes this is 404 (route does not
    # exist); afterwards the admin-only dependency must return 403.
    assert response.status_code in (403, 404)
    if response.status_code == 403:
        assert response.json()["code"] == "FORBIDDEN"
