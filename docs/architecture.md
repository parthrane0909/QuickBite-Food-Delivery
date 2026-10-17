# QuickBite Architecture (Milestone 5)

PostgreSQL is the sole source of truth; RabbitMQ only distributes work.
Everything below is reproducible from `compose.yaml`.

## Runtime components

```
   ┌─────────────── client boundary (Milestone 5) ────────────────┐
   │ Flutter app: Android / Web (nginx `web`, :8080) / iOS (pending)│
   │   HTTP + bearer token only — no broker/DB knowledge, no secrets │
   └──────────────────────────┬───────────────────────────────────┘
                       127.0.0.1:8000
 client ── HTTP ──▶ api (FastAPI, uvicorn)
                      │  checkout: ONE tx → orders + items + history +
                      │             checkout_idempotency + outbox_events
                      ▼
                 postgres 17.11  ◀───────────┐  read/write everywhere else
                      ▲                      │
   ┌──────────────────┴──────────────────┐   │
   │ outbox-dispatcher                  │   │
   │  claim (SKIP LOCKED + 30s lease)   │   │
   │  publish: confirms + mandatory     │   │
   │  SENT only after confirmed routing │   │
   └──────────────────┬──────────────────┘   │
                      ▼                      │
        RabbitMQ 4.3.6  topic exchange quickbite.orders
        ├─ payment.queue      ← order.created
        ├─ restaurant.queue   ← order.paid
        ├─ delivery.queue     ← order.confirmed
        ├─ notification.queue ← order.#            (all six types)
        ├─ quickbite.dead (direct) → orders.dead-letter.queue ← failed
        │
        │  default exchange (retries — TARGETED, never quickbite.orders)
        ├─ payment.queue      ← order.<...> retry (exchange='', rk=payment.queue)
        ├─ restaurant.queue   ← ...      delivery.queue / notification.queue likewise
                      │  manual acks, prefetch 8, one channel per consumer
        ┌─────────────┴─────────────┬───────────────┬──────────────────┐
        ▼                           ▼               ▼                  ▼
  payment-worker            restaurant-worker  delivery-worker  notification-worker
  PAID / PAYMENT_FAILED     CONFIRMED/FAILED   DRIVER_ASSIGNED  notification rows
        │                           │               │                  │
        │  transient failure: NEW tx = retry_jobs row + scheduled       │
        │  targeted outbox row → commit → ACK (ladder 2s/10s/30s)       │
        │                           │               │                  │
        └───────── child event written to outbox_events IN THE SAME tx ─┘
                                   │
                                   └──▶ back through the dispatcher (loop)

   ┌──────────────────────────────┐
   │ retry-scheduler (PostgreSQL) │  claims DUE retry_jobs (SKIP LOCKED),
   │  DB-only, no broker          │  makes their publications eligible,
   └──────────────┬───────────────┘  marks jobs PUBLISHED, logs backlog
                  ▲ due_at reached
                  └── retry_jobs / quarantine_records / outbox_events tables
```

| Compose service | Role |
| --- | --- |
| `postgres` | Source of truth (health-gated) |
| `rabbitmq` | Work distribution only (management UI on `127.0.0.1:15672`) |
| `migrate` / `seed` | One-shots: schema (0001 + 0002) → idempotent demo data |
| `topology-init` | One-shot: declares exchanges/queues/bindings **before** any publisher/consumer starts |
| `api` | FastAPI: auth, menu, checkout, order reads, notifications endpoint, **admin orders + summary (M5)**, health |
| `outbox-dispatcher` | Separate process loop publishing committed outbox rows (topic events, targeted retries, dead publications) |
| `retry-scheduler` | Separate DB-only process activating due retries; crash-recovering, `SKIP LOCKED` (multi-instance safe); absence only delays retries |
| `payment/restaurant/delivery/notification-worker` | Four independent processes, one stage each, freely scalable |
| `web` | nginx hosting the built Flutter SPA (static files, SPA deep-link fallback; browser calls the API directly under CORS) |

Startup order is enforced in compose: postgres → migrate → seed; rabbitmq →
`topology-init` → dispatcher + retry-scheduler + workers (all also wait on
postgres/rabbitmq healthy). Ports bind `127.0.0.1` only.

