"""Pydantic-validated application settings (fail fast on missing/unsafe config).

Every runtime dependency — database, broker, JWT, CORS, demo controls, retry
policy — is read from the environment. Nothing here has a production-unsafe
default; the process refuses to start when required values are absent or
clearly placeholders in production.
"""

from __future__ import annotations

from functools import lru_cache

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

VALID_ENVIRONMENTS = frozenset({"development", "test", "production"})
VALID_LOG_LEVELS = frozenset({"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"})
VALID_MODES = frozenset({"always_succeed", "fail_twice", "always_fail", "crash_after_checkpoint"})
_PLACEHOLDER_MARKERS = ("change-me", "replace-", "example-secret")


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # --- Environment / logging ---
    environment: str = "development"
    log_level: str = "INFO"

    # --- Required infrastructure ---
    database_url: str
    amqp_url: str

    # --- Authentication ---
    jwt_secret: str = Field(min_length=32)
    jwt_algorithm: str = "HS256"
    jwt_issuer: str = "quickbite"
    jwt_expiry_seconds: int = Field(default=1800, ge=60, le=86400)

    # --- CORS ---
    cors_origins: str = "http://localhost:8080,http://127.0.0.1:8080"

    # --- Health / readiness ---
    health_check_timeout_seconds: float = Field(default=2.0, ge=0.1, le=10.0)

    # --- Deterministic demo controls (dev/test only; never selectable via checkout) ---
    payment_mode: str = "always_succeed"
    restaurant_mode: str = "always_succeed"
    delivery_mode: str = "always_succeed"
    notification_mode: str = "always_succeed"

    # --- Simulated per-stage delays (seconds) ---
    payment_delay_seconds: float = Field(default=1.0, ge=0.0, le=60.0)
    restaurant_delay_seconds: float = Field(default=1.0, ge=0.0, le=60.0)
    delivery_delay_seconds: float = Field(default=1.0, ge=0.0, le=60.0)
    notification_delay_seconds: float = Field(default=0.0, ge=0.0, le=60.0)

    # --- Bounded retry policy: 1 initial attempt + len(retry_delays) retries ---
    retry_delays_seconds: str = "2,10,30"
    retry_max_attempts: int = Field(default=4, ge=2, le=10)

    # --- Outbox dispatcher tuning (used from Milestone 3) ---
    outbox_batch_size: int = Field(default=50, ge=1, le=1000)
    outbox_poll_interval_seconds: float = Field(default=0.5, ge=0.05, le=30.0)
    outbox_lease_seconds: float = Field(default=30.0, ge=5.0, le=600.0)

    # ---------------- validators ----------------

    @field_validator("environment")
    @classmethod
    def _valid_environment(cls, value: str) -> str:
        normalized = value.strip().lower()
        if normalized not in VALID_ENVIRONMENTS:
            raise ValueError(f"ENVIRONMENT must be one of {sorted(VALID_ENVIRONMENTS)}")
        return normalized

    @field_validator("log_level")
    @classmethod
    def _valid_log_level(cls, value: str) -> str:
        normalized = value.strip().upper()
        if normalized not in VALID_LOG_LEVELS:
            raise ValueError(f"LOG_LEVEL must be one of {sorted(VALID_LOG_LEVELS)}")
        return normalized

    @field_validator("database_url")
    @classmethod
    def _valid_database_url(cls, value: str) -> str:
        if not value.startswith(("postgresql+asyncpg://", "postgresql://")):
            raise ValueError(
                "DATABASE_URL must be a postgresql:// (asyncpg) URL — SQLite is not permitted"
            )
        return value

    @field_validator("amqp_url")
    @classmethod
    def _valid_amqp_url(cls, value: str) -> str:
        if not value.startswith(("amqp://", "amqps://")):
            raise ValueError("AMQP_URL must be an amqp:// or amqps:// URL")
        return value

    @field_validator("jwt_algorithm")
    @classmethod
    def _valid_algorithm(cls, value: str) -> str:
        if value != "HS256":
            raise ValueError("Only HS256 is permitted for JWT signing in this assignment")
        return value

    @field_validator("jwt_issuer")
    @classmethod
    def _valid_issuer(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("JWT_ISSUER must not be empty")
        return value

    @staticmethod
    def _normalize_mode(value: str) -> str:
        normalized = value.strip().lower()
        if normalized not in VALID_MODES:
            raise ValueError(f"mode must be one of {sorted(VALID_MODES)}")
        return normalized

    @field_validator("payment_mode")
    @classmethod
    def _valid_payment_mode(cls, value: str) -> str:
        return cls._normalize_mode(value)

    @field_validator("restaurant_mode")
    @classmethod
    def _valid_restaurant_mode(cls, value: str) -> str:
        return cls._normalize_mode(value)

    @field_validator("delivery_mode")
    @classmethod
    def _valid_delivery_mode(cls, value: str) -> str:
        return cls._normalize_mode(value)

    @field_validator("notification_mode")
    @classmethod
    def _valid_notification_mode(cls, value: str) -> str:
        return cls._normalize_mode(value)

    @field_validator("retry_delays_seconds")
    @classmethod
    def _valid_retry_delays(cls, value: str) -> str:
        parts = [p.strip() for p in value.split(",") if p.strip()]
        if not parts:
            raise ValueError("RETRY_DELAYS_SECONDS must contain at least one delay")
        delays = [float(p) for p in parts]  # raises ValueError on bad input
        if any(d <= 0 for d in delays):
            raise ValueError("RETRY_DELAYS_SECONDS values must be > 0")
        return ",".join(str(d) for d in delays)

    @model_validator(mode="after")
    def _consistent_retry_policy(self) -> Settings:
        if self.retry_max_attempts != len(self.retry_delays) + 1:
            raise ValueError(
                "RETRY_MAX_ATTEMPTS must equal len(RETRY_DELAYS_SECONDS) + 1 "
                "(one initial attempt plus each configured delayed retry)"
            )
        return self

    @model_validator(mode="after")
    def _reject_production_placeholders(self) -> Settings:
        if self.environment == "production":
            lowered = self.jwt_secret.lower()
            if any(marker in lowered for marker in _PLACEHOLDER_MARKERS):
                raise ValueError("JWT_SECRET still contains a placeholder value in production")
            if "localhost" in self.cors_origins and "*" in self.cors_origins:
                raise ValueError("Wildcard CORS origins are not allowed with credentials")
        return self

    # ---------------- derived values ----------------

    @property
    def cors_origin_list(self) -> list[str]:
        origins = [o.strip() for o in self.cors_origins.split(",") if o.strip()]
        if not origins:
            raise ValueError("CORS_ORIGINS must contain at least one origin")
        if "*" in origins:
            raise ValueError("Wildcard CORS origins are not allowed with credentials")
        return origins

    @property
    def retry_delays(self) -> tuple[float, ...]:
        return tuple(float(p) for p in self.retry_delays_seconds.split(",") if p.strip())


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Cached settings instance. Configuration errors raise at first use (fail fast)."""
    return Settings()
