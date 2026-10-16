"""Auth routes: POST /api/v1/auth/login and GET /api/v1/me.

Note the exact paths from assignment §7 — the profile endpoint is
/api/v1/me, NOT /api/v1/auth/me.
"""

from __future__ import annotations

from fastapi import APIRouter

from app.api.deps import CurrentUserDep, SessionDep, SettingsDep
from app.schemas.auth import LoginRequest, LoginResponse, ProfileResponse
from app.services import auth_service

router = APIRouter(tags=["auth"])


@router.post("/auth/login", response_model=LoginResponse)
async def login(
    payload: LoginRequest,
    session: SessionDep,
    settings: SettingsDep,
) -> LoginResponse:
    return await auth_service.login(
        session, settings, email=payload.email, password=payload.password
    )


@router.get("/me", response_model=ProfileResponse)
async def me(user: CurrentUserDep) -> ProfileResponse:
    return ProfileResponse(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        role=user.role,
        is_active=user.is_active,
        created_at=user.created_at,
    )
