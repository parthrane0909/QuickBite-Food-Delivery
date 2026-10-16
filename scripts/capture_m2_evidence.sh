#!/usr/bin/env bash
# Reproducible Milestone 2 evidence capture (assignment §14/§16).
#
# Prerequisites (from the repository root):
#   docker compose build api && docker compose up -d
#
# Runs every M2 acceptance scenario against the LIVE stack and stores raw
# output under docs/evidence/m2/. Access tokens are used in flight only and
# are NEVER written to any evidence file (assignment §16).
set -euo pipefail

BASE="http://127.0.0.1:8000"
EV="docs/evidence/m2"
mkdir -p "$EV"

login() { # email password -> access_token on stdout (never stored)
  curl -s -X POST "$BASE/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" |
    python3 -c 'import sys, json; print(json.load(sys.stdin)["access_token"])'
}

ALICE_TOKEN="$(login alice@quickbite.dev 'quickbite!alice1')"
BOB_TOKEN="$(login bob@quickbite.dev 'quickbite!bob1')"
ADMIN_TOKEN="$(login admin@quickbite.dev 'quickbite!admin1')"
AUTH="Authorization: Bearer $ALICE_TOKEN"
KEY="$(python3 -c 'import uuid; print(uuid.uuid4())')"
PAYLOAD='{"restaurant_id":"rest_bella_napoli","delivery_address":"12 Lake Road, Bengaluru","items":[{"menu_item_id":"item_margherita_pizza","quantity":2},{"menu_item_id":"item_garlic_bread","quantity":1}]}'

# Guarantee the broker is back even if a step fails mid-script.
cleanup() { docker compose start rabbitmq >/dev/null 2>&1 || true; }
trap cleanup EXIT

# ---- 0. migrations cycle (M2 needs NO new migration: 0001 remains head) ----
{
  echo '$ docker compose run --rm api sh -c "alembic downgrade base && alembic upgrade head"'
  docker compose run --rm api sh -c "alembic downgrade base && alembic upgrade head" 2>&1 |
    grep -E "Running downgrade|Running upgrade|Can't locate|ERROR" || true
  echo
  echo '$ docker compose run --rm seed   # re-seed after the deliberate downgrade'
  docker compose run --rm seed 2>&1 | tail -1
} > "$EV/00_migrations_cycle.txt"

# ---- 1. service health ----
{
  echo '$ curl /health/live'
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/health/live"
  echo '$ curl /health/ready'
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/health/ready"
  echo
  echo '$ docker compose ps -a'
  docker compose ps -a
} > "$EV/01_service_health.txt"

# ---- 2. happy-path checkout: 202 + Location + documented body ----
curl -s -i -X POST "$BASE/api/v1/orders" \
  -H "$AUTH" -H "Idempotency-Key: $KEY" -H "Content-Type: application/json" \
  -H "X-Request-ID: req_m2_demo" -d "$PAYLOAD" > "$EV/02_checkout_202_accepted.txt"
ORDER_ID="$(grep -o 'order_[a-f0-9]\{32\}' "$EV/02_checkout_202_accepted.txt" | head -1)"

# ---- 3. replay: same key + same payload -> identical 202, no new order ----
curl -s -i -X POST "$BASE/api/v1/orders" \
  -H "$AUTH" -H "Idempotency-Key: $KEY" -H "Content-Type: application/json" \
  -d "$PAYLOAD" > "$EV/03_checkout_replay_same_key.txt"

# ---- 4. conflict: same key + changed payload -> 409 ----
curl -s -i -X POST "$BASE/api/v1/orders" \
  -H "$AUTH" -H "Idempotency-Key: $KEY" -H "Content-Type: application/json" \
  -d '{"restaurant_id":"rest_bella_napoli","delivery_address":"12 Lake Road, Bengaluru","items":[{"menu_item_id":"item_margherita_pizza","quantity":3}]}' \
  > "$EV/04_checkout_conflict_409.txt"

