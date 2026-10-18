# QuickBite — Full-Stack Food Delivery App

QuickBite is a full-stack food ordering and management system: customers browse a
paginated restaurant catalogue, check out with an idempotency key, and track an
order through a simulated asynchronous pipeline (payment → restaurant → delivery
→ notification). Admins can inspect orders, manage restaurants, menus and customer
accounts, and enter the customer shopping experience as their own account.
**PostgreSQL is the sole source of truth**; RabbitMQ only distributes work.

> Status: **M5 baseline retained; admin/catalogue extensions implemented; final
> platform and load evidence is in progress.** See [Milestones](#milestones).
> API
> contract: [`docs/api.md`](docs/api.md); events/routing:
> [`docs/event-contract.md`](docs/event-contract.md); reliability:
> [`docs/reliability.md`](docs/reliability.md); frontend:
> [`docs/frontend.md`](docs/frontend.md); platforms:
> [`docs/platforms.md`](docs/platforms.md).

## Stack (pinned)

| Layer | Choice |
| --- | --- |
| API | FastAPI `0.143.2`, Pydantic `2.14.1`, Uvicorn `0.54.0` |
| Persistence | SQLAlchemy `2.1.4` (async), Alembic `1.20.0`, asyncpg `0.32.0`, PostgreSQL `17.11` |
| Messaging | RabbitMQ `4.3.6-management`, aio-pika `10.1.1` (outbox pattern from M3; durable retries + quarantine from M4) |
| Auth | pwdlib `0.3.1` (Argon2id), PyJWT `2.15.1` (expiring bearer tokens) |
| Tooling | uv `0.13.1` (`uv.lock` committed), pytest `9.1.1`, ruff `0.17.1` |
| UI | Flutter `3.47.7` stable — one app for Android / Web / iOS (iOS build pending, Linux host) |
| Reverse proxy | nginx `1.30.6-alpine` (introduced when the web target is added) |

## Repository layout

```
backend/            FastAPI app (app/), Alembic migrations (migrations/), tests, workers
frontend/           Flutter app (Android / Web / iOS targets; lib/app, lib/core,
                    lib/features, widget tests, emulator integration test)
compose.yaml        postgres, rabbitmq, api, migrate, seed, topology-init,
                    outbox-dispatcher, retry-scheduler, 4 independent workers,
                    web (nginx SPA host, port 8080)
infra/rabbitmq.conf Broker configuration
infra/web-nginx.conf    nginx config for the Flutter web SPA (SPA fallback)
docs/api.md         API contract: pagination, errors, money, idempotency, notifications
docs/event-contract.md   Envelope, the six event types, routing, retry + dead-letter rules
docs/architecture.md     Runtime components, data flow, module map
docs/reliability.md      Delivery semantics, retry/quarantine lifecycle, crash windows, limits
docs/frontend.md        Flutter architecture: state, networking, idempotency UX, polling
docs/admin.md           Admin/customer authorization, management flows and safe catalogue seeding
docs/performance.md     Reproducible M7 measurements and scaling caveats
docs/platforms.md     Clean install + web/Android/iOS build & run commands (iOS pending)
docs/openapi.json   Exported OpenAPI document (regenerate: scripts note inside docs/api.md)
docs/evidence/      Per-milestone run evidence (m1/, m2/, m3/, m4/, m5/, …)
scripts/            Reproducible evidence capture (capture_m2..m4_evidence.sh),
                    web build (build_web.sh), Android SDK setup, food-image generator,
                    reviewed crash/failure overrides (crash-overrides/*.yaml)
backend/scripts/    inspect_state.py (backlog inspection), demo_failures.py (failure demos)
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
| http://localhost:8080 | Flutter web SPA (nginx, built by `./scripts/build_web.sh`) |

### Demo accounts (seeded, fictional)

| Role | Email | Password |
| --- | --- | --- |
| Customer | `alice@quickbite.dev` | `quickbite!alice1` |
| Customer | `bob@quickbite.dev` | `quickbite!bob1` |
| Customer | `carol@quickbite.dev` | `quickbite!carol1` |
| Admin | `admin@quickbite.dev` | `quickbite!admin1` |

Baseline fixtures: 4 restaurants, 24 menu items, and fictional demo accounts.
The optional showcase catalogue currently contains 2,000 restaurants and
19,992 menu items (integer INR minor units). It is added explicitly; ordinary
application startup never bulk-seeds the catalogue.

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

# Optional showcase catalogue (repeatable; additive and idempotent)
docker compose exec api python -m scripts.seed_large_catalogue

# Reset the database completely
docker compose down -v && docker compose up -d --build

# Worker + dispatcher + scheduler logs (each is an independent process, same image)
docker compose logs -f outbox-dispatcher retry-scheduler payment-worker delivery-worker restaurant-worker notification-worker

# Reliability backlog inspection: outbox, retry jobs, quarantine, queue depths
docker compose exec api python -m scripts.inspect_state

# Interactive failure-control demos (see scripts/crash-overrides/ for the env-only controls)
docker compose run --rm api python -m scripts.demo_failures --list

# RabbitMQ view: exchanges, bindings, queue depths, consumers
docker compose exec rabbitmq rabbitmqctl list_bindings -q source_name destination_name routing_key
docker compose exec rabbitmq rabbitmqctl list_queues -q name messages consumers

# Flutter: static checks and the widget/DTO suite
cd frontend
flutter pub get && flutter analyze && flutter test

# Web dev server (browser calls the API directly; CORS allows :8080)
cd frontend
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/api/v1

# Release web build + nginx SPA hosting in Compose (UI at http://localhost:8080)
./scripts/build_web.sh

# Android: build the debug APK and run the end-to-end integration test
cd frontend
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
flutter test integration_test/app_flow_test.dart -d emulator-5554

# Reproduce this milestone's live evidence (stack must be up):
./scripts/capture_m4_evidence.sh        # writes docs/evidence/m4/
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
| 3 | Outbox dispatcher, broker topology, four consumers, notifications endpoint | ✅ approved |
| 4 | Durable retries, quarantine, failure simulation, crash recovery | ✅ approved |
| 5 | Customer Flutter UI (Android/Web), original read-only admin overview | ✅ baseline complete |
| 6 | Admin management extension, session hardening, docs, acceptance verification | 🟡 implementation present; final runtime/recovery matrix in progress |
| 7 | Catalogue scale, load comparison, submission evidence | 🟡 catalogue seeded; reproducible load comparison and final evidence pending |

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

### Milestone 4 at a glance

Failures are now **durable, bounded and observable** — a transient failure is
retried 1 + 3 times at **2 s / 10 s / 30 s** (default, configurable), routed
only back to the queue that failed, and terminally handled (state-guarded
order transition or quarantine) instead of looping:

```bash
# Protected failure demo: payment fails twice, durable retries carry the
# order to DRIVER_ASSIGNED with a single committed payment (env-only control;
# the live payment-worker must be stopped so this process drives the queue):
docker compose stop payment-worker
docker compose run --rm api python -m scripts.demo_failures payment_fail_twice
docker compose start payment-worker
#   retry ladder: attempt #2 scheduled_in=2.0s, attempt #3 scheduled_in=10.0s
#   order: DRIVER_ASSIGNED, one payment, no quarantine

# Inspect the reliability backlog (outbox, retries, quarantine, queue depths):
docker compose exec api python -m scripts.inspect_state
```

Deterministic failure controls (payment decline / exhaust, restaurant reject,
delivery failure, notification failure) and real crash checkpoints
(`os._exit` 70/71/72/73, physical `docker compose kill`, broker outage with a
pending retry) are driven by `scripts/crash-overrides/*.yaml` and captured
reproducibly by `./scripts/capture_m4_evidence.sh`. Guarantees, schedules and
crash windows are stated in [`docs/reliability.md`](docs/reliability.md).

Acceptance evidence (migration cycle, default 2/10/30 s timing, terminal
paths, quarantine dedup, four crash checkpoints, SIGKILL ×3, broker outage,
logs, tests, lint):
[`docs/evidence/m4/`](docs/evidence/m4/).

### Milestone 5 at a glance

The Flutter app now covers the complete customer journey and a read-only
admin dashboard, on phone and desktop layouts:

```bash
# Web SPA behind nginx (SPA fallback for deep links, port matches CORS)
./scripts/build_web.sh                     # then open http://localhost:8080

# Android debug APK + end-to-end integration flow on the emulator
cd frontend
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
flutter test integration_test/app_flow_test.dart -d emulator-5554

# Full frontend suite: analyzer + 75 widget/DTO tests
flutter analyze && flutter test
```

Highlights (details in [`docs/frontend.md`](docs/frontend.md)):

- **Screens**: sign-in, restaurant list, menu, cart (single-restaurant,
  quantities clamped to the server's 1..20), checkout, acceptance, live
  tracking with per-order notifications, order history with status
  filters, and an admin overview (cross-customer list + operations
  summary) that is unreachable for customers.
- **Safe checkout**: the idempotency key is persisted before the request;
  timeouts/network errors keep the same key for a safe retry, 4xx
  definite failures discard it, 409 surfaces a conflict with an explicit
  discard path, and the in-flight submit is disabled.
- **Honest tracking**: ~2 s polling only while visible — stopped on
  terminal state, dispose, backgrounding and auth loss, with exponential
  backoff on errors; a "202 accepted" is never presented as paid/delivered.
- **New admin endpoints**: `GET /api/v1/admin/orders` and
  `GET /api/v1/admin/summary` (admin-only; customers get 403).
- **Platforms**: web + Android validated with evidence; **iOS build
  documented and pending** (no macOS host — see
  [`docs/platforms.md`](docs/platforms.md)).

Acceptance evidence (backend suite, widget/DTO suite, integration flow on
the emulator, web build + nginx deep-link reload, CORS, screenshots,
admin access control):
[`docs/evidence/m5/`](docs/evidence/m5/).

### Known limitations (honest status)

- **iOS is not built or run**: this host is Linux without Xcode. The iOS
  target is the standard Flutter scaffolding; the exact macOS build/run
  procedure is documented in [`docs/platforms.md`](docs/platforms.md) and
  validation is explicitly pending — iOS is not claimed complete.
- A physical broker restart is proven by the evidence scripts
  (`docs/evidence/m3/05_broker_restart_no_loss.txt`,
  `docs/evidence/m4/14_broker_outage_pending_retries.txt` — the latter with a
  pending retry) rather than inside pytest, which shares one broker container;
  the connection-loss class is covered by tests.
- The Flutter app implements no search, category filter (the catalog API
  has no category field), coupons, payments UI, maps/ratings/chat — those
  backend capabilities do not exist and nothing is fabricated.
- Failure simulations and crash checkpoints are **environment/process-only**
  controls (compose overrides, demo script); they are rejected outside test
  mode where appropriate and never reachable from API/checkout fields.
- No licensed assets are used. Screenshots and the Dribbble reference are visual
  inspiration only; food imagery is generated by a committed script and the
  bundled font is OFL-licensed.

## Security notes

- `.env` is git-ignored; `.env.example` carries placeholders only.
- Broker/database ports bind to `127.0.0.1` (local training); a deployment would
  keep them private.
- Passwords are Argon2id-hashed; tokens are signed, expiring JWTs; CORS allows
  explicit origins only (no wildcards with credentials).
