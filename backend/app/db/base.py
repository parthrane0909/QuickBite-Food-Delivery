"""Declarative SQLAlchemy base, constraint naming conventions and ID helper.

All identifiers are application-generated strings with a readable prefix
(e.g. ``order_9f2c...``) so API payloads and logs stay human-traceable while
remaining collision-free (UUID-derived suffix).
"""

from __future__ import annotations

import uuid

from sqlalchemy import MetaData
from sqlalchemy.orm import DeclarativeBase

# Deterministic constraint names so Alembic autogenerate never churns and
# migrations stay readable/repeatable.
NAMING_CONVENTION = {
    "ix": "ix_%(table_name)s_%(column_0_name)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)


def generate_id(prefix: str) -> str:
    """Return a prefixed, UUID-derived identifier such as ``order_ab12…``."""
    return f"{prefix}_{uuid.uuid4().hex}"
