#!/usr/bin/env bash
# Reproducible Milestone 4 evidence capture (assignment §11-§16, §20).
#
# Prerequisites (from the repository root):
#   docker compose build api && docker compose up -d && docker compose run --rm seed
#
# Runs every M4 acceptance scenario against the LIVE stack (production queue
# and exchange names, DEFAULT 2s/10s/30s retry schedule) and stores raw output
# under docs/evidence/m4/. Access tokens are used in flight only and are NEVER
# written to any evidence file (assignment §16).
#
# Failure controls come ONLY from worker process environments through the
# reviewed overrides in scripts/crash-overrides/ (assignment §12) — never from
# checkout/API fields. Crash checkpoints are REAL process deaths (os._exit
# 71/72/70/73) and REAL signals (docker compose kill = SIGKILL,
# docker compose stop = SIGTERM).
#
# Operational procedure: each override scenario recreates the targeted service
# in BASE configuration afterwards; the EXIT trap restores every pipeline
# service and restarts the broker no matter where the script stops.
set -euo pipefail

BASE="http://127.0.0.1:8000"
EV="docs/evidence/m4"
OV="scripts/crash-overrides"
PIPELINE="outbox-dispatcher retry-scheduler payment-worker restaurant-worker delivery-worker notification-worker"
PROD_QUEUE_RE='^(payment\.queue|restaurant\.queue|delivery\.queue|notification\.queue|orders\.dead-letter\.queue)$'
mkdir -p "$EV"

login() { # email password -> access_token on stdout (never stored)
  local body
  body="$(curl -s -X POST "$BASE/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}")" ||
    fail "login request to $BASE failed"
  printf '%s' "$body" |
    python3 -c 'import sys, json; print(json.load(sys.stdin)["access_token"])' ||
    fail "login response was not a token: ${body:0:300}"
}

wait_api() { # bounded wait until the API actually accepts requests
  local deadline=$(($(date +%s) + 90)) code="000"
  while [ "$(date +%s)" -lt "$deadline" ]; do
    code="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/health/ready" || true)"
    [ "$code" = "200" ] && return 0
    sleep 1
  done
  fail "API not ready within 90s (last health/ready code: $code)"
}

refresh_tokens() { # JWTs expire after 1800s; re-login between step groups
  ALICE_TOKEN="$(login alice@quickbite.dev 'quickbite!alice1')"
  BOB_TOKEN="$(login bob@quickbite.dev 'quickbite!bob1')"
  ADMIN_TOKEN="$(login admin@quickbite.dev 'quickbite!admin1')"
  AUTH="Authorization: Bearer $ALICE_TOKEN"
}

cleanup() {
  docker compose start rabbitmq >/dev/null 2>&1 || true
  # shellcheck disable=SC2086
  docker compose up -d --force-recreate $PIPELINE >/dev/null 2>&1 || true
}
trap cleanup EXIT

KEY="$(python3 -c 'import uuid; print(uuid.uuid4())')"
PAYLOAD='{"restaurant_id":"rest_bella_napoli","delivery_address":"12 Lake Road, Bengaluru","items":[{"menu_item_id":"item_margherita_pizza","quantity":2},{"menu_item_id":"item_garlic_bread","quantity":1}]}'

fail() { # hard stop; the EXIT trap restores the stack
  echo "FAIL: $*" >&2
  exit 1
}

expect() { # description actual expected
  if [ "$2" = "$3" ]; then
    echo "PASS: $1 = $2"
  else
    fail "$1 = '$2' (expected '$3')"
  fi
}

psql_q() { # SQL -> pipe-separated single-line rows (no headers)
  docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -F" | "' <<<"$1"
}

place_order() { # $1=idempotency-key $2=response-file -> echoes new order id
  curl -s -i -X POST "$BASE/api/v1/orders" \
    -H "$AUTH" -H "Idempotency-Key: $1" -H "Content-Type: application/json" \
    -H "X-Request-ID: req_m4_$(printf '%s' "$1" | cut -c1-12)" -d "$PAYLOAD" >"$2"
  grep -o 'order_[a-f0-9]\{32\}' "$2" | head -1
}

recreate() { # $1=override file (under scripts/crash-overrides) $2...=services
  local file="$1"
  shift
  docker compose -f compose.yaml -f "$OV/$file" up -d --force-recreate "$@" >/dev/null
}

restore() { # services back to BASE configuration
  docker compose up -d --force-recreate "$@" >/dev/null
}

wait_exit() { # $1=service -> echoes exit code once it stops (bounded 60s)
  local cid deadline
  cid="$(docker compose ps -aq "$1" | tail -1)"
  deadline=$(($(date +%s) + 60))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if [ "$(docker inspect --format '{{.State.Running}}' "$cid" 2>/dev/null || echo true)" = "false" ]; then
      docker inspect --format '{{.State.ExitCode}}' "$cid"
      return 0
    fi
    sleep 1
  done
  echo "timeout"
  return 1
}

wait_status() { # order_id token target [timeout] -> echoes final status
  local id="$1" tok="$2" want="$3" deadline status=""
  deadline=$(($(date +%s) + ${4:-120}))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    status="$(curl -s "$BASE/api/v1/orders/$id" -H "Authorization: Bearer $tok" |
      python3 -c 'import sys,json; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || true)"
    [ "$status" = "$want" ] && { echo "$status"; return 0; }
    sleep 1
  done
  echo "$status"
  return 1
}

