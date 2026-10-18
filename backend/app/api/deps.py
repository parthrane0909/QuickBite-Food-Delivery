"""API dependencies: session, request ID, authentication and role guards.

Access rules (assignment §7): missing/invalid/expired token -> 401; wrong role
-> 403; another customer's order -> 404 (never 403, to avoid existence leaks).
Customer identity ALWAYS comes from the validated token, never from the body.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.core.errors import (
    ForbiddenError,
    TokenExpiredError,
    TokenInvalidError,
    UnauthenticatedError,
)
from app.core.security import (
    TokenError,
    decode_token,
)
from app.core.security import (
    TokenExpiredError as JwtTokenExpiredError,
)
from app.db.models.user import User
from app.db.session import get_session
from app.repositories import users as users_repo

SessionDep = Annotated[AsyncSession, Depends(get_session)]
SettingsDep = Annotated[Settings, Depends(get_settings)]


def get_request_id(request: Request) -> str:
    return getattr(request.state, "request_id", "-")


RequestIdDep = Annotated[str, Depends(get_request_id)]


async def get_current_user(
    request: Request,
    session: SessionDep,
    settings: SettingsDep,
) -> User:
    """Validate bearer token, then re-check the user server-side (active)."""
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        raise UnauthenticatedError("Missing bearer token.")
    token = header.removeprefix("Bearer ").strip()
    if not token:
        raise UnauthenticatedError("Missing bearer token.")

    try:
        claims = decode_token(settings, token)
    except JwtTokenExpiredError as exc:
        raise TokenExpiredError("Access token has expired; please sign in again.") from exc
    except TokenError as exc:
        raise TokenInvalidError("Access token is invalid.") from exc

    user = await users_repo.get_by_id(session, claims.subject)
    if user is None or not user.is_active:
        raise TokenInvalidError("Access token is invalid.")
    return user


CurrentUserDep = Annotated[User, Depends(get_current_user)]


async def require_customer(user: CurrentUserDep) -> User:
    if user.role != "customer":
        raise ForbiddenError("This endpoint requires a customer account.")
    return user


async def require_shopper(user: CurrentUserDep) -> User:
    """Customer endpoints also serve an admin's own account in shopping mode.

    Identity and ownership remain derived from the same bearer token; this
    grants no cross-customer reads and no role changes.
    """
    if user.role not in {"customer", "admin"}:
        raise ForbiddenError("This endpoint requires an authenticated shopper.")
    return user


async def require_admin(user: CurrentUserDep) -> User:
    if user.role != "admin":
        raise ForbiddenError("This endpoint requires an admin account.")
    return user


CustomerDep = Annotated[User, Depends(require_customer)]
ShopperDep = Annotated[User, Depends(require_shopper)]
AdminDep = Annotated[User, Depends(require_admin)]