## Why the outbox exists

Checkout performs **no broker I/O**: the order, its items, the status-history
v1 row, the idempotency record and the `order.created` outbox row commit in a
single transaction. A 202 therefore means "durable in PostgreSQL", never
"probably queued". The dispatcher — a separate process — moves rows to the
broker with confirms + mandatory routing, so neither a broker outage nor a
dispatcher crash can lose an accepted order (see `docs/reliability.md`).

The same pattern now covers **failure handling**: a consumer's retry
(persistence transaction), its scheduled targeted publication, and every
quarantine record + dead publication are PostgreSQL rows committed before the
source message is acked. Retries and quarantines survive crashes exactly like
orders do.

## One worker transaction (and its failure sibling)

All four workers share `app/messaging/consumer_runtime.py`:

1. lock the order row (`FOR UPDATE`);
2. dedup check on `(consumer_name, event_id)`;
3. apply the stage: status transition + one `order_status_history` row
   (version+1) + child outbox event **in this same transaction**;
4. insert the processed-event marker; commit; only then ack.

On a transient failure the business transaction rolls back and a **second**
transaction writes the next `retry_jobs` attempt (DB-authoritative attempt
number) plus the scheduled `exchange=''` publication to the failing queue,
commits, and only then acks. Exhaustion adds a state-guarded terminal
transition (payment/restaurant/delivery) or a quarantine-only outcome
(notification), always with a quarantine record in the same transaction.
No event is ever acked before its effects — or its failure handling — are
durable; duplicates become no-ops. Notifications are rendered from committed
state and never change order status.

## Module map

| Module | Responsibility |
| --- | --- |
| `app/messaging/topology.py` | Names (`TopologyNames(prefix)`), bindings, idempotent declaration |
| `app/messaging/outbox_dispatcher.py` | Claim/lease cycle, confirms+mandatory publish (topic + default-exchange retries), crash checkpoint, bounded backoff |
| `app/messaging/retry_scheduler.py` | Due-job claim (`SKIP LOCKED`) + publication activation + backlog logging |
| `app/messaging/publisher.py` | Channel lifecycle, unroutable detection (`PublishError` with stable reasons), default-exchange routing |
| `app/messaging/envelope.py` | Envelope build/parse + classification of unprocessable input |
| `app/messaging/consumer_runtime.py` | Consume loop, ack protocol, failure classification, durable-retry persistence, quarantine, reconnect, graceful shutdown |
| `app/repositories/messaging.py` | retry_jobs / outbox / quarantine DB operations (re-arm, SKIP LOCKED claim, backlog) |
| `app/services/quarantine_service.py` | Durable quarantine records + dead publications; state-guarded exhaustion terminals |
| `app/services/*_service.py` | Stage decisions (payment/restaurant/delivery/notification), protected simulation modes |
| `app/services/transitions.py` | State machine transitions + `emit_outbox_event` |
| `app/services/processing.py` | The shared one-transaction stage runner |
| `app/services/admin_service.py` | Cross-customer order page + operations summary (counters only) |
| `app/repositories/processed_events.py` | Dedup markers |
| `scripts/init_topology.py` | The `topology-init` entrypoint |
| `scripts/inspect_state.py` | Operational backlog inspection (outbox/retry/quarantine/queue depths) |
| `scripts/demo_failures.py` | Interactive protected failure-control demonstrations |

## Environments and namespaces

- `ENVIRONMENT=test` forces NullPool, zero stage delays, fast outbox polling
  and crash checkpoints that log instead of exiting (see
  `backend/tests/conftest.py`) — same code paths, deterministic timing; tests
  shorten `RETRY_DELAYS_SECONDS` to `0.2,0.4,0.8` while production defaults
  stay `2,10,30`.
- Tests declare a **`tst_`-prefixed** copy of the topology, so an active
  Compose stack and the test suite never touch each other's messages; retry
  routing keys are stored as final queue names and never re-prefixed.
- Same image for api/dispatcher/scheduler/workers; only the command differs.
- Migrations: `0001` initial schema, `0002` publication identity
  (`UNIQUE (exchange, routing_key, event_id)` on `outbox_events`).
