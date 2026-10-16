# QuickBite Reliability & Operations (Milestone 3)

Delivery guarantees, failure schedules, crash windows, and what is deliberately
deferred to Milestone 4.

## Delivery semantics (stated honestly)

- Broker delivery is **at-least-once**. There is no exactly-once claim anywhere:
  the dispatcher can republish after a crash between "confirmed" and
  "SENT", and the broker redelivers unacked messages after any consumer death.
- **Effectively-once business outcomes** come from PostgreSQL:
  `(consumer_name, event_id)` markers in `processed_events`, a row lock on the
  order (`FOR UPDATE`), version-checked transitions and one history row per
  version. Duplicates are detected, recorded as no-ops, and acked.
- Tolerated duplicates are documented as safe by design (assignment §9/§10).

## ACK protocol

```
parse → stage delay → [tx: lock order | dedup check | effects+history+child event | marker]
      → commit → ACK
```

- Ack **only after** the transaction commits.
- `crash_after_checkpoint` stage mode exits the process between commit and ack
  (`os._exit(70)`, simulated under test) to prove redelivery is a no-op.
- Processing/DB failure → the message stays **unacked** and the same
  transaction is retried in place (never an immediate nack/requeue loop).

## Schedules (all bounded, all logged with `retry_in_s`)

| Situation | Schedule |
| --- | --- |
| Dispatcher publish failure | row `available_at` += `2^(attempts-1)` capped **60 s**, attempts never reset, no attempt cap |
| Dispatcher cycle error (DB/broker down) | 1, 2, 5, 10, 30 s, then 30 s; connection redialed each cycle |
| Consumer connect/reconnect | 1, 2, 5, 10, 30 s, then 30 s; topology re-declared idempotently on each connect |
| Processing/DB error mid-message | 1, 2, 5, 10, 30 s in place (message unacked) |
| Event ahead of order state (disorder) | deferred retry 1, 2, 4 s, then dead-letter |
| Dead-letter parking failure | 3 attempts, 2 s apart, then requeue for a later redelivery |
| Graceful shutdown | finish in-flight message, budget **30 s**, else close channel so the copy is redelivered |

## Crash windows

| Crash point | Outcome |
| --- | --- |
| After outbox claim, before publish | lease (`outbox_lease_seconds` = 30 s) expires → reclaimed → published |
| After publish, before `SENT` | row reclaimed → republished (duplicate `event_id`, deduped downstream) |
| Broker outage while events commit | rows stay `PENDING`; API keeps accepting (readiness: PostgreSQL gates, RabbitMQ reported `degraded`); dispatcher publishes them all after recovery — proven live in `docs/evidence/m3/05_broker_restart_no_loss.txt` (`attempts=5` on the recovered row) |
| After worker commit, before ack | channel death → redelivery → dedup no-op → ack |
| Worker/container restart | bounded reconnect loop; queued backlog drains exactly once |

## Failure classification (what happens to a bad message)

| Class | Action |
| --- | --- |
| Malformed / unsupported schema / wrong shape | dead-letter (`failed`) + ack |
| Well-formed unknown future `event_type` | log + ack |
| Order state behind the event | bounded defer, then dead-letter |
| Order missing entirely | dead-letter (`missing_order`) |
| DB/processing error | unacked, retried in place with backoff |
| Shutdown mid-processing | single nack(requeue) |

Nothing in a failure path acks work away, and no path spins without backoff.

## Operations

- **Startup order** (compose): postgres healthy → `migrate` (exit 0) → `seed`
  (exit 0); rabbitmq healthy → `topology-init` (exit 0) → `outbox-dispatcher`
  + the four workers. The dispatcher never publishes before the topology
  exists.
- **Schema changes**: stop the dispatcher and workers, run
  `alembic downgrade/upgrade`, restart them (procedure exercised in
  `docs/evidence/m3/00_migrations_cycle.txt`). Loss is impossible either way —
  events live in PostgreSQL until confirmed+routed, and consumers deduplicate.
- **Health**: `/health/live` never fails for outages; `/health/ready` requires
  PostgreSQL only. A broker outage is a `200 status:"degraded"`, not a 503 —
  accepted orders may legally wait in the outbox.
- **Scale**: `docker compose up -d --scale payment-worker=3` — competing
  consumers are safe (tested: each event applied exactly once across replicas).

## Known limitations / deferred to Milestone 4

1. **No durable retry scheduler or quarantine persistence yet.** Parked
   messages live in `orders.dead-letter.queue`; `quarantine_records` (schema
   from M1) is not written by M3. M4 adds the durable retry_jobs/quarantine
   lifecycle with exhaustion handling.
2. **Precondition exhaustion is dead-lettered in-process** (after 1/2/4 s
   defers) as an M3 stopgap instead of durable delayed retries.
3. **Failure-path stage injections** (`restaurant_mode/delivery_mode =
   fail_twice`, non-always-succeed notification mode) are rejected at worker
   startup in M3 — those scenarios are M4 tests by agreement.
4. **Automated in-test broker restart is not part of pytest** (the test
   suite shares one broker container; restarting it mid-suite would break
   unrelated tests). The equivalent connection-loss class is covered by
   `test_committed_outbox_events_survive_broker_connection_loss`, and the
   *physical* restart is proven by the live evidence script
   (`scripts/capture_m3_evidence.sh` → `05_broker_restart_no_loss.txt`).
5. `checkout_idempotency` records are retained for the assignment lifetime
   (production would expire them after the retry window).
