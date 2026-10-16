# QuickBite — Full-Stack Food Delivery App

QuickBite is a training full-stack food ordering system: customers browse a seeded
restaurant catalog, check out with an idempotency key, and track an order through a
simulated asynchronous pipeline (payment → restaurant → delivery → notification)
while an admin observes read-only aggregates. **PostgreSQL is the sole source of
truth**; RabbitMQ only distributes work.

> Status: **Milestone 3 (Outbox Dispatcher, Broker Topology, Four Workers,
> Notifications) complete**, pending milestone approval. See
> [Milestones](#milestones) for what is and is not implemented yet. API
> contract: [`docs/api.md`](docs/api.md); events/routing:
> [`docs/event-contract.md`](docs/event-contract.md).

## Stack (pinned)

| Layer | Choice |
| --- | --- |
| API | FastAPI `0.143.2`, Pydantic `2.14.1`, Uvicorn `0.54.0` |
| Persistence | SQLAlchemy `2.1.4` (async), Alembic `1.20.0`, asyncpg `0.32.0`, PostgreSQL `17.11` |
| Messaging | RabbitMQ `4.3.6-management`, aio-pika `10.1.1` (outbox pattern from M3) |
| Auth | pwdlib `0.3.1` (Argon2id), PyJWT `2.15.1` (expiring bearer tokens) |
| Tooling | uv `0.13.1` (`uv.lock` committed), pytest `9.1.1`, ruff `0.17.1` |
| UI | Flutter `3.47.7` stable — one app for Android / Web / iOS (iOS build pending, Linux host) |
| Reverse proxy | nginx `1.30.6-alpine` (introduced when the web target is added) |

## Repository layout

```
backend/            FastAPI app (app/), Alembic migrations (migrations/), tests, workers
frontend/           Flutter app (lib/app, lib/core, lib/features — grows per milestone)
compose.yaml        postgres, rabbitmq, api, migrate, seed, topology-init,
                    outbox-dispatcher, 4 independent workers
infra/rabbitmq.conf Broker configuration
docs/api.md         API contract: pagination, errors, money, idempotency, notifications
docs/event-contract.md   Envelope, the six event types, routing, consumer + dead-letter rules
docs/architecture.md     Runtime components, data flow, module map
docs/reliability.md      Delivery semantics, schedules, crash windows, M4-deferred limits
docs/openapi.json   Exported OpenAPI document (regenerate: scripts note inside docs/api.md)
docs/evidence/      Per-milestone run evidence (m1/, m2/, m3/, …)
scripts/            Reproducible evidence capture (capture_m2_evidence.sh, capture_m3_evidence.sh)
.env.example        Full configuration template (copy to .env; real .env is git-ignored)
QuickBite_Master_Implementation_Prompt.md   Implementation contract (milestones + gates)
```

## Quick start

Prerequisites: Docker + Docker Compose, and (for the mobile/web UI) Flutter 3.47.7.

```bash
cp .env.example .env                 # then edit the placeholders
docker compose up -d --build         # migrations and seed run automatically
```

Services (bound to `127.0.0.1` only):

| URL | What |
| --- | --- |
| http://127.0.0.1:8000/health/live | Process liveness |
| http://127.0.0.1:8000/health/ready | Readiness (PostgreSQL required, RabbitMQ reported) |
| http://127.0.0.1:8000/openapi.json | Versioned OpenAPI (`/api/v1/...`) |
| http://127.0.0.1:15672 | RabbitMQ management UI |

### Demo accounts (seeded, fictional)

| Role | Email | Password |
| --- | --- | --- |
| Customer | `alice@quickbite.dev` | `quickbite!alice1` |
| Customer | `bob@quickbite.dev` | `quickbite!bob1` |
| Customer | `carol@quickbite.dev` | `quickbite!carol1` |
| Admin | `admin@quickbite.dev` | `quickbite!admin1` |

Seed data: 4 restaurants, 24 menu items, prices as integer minor units (INR paise).

```bash
curl -X POST http://127.0.0.1:8000/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"alice@quickbite.dev","password":"quickbite!alice1"}'
```

## Everyday commands

```bash
# Backend tests (uses the throwaway quickbite_test database inside Compose)
docker compose run --rm api pytest -q

# Lint / format (host, via uv)
export PATH="$HOME/.local/bin:$PATH"
cd backend && uv run --frozen ruff check . && uv run --frozen ruff format --check .

# Migrations and seed (idempotent, safe to re-run)
docker compose run --rm migrate
docker compose run --rm seed

# Reset the database completely
docker compose down -v && docker compose up -d --build

# Worker + dispatcher logs (each is an independent process, same image)
docker compose logs -f outbox-dispatcher payment-worker delivery-worker restaurant-worker notification-worker

# RabbitMQ view: exchanges, bindings, queue depths, consumers
docker compose exec rabbitmq rabbitmqctl list_bindings -q source_name destination_name routing_key
docker compose exec rabbitmq rabbitmqctl list_queues -q name messages consumers

# Flutter (web during development)
cd frontend
flutter pub get && flutter analyze && flutter test
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000

# Reproduce this milestone's live evidence (stack must be up):
./scripts/capture_m3_evidence.sh        # writes docs/evidence/m3/
```

Scale workers freely — the compose file defines no fixed container names or
per-worker host ports: `docker compose up -d --scale payment-worker=3`.

## Health semantics (documented on purpose)

- `/health/live` — process liveness only; never fails because of an outage.
- `/health/ready` — **PostgreSQL required** (503 with the standard error envelope
  when down). RabbitMQ is reported `up`/`down` but does **not** gate readiness:
  a committed order may legally wait in the outbox during a broker outage.

## Milestones

| # | Scope | Status |
| --- | --- | --- |
| 1 | Foundation: repo, Compose, migrations, seed, auth, health, worker scaffolds, Flutter shell | ✅ approved |
| 2 | Browsing, server-priced idempotent checkout, order reads, ownership, transactional outbox | ✅ approved |
| 3 | Outbox dispatcher, broker topology, four consumers, notifications endpoint | ✅ complete, awaiting approval |
| 4 | Retry scheduler, quarantine, failure paths | ⬜ not started |
| 5 | Full Flutter UI (Android/Web) | ⬜ not started |
| 6 | Admin, hardening, docs, final verification | ⬜ not started |
| 7 | Submission packaging | ⬜ not started |

### Milestone 2 at a glance

```bash
# Idempotent checkout (Idempotency-Key required) — returns 202 + Location
curl -i -X POST http://127.0.0.1:8000/api/v1/orders \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: 6f1d0d6e-2a5c-4a4e-9b3a-1f4f0f7c9a11" \
  -H 'Content-Type: application/json' \
  -d '{"restaurant_id":"rest_bella_napoli","delivery_address":"12 Lake Road, Bengaluru","items":[{"menu_item_id":"item_margherita_pizza","quantity":2}]}'

# Re-running with the same key + payload returns the SAME response (no new
# order/event); a changed payload returns 409. See docs/api.md for semantics.
```

Acceptance evidence (live-stack captures + test output):
[`docs/evidence/m2/`](docs/evidence/m2/).

### Milestone 3 at a glance

The committed `order.created` row now moves through the whole asynchronous
pipeline with no API involvement after checkout:

```bash
# Place an order (202 + Location), then watch PostgreSQL be the only writer
# while the dispatcher and workers drive it to completion:
TOKEN=$(curl -s -X POST http://127.0.0.1:8000/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"alice@quickbite.dev","password":"quickbite!alice1"}' |
  python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

curl -s -i -X POST http://127.0.0.1:8000/api/v1/orders \
  -H "Authorization: Bearer $TOKEN" -H "Idempotency-Key: $(python3 -c 'import uuid;print(uuid.uuid4())')" \
  -H 'Content-Type: application/json' \
  -d '{"restaurant_id":"rest_bella_napoli","delivery_address":"12 Lake Road, Bengaluru","items":[{"menu_item_id":"item_margherita_pizza","quantity":2}]}'

# ~5 s later the same order reads DRIVER_ASSIGNED with history v1..v4, four
# notifications, and seven dedup markers — no API writes after checkout:
curl -s http://127.0.0.1:8000/api/v1/orders/<order_id> -H "Authorization: Bearer $TOKEN"
curl -s http://127.0.0.1:8000/api/v1/orders/<order_id>/notifications -H "Authorization: Bearer $TOKEN"
```

Delivery is at-least-once with idempotent consumers — `docs/reliability.md`
states the guarantees and schedules honestly; routing lives in
`docs/event-contract.md`.

Acceptance evidence (migrations cycle, live chain, broker restart with zero
loss, topology/consumer inspection, tests, lint):
[`docs/evidence/m3/`](docs/evidence/m3/).

### Known limitations (honest status)

- **iOS is not built**: this host is Linux without Xcode. Android/Web targets are
  scaffolded; the Android SDK is installed in Milestone 5 by agreement.
- **Milestone 4 not started**: there is no durable retry scheduler or
  quarantine persistence yet — unprocessable/disordered messages park on the
  dead-letter queue, and failure-mode stage injections (`fail_twice`) are
  rejected at worker startup by design. Full list:
  [`docs/reliability.md`](docs/reliability.md#known-limitations--deferred-to-milestone-4).
- A physical broker restart is proven by the evidence script
  (`05_broker_restart_no_loss.txt`) rather than inside pytest, which shares one
  broker container; the connection-loss class is covered by tests.
- `GET /admin/orders` and `GET /admin/summary` (admin endpoints) are not served
  yet — due by Milestone 6 at the latest (milestone agreement).
- The Flutter shell renders home + not-found only; feature screens arrive with M5.
- No licensed assets are used. Screenshots and the Dribbble reference are visual
  inspiration only.

## Security notes

- `.env` is git-ignored; `.env.example` carries placeholders only.
- Broker/database ports bind to `127.0.0.1` (local training); a deployment would
  keep them private.
- Passwords are Argon2id-hashed; tokens are signed, expiring JWTs; CORS allows
  explicit origins only (no wildcards with credentials).
