#!/usr/bin/env bash
# Reproducible Milestone 3 evidence capture (assignment §14/§16/§20).
#
# Prerequisites (from the repository root):
#   docker compose build api && docker compose up -d
#
# Runs every M3 acceptance scenario against the LIVE stack and stores raw
# output under docs/evidence/m3/. Access tokens are used in flight only and
# are NEVER written to any evidence file (assignment §16).
#
# Operational procedure documented here (and in docs/reliability.md): the
# outbox dispatcher and the four workers are stopped around a full-schema
# migration cycle, then restarted. Message loss is impossible by design —
# events live in PostgreSQL until confirmed+routed, and consumers deduplicate.
#
# Broker inspection shows PRODUCTION names only (quickbite.* / *.queue);
# tst_* is the isolated integration-test namespace.
set -euo pipefail

BASE="http://127.0.0.1:8000"
EV="docs/evidence/m3"
PIPELINE="outbox-dispatcher payment-worker restaurant-worker delivery-worker notification-worker"
PROD_QUEUE_RE='^(payment\.queue|restaurant\.queue|delivery\.queue|notification\.queue|orders\.dead-letter\.queue)$'
mkdir -p "$EV"

login() { # email password -> access_token on stdout (never stored)
  curl -s -X POST "$BASE/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" |
    python3 -c 'import sys, json; print(json.load(sys.stdin)["access_token"])'
}

# Guarantee broker + pipeline are back even if a step fails mid-script.
cleanup() {
  docker compose start rabbitmq >/dev/null 2>&1 || true
  # shellcheck disable=SC2086
  docker compose start $PIPELINE >/dev/null 2>&1 || true
}
trap cleanup EXIT

ALICE_TOKEN="$(login alice@quickbite.dev 'quickbite!alice1')"
BOB_TOKEN="$(login bob@quickbite.dev 'quickbite!bob1')"
ADMIN_TOKEN="$(login admin@quickbite.dev 'quickbite!admin1')"
AUTH="Authorization: Bearer $ALICE_TOKEN"
KEY="$(python3 -c 'import uuid; print(uuid.uuid4())')"
PAYLOAD='{"restaurant_id":"rest_bella_napoli","delivery_address":"12 Lake Road, Bengaluru","items":[{"menu_item_id":"item_margherita_pizza","quantity":2},{"menu_item_id":"item_garlic_bread","quantity":1}]}'

queue_total() { # messages waiting in the four PRODUCTION business queues
  docker compose exec -T rabbitmq rabbitmqctl list_queues --quiet name messages 2>/dev/null |
    awk -v re="$PROD_QUEUE_RE" '$1 ~ re {s += $2} END {print s+0}'
}

quiesce() { # wait for in-flight demo chains to finish (max 120s)
  local i
  for i in $(seq 1 60); do
    [ "$(queue_total)" -eq 0 ] && return 0
    sleep 2
  done
  echo "WARNING: business queues did not drain within 120s" >&2
  return 1
}

