"""Password hashing and short-lived signed bearer tokens.

Follows the FastAPI OAuth2-with-JWT pattern:
https://fastapi.tiangolo.com/tutorial/security/oauth2-jwt/
Passwords use Argon2id via pwdlib; tokens are HS256-signed, expiring, and
carry issuer/subject/role claims that are re-checked against the database.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import jwt as pyjwt
from pwdlib import PasswordHash

from app.core.config import Settings

_password_hash = PasswordHash.recommended()  # Argon2id

VALID_ROLES = frozenset({"customer", "admin"})


class TokenError(Exception):
    """Base class for any invalid bearer token."""


class TokenExpiredError(TokenError):
    """The token's signature is valid but its expiry has passed."""


class TokenInvalidError(TokenError):
    """Signature, claims or format are invalid."""


@dataclass(frozen=True, slots=True)
class TokenClaims:
    subject: str  # user id
    role: str
    issued_at: datetime
    expires_at: datetime
    token_id: str


def hash_password(password: str) -> str:
    return _password_hash.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    return _password_hash.verify(password, password_hash)


def create_access_token(
    settings: Settings,
    *,
    user_id: str,
    role: str,
    ttl_seconds: int | None = None,
) -> tuple[str, datetime]:
    """Return (token, expires_at). Tokens are short-lived and signed server-side."""
    if role not in VALID_ROLES:
        raise ValueError(f"unknown role: {role}")
    now = datetime.now(UTC)
    expires_at = now + timedelta(seconds=ttl_seconds or settings.jwt_expiry_seconds)
    token_id = uuid.uuid4().hex
    payload = {
        "sub": user_id,
        "role": role,
        "iat": int(now.timestamp()),
        "exp": int(expires_at.timestamp()),
        "iss": settings.jwt_issuer,
        "jti": token_id,
    }
    token = pyjwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    return token, expires_at


def decode_token(settings: Settings, token: str) -> TokenClaims:
    """Validate signature, expiry, required claims and issuer.

    Raises TokenExpiredError / TokenInvalidError. The caller must still
    re-check the user exists and is active (claims alone are not authority).
    """
    try:
        payload = pyjwt.decode(
            token,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],
            issuer=settings.jwt_issuer,
            options={"require": ["sub", "iat", "exp", "iss"]},
        )
    except pyjwt.ExpiredSignatureError as exc:
        raise TokenExpiredError("access token has expired") from exc
    except pyjwt.PyJWTError as exc:
        raise TokenInvalidError("access token is invalid") from exc

    role = payload.get("role")
    if role not in VALID_ROLES:
        raise TokenInvalidError("access token carries an unknown role")
    subject = payload.get("sub")
    if not isinstance(subject, str) or not subject:
        raise TokenInvalidError("access token has no subject")

    return TokenClaims(
        subject=subject,
        role=role,
        issued_at=datetime.fromtimestamp(payload["iat"], tz=UTC),
        expires_at=datetime.fromtimestamp(payload["exp"], tz=UTC),
        token_id=str(payload.get("jti", "")),
    )
