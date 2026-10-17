"""publication identity: unique (exchange, routing_key, event_id)

Milestone 4 publishes RETRIED events through the SAME immutable event_id but a
DIFFERENT publication identity: the RabbitMQ default exchange with routing key
equal to the failing queue's name (assignment §11 — targeted retries that never
redeliver to unrelated subscribers). Two consumers (e.g. payment and
notification) may also retry the same event independently, each with its own
target queue. The former UNIQUE(event_id) therefore rejected legitimate rows;
it is replaced by the full publication identity UNIQUE(exchange, routing_key,
event_id) exactly as specified by the master implementation prompt.

One row per publication identity is RE-ARMED across attempts (state back to
PENDING, fresh available_at) — the per-attempt counter lives durably in
retry_jobs (UNIQUE consumer_name, event_id, attempt).

Downgrade note: M4 publication rows (targeted retries on the default exchange
and durable dead-exchange copies) intentionally SHARE an event_id with their
topic row, so M3's UNIQUE(event_id) cannot be restored while they exist. The
downgrade therefore removes exactly those M4-only rows (retry_jobs and
quarantine_records inspection history is retained; the dangling outbox_event_id
reference is nulled first) and then restores the M3 constraint.

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-17
"""

from collections.abc import Sequence

from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_constraint("uq_outbox_events_event_id", "outbox_events", type_="unique")
    op.create_unique_constraint(
        "uq_outbox_events_publication_identity",
        "outbox_events",
        ["exchange", "routing_key", "event_id"],
    )


def downgrade() -> None:
    # M4-only publication rows share their event_id with the topic row (by
    # design) — drop them before UNIQUE(event_id) can be restored. They have
    # no M3 representation; their inspection history lives on in
    # retry_jobs / quarantine_records (retained).
    op.execute(
        "UPDATE quarantine_records SET outbox_event_id = NULL "
        "WHERE outbox_event_id IN ("
        "SELECT id FROM outbox_events "
        "WHERE exchange = '' OR exchange = 'quickbite.dead')"
    )
    op.execute("DELETE FROM outbox_events WHERE exchange = '' OR exchange = 'quickbite.dead'")
    op.drop_constraint("uq_outbox_events_publication_identity", "outbox_events", type_="unique")
    op.create_unique_constraint("uq_outbox_events_event_id", "outbox_events", ["event_id"])
