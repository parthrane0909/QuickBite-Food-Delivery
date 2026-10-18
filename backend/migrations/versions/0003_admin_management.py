"""admin management and audit fields

Revision ID: 0003
Revises: 0002
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "drivers",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("full_name", sa.String(120), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
    )
    op.bulk_insert(
        sa.table(
            "drivers",
            sa.column("id", sa.String),
            sa.column("full_name", sa.String),
            sa.column("is_active", sa.Boolean),
        ),
        [
            {"id": "drv_arjun", "full_name": "Arjun Nair", "is_active": True},
            {"id": "drv_meera", "full_name": "Meera Iyer", "is_active": True},
            {"id": "drv_kabir", "full_name": "Kabir Singh", "is_active": True},
            {"id": "drv_sana", "full_name": "Sana Fernandes", "is_active": True},
            {"id": "drv_rohit", "full_name": "Rohit Menon", "is_active": True},
            {"id": "drv_zoya", "full_name": "Zoya Khan", "is_active": True},
        ],
    )
    op.create_foreign_key(
        "fk_driver_assignments_driver_id_drivers",
        "driver_assignments",
        "drivers",
        ["driver_id"],
        ["id"],
        ondelete="RESTRICT",
    )
    op.add_column("restaurants", sa.Column("cuisine", sa.String(80), nullable=True))
    op.create_index("ix_restaurants_cuisine", "restaurants", ["cuisine"])
    op.create_index("ix_restaurants_is_available", "restaurants", ["is_available"])
    op.execute(
        "UPDATE restaurants SET cuisine = CASE id "
        "WHEN 'rest_spice_route' THEN 'North Indian' "
        "WHEN 'rest_coastal_catch' THEN 'Seafood' "
        "WHEN 'rest_bella_napoli' THEN 'Italian' "
        "WHEN 'rest_sweet_crumb' THEN 'Bakery' END "
        "WHERE cuisine IS NULL AND id IN "
        "('rest_spice_route', 'rest_coastal_catch', 'rest_bella_napoli', 'rest_sweet_crumb')"
    )
    op.create_table(
        "admin_audit_logs",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("admin_id", sa.String(64), nullable=False),
        sa.Column("action", sa.String(64), nullable=False),
        sa.Column("target_type", sa.String(32), nullable=False),
        sa.Column("target_id", sa.String(64), nullable=False),
        sa.Column("changed_fields", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["admin_id"], ["users.id"], ondelete="RESTRICT"),
    )
    op.create_index("ix_admin_audit_logs_admin_id", "admin_audit_logs", ["admin_id"])
    op.create_index("ix_admin_audit_logs_target_id", "admin_audit_logs", ["target_id"])
    op.create_index("ix_admin_audit_logs_created_at", "admin_audit_logs", ["created_at"])


def downgrade() -> None:
    op.drop_table("admin_audit_logs")
    op.drop_index("ix_restaurants_cuisine", table_name="restaurants")
    op.drop_index("ix_restaurants_is_available", table_name="restaurants")
    op.drop_column("restaurants", "cuisine")
    op.drop_constraint(
        "fk_driver_assignments_driver_id_drivers", "driver_assignments", type_="foreignkey"
    )
    op.drop_table("drivers")
