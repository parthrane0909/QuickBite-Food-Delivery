# QuickBite Reliability & Operations (Milestone 4)

Delivery guarantees, the durable retry/quarantine lifecycle, crash windows with
their real exit codes, terminal failure paths, protected failure controls, and
what remains deferred.

## Delivery semantics (stated honestly)

- Broker delivery is **at-least-once**. There is no exactly-once claim anywhere:
  the dispatcher can republish after a crash between "confirmed" and "SENT",
  the broker redelivers unacked messages after any consumer death, and a retry
  publication is re-armed rather than guaranteed unique.
- **Effectively-once business outcomes** come from PostgreSQL:
  `(consumer_name, event_id)` markers in `processed_events`, a row lock on the
  order (`FOR UPDATE`), version-checked transitions and one history row per
  version. Duplicates are detected, recorded as no-ops, and acked — a single
  committed effect per logical event even under repeated delivery.
- Retries and quarantine are **durable in PostgreSQL first**: a transient
  failure is only acknowledged after its retry row and scheduled publication
  commit, so no crash window can drop a failed message.

## ACK protocol

```
parse → classify → stage delay → [tx: lock order | dedup | effects+history+child event | marker]
      → commit → ACK
```

- Ack **only after** the transaction commits.
- **Transient business failure**: the business transaction rolls back, then a
  NEW transaction inserts one `retry_jobs` row (next attempt, `due_at = now +
  delay`) plus one scheduled, TARGETED outbox publication (default exchange,
  routing key = the failing queue's name) and commits — **then** the original
  message is acked. If that persistence transaction fails, the message stays
  **unacked** and is retried in place with bounded backoff (below); nothing is
  ever acked on a failed persist.
- `crash_after_checkpoint` exits the process between commit and ack
  (`os._exit(70)`, simulated under test) to prove redelivery is a no-op.
- Attempt numbers are **DB-authoritative** (`MAX(attempt)` per
  `(consumer, event_id)`, else 1), so a redelivery can never restart or skip a
  ladder — proven in `docs/evidence/m4/10_crash_during_retry_persistence.txt`.

## Retry policy (assignment §11)

- Default: **1 initial attempt + 3 retries at 2 s / 10 s / 30 s**, then
  terminal handling. Configurable via `RETRY_DELAYS_SECONDS` (comma list) and
  `RETRY_MAX_ATTEMPTS` (must equal `len(delays) + 1`, validated at startup).
  The integration suite forces `0.2,0.4,0.8` for speed; evidence captures use
  the untouched defaults — see
  `docs/evidence/m4/07_payment_exhaust_default_timing.txt`
  (`scheduled_after = 00:00:02 / 00:00:10 / 00:00:30` straight from
  `retry_jobs.due_at - created_at`).
- **Targeted only**: a retry is published on the RabbitMQ **default exchange**
  with routing key = the failing queue (`payment.queue` /
  `restaurant.queue` / `delivery.queue` / `notification.queue`) — never to
  `quickbite.orders`, so unrelated subscribers never see another consumer's
  retry. The original `event_id` and payload are immutable; only the attempt
  counter in `retry_jobs` changes.
- **Publication identity**: one outbox row per
  `(exchange, routing_key, event_id)` is RE-ARMED across attempts
  (migration `0002`); per-attempt history lives in `retry_jobs`
  (`UNIQUE (consumer_name, event_id, attempt)`).
- **Retry scheduler** (separate `retry-scheduler` service, PostgreSQL only):
  claims due `PENDING` jobs with `FOR UPDATE SKIP LOCKED`, makes their
  targeted publications eligible and marks the jobs `PUBLISHED` in one
  transaction — crash-recovering and safe with multiple instances. Its absence
  can only DELAY activation, never lose retries: every retry row also carries
  its own `available_at` the dispatcher honours.

## Schedules (all bounded, all logged)

| Situation | Schedule |
| --- | --- |
| Consumer transient failure / precondition not yet met | durable ladder **2, 10, 30 s** (default) then terminal handling; attempts capped at `RETRY_MAX_ATTEMPTS` |
| Retry-persistence transaction fails (DB down) | 1, 2, 5, 10, 30 s then 30 s **in place** (message unacked) — the only remaining in-place retry |
| Dispatcher publish failure | row `available_at` += `2^(attempts-1)` capped **60 s**, attempts never reset, no attempt cap |
| Dispatcher cycle error (DB/broker down) | 1, 2, 5, 10, 30 s then 30 s; connection redialed each cycle |
| Retry scheduler cycle | poll every `RETRY_SCHEDULER_POLL_INTERVAL_SECONDS` (0.5 s default); DB-only, unaffected by broker outages |
| Consumer connect/reconnect | 1, 2, 5, 10, 30 s then 30 s; topology re-declared idempotently |
| Graceful shutdown | finish in-flight message, budget **30 s**, else close channel so the copy is redelivered |

## Crash windows (all demonstrated with real process deaths)

| Crash point | Mechanism | Outcome |
| --- | --- | --- |
| Inside the business transaction, before commit | `CRASH_POINT=before_commit` → `os._exit(71)` | nothing persisted; unacked copy redelivered; recovery completes exactly once (`m4/09_crash_before_commit.txt`) |
| Inside the retry-persistence transaction | `CRASH_POINT=during_retry_persistence` → `os._exit(72)` | retry row + publication roll back with the crash; message never acked; ladder restarts from the redelivery (`m4/10_crash_during_retry_persistence.txt`) |
| After commit, before ack | `PAYMENT_MODE=crash_after_checkpoint` → `os._exit(70)` | effect committed; redelivery deduplicates — payments stay 1 (`m4/11_crash_after_checkpoint.txt`) |
| Dispatcher after confirmed publish, before `SENT` | `DISPATCHER_CRASH_AFTER_PUBLISH` → `os._exit(73)` | lease expires (30 s) → reclaimed → same `event_id` republished → deduped downstream (`m4/12_crash_after_publish.txt`) |
| Physical SIGKILL, any moment | `docker compose kill` ×3 mid-chain | unacked copies redeliver; one committed effect (`m4/13_physical_kill_and_shutdown.txt`) |
| Graceful SIGTERM | `docker compose stop` | bounded in-flight finish, exit 0 (`m4/13_physical_kill_and_shutdown.txt`) |
| Broker outage with a pending retry | stop/start `rabbitmq` | due job waits, dispatcher logs bounded backoff, ladder resumes — nothing lost (`m4/14_broker_outage_pending_retries.txt`) |
| Broker outage while events commit | rows stay `PENDING`; readiness reports `degraded` (PostgreSQL gates) | dispatcher publishes everything after recovery |
| Worker/container restart | bounded reconnect loop | queued backlog drains exactly once |

Crash exits (`70/71/72/73`) are real `os._exit` calls outside the test
environment; under `ENVIRONMENT=test` they log the checkpoint instead.

## Terminal paths (state-guarded, never regress an order)

| Consumer | Exhaustion / permanent outcome | Guard |
| --- | --- | --- |
| payment | `PENDING → PAYMENT_FAILED`, `failure_code = PAYMENT_RETRIES_EXHAUSTED` (or immediate `PAYMENT_DECLINED`), + `order.payment.failed` event, one `simulated_payments` FAILED row | only from `PENDING`; stale/missing order → quarantine only |
| restaurant | `PAID → FAILED`, `RESTAURANT_RETRIES_EXHAUSTED` (or immediate `RESTAURANT_REJECTED`) | only from `PAID` |
| delivery | `CONFIRMED → FAILED`, `DELIVERY_RETRIES_EXHAUSTED` (or immediate `DRIVER_UNAVAILABLE`); no assignment row | only from `CONFIRMED` |
| notification | **quarantine only** (`NOTIFICATION_RETRIES_EXHAUSTED`) — order business state is NEVER touched (§10) | n/a |

Permanent classifications (`PAYMENT_DECLINED`, `RESTAURANT_REJECTED`,
`DRIVER_UNAVAILABLE`) bypass the ladder entirely: immediate terminal, no retry
churn (`m4/06_payment_decline_terminal.txt`, `m4/08_terminal_business_failures.txt`).

## Quarantine (durable, deduplicating, published before ack)

- Every terminally failed delivery writes ONE `quarantine_records` row —
  `UNIQUE (consumer_name, event_id)` makes duplicates no-ops — **and** its
  transactional outbox publication to `quickbite.dead` routing key `failed`
  → `orders.dead-letter.queue`, in the same transaction, committed **before**
  the ack. RabbitMQ's dead-letter behaviour is never the only copy.
- **Logical identity** is never the AMQP `message_id`: aiormq/RabbitMQ
  generates a UNIQUE `message_id` per delivery when the publisher omits one,
  which would defeat dedup. Identity is: the envelope/payload `event_id` for
  parseable events, a canonical-JSON digest `undecoded_<sha256[:32]>` for
  unknown event types, and a raw-bytes digest for malformed bodies.
- One dead publication per identity: two consumers quarantining the same event
  share a single publication (dedup tests in
  `backend/tests/test_quarantine_dedup.py` + evidence
  `m4/08_terminal_business_failures.txt` shows a single dead copy per
  exhaust event).
- Malformed payloads are quarantined with **no order reference at all** —
  they can never read or mutate an unrelated order.

## Failure classification (what happens to a bad message)

| Class | Action |
| --- | --- |
| Transient (DB/processing error, precondition not yet met, order missing) | durable retry ladder → on exhaustion: state-guarded terminal (payment/restaurant/delivery) or quarantine (notification), + quarantine record |
| Permanent (decline / reject / no driver) | immediate terminal transition, no retries, no quarantine |
| Malformed JSON / unsupported `schema_version` / invalid envelope | immediate quarantine (durable record + dead publication) + ack; never retried |
| Well-formed unknown future `event_type` | business consumers: quarantine + ack; notification worker: log + ack (§9) |
| Well-formed event no consumer serves yet | log + ack |
| Stale event (order already at/beyond the state) | `STALE_NOOP` marker + ack; never a backward transition |
| Duplicate race (`IntegrityError` on the marker) | treated as stale: re-read, no-op, ack |
| Shutdown mid-processing | bounded in-flight finish, else close channel → redelivery |

Nothing in a failure path acks work away, and no path spins without backoff.

## Protected failure controls (assignment §12)

Failure simulation is **environment/process only** — checkout and every API
field are unaffected, so a customer can never trigger or steer a failure:

- Stage modes: payment `always_succeed | fail_twice | always_fail |
  always_decline | crash_after_checkpoint`; restaurant/delivery
  `always_succeed | always_fail | crash_after_checkpoint`; notification
  `always_fail` (transient before any write). Unknown modes are rejected at
  worker startup.
- Crash controls: `CRASH_POINT` (`before_commit`, `during_retry_persistence`),
  `DISPATCHER_CRASH_AFTER_PUBLISH` (validated at startup).
- Reviewed overrides live in `scripts/crash-overrides/*.yaml`; the interactive
  runner is `backend/scripts/demo_failures.py`
  (`docker compose run --rm api python -m scripts.demo_failures --list`).

## Operations

- **Startup order** (compose): postgres healthy → `migrate` (exit 0) → `seed`
  (exit 0); rabbitmq healthy → `topology-init` (exit 0) → `outbox-dispatcher`
  + `retry-scheduler` + the four workers.
- **Schema changes**: stop the pipeline (`outbox-dispatcher retry-scheduler`
  + four workers), `alembic downgrade/upgrade`, restart. Migration `0002`'s
  downgrade documents the one data consequence: M4-only publication rows are
  removed so M3's `UNIQUE(event_id)` can be restored (inspection history in
  `retry_jobs`/`quarantine_records` is retained). Full cycle evidence:
  `docs/evidence/m4/00_migrations_cycle.txt`.
