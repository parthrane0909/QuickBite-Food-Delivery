# QuickBite Event Contract (v1, Milestone 4)

What crosses the broker: envelope, event types, routing, consumer protocol,
the targeted-retry contract and the quarantine/dead-letter contract. Source of
truth for type names: `backend/app/schemas/events.py`; for bindings:
`backend/app/messaging/topology.py`.

## Envelope

Every AMQP message body is JSON with `AMQP message_id = event_id` (set by our
publisher):

```json
{
  "event_id": "evt_created_d11f73cfe679467b99065c9feaeeec15",
  "schema_version": 1,
  "event_type": "order.created",
  "order_id": "order_8ff2b1c3241a4cedac181b63bca7642b",
  "order_version": 1,
  "occurred_at": "2026-10-16T15:57:51.226147Z",
  "correlation_id": "req_m2_demo",
  "causation_id": null,
  "data": {"customer_id": "user_alice", "restaurant_id": "rest_bella_napoli"}
}
```

| Field | Rule |
| --- | --- |
| `event_id` | Immutable idempotency key, `evt_<kind>_<hex>`; **retained across every publish attempt, retry and redelivery** — never regenerated |
| `schema_version` | Integer; `1` today. Consumers reject versions they don't know (→ quarantine), never crash |
| `event_type` | One of the six types below |
| `order_version` | The order version the event describes (child events carry the version they produced) |
| `correlation_id` | Inherited from the originating request (`X-Request-ID`), never regenerated downstream |
| `causation_id` | The `event_id` that directly caused this event (`null` for `order.created`) |
| `data` | `{customer_id, restaurant_id}` only — **no addresses, names or money free-text** |

The AMQP `message_id` property is **not** a durable logical identity by
itself: when a publisher omits it, aiormq/RabbitMQ generates a unique value
per delivery. Durable identities (quarantine keys, dedup markers) always come
from the payload, never from the transport property.

## Event types, producers, consumers

| `event_type` | Emitted by | Serves |
| --- | --- | --- |
| `order.created` | Checkout (in the order transaction, via outbox) | payment, notification |
| `order.paid` | payment worker (success branch) | restaurant, notification |
| `order.payment.failed` | payment worker (terminal decline/exhaustion branch) | notification |
| `order.confirmed` | restaurant worker (accept branch) | delivery, notification |
| `order.driver.assigned` | delivery worker (success branch) | notification |
| `order.failed` | restaurant/delivery worker (terminal reject branch) | notification |

Child events are written to `outbox_events` **inside the same transaction** as
the transition that caused them, so a committed state change always has its
event (and vice versa: no event without a committed cause).

## Routing (production names)

Durable **topic** exchange `quickbite.orders`:

| Queue | Binding key |
| --- | --- |
| `payment.queue` | `order.created` |
| `restaurant.queue` | `order.paid` |
| `delivery.queue` | `order.confirmed` |
| `notification.queue` | `order.#` |
| `orders.dead-letter.queue` | `failed` (from **direct** exchange `quickbite.dead`) |

`order.#` (multi-segment wildcard) is deliberate: `order.*` matches exactly
ONE segment and would silently drop `order.payment.failed` and
`order.driver.assigned` (assignment §20). Topology is declared idempotently by
the `topology-init` one-shot **before** the dispatcher starts, and re-declared
defensively by every consumer on (re)connect.

### Targeted retries (Milestone 4)

Retry publications **never** ride `quickbite.orders`. They use the RabbitMQ
**default exchange** (empty name) with `routing_key` = the failing queue's
name, written as a scheduled outbox row with
`exchange='' / routing_key=<queue>`:

| Consumer | Retry routing key |
| --- | --- |
| payment | `payment.queue` |
| restaurant | `restaurant.queue` |
| delivery | `delivery.queue` |
| notification | `notification.queue` |

Only the queue that failed ever receives the retry — unrelated subscribers are
never re-delivered another consumer's failure. One outbox row per
`(exchange, routing_key, event_id)` is **re-armed** across attempts
(migration `0002`); the attempt history lives in `retry_jobs`
(`UNIQUE (consumer_name, event_id, attempt)`), keyed by the immutable
`event_id`.

## Publication semantics

- The dispatcher claims rows with `FOR UPDATE SKIP LOCKED` + a lease
  (`outbox_lease_seconds`, default 30 s), publishes with **publisher confirms
  and `mandatory` routing**, and marks `SENT` only after confirmed routing.
