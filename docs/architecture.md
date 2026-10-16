# QuickBite Architecture (Milestone 3)

PostgreSQL is the sole source of truth; RabbitMQ only distributes work.
Everything below is reproducible from `compose.yaml`.

## Runtime components

```
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
        └─ quickbite.dead (direct) → orders.dead-letter.queue ← failed
                      │  manual acks, prefetch 8, one channel per consumer
        ┌─────────────┴─────────────┬───────────────┬──────────────────┐
        ▼                           ▼               ▼                  ▼
  payment-worker            restaurant-worker  delivery-worker  notification-worker
  PAID / PAYMENT_FAILED     CONFIRMED/FAILED   DRIVER_ASSIGNED  notification rows
        │                           │               │                  │
        └───────── child event written to outbox_events IN THE SAME tx ─┘
                                   │
                                   └──▶ back through the dispatcher (loop)
```

| Compose service | Role |
| --- | --- |
| `postgres` | Source of truth (health-gated) |
| `rabbitmq` | Work distribution only (management UI on `127.0.0.1:15672`) |
| `migrate` / `seed` | One-shots: schema → idempotent demo data |
| `topology-init` | One-shot: declares exchanges/queues/bindings **before** any publisher/consumer starts |
| `api` | FastAPI: auth, menu, checkout, order reads, notifications endpoint, health |
| `outbox-dispatcher` | Separate process loop publishing committed outbox rows |
| `payment/restaurant/delivery/notification-worker` | Four independent processes, one stage each, freely scalable |

Startup order is enforced in compose: postgres → migrate → seed; rabbitmq →
`topology-init` → dispatcher + workers (all also wait on postgres/rabbitmq
healthy). Ports bind `127.0.0.1` only.

## Why the outbox exists

Checkout performs **no broker I/O**: the order, its items, the status-history
v1 row, the idempotency record and the `order.created` outbox row commit in a
single transaction. A 202 therefore means "durable in PostgreSQL", never
"probably queued". The dispatcher — a separate process — moves rows to the
broker with confirms + mandatory routing, so neither a broker outage nor a
dispatcher crash can lose an accepted order (see `docs/reliability.md`).

## One worker transaction

All four workers share `app/messaging/consumer_runtime.py` and
`app/services/processing.py`:

1. lock the order row (`FOR UPDATE`);
2. dedup check on `(consumer_name, event_id)`;
3. apply the stage: status transition + one `order_status_history` row
   (version+1) + child outbox event **in this same transaction**;
4. insert the processed-event marker; commit; only then ack.

No event is ever acked before its effects are durable; duplicates become
no-ops. Notifications (`notifications` rows) are rendered from the committed
state by the notification worker — they never change order status.

## Module map

| Module | Responsibility |
| --- | --- |
| `app/messaging/topology.py` | Names (`TopologyNames(prefix)`), bindings, idempotent declaration |
| `app/messaging/outbox_dispatcher.py` | Claim/lease cycle, confirms+mandatory publish, `run_forever` with bounded backoff |
| `app/messaging/publisher.py` | Channel lifecycle, unroutable detection (`PublishError` with stable reasons) |
| `app/messaging/envelope.py` | Envelope build/parse + classification of unprocessable input |
| `app/messaging/consumer_runtime.py` | Consume loop, ack protocol, failure classification, reconnect, graceful shutdown |
| `app/services/*_service.py` | Stage decisions (payment/restaurant/delivery/notification) |
| `app/services/transitions.py` | State machine transitions + `emit_outbox_event` |
| `app/services/processing.py` | The shared one-transaction stage runner |
| `app/repositories/processed_events.py` | Dedup markers |
| `scripts/init_topology.py` | The `topology-init` entrypoint |

## Environments and namespaces

- `ENVIRONMENT=test` forces NullPool, zero stage delays, fast outbox polling
  (see `backend/tests/conftest.py`) — same code paths, deterministic timing.
- Tests declare a **`tst_`-prefixed** copy of the topology, so an active
  Compose stack and the test suite never touch each other's messages.
- Same image for api/dispatcher/workers; only the command differs.