wait_healthy() { # service -> health status (bounded 60s)
  local cid h="starting"
  cid="$(docker compose ps -q "$1")"
  for _ in $(seq 1 60); do
    h="$(docker inspect --format '{{.State.Health.Status}}' "$cid" 2>/dev/null || echo starting)"
    [ "$h" = "healthy" ] && break
    sleep 1
  done
  echo "$h"
}

wait_for() { # SQL expected-value timeout -> polls once per second
  local deadline=$(($(date +%s) + ${3:-60}))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    [ "$(psql_q "$1")" = "$2" ] && return 0
    sleep 1
  done
  return 1
}

queue_total() { # messages waiting in the four PRODUCTION business queues
  docker compose exec -T rabbitmq rabbitmqctl list_queues --quiet name messages 2>/dev/null |
    awk -v re="$PROD_QUEUE_RE" '$1 ~ re && $1 !~ /dead-letter/ {s += $2} END {print s+0}'
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

RESP="$(mktemp)"
wait_api     # the stack may have just been (re)created; logins come after this
refresh_tokens

# ---- 0. settle, then full migration cycle (M4 adds 0002) -------------------
quiesce || true
{
  echo "\$ docker compose stop $PIPELINE   # pipeline stopped around schema changes"
  # shellcheck disable=SC2086
  docker compose stop $PIPELINE
  echo
  echo '$ docker compose run --rm api sh -c "alembic downgrade base && alembic upgrade head"'
  docker compose run --rm api sh -c "alembic downgrade base && alembic upgrade head" 2>&1 |
    grep -E "Running downgrade|Running upgrade|ERROR" || true
  echo
  echo '$ docker compose run --rm api sh -c "alembic heads && alembic current"   # single head'
  docker compose run --rm api sh -c "alembic heads && alembic current" 2>&1 |
    grep -E "0001|0002|head|None" || true
  echo
  echo '$ docker compose run --rm seed'
  docker compose run --rm seed 2>&1 | tail -1
  echo
  echo "\$ docker compose start $PIPELINE"
  # shellcheck disable=SC2086
  docker compose start $PIPELINE
} >"$EV/00_migrations_cycle.txt" 2>&1
sleep 3
refresh_tokens # migration cycle recreated the demo users

# ---- 1. service health + retry-scheduler gating ----------------------------
{
  echo '$ docker compose ps -a   # retry-scheduler added in M4'
  docker compose ps -a
  echo
  echo '$ curl /health/live'
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/health/live"
  echo '$ curl /health/ready'
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/health/ready"
  echo
  echo '$ docker compose logs --tail 10 retry-scheduler'
  docker compose logs --tail 10 retry-scheduler 2>&1
} >"$EV/01_service_health.txt"

# ---- 2. live happy chain PENDING -> DRIVER_ASSIGNED ------------------------
{
  echo "1) POST /api/v1/orders (202 + Location + idempotent body)"
  ORDER_ID="$(place_order "$KEY" "$RESP")"
  cat "$RESP"
  echo
  echo "order: $ORDER_ID"
  echo "2) polling GET until DRIVER_ASSIGNED (no API writes after checkout)"
  START="$(date +%s)"
  STATUS="$(wait_status "$ORDER_ID" "$ALICE_TOKEN" DRIVER_ASSIGNED 120 || true)"
  END="$(date +%s)"
  echo "final status: $STATUS   elapsed: $((END - START))s"
  [ "$STATUS" = "DRIVER_ASSIGNED" ] || fail "happy chain did not complete"
  echo
  echo "3) GET history (owner)"
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/api/v1/orders/$ORDER_ID/history" -H "$AUTH"
  echo "4) GET notifications (owner)"
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/api/v1/orders/$ORDER_ID/notifications" -H "$AUTH"
  echo "5) notifications as ANOTHER customer -> 404, as admin -> 200"
  curl -s -o /dev/null -w "HTTP %{http_code}\n" "$BASE/api/v1/orders/$ORDER_ID/notifications" \
    -H "Authorization: Bearer $BOB_TOKEN"
  curl -s -o /dev/null -w "HTTP %{http_code}\n" "$BASE/api/v1/orders/$ORDER_ID/notifications" \
    -H "Authorization: Bearer $ADMIN_TOKEN"
  echo
  echo "6) retry/quarantine tables EMPTY on the happy path"
  echo "retry_jobs:    $(psql_q "SELECT count(*) FROM retry_jobs WHERE order_id='$ORDER_ID'")"
  echo "quarantine:    $(psql_q "SELECT count(*) FROM quarantine_records WHERE order_id='$ORDER_ID'")"
} >"$EV/02_live_worker_chain.txt"

# ---- 3. database state for that chain --------------------------------------
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' <<SQL >"$EV/03_db_state_chain.txt"
select event_id, event_type, exchange, routing_key, state, attempts
from outbox_events where order_id = '$ORDER_ID' order by id;
select version, from_status, status, failure_code, source
from order_status_history where order_id = '$ORDER_ID' order by version;
select consumer_name, event_id, outcome from processed_events
where order_id = '$ORDER_ID' order by consumer_name;
select seq, type, left(message, 60) as message from notifications
where order_id = '$ORDER_ID' order by seq;
select consumer_name, attempt, state, due_at - created_at as scheduled_after
from retry_jobs where order_id = '$ORDER_ID' order by attempt;
select consumer_name, failure_code from quarantine_records
where order_id = '$ORDER_ID';
SQL

# ---- 4. broker topology incl. dead-letter path + management UI -------------
{
  echo '$ rabbitmqctl list_exchanges -q name type | grep quickbite   # production names only'
  docker compose exec -T rabbitmq rabbitmqctl list_exchanges -q name type | grep -E '^quickbite\.'
  echo
  echo '$ rabbitmqctl list_bindings -q source_name destination_name routing_key | grep ^quickbite'
  docker compose exec -T rabbitmq rabbitmqctl list_bindings -q source_name destination_name routing_key |
    grep -E '^quickbite\.'
  echo
  echo '# dead-letter path: quarantine publications route quickbite.dead/failed -> orders.dead-letter.queue'
  docker compose exec -T rabbitmq rabbitmqctl list_bindings -q source_name destination_name routing_key |
    grep -E 'dead' || true
  echo
  echo '$ rabbitmqctl list_queues -q name messages consumers | <production queues only>'
  docker compose exec -T rabbitmq rabbitmqctl list_queues -q name messages consumers |
    awk -v re="$PROD_QUEUE_RE" '$1 ~ re'
  echo
  echo '$ rabbitmqctl list_consumers -q queue_name consumer_tag channel_pid prefetch_count ack_required active | <production queues>'
  docker compose exec -T rabbitmq rabbitmqctl list_consumers -q queue_name consumer_tag channel_pid prefetch_count ack_required active |
    awk -v re="$PROD_QUEUE_RE" '$1 ~ re'
  echo
  echo "# RabbitMQ management UI (kept in M4): http://127.0.0.1:15672"
} >"$EV/04_broker_topology.txt"

# ---- 5. control: fail_twice -> durable retries, then success ---------------
refresh_tokens
recreate payment_fail_twice.yaml payment-worker
{
  echo "PAYMENT_MODE=fail_twice via $OV/payment_fail_twice.yaml"
  echo "expect: attempt 1 + 2 transient failures (durable retries), attempt 3 success"
  echo
  echo "1) place order"
  KEY5="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  ORDER5="$(place_order "$KEY5" "$RESP")"
  cat "$RESP"
  echo "order: $ORDER5"
  echo
  echo "2) poll until DRIVER_ASSIGNED"
  START="$(date +%s)"
  STATUS="$(wait_status "$ORDER5" "$ALICE_TOKEN" DRIVER_ASSIGNED 90 || true)"
  END="$(date +%s)"
  echo "final status: $STATUS   elapsed: $((END - START))s (includes the 2s + 10s schedule)"
  [ "$STATUS" = "DRIVER_ASSIGNED" ] || fail "fail_twice chain did not complete"
  echo
  echo "3) retry ladder: attempts 2 and 3, scheduled 2s/10s after their failure"
  psql_q "select attempt || ' | state=' || state || ' | created=' || created_at ||
          ' | due=' || due_at || ' | scheduled_after=' || (due_at - created_at)
          from retry_jobs where order_id = '$ORDER5' and consumer_name = 'payment' order by attempt"
  echo
  echo "4) targeted retry publications (default exchange '', routing key = payment.queue ONLY)"
  psql_q "select id || ' | exchange=' || coalesce(nullif(exchange, ''), '<default>') ||
          ' | rk=' || routing_key || ' | state=' || state || ' | event=' || event_id
          from outbox_events where order_id = '$ORDER5' order by id"
  echo
  echo "5) business outcome: one payment, ordered history, no quarantine"
  echo "payments:   $(psql_q "select string_agg(status, ',') from simulated_payments where order_id='$ORDER5'")"
  echo "history:    $(psql_q "select string_agg(version::text, ',' order by version) from order_status_history where order_id='$ORDER5'")"
  echo "quarantine: $(psql_q "select count(*) from quarantine_records where order_id='$ORDER5'")"
} >"$EV/05_payment_fail_twice.txt"
restore payment-worker
quiesce || true

# ---- 6. control: always_decline -> terminal, NO retry churn ----------------
recreate payment_always_decline.yaml payment-worker
{
  echo "PAYMENT_MODE=always_decline via $OV/payment_always_decline.yaml"
  echo "expect: immediate PAYMENT_FAILED/PAYMENT_DECLINED, retry ladder bypassed"
  echo
  KEY6="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  ORDER6="$(place_order "$KEY6" "$RESP")"
  cat "$RESP"
  echo "order: $ORDER6"
  STATUS="$(wait_status "$ORDER6" "$ALICE_TOKEN" PAYMENT_FAILED 60 || true)"
  echo "final status: $STATUS"
  [ "$STATUS" = "PAYMENT_FAILED" ] || fail "decline did not reach PAYMENT_FAILED"
  echo
  echo "order:      $(psql_q "select status || ' / ' || failure_code || ' / v' || version from orders where id='$ORDER6'")"
  echo "history:    $(psql_q "select string_agg(version::text || ':' || status, ' -> ' order by version) from order_status_history where order_id='$ORDER6'")"
  echo "payments:   $(psql_q "select status || ' / ' || failure_code from simulated_payments where order_id='$ORDER6'")"
  echo "retry_jobs: $(psql_q "select count(*) from retry_jobs where order_id='$ORDER6'")   (expect 0: permanent decline never enters the ladder)"
  echo "quarantine: $(psql_q "select count(*) from quarantine_records where order_id='$ORDER6'")   (expect 0)"
  echo
  echo "worker log (terminal path):"
  docker compose logs --tail 8 payment-worker 2>&1
} >"$EV/06_payment_decline_terminal.txt"
restore payment-worker
quiesce || true

# ---- 7. control: always_fail -> DEFAULT 2s/10s/30s ladder + quarantine -----
recreate payment_always_fail.yaml payment-worker
{
  echo "PAYMENT_MODE=always_fail via $OV/payment_always_fail.yaml"
  echo "expect: 1 initial + 3 retries at 2s/10s/30s (DEFAULT schedule) ->"
  echo "        PAYMENT_FAILED/PAYMENT_RETRIES_EXHAUSTED + ONE quarantine record"
  echo
  KEY7="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  ORDER7="$(place_order "$KEY7" "$RESP")"
  cat "$RESP"
  echo "order: $ORDER7"
  echo
  echo "1) poll until terminal PAYMENT_FAILED (wall clock includes the full ladder)"
  START="$(date +%s)"
  STATUS="$(wait_status "$ORDER7" "$ALICE_TOKEN" PAYMENT_FAILED 150 || true)"
  END="$(date +%s)"
  ELAPSED=$((END - START))
  echo "final status: $STATUS   elapsed: ${ELAPSED}s (expect ~42s = 2+10+30 plus dispatcher/scheduler ticks)"
  [ "$STATUS" = "PAYMENT_FAILED" ] || fail "exhaustion did not reach PAYMENT_FAILED"
  if [ "$ELAPSED" -ge 40 ] && [ "$ELAPSED" -le 120 ]; then
    echo "PASS: ladder wall time within [40,120]s"
  else
    fail "ladder wall time ${ELAPSED}s outside [40,120]s"
  fi
  echo
  echo "2) retry ladder (scheduled_after proves the DEFAULT 2s/10s/30s policy)"
  psql_q "select attempt || ' | state=' || state || ' | created=' || created_at ||
          ' | due=' || due_at || ' | scheduled_after=' || (due_at - created_at)
          from retry_jobs where order_id = '$ORDER7' and consumer_name = 'payment' order by attempt"
  # Tolerance: created_at uses a Python-side clock (sub-ms skew vs due_at).
  expect "attempt 2 scheduled ~2s" \
    "$(psql_q "select count(*) from retry_jobs where order_id='$ORDER7' and attempt=2 and (due_at - created_at) between interval '1.9 seconds' and interval '2.1 seconds'")" "1"
  expect "attempt 3 scheduled ~10s" \
    "$(psql_q "select count(*) from retry_jobs where order_id='$ORDER7' and attempt=3 and (due_at - created_at) between interval '9.9 seconds' and interval '10.1 seconds'")" "1"
  expect "attempt 4 scheduled ~30s" \
    "$(psql_q "select count(*) from retry_jobs where order_id='$ORDER7' and attempt=4 and (due_at - created_at) between interval '29.9 seconds' and interval '30.1 seconds'")" "1"
  expect "ladder exhausted (EXHAUSTED)" \
    "$(psql_q "select state from retry_jobs where order_id='$ORDER7' and attempt=4")" "EXHAUSTED"
  echo
  echo "3) terminal transition + failure code"
  echo "order:   $(psql_q "select status || ' / ' || failure_code || ' / v' || version from orders where id='$ORDER7'")"
  echo "history: $(psql_q "select string_agg(version::text || ':' || status, ' -> ' order by version) from order_status_history where order_id='$ORDER7'")"
  echo "payment: $(psql_q "select status || ' / ' || failure_code from simulated_payments where order_id='$ORDER7'")"
  echo
  echo "4) ONE durable quarantine record + its dead-letter publication"
  psql_q "select consumer_name || ' | ' || coalesce(envelope->>'event_type', 'malformed') ||
          ' | code=' || failure_code || ' | attempts=' || attempts || ' | event=' || event_id
          from quarantine_records where order_id = '$ORDER7'"
  psql_q "select id || ' | exchange=' || exchange || ' | rk=' || routing_key || ' | state=' || state
          from outbox_events where order_id = '$ORDER7' and routing_key = 'failed'"
  sleep 2   # let the dispatcher publish the dead publication before sampling depth
  echo "dead-letter queue depth: $(docker compose exec -T rabbitmq rabbitmqctl list_queues --quiet name messages 2>/dev/null | awk '$1=="orders.dead-letter.queue"{print $2+0}')"
  echo
  echo "5) scheduler activation + dead publication logs"
  docker compose logs --tail 8 retry-scheduler 2>&1
  docker compose logs --tail 6 outbox-dispatcher 2>&1
  echo
  echo "6) ladder duration inside the database (first failure -> quarantine):"
  psql_q "select (select min(created_at) from retry_jobs where order_id='$ORDER7') as first_failure,
                 (select created_at from quarantine_records where order_id='$ORDER7') as quarantined_at,
                 (select created_at from quarantine_records where order_id='$ORDER7')
               - (select min(created_at) from retry_jobs where order_id='$ORDER7') as ladder_duration"
} >"$EV/07_payment_exhaust_default_timing.txt"
restore payment-worker
quiesce || true

# ---- 8. terminal business failures (restaurant / delivery / notification) --
refresh_tokens
{
  echo "=== RESTAURANT_MODE=always_fail (permanent rejection, no retries) ==="
  recreate restaurant_always_fail.yaml restaurant-worker
  KEY8="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  ORDER8="$(place_order "$KEY8" "$RESP")"
  cat "$RESP"
  echo "order: $ORDER8"
  STATUS="$(wait_status "$ORDER8" "$ALICE_TOKEN" FAILED 90 || true)"
  echo "final status: $STATUS"
  [ "$STATUS" = "FAILED" ] || fail "restaurant rejection did not reach FAILED"
  echo "order:      $(psql_q "select status || ' / ' || failure_code from orders where id='$ORDER8'")"
  echo "history:    $(psql_q "select string_agg(version::text || ':' || status, ' -> ' order by version) from order_status_history where order_id='$ORDER8'")"
  echo "retry_jobs: $(psql_q "select count(*) from retry_jobs where order_id='$ORDER8'")   (expect 0)"
  echo "quarantine: $(psql_q "select count(*) from quarantine_records where order_id='$ORDER8'")   (expect 0)"
  restore restaurant-worker
  quiesce || true
  echo

  echo "=== DELIVERY_MODE=always_fail (permanent failure, no assignment) ==="
  recreate delivery_always_fail.yaml delivery-worker
  KEY9="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  ORDER9="$(place_order "$KEY9" "$RESP")"
  cat "$RESP"
  echo "order: $ORDER9"
  STATUS="$(wait_status "$ORDER9" "$ALICE_TOKEN" FAILED 90 || true)"
  echo "final status: $STATUS"
  [ "$STATUS" = "FAILED" ] || fail "delivery failure did not reach FAILED"
  echo "order:       $(psql_q "select status || ' / ' || failure_code from orders where id='$ORDER9'")"
  echo "history:     $(psql_q "select string_agg(version::text || ':' || status, ' -> ' order by version) from order_status_history where order_id='$ORDER9'")"
  echo "assignments: $(psql_q "select count(*) from driver_assignments where order_id='$ORDER9'")   (expect 0)"
  echo "retry_jobs:  $(psql_q "select count(*) from retry_jobs where order_id='$ORDER9'")   (expect 0)"
  echo "quarantine:  $(psql_q "select count(*) from quarantine_records where order_id='$ORDER9'")   (expect 0)"
  restore delivery-worker
  quiesce || true
  echo

  echo "=== NOTIFICATION_MODE=always_fail (order status must NEVER change) ==="
  recreate notification_always_fail.yaml notification-worker
  KEY10="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  ORDER10="$(place_order "$KEY10" "$RESP")"
  cat "$RESP"
  echo "order: $ORDER10"
  STATUS="$(wait_status "$ORDER10" "$ALICE_TOKEN" DRIVER_ASSIGNED 120 || true)"
  echo "business chain final status: $STATUS (notifications failing independently)"
  [ "$STATUS" = "DRIVER_ASSIGNED" ] || fail "notification failures changed the chain outcome"
  echo "waiting for all FOUR chain events to exhaust their notification ladders (~45s)..."
  wait_for "select count(*) from quarantine_records where order_id='$ORDER10' and consumer_name='notification'" "4" 180 ||
    fail "notification ladders did not exhaust to 4 quarantines"
  echo "order:        $(psql_q "select status || ' / ' || coalesce(failure_code, 'NULL') from orders where id='$ORDER10'")"
  echo "history:      $(psql_q "select string_agg(version::text || ':' || status, ' -> ' order by version) from order_status_history where order_id='$ORDER10'")"
  echo "notifications:$(psql_q "select count(*) from notifications where order_id='$ORDER10'")   (expect 0)"
  echo "quarantines:  $(psql_q "select count(*) from quarantine_records where order_id='$ORDER10' and consumer_name='notification'")   (expect 4)"
  echo "ladder rows:  $(psql_q "select count(*) from retry_jobs where order_id='$ORDER10'")   (expect 4 events x 3 retries = 12)"
  psql_q "select consumer_name || ' | ' || coalesce(envelope->>'event_type', 'malformed') ||
          ' | code=' || failure_code || ' | attempts=' || attempts
          from quarantine_records where order_id = '$ORDER10' order by created_at"
  echo "exhausted markers: $(psql_q "select string_agg(outcome, ',' order by outcome) from processed_events where order_id='$ORDER10' and consumer_name='notification'")"
  restore notification-worker
  quiesce || true
} >"$EV/08_terminal_business_failures.txt"

# ---- 9. crash BEFORE commit (exit 71) ---------------------------------------
refresh_tokens
recreate payment_before_commit.yaml payment-worker
{
  echo "CRASH_POINT=before_commit via $OV/payment_before_commit.yaml (restart: no)"
  KEY11="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  ORDER11="$(place_order "$KEY11" "$RESP")"
  cat "$RESP"
  echo "order: $ORDER11"
  CODE="$(wait_exit payment-worker || true)"
  echo "payment-worker exit code: $CODE   (expect 71 = died INSIDE the transaction, before commit)"
  [ "$CODE" = "71" ] || fail "expected exit code 71, got $CODE"
  echo "crash log:"
  docker compose logs --tail 6 payment-worker 2>&1
  echo
  echo "BEFORE recovery — zero partial effects:"
  echo "order:      $(psql_q "select status || ' / v' || version from orders where id='$ORDER11'")   (expect PENDING / v1)"
  echo "payments:   $(psql_q "select count(*) from simulated_payments where order_id='$ORDER11'")   (expect 0)"
  echo "history:    $(psql_q "select string_agg(version::text, ',' order by version) from order_status_history where order_id='$ORDER11'")   (expect 1)"
  echo "markers(payment): $(psql_q "select count(*) from processed_events where order_id='$ORDER11' and consumer_name='payment'")   (expect 0 — no payment marker can survive the rollback; the notification consumer's own order.created marker is a separate, legitimate row)"
  echo "retry_jobs: $(psql_q "select count(*) from retry_jobs where order_id='$ORDER11'")   (expect 0)"
  echo "quarantine: $(psql_q "select count(*) from quarantine_records where order_id='$ORDER11'")   (expect 0)"
  echo
  echo "RECOVERY: docker compose up -d --force-recreate payment-worker (base config)"
  restore payment-worker
  STATUS="$(wait_status "$ORDER11" "$ALICE_TOKEN" DRIVER_ASSIGNED 120 || true)"
  echo "final status after redelivery: $STATUS"
  [ "$STATUS" = "DRIVER_ASSIGNED" ] || fail "pre-commit crash did not recover to completion"
  echo "AFTER recovery — exactly one committed effect:"
  echo "payments:   $(psql_q "select count(*) from simulated_payments where order_id='$ORDER11'")   (expect 1)"
  echo "history:    $(psql_q "select string_agg(version::text || ':' || status, ' -> ' order by version) from order_status_history where order_id='$ORDER11'")"
  echo "markers:    $(psql_q "select count(*) from processed_events where order_id='$ORDER11' and consumer_name='payment'")   (expect 1)"
  echo "quarantine: $(psql_q "select count(*) from quarantine_records where order_id='$ORDER11'")   (expect 0)"
} >"$EV/09_crash_before_commit.txt"
quiesce || true

# ---- 10. crash DURING retry persistence (exit 72) ---------------------------
recreate payment_during_retry_persistence.yaml payment-worker
{
  echo "CRASH_POINT=during_retry_persistence + PAYMENT_MODE=always_fail via"
  echo "$OV/payment_during_retry_persistence.yaml (restart: no)"
  KEY12="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  ORDER12="$(place_order "$KEY12" "$RESP")"
  cat "$RESP"
  echo "order: $ORDER12"
  CODE="$(wait_exit payment-worker || true)"
  echo "payment-worker exit code: $CODE   (expect 72 = died INSIDE the retry-persistence tx)"
  [ "$CODE" = "72" ] || fail "expected exit code 72, got $CODE"
  echo
  echo "BEFORE recovery — the persist transaction rolled back, the message was NEVER acked:"
  echo "retry_jobs: $(psql_q "select count(*) from retry_jobs where order_id='$ORDER12'")   (expect 0: rolled back with the crash)"
  echo "order:      $(psql_q "select status || ' / v' || version from orders where id='$ORDER12'")   (expect PENDING)"
  echo "outbox:     $(psql_q "select string_agg(event_type || ':' || state, ', ' order by id) from outbox_events where order_id='$ORDER12'")"
  echo "payment.queue depth (redelivery waiting): $(docker compose exec -T rabbitmq rabbitmqctl list_queues --quiet name messages 2>/dev/null | awk '$1=="payment.queue"{print $2+0}')"
  echo
  echo "RECOVERY: recreate with PAYMENT_MODE=always_fail only (crash point cleared)"
  recreate payment_always_fail.yaml payment-worker
  STATUS="$(wait_status "$ORDER12" "$ALICE_TOKEN" PAYMENT_FAILED 150 || true)"
  echo "final status: $STATUS"
  [ "$STATUS" = "PAYMENT_FAILED" ] || fail "retry-persistence crash did not resume to exhaustion"
  echo "ladder restarted from the redelivery and ran to completion:"
  psql_q "select attempt || ' | state=' || state || ' | scheduled_after=' || (due_at - created_at)
          from retry_jobs where order_id = '$ORDER12' and consumer_name = 'payment' order by attempt"
  expect "single ladder (no duplicates from the redelivery)" \
    "$(psql_q "select count(*) from retry_jobs where order_id='$ORDER12'")" "3"
  expect "quarantine recorded once" \
    "$(psql_q "select count(*) from quarantine_records where order_id='$ORDER12'")" "1"
  echo "order: $(psql_q "select status || ' / ' || failure_code from orders where id='$ORDER12'")"
} >"$EV/10_crash_during_retry_persistence.txt"
restore payment-worker
quiesce || true

# ---- 11. crash AFTER commit, BEFORE ack (exit 70) ---------------------------
recreate payment_after_checkpoint.yaml payment-worker
{
  echo "PAYMENT_MODE=crash_after_checkpoint via $OV/payment_after_checkpoint.yaml (restart: no)"
  echo "worker commits the payment, then dies BEFORE acknowledging (exit 70)"
  KEY13="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  ORDER13="$(place_order "$KEY13" "$RESP")"
  cat "$RESP"
  echo "order: $ORDER13"
  CODE="$(wait_exit payment-worker || true)"
  echo "payment-worker exit code: $CODE   (expect 70 = post-commit, pre-ack)"
  [ "$CODE" = "70" ] || fail "expected exit code 70, got $CODE"
  echo
  echo "BEFORE recovery — the effect IS committed (that is the double-processing window):"
  echo "payments:  $(psql_q "select count(*) from simulated_payments where order_id='$ORDER13'")   (expect 1: committed pre-crash)"
  echo "markers:   $(psql_q "select count(*) from processed_events where order_id='$ORDER13' and consumer_name='payment'")   (expect 1)"
  echo "history:   $(psql_q "select string_agg(version::text || ':' || status, ' -> ' order by version) from order_status_history where order_id='$ORDER13'")"
  echo "unacked copy returned to payment.queue depth: $(docker compose exec -T rabbitmq rabbitmqctl list_queues --quiet name messages 2>/dev/null | awk '$1=="payment.queue"{print $2+0}')"
  echo
  echo "RECOVERY: redelivery of the SAME delivery must deduplicate, not repeat"
  restore payment-worker
  STATUS="$(wait_status "$ORDER13" "$ALICE_TOKEN" DRIVER_ASSIGNED 120 || true)"
  echo "final status after redelivery: $STATUS"
  [ "$STATUS" = "DRIVER_ASSIGNED" ] || fail "post-commit crash did not recover to completion"
  echo "AFTER recovery — still exactly ONE effect:"
  echo "payments:   $(psql_q "select count(*) from simulated_payments where order_id='$ORDER13'")   (expect 1: never 2)"
  echo "markers:    $(psql_q "select count(*) from processed_events where order_id='$ORDER13' and consumer_name='payment'")   (expect 1)"
  echo "history:    $(psql_q "select string_agg(version::text || ':' || status, ' -> ' order by version) from order_status_history where order_id='$ORDER13'")"
  echo "quarantine: $(psql_q "select count(*) from quarantine_records where order_id='$ORDER13'")   (expect 0)"
} >"$EV/11_crash_after_checkpoint.txt"
quiesce || true

# ---- 12. dispatcher crash AFTER publish, BEFORE SENT (exit 73) -------------
recreate dispatcher_after_publish.yaml outbox-dispatcher
{
  echo "DISPATCHER_CRASH_AFTER_PUBLISH=true via $OV/dispatcher_after_publish.yaml (restart: no)"
  echo "dispatcher publishes a confirmed copy, then dies before marking SENT (exit 73)"
  KEY14="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  ORDER14="$(place_order "$KEY14" "$RESP")"
  cat "$RESP"
  echo "order: $ORDER14"
  CODE="$(wait_exit outbox-dispatcher || true)"
  echo "outbox-dispatcher exit code: $CODE   (expect 73)"
  [ "$CODE" = "73" ] || fail "expected exit code 73, got $CODE"
  echo
  echo "BEFORE recovery — row stuck mid-claim (published copy already delivered):"
  psql_q "select event_type || ' | state=' || state || ' | attempts=' || attempts ||
          ' | lease_expires=' || coalesce(lease_expires_at::text, '-')
          from outbox_events where order_id = '$ORDER14' order by id"
  echo
  echo "RECOVERY: dispatcher restart reclaims the expired lease (<=30s) and republishes;"
  echo "the consumer deduplicates the duplicate copy."
  restore outbox-dispatcher
  STATUS="$(wait_status "$ORDER14" "$ALICE_TOKEN" DRIVER_ASSIGNED 150 || true)"
  echo "final status: $STATUS"
  [ "$STATUS" = "DRIVER_ASSIGNED" ] || fail "dispatcher crash did not recover to completion"
  wait_for "select state from outbox_events where order_id='$ORDER14' and event_type='order.created'" "SENT" 90 ||
    fail "order.created row never reached SENT after recovery"
  echo
  echo "AFTER recovery:"
  psql_q "select event_type || ' | state=' || state || ' | attempts=' || attempts
          from outbox_events where order_id = '$ORDER14' order by id"
  echo "attempts>1 on order.created proves the crash-window row was RE-published, not lost"
  echo "payments: $(psql_q "select count(*) from simulated_payments where order_id='$ORDER14'")   (expect 1: duplicate copy deduplicated)"
  echo "payment markers: $(psql_q "select count(*) from processed_events where order_id='$ORDER14' and consumer_name='payment'")   (expect 1)"
  echo "quarantine: $(psql_q "select count(*) from quarantine_records where order_id='$ORDER14'")   (expect 0)"
} >"$EV/12_crash_after_publish.txt"
quiesce || true

# ---- 13. physical SIGKILL x3 mid-chain + graceful SIGTERM ------------------
refresh_tokens
recreate payment_fail_twice.yaml payment-worker
{
  echo "PHYSICAL KILLS: docker compose kill payment-worker (SIGKILL, real signal)"
  echo "x3 during a fail_twice chain, then restart — at-least-once delivery with"
  echo "a single committed business effect, wherever the kill lands."
  KEY15="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  ORDER15="$(place_order "$KEY15" "$RESP")"
  cat "$RESP"
  echo "order: $ORDER15"
  for i in 1 2 3; do
    sleep 0.5
    docker compose kill payment-worker 2>/dev/null || true
    echo "kill #$i sent at $(date -Is)  exit=$(docker inspect --format '{{.State.ExitCode}}' "$(docker compose ps -aq payment-worker | tail -1)" 2>/dev/null || echo '?')"
    sleep 0.3
    docker compose start payment-worker >/dev/null 2>&1 || true
    echo "restart #$i sent at $(date -Is)"
  done
  sleep 1
  STATUS="$(wait_status "$ORDER15" "$ALICE_TOKEN" DRIVER_ASSIGNED 120 || true)"
  echo "final status after three SIGKILLs: $STATUS"
  [ "$STATUS" = "DRIVER_ASSIGNED" ] || fail "chain did not survive three physical kills"
  echo "payments:   $(psql_q "select count(*) from simulated_payments where order_id='$ORDER15'")   (expect 1)"
  echo "history:    $(psql_q "select string_agg(version::text || ':' || status, ' -> ' order by version) from order_status_history where order_id='$ORDER15'")"
  echo "ladder:     $(psql_q "select string_agg(attempt::text, ',' order by attempt) from retry_jobs where order_id='$ORDER15'")   (expect 2,3)"
  echo "quarantine: $(psql_q "select count(*) from quarantine_records where order_id='$ORDER15'")   (expect 0)"
  echo
  echo "GRACEFUL STOP: docker compose stop payment-worker (SIGTERM) mid-flight"
  KEY16="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  ORDER16="$(place_order "$KEY16" "$RESP")"
  cat "$RESP"
  echo "order: $ORDER16"
  sleep 0.8
  docker compose stop payment-worker >/dev/null
  echo "exit code after SIGTERM: $(docker inspect --format '{{.State.ExitCode}}' "$(docker compose ps -aq payment-worker | tail -1)")   (expect 0 = bounded graceful shutdown)"
  echo "shutdown log:"
  docker compose logs payment-worker 2>&1 | grep -E "shutdown requested|in-flight" | tail -3 || true
  restore payment-worker
  STATUS="$(wait_status "$ORDER16" "$ALICE_TOKEN" DRIVER_ASSIGNED 120 || true)"
  echo "final status after graceful stop + restart: $STATUS"
  [ "$STATUS" = "DRIVER_ASSIGNED" ] || fail "chain did not survive graceful stop"
  echo "payments for that order: $(psql_q "select count(*) from simulated_payments where order_id='$ORDER16'")   (expect 1)"
} >"$EV/13_physical_kill_and_shutdown.txt"
restore payment-worker
quiesce || true

# ---- 14. broker DOWN with a pending retry -> zero loss ---------------------
recreate payment_always_fail.yaml payment-worker
{
  echo "BROKER OUTAGE during the retry window (PAYMENT_MODE=always_fail)"
  KEY17="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  ORDER17="$(place_order "$KEY17" "$RESP")"
  cat "$RESP"
  echo "order: $ORDER17"
  echo
  echo "1) wait until attempt 1 failed and its durable retry was scheduled"
  wait_for "select count(*) from retry_jobs where order_id='$ORDER17'" "1" 60 ||
    fail "retry job was not scheduled before the outage"
  echo "retry job exists; stopping the broker DURING the retry window"
  docker compose stop rabbitmq
  echo
  echo "2) readiness during the outage (PostgreSQL gates; RabbitMQ reported)"
  curl -s -w "\nHTTP %{http_code}\n" "$BASE/health/ready"
  echo "waiting 8s (past the due time of the pending retry) with the broker DOWN..."
  sleep 8
  echo
  echo "3) state during the outage — due work waits, never vanishes:"
  psql_q "select attempt || ' | state=' || state || ' | due=' || due_at || ' | now=' || now()
          from retry_jobs where order_id = '$ORDER17' order by attempt"
  echo "targeted outbox publication:"
  psql_q "select state || ' | attempts=' || attempts || ' | available_at=' || available_at ||
          ' | last_error=' || coalesce(left(last_error, 70), '-')
          from outbox_events where order_id = '$ORDER17' and exchange = ''"
  echo "dispatcher log (bounded publish backoff, row remains eligible):"
  docker compose logs --tail 6 outbox-dispatcher 2>&1
  echo "scheduler log (DB-only: keeps operating through broker downtime):"
  docker compose logs --tail 4 retry-scheduler 2>&1
  echo
  echo "4) restart the broker; the ladder resumes from where it stopped"
  docker compose start rabbitmq >/dev/null
  echo "rabbitmq health: $(wait_healthy rabbitmq)"
  STATUS="$(wait_status "$ORDER17" "$ALICE_TOKEN" PAYMENT_FAILED 180 || true)"
  echo "final status: $STATUS"
  [ "$STATUS" = "PAYMENT_FAILED" ] || fail "ladder did not resume after broker recovery"
  echo
  echo "5) AFTER recovery — schedule preserved, exhaustion + quarantine reached:"
  psql_q "select attempt || ' | state=' || state || ' | scheduled_after=' || (due_at - created_at)
          from retry_jobs where order_id = '$ORDER17' and consumer_name = 'payment' order by attempt"
  echo "order:      $(psql_q "select status || ' / ' || failure_code from orders where id='$ORDER17'")"
  echo "quarantine: $(psql_q "select count(*) from quarantine_records where order_id='$ORDER17'")   (expect 1)"
  echo "payments:   $(psql_q "select count(*) from simulated_payments where order_id='$ORDER17'")   (expect 1 FAILED record)"
  echo "outbox after recovery:"
  psql_q "select event_type || ' | ' || coalesce(nullif(exchange, ''), '<default>') || '/' || routing_key ||
          ' | ' || state || ' | attempts=' || attempts
          from outbox_events where order_id = '$ORDER17' order by id"
  echo "worker reconnect + retry logs:"
  docker compose logs --tail 12 payment-worker 2>&1
} >"$EV/14_broker_outage_pending_retries.txt"
restore payment-worker
quiesce || true

# ---- 15. structured logs from every M4 component ---------------------------
{
  for c in outbox-dispatcher retry-scheduler payment-worker restaurant-worker delivery-worker notification-worker; do
    echo "\$ docker compose logs --tail 50 $c"
    docker compose logs --tail 50 "$c" 2>&1
    echo
  done
} >"$EV/15_structured_logs.txt"

# ---- 16. documented inspection script --------------------------------------
{
  echo '$ docker compose exec -T api python -m scripts.inspect_state'
  docker compose exec -T api python -m scripts.inspect_state 2>&1
} >"$EV/16_inspect_state.txt"

# ---- 17. automated acceptance evidence -------------------------------------
docker compose run --rm api pytest -q 2>&1 | tee "$EV/17_pytest_full.txt" | tail -2
{
  docker compose run --rm api ruff check . 2>&1 | tail -2
  docker compose run --rm api ruff format --check . 2>&1 | tail -1
} >"$EV/18_ruff.txt"

# ---- 18. exported API contract ---------------------------------------------
docker compose run --rm api python -m scripts.export_openapi >docs/openapi.json

rm -f "$RESP"
echo "Evidence written to $EV/"