# ---- 5. validation failures -> 422/404 with envelope, nothing persisted ----
{
  echo 'A) unavailable menu item'
  curl -s -w "\nHTTP %{http_code}\n" -X POST "$BASE/api/v1/orders" \
    -H "$AUTH" -H "Idempotency-Key: $(python3 -c 'import uuid; print(uuid.uuid4())')" \
    -H 'Content-Type: application/json' \
    -d '{"restaurant_id":"rest_bella_napoli","delivery_address":"12 Lake Road, Bengaluru","items":[{"menu_item_id":"item_bbq_chicken_pizza","quantity":1}]}'
  echo
  echo 'B) item from another restaurant (mixed cart)'
  curl -s -w "\nHTTP %{http_code}\n" -X POST "$BASE/api/v1/orders" \
    -H "$AUTH" -H "Idempotency-Key: $(python3 -c 'import uuid; print(uuid.uuid4())')" \
    -H 'Content-Type: application/json' \
    -d '{"restaurant_id":"rest_bella_napoli","delivery_address":"12 Lake Road, Bengaluru","items":[{"menu_item_id":"item_dal_makhani","quantity":1}]}'
  echo
  echo 'C) missing Idempotency-Key header'
  curl -s -w "\nHTTP %{http_code}\n" -X POST "$BASE/api/v1/orders" \
    -H "$AUTH" -H 'Content-Type: application/json' -d "$PAYLOAD"
  echo
  echo 'D) client-supplied price/total fields'
  curl -s -w "\nHTTP %{http_code}\n" -X POST "$BASE/api/v1/orders" \
    -H "$AUTH" -H "Idempotency-Key: $(python3 -c 'import uuid; print(uuid.uuid4())')" \
    -H 'Content-Type: application/json' \
    -d '{"restaurant_id":"rest_bella_napoli","delivery_address":"12 Lake Road, Bengaluru","items":[{"menu_item_id":"item_margherita_pizza","quantity":1}],"total_amount_minor":1}'
  echo
  echo 'E) unauthenticated'
  curl -s -w "\nHTTP %{http_code}\n" -X POST "$BASE/api/v1/orders" \
    -H "Idempotency-Key: $(python3 -c 'import uuid; print(uuid.uuid4())')" \
    -H 'Content-Type: application/json' -d "$PAYLOAD"
} > "$EV/05_checkout_validation_rejections.txt"

# ---- 6. order reads + ownership authorization ----
{
  echo "A) GET /api/v1/orders (customer list, newest first)"
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/api/v1/orders?page=1&page_size=5" -H "$AUTH"
  echo
  echo "B) GET /api/v1/orders/$ORDER_ID (owner)"
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/api/v1/orders/$ORDER_ID" -H "$AUTH"
  echo
  echo "C) GET /api/v1/orders/$ORDER_ID/history (owner)"
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/api/v1/orders/$ORDER_ID/history" -H "$AUTH"
  echo
  echo "D) GET the same order as ANOTHER customer -> 404 (no existence leak)"
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/api/v1/orders/$ORDER_ID" \
    -H "Authorization: Bearer $BOB_TOKEN"
  echo
  echo "E) GET the same order as admin -> 200"
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/api/v1/orders/$ORDER_ID" \
    -H "Authorization: Bearer $ADMIN_TOKEN"
  echo
  echo "F) admin on the customer-only list endpoint -> 403"
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/api/v1/orders" \
    -H "Authorization: Bearer $ADMIN_TOKEN"
} > "$EV/06_order_reads_and_access_control.txt"

# ---- 7. committed outbox row for this order ----
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' <<SQL > "$EV/07_outbox_row.txt"
select event_id, event_type, exchange, routing_key, state, attempts
from outbox_events where order_id = '$ORDER_ID';
select jsonb_pretty(payload::jsonb) as event_envelope
from outbox_events where order_id = '$ORDER_ID';
SQL

# ---- 8. automated acceptance evidence ----
docker compose run --rm api pytest -q 2>&1 | tee "$EV/08_pytest_full.txt" | tail -2
docker compose run --rm api pytest -q -k "concurrent" -v 2>&1 |
  tee "$EV/09_pytest_concurrency.txt" | tail -3
docker compose run --rm api ruff check . 2>&1 | tail -2 > "$EV/10_ruff_check.txt"
docker compose run --rm api ruff format --check . 2>&1 | tail -1 >> "$EV/10_ruff_check.txt"

# ---- 9. exported API contract ----
docker compose run --rm api python -m scripts.export_openapi > docs/openapi.json

# ---- 10. broker outage: acceptance must not depend on RabbitMQ ----
OUTAGE_KEY="$(python3 -c 'import uuid; print(uuid.uuid4())')"
{
  echo '1) docker compose stop rabbitmq'
  docker compose stop rabbitmq
  echo
  echo '2) readiness during the outage (200 "degraded": PostgreSQL gates, RabbitMQ reported)'
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/health/ready"
  echo
  echo '3) checkout during the outage -> still 202, order committed to PostgreSQL'
  curl -s -i -X POST "$BASE/api/v1/orders" \
    -H "$AUTH" -H "Idempotency-Key: $OUTAGE_KEY" -H "Content-Type: application/json" \
    -H "X-Request-ID: req_m2_broker_outage" -d "$PAYLOAD"
} > "$EV/11_broker_outage_checkout.txt" 2>&1
OUTAGE_ORDER_ID="$(grep -o 'order_[a-f0-9]\{32\}' "$EV/11_broker_outage_checkout.txt" | head -1)"

docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' <<SQL >> "$EV/11_broker_outage_checkout.txt"
select order_id, state, published_at
from outbox_events where order_id = '$OUTAGE_ORDER_ID';
SQL

{
  echo
  echo '4) docker compose start rabbitmq  (outbox stays PENDING until the M3 dispatcher runs)'
  docker compose start rabbitmq
  sleep 5
  echo '5) readiness after recovery'
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/health/ready"
} >> "$EV/11_broker_outage_checkout.txt" 2>&1

echo "Evidence written to $EV/"