- Unroutable or failed publishes keep the row eligible with exponential
  `available_at` backoff (`2^(attempts-1)`, capped 60 s, no attempt cap).
- Due retry rows are made eligible by the `retry-scheduler` service (DB-only,
  `SKIP LOCKED`); the dispatcher also honours each row's own `available_at`,
  so scheduler downtime delays activation but never loses a retry.
- Consequence: **at-least-once**. A crash between "broker confirmed" and
  "row marked SENT" republishes the same `event_id` — consumers deduplicate.

## Consumer protocol (all four workers)

1. Parse envelope: malformed JSON / unknown `schema_version` / wrong shape →
   **quarantine + ack** (durable record, no retries). A well-formed event with
   an unknown future `event_type`: business consumers quarantine + ack; the
   notification worker logs + acks (§9). A well-formed type no consumer serves
   yet → log + ack.
2. Stage delay (demo latency control: payment/restaurant/delivery 1 s,
   notification 0 s by default).
3. **One transaction**: lock the order row (`FOR UPDATE`) → check
   `(consumer_name, event_id)` in `processed_events` → if present, no-op;
   otherwise apply the stage (effects + one `order_status_history` row + child
   outbox event) and insert the dedup marker in the same transaction.
4. Commit, **then** ack. Crash between commit and ack → redelivery → dedup
   no-op → ack (no repeated effects).
5. **Transient failure** (business rule not yet satisfiable, order missing,
   DB error): business tx rolls back → one new transaction writes the next
   `retry_jobs` attempt (due 2 s / 10 s / 30 s by default) plus its scheduled
   targeted publication → commit → ack. On exhaustion
   (`attempt = RETRY_MAX_ATTEMPTS = 4`): state-guarded terminal transition for
   payment/restaurant/delivery, quarantine-only for notifications, always with
   a quarantine record. Permanent declines/rejects bypass the ladder entirely.

Stale events (order already at/beyond the described state) are recorded as
`STALE_NOOP` markers instead of forcing backward transitions.

## Quarantine / dead-letter contract

Every terminally failed delivery produces BOTH, in one transaction, committed
**before** the ack:

1. one `quarantine_records` row — `UNIQUE (consumer_name, event_id)` so a
   duplicate delivery can never create a second logical record (it acks);
2. one transactional outbox publication to direct exchange `quickbite.dead`,
   routing key `failed` → `orders.dead-letter.queue`, published with the same
   confirms + mandatory discipline as every other outbox row (RabbitMQ's
   dead-letter behaviour alone is never the only copy).

**Logical identity** (what `quarantine_records.event_id` holds):

| Input | Identity |
| --- | --- |
| Parseable envelope (exhaustion, permanent, stale/missing order, unknown type) | payload `event_id` |
| Parseable JSON without an `event_id` (unknown type) | digest `undecoded_<sha256(canonical json)[:32]>` |
| Malformed bytes (bad JSON, unsupported `schema_version`) | digest `undecoded_<sha256(raw bytes)[:32]>` — never the transport `message_id` |

The dead-lettered body is self-describing:

```json
{"event_id": "...", "failure_code": "malformed_envelope",
 "reason": "invalid_json: ...", "consumer": "payment",
 "body": "...original bytes..."}
```

| `failure_code` (classification) | When |
| --- | --- |
| `malformed_envelope` / `unsupported_schema` | Unprocessable envelope — quarantined immediately, no retries, acked |
| `transient` exhausted → e.g. `PAYMENT_RETRIES_EXHAUSTED` | Ladder ran out; terminal transition (state-guarded) already applied where applicable |
| Notification ladder exhausted (`NOTIFICATION_RETRIES_EXHAUSTED`) | Order state never touched (§10) |
| `missing_order` after the ladder | Envelope references an order that no longer exists |

Malformed quarantine records carry **no order reference at all**, so a broken
payload can never mutate an unrelated order.

## Evolution rules

- Adding a field: allowed, consumers ignore unknowns.
- Adding an event type: old consumers log + ack or quarantine it (see protocol
  step 1); it never blocks the queue.
- Renaming/removing a field or changing semantics: bump `schema_version`;
  both versions must be handled during a rolling deploy.

## Test namespace

Integration tests publish/consume under a `tst_`-prefixed copy of the exact
same topology (`TopologyNames(prefix)`), so a running Compose stack never
competes with test messages. Production names have no prefix. Retry routing
keys are stored as final (already-namespaced) queue names and are never
re-prefixed; topic routing keys are likewise never prefixed.