- **Health**: `/health/live` never fails for outages; `/health/ready` requires
  PostgreSQL only; a broker outage is `200 status:"degraded"`.
- **Scale**: `--scale payment-worker=N` is safe (competing replicas tested);
  `--scale retry-scheduler=N` too (`SKIP LOCKED`).
- **Inspection** (documented scripts, assignment §13):
  `docker compose exec api python -m scripts.inspect_state` (outbox backlog,
  retry backlog with oldest-due age, quarantine records, production queue
  depths via the management API), the RabbitMQ management UI at
  `127.0.0.1:15672`, `rabbitmqctl`, and psql one-liners as used by
  `scripts/capture_m4_evidence.sh`.

## Known limitations / deferred

1. **Admin endpoints** (`/api/v1/admin/orders`, `/api/v1/admin/summary`) are
   not served yet — due by Milestone 5 at the latest (milestone agreement).
2. **Flutter feature screens** arrive with M5; Android SDK likewise. iOS stays
   pending (Linux host, no Xcode) — never claimed complete.
3. **A physical broker restart is not part of pytest** (the suite shares one
   broker container); the connection-loss class is covered by tests and the
   physical outage — including with a pending retry — is proven live in
   `m4/14_broker_outage_pending_retries.txt`.
4. Default 2/10/30 s timing is demonstrated by the evidence script against the
   live stack; pytest uses shortened delays by design (documented in
   `backend/tests/conftest.py`).
5. `checkout_idempotency` records are retained for the assignment lifetime
   (production would expire them after the retry window).
