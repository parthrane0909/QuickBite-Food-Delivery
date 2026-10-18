"""trigram indexes for live restaurant, cuisine, and dish search

Revision ID: 0004
Revises: 0003
"""

from collections.abc import Sequence

from alembic import op

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # GIN trigram indexes support the case-insensitive contains queries used
    # by the customer discovery field at the 2k-restaurant catalogue size.
    op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    op.execute("CREATE INDEX ix_restaurants_name_trgm ON restaurants USING gin (name gin_trgm_ops)")
    op.execute(
        "CREATE INDEX ix_restaurants_cuisine_trgm ON restaurants USING gin (cuisine gin_trgm_ops)"
    )
    op.execute("CREATE INDEX ix_menu_items_name_trgm ON menu_items USING gin (name gin_trgm_ops)")
    op.execute(
        "CREATE INDEX ix_menu_items_description_trgm ON menu_items "
        "USING gin (description gin_trgm_ops)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_menu_items_description_trgm")
    op.execute("DROP INDEX IF EXISTS ix_menu_items_name_trgm")
    op.execute("DROP INDEX IF EXISTS ix_restaurants_cuisine_trgm")
    op.execute("DROP INDEX IF EXISTS ix_restaurants_name_trgm")
