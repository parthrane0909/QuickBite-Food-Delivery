# Milestone 2 — Evidence Index

Captured **2026-10-16** against the live Compose stack. Reproduce everything:

```bash
docker compose build api && docker compose up -d
./scripts/capture_m2_evidence.sh    # regenerates every file in this folder
```

No access tokens, secrets or real customer data appear in any file.

| File | What it proves |
| --- | --- |
| `00_migrations_cycle.txt` | Migrations remain reproducible: `0001 (head)` → `downgrade base` → `upgrade head`, then idempotent re-seed. **Milestone 2 required no new migration** — M1 created the full 14-table schema. |
| `01_service_health.txt` | `/health/live` and `/health/ready` return 200; `docker compose ps -a` shows api/postgres/rabbitmq healthy, migrate/seed exited 0, 4 independent workers running. |
| `02_checkout_202_accepted.txt` | Happy-path checkout: `202 Accepted`, `Location: /api/v1/orders/{id}`, documented body (`total_amount_minor: 71000` = server-priced 2×28000 + 15000). |
| `03_checkout_replay_same_key.txt` | Same key + same payload → byte-identical 202 body and Location, no new order/event. |
| `04_checkout_conflict_409.txt` | Same key + changed quantity → `409` `IDEMPOTENCY_CONFLICT` with envelope. |
| `05_checkout_validation_rejections.txt` | Unavailable item, mixed-restaurant item, missing `Idempotency-Key`, client-supplied `total_amount_minor`, and missing auth → 422/401 with machine-readable reasons (tests assert zero rows written). |
| `06_order_reads_and_access_control.txt` | List/detail/history 200 for owner; **404** for another customer (no existence leak); admin 200 on detail; admin 403 on the customer-only list. |
| `07_outbox_row.txt` | The committed outbox row + exact `order.created` envelope (event_id, schema_version 1, order_version 1, UTC `occurred_at`, correlation/causation, PII-free data, state `PENDING`). |
| `08_pytest_full.txt` | Full backend suite: **84 passed** (38 Milestone 1 + 46 new) on real PostgreSQL. |
| `09_pytest_concurrency.txt` | Concurrent identical submissions → exactly one order/event; conflicting concurrent payloads → one 202 + one 409. |
| `10_ruff_check.txt` | `ruff check` and `ruff format --check` clean. |
| `11_broker_outage_checkout.txt` | With RabbitMQ **stopped**: readiness `200 "degraded"` (PostgreSQL gates), checkout still `202`, order + outbox row committed `PENDING`; broker restarted → readiness `ready` again. Broker downtime never invalidates a committed order. |

Atomic-rollback proof (mid-transaction failure writes zero rows) and
server-pricing proof (total follows current menu price) live in the automated
tests `tests/test_checkout_idempotency.py::test_mid_transaction_failure_rolls_back_the_entire_acceptance`
and `tests/test_checkout_validation.py::test_total_follows_current_menu_price_change`.