wait_status() { # order_id token target_status [timeout_s] -> echoes final status
  local id="$1" tok="$2" want="$3" deadline status=""
  deadline=$(( $(date +%s) + ${4:-120} ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    status="$(curl -s "$BASE/api/v1/orders/$id" -H "Authorization: Bearer $tok" |
      python3 -c 'import sys,json; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || true)"
    [ "$status" = "$want" ] && { echo "$status"; return 0; }
    sleep 1
  done
  echo "$status"
  return 1
}

wait_healthy() { # container service -> echoes health status (bounded 60s)
  local cid h="starting"
  cid="$(docker compose ps -q "$1")"
  for _ in $(seq 1 60); do
    h="$(docker inspect --format '{{.State.Health.Status}}' "$cid" 2>/dev/null || echo starting)"
    [ "$h" = "healthy" ] && break
    sleep 1
  done
  echo "$h"
}

# ---- 0. settle in-flight chains (fresh stack may still be flushing) --------
quiesce || true

# ---- 1. full migration cycle (M3 adds NO migration: 0001 stays head) -------
{
  echo "\$ docker compose stop $PIPELINE   # pipeline stopped around schema changes"
  # shellcheck disable=SC2086
  docker compose stop $PIPELINE
  echo
  echo '$ docker compose run --rm api sh -c "alembic downgrade base && alembic upgrade head"'
  docker compose run --rm api sh -c "alembic downgrade base && alembic upgrade head" 2>&1 |
    grep -E "Running downgrade|Running upgrade|Can't locate|ERROR" || true
  echo
  echo '$ docker compose run --rm api sh -c "alembic heads && alembic current"   # single head: no M3 migration'
  docker compose run --rm api sh -c "alembic heads && alembic current" 2>&1 |
    grep -E "0001|head|None" || true
  echo
  echo '$ docker compose run --rm seed'
  docker compose run --rm seed 2>&1 | tail -1
  echo
  echo "\$ docker compose start $PIPELINE"
  # shellcheck disable=SC2086
  docker compose start $PIPELINE
} > "$EV/00_migrations_cycle.txt" 2>&1
sleep 3

# ---- 2. service health + topology-init gating -----------------------------
{
  echo '$ docker compose ps -a   # topology-init / migrate / seed exited (0) gate the rest'
  docker compose ps -a
  echo
  echo '$ curl /health/live'
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/health/live"
  echo '$ curl /health/ready'
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/health/ready"
  echo
  echo '$ docker compose logs topology-init | tail -3'
  docker compose logs topology-init 2>&1 | tail -3
} > "$EV/01_service_health.txt"

# ---- 3. LIVE worker-driven chain: PENDING -> DRIVER_ASSIGNED ---------------
{
  echo "1) POST /api/v1/orders (202 + Location + idempotent body)"
  curl -s -i -X POST "$BASE/api/v1/orders" \
    -H "$AUTH" -H "Idempotency-Key: $KEY" -H "Content-Type: application/json" \
    -H "X-Request-ID: req_m3_live_demo" -d "$PAYLOAD"
  echo
} > "$EV/02_live_worker_chain.txt"
ORDER_ID="$(grep -o 'order_[a-f0-9]\{32\}' "$EV/02_live_worker_chain.txt" | head -1)"

{
  echo
  echo "2) polling GET /api/v1/orders/$ORDER_ID until DRIVER_ASSIGNED (no API writes after checkout)"
  START="$(date +%s)"
  STATUS="$(wait_status "$ORDER_ID" "$ALICE_TOKEN" DRIVER_ASSIGNED 120 || true)"
  END="$(date +%s)"
  echo "final status: $STATUS   elapsed: $((END - START))s"
  [ "$STATUS" = "DRIVER_ASSIGNED" ] || { echo "FAIL: chain did not complete"; exit 1; }
  echo
  echo "3) GET /api/v1/orders/$ORDER_ID/history (owner)"
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/api/v1/orders/$ORDER_ID/history" -H "$AUTH"
  echo
  echo "4) GET /api/v1/orders/$ORDER_ID/notifications (NEW in M3, owner)"
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/api/v1/orders/$ORDER_ID/notifications" -H "$AUTH"
  echo
  echo "5) same notifications as ANOTHER customer -> 404 (no existence leak)"
  curl -s -o /dev/null -w "HTTP %{http_code}\n" "$BASE/api/v1/orders/$ORDER_ID/notifications" \
    -H "Authorization: Bearer $BOB_TOKEN"
  echo "6) same notifications as admin -> 200"
  curl -s -o /dev/null -w "HTTP %{http_code}\n" "$BASE/api/v1/orders/$ORDER_ID/notifications" \
    -H "Authorization: Bearer $ADMIN_TOKEN"
  echo
  echo "7) pagination: page=2&page_size=3 -> only entry 4"
  curl -s "$BASE/api/v1/orders/$ORDER_ID/notifications?page=2&page_size=3" -H "$AUTH"
  echo
} >> "$EV/02_live_worker_chain.txt"

# ---- 4. database state for that chain -------------------------------------
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' <<SQL > "$EV/03_db_state_chain.txt"
select event_id, event_type, routing_key, state, attempts
from outbox_events where order_id = '$ORDER_ID' order by id;
select jsonb_pretty(payload::jsonb) as event_envelope
from outbox_events where order_id = '$ORDER_ID' and event_type = 'order.driver.assigned';
select version, from_status, status, failure_code, source
from order_status_history where order_id = '$ORDER_ID' order by version;
select consumer_name, event_id, outcome from processed_events
where order_id = '$ORDER_ID' order by consumer_name;
select seq, type, left(message, 60) as message from notifications
where order_id = '$ORDER_ID' order by seq;
SQL

# ---- 5. broker topology: exchanges, bindings, queues, consumers ------------
{
  echo '$ rabbitmqctl list_exchanges -q name type | grep quickbite   # production names only'
  docker compose exec -T rabbitmq rabbitmqctl list_exchanges -q name type | grep -E '^quickbite\.'
  echo
  echo '$ rabbitmqctl list_bindings -q source_name destination_name routing_key | grep ^quickbite'
  docker compose exec -T rabbitmq rabbitmqctl list_bindings -q source_name destination_name routing_key |
    grep -E '^quickbite\.'
  echo
  echo '$ rabbitmqctl list_queues -q name messages consumers | <production queues only>'
  docker compose exec -T rabbitmq rabbitmqctl list_queues -q name messages consumers |
    awk -v re="$PROD_QUEUE_RE" '$1 ~ re'
  echo
  echo '$ rabbitmqctl list_consumers -q queue_name consumer_tag channel_pid prefetch_count ack_required active | <production queues only>'
  docker compose exec -T rabbitmq rabbitmqctl list_consumers -q queue_name consumer_tag channel_pid prefetch_count ack_required active |
    awk -v re="$PROD_QUEUE_RE" '$1 ~ re'
} > "$EV/04_broker_topology.txt"

# ---- 6. physical broker restart: committed events are NEVER lost -----------
OUTAGE_KEY="$(python3 -c 'import uuid; print(uuid.uuid4())')"
{
  echo '1) docker compose stop rabbitmq'
  docker compose stop rabbitmq
  echo
  echo '2) readiness during the outage (200 "degraded": PostgreSQL gates, RabbitMQ reported)'
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/health/ready"
  echo
  echo "3) POST /api/v1/orders during the outage -> still 202, event committed to PostgreSQL only"
} > "$EV/05_broker_restart_no_loss.txt" 2>&1
curl -s -i -X POST "$BASE/api/v1/orders" \
  -H "$AUTH" -H "Idempotency-Key: $OUTAGE_KEY" -H "Content-Type: application/json" \
  -H "X-Request-ID: req_m3_broker_restart" -d "$PAYLOAD" >> "$EV/05_broker_restart_no_loss.txt" 2>&1
OUTAGE_ORDER="$(grep -o 'order_[a-f0-9]\{32\}' "$EV/05_broker_restart_no_loss.txt" | head -1)"

{
  echo
  echo "4) outbox rows while the broker is DOWN (order $OUTAGE_ORDER: PENDING/CLAIMED, never SENT)"
  docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At' \
    <<<"select event_type || ' | state=' || state || ' | attempts=' || attempts from outbox_events where order_id = '$OUTAGE_ORDER' order by id;"
  echo
  echo '5) dispatcher log during the outage (row stays eligible; bounded cycle backoff)'
  docker compose logs --tail 12 outbox-dispatcher 2>&1
  echo
  sleep 8
  echo '6) docker compose start rabbitmq  (waiting for the healthcheck)'
  docker compose start rabbitmq
  echo "rabbitmq health: $(wait_healthy rabbitmq)"
  sleep 2
  echo
  echo "7) polling GET /api/v1/orders/$OUTAGE_ORDER until DRIVER_ASSIGNED after the restart"
  STATUS="$(wait_status "$OUTAGE_ORDER" "$ALICE_TOKEN" DRIVER_ASSIGNED 180 || true)"
  echo "final status: $STATUS"
  [ "$STATUS" = "DRIVER_ASSIGNED" ] || { echo "FAIL: chain did not resume after broker restart"; exit 1; }
  echo
  echo "8) outbox rows after recovery (all SENT; attempts > 1 proves failed attempts were retried)"
  docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
    <<<"select event_type, state, attempts, left(coalesce(last_error,''),60) as last_error from outbox_events where order_id = '$OUTAGE_ORDER' order by id;"
  echo
  echo "9) worker reconnect + processing logs"
  docker compose logs --tail 15 payment-worker 2>&1
} >> "$EV/05_broker_restart_no_loss.txt" 2>&1

# ---- 7. structured logs from every pipeline component ----------------------
{
  echo '$ docker compose logs --tail 60 outbox-dispatcher'
  docker compose logs --tail 60 outbox-dispatcher 2>&1
  echo
  for w in payment-worker restaurant-worker delivery-worker notification-worker; do
    echo "\$ docker compose logs --tail 40 $w"
    docker compose logs --tail 40 "$w" 2>&1
    echo
  done
} > "$EV/06_pipeline_structured_logs.txt"

# ---- 8. automated acceptance evidence --------------------------------------
docker compose run --rm api pytest -q 2>&1 | tee "$EV/07_pytest_full.txt" | tail -2
{
  docker compose run --rm api ruff check . 2>&1 | tail -2
  docker compose run --rm api ruff format --check . 2>&1 | tail -1
} > "$EV/08_ruff.txt"

# ---- 9. exported API contract (notifications endpoint included) ------------
docker compose run --rm api python -m scripts.export_openapi > docs/openapi.json

echo "Evidence written to $EV/"
