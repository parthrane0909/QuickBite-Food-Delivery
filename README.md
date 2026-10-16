# QuickBite — Full-Stack Food Delivery App

QuickBite is a training full-stack food ordering system: customers browse a seeded
restaurant catalog, check out with an idempotency key, and track an order through a
simulated asynchronous pipeline (payment → restaurant → delivery → notification)
while an admin observes read-only aggregates. **PostgreSQL is the sole source of
truth**; RabbitMQ only distributes work.

> Status: **Milestone 1 (Foundation) complete**, pending milestone approval.
> See [Milestones](#milestones) for what is and is not implemented yet.

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
compose.yaml        postgres, rabbitmq, api, migrate, seed, 4 independent workers
infra/rabbitmq.conf Broker configuration
.env.example        Full configuration template (copy to .env; real .env is git-ignored)
docs/evidence/      Screenshots and captured run evidence per milestone
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

# Worker logs (each worker is an independent process running the same image)
docker compose logs -f payment-worker delivery-worker restaurant-worker notification-worker

# Flutter (web during development)
cd frontend
flutter pub get && flutter analyze && flutter test
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
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
| 1 | Foundation: repo, Compose, migrations, seed, auth, health, worker scaffolds, Flutter shell | ✅ complete, awaiting approval |
| 2 | Checkout contract + idempotency | ⬜ not started |
| 3 | Outbox, topology, consumers, dispatcher | ⬜ not started |
| 4 | Retry scheduler, quarantine, failure paths | ⬜ not started |
| 5 | Full Flutter UI (Android/Web) | ⬜ not started |
| 6 | Admin, hardening, docs, final verification | ⬜ not started |
| 7 | Submission packaging | ⬜ not started |

### Known limitations (honest status)

- **iOS is not built**: this host is Linux without Xcode. Android/Web targets are
  scaffolded; the Android SDK is installed in Milestone 5 by agreement.
- Worker processes currently verify the database, log a heartbeat and **idle** —
  message consumption arrives with Milestone 3.
- The Flutter shell renders home + not-found only; feature screens arrive with M5.
- No licensed assets are used. Screenshots and the Dribbble reference are visual
  inspiration only.

## Security notes

- `.env` is git-ignored; `.env.example` carries placeholders only.
- Broker/database ports bind to `127.0.0.1` (local training); a deployment would
  keep them private.
- Passwords are Argon2id-hashed; tokens are signed, expiring JWTs; CORS allows
  explicit origins only (no wildcards with credentials).
