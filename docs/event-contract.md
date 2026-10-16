# QuickBite Event Contract (v1)

What crosses the broker: envelope, event types, routing, consumer protocol and
the dead-letter contract. Source of truth for type names:
`backend/app/schemas/events.py`; for bindings: `backend/app/messaging/topology.py`.

## Envelope

Every AMQP message body is JSON with `AMQP message_id = event_id`:

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
| `event_id` | Immutable idempotency key, `evt_<kind>_<hex>`; **retained across every publish attempt and redelivery** |
| `schema_version` | Integer; `1` today. Consumers reject versions they don't know (→ dead letter), never crash |
| `event_type` | One of the six types below |
| `order_version` | The order version the event describes (child events carry the version they produced) |
| `correlation_id` | Inherited from the originating request (`X-Request-ID`), never regenerated downstream |
| `causation_id` | The `event_id` that directly caused this event (`null` for `order.created`) |
| `data` | `{customer_id, restaurant_id}` only — **no addresses, names or money free-text** |

## Event types, producers, consumers

| `event_type` | Emitted by | Serves |
| --- | --- | --- |
| `order.created` | Checkout (in the order transaction, via outbox) | payment, notification |
| `order.paid` | payment worker (success branch) | restaurant, notification |
| `order.payment.failed` | payment worker (terminal decline branch) | notification |
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

## Publication semantics

- The dispatcher claims rows with `FOR UPDATE SKIP LOCKED` + a lease
  (`outbox_lease_seconds`, default 30 s), publishes with **publisher confirms
  and `mandatory` routing**, and marks `SENT` only after confirmed routing.
- Unroutable or failed publishes keep the row eligible with exponential
  `available_at` backoff (`2^(attempts-1)`, capped 60 s, no attempt cap).
- Consequence: **at-least-once**. A crash between "broker confirmed" and
  "row marked SENT" republishes the same `event_id` — consumers deduplicate.

## Consumer protocol (all four workers)

1. Parse envelope: malformed JSON / unknown `schema_version` / wrong shape →
   dead-letter + ack. A well-formed event with an **unknown future
   `event_type`** is logged + acked (never retried, never parked).
2. Stage delay (demo latency control: payment/restaurant/delivery 1 s,
   notification 0 s by default).
3. **One transaction**: lock the order row (`FOR UPDATE`) → check
   `(consumer_name, event_id)` in `processed_events` → if present, no-op;
   otherwise apply the stage (effects + one `order_status_history` row + child
   outbox event) and insert the dedup marker in the same transaction.
4. Commit, **then** ack. Crash between commit and ack → redelivery → dedup
   no-op → ack (no repeated effects).

Stale events (order already at/beyond the described state) are recorded as
`STALE_NOOP` markers instead of forcing backward transitions; an event
describing a state the order hasn't reached yet gets a bounded deferred retry
(1 s, 2 s, 4 s) and then dead-letters (durable delayed retries arrive with M4).

## Dead-letter contract

Everything parked lands on `orders.dead-letter.queue` via `quickbite.dead`
routing key `failed`, with a body:

```json
{"event_id": "...", "reason": "precondition_not_met", "detail": "...",
 "consumer": "restaurant", "body": "...original envelope..."}
```

| `reason` | When |
| --- | --- |
| `invalid_json`, `unsupported_schema_version`, `invalid_envelope` | Unprocessable envelope (ack + park; never a tight requeue loop) |
| `missing_order` | Envelope references an order that no longer exists (e.g. after a schema reset) |
| `precondition_not_met` | Order state never caught up within the in-process defer budget |

Parking itself is retried at most 3× (2 s apart); if the broker makes parking
impossible the copy is requeued for a later attempt — **failed work is never
acked away**. Durable `quarantine_records` persistence and retry scheduling
are Milestone 4 (the table exists in the schema from M1).

## Evolution rules

- Adding a field: allowed, consumers ignore unknowns.
- Adding an event type: old consumers log + ack it (see protocol step 1).
- Renaming/removing a field or changing semantics: bump `schema_version`;
  both versions must be handled during a rolling deploy.

## Test namespace

Integration tests publish/consume under a `tst_`-prefixed copy of the exact
same topology (`TopologyNames(prefix)`), so a running Compose stack never
competes with test messages. Production names have no prefix.
