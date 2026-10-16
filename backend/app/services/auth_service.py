"""Authentication service — credential validation and token issuance.

The response never reveals whether an email exists; inactive accounts are
treated exactly like wrong passwords.
"""

from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import InvalidCredentialsError
from app.core.security import create_access_token, hash_password, verify_password
from app.db.models.user import User
from app.repositories import users as users_repo
from app.schemas.auth import LoginResponse, UserSummary

# A real, valid Argon2 hash verified when the email is unknown, so response
# timing does not reveal account existence.
_TIMING_DUMMY_HASH = hash_password("quickbite-timing-equalization-dummy")


async def login(
    session: AsyncSession, settings: Settings, *, email: str, password: str
) -> LoginResponse:
    user = await users_repo.get_by_email(session, email)
    # Verify against a dummy hash when the user is missing so timing does not
    # reveal account existence.
    if user is None:
        verify_password(password, _TIMING_DUMMY_HASH)
        raise InvalidCredentialsError("Invalid email or password.")
    if not user.is_active or not verify_password(password, user.password_hash):
        raise InvalidCredentialsError("Invalid email or password.")

    token, expires_at = create_access_token(settings, user_id=user.id, role=user.role)
    return LoginResponse(
        access_token=token,
        expires_in=settings.jwt_expiry_seconds,
        expires_at=expires_at,
        role=user.role,
        user=UserSummary(id=user.id, email=user.email, full_name=user.full_name, role=user.role),
    )


def summarize(user: User) -> UserSummary:
    return UserSummary(id=user.id, email=user.email, full_name=user.full_name, role=user.role)
