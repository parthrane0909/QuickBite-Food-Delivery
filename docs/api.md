# QuickBite API Contract (v1)

Versioned REST contract for the QuickBite backend (assignment §7/§20). The
machine-readable source of truth is the exported OpenAPI document:
[`docs/openapi.json`](openapi.json) (regenerate with
`docker compose run --rm api python -m scripts.export_openapi > docs/openapi.json`).

Base path: `/api/v1` (health probes are unversioned: `/health/live`,
`/health/ready`).

## Conventions

| Topic | Rule |
| --- | --- |
| Authentication | `Authorization: Bearer <access_token>`; short-lived signed JWT (default 30 min), validated against the user record (inactive/unknown user → 401) |
| Pagination | `page >= 1`, `page_size >= 1`, **max `page_size = 100`** (422 above); list bodies are exactly `{items, page, page_size, total}` with stable ordering (ties broken by id) |
| Timestamps | UTC ISO-8601 **with timezone information** (`2026-10-16T15:57:51.226147Z`) |
| Money | Integer **minor units**: `1250` = INR 12.50 with `"currency": "INR"`. Never floating point; totals computed server-side from the menu inside the checkout transaction |
| Error envelope | Always `{"code", "message", "details", "request_id"}` — including validation errors |
| Status codes | `401` unauthenticated, `403` wrong role, `404` unknown **or other customer's** order, `409` idempotency payload conflict, `422` invalid input, `202` checkout accepted |
| Correlation | `X-Request-ID` is echoed on every response and used as the event `correlation_id` |

## Endpoints

| Method and route | Access | Behavior |
| --- | --- | --- |
| `POST /api/v1/auth/login` | Public | `{email, password}` → bearer token, expiry, role, user summary |
| `GET /api/v1/me` | Signed in | Current profile and role |
| `GET /api/v1/restaurants` | Signed in | Paginated restaurant list |
| `GET /api/v1/restaurants/{id}/menu` | Signed in | Paginated menu with authoritative minor-unit prices (unavailable items are listed with `is_available: false`) |
| `POST /api/v1/orders` | Customer | Idempotent checkout → `202` + `Location` |
| `GET /api/v1/orders` | Customer | Paginated **own** orders; optional exact `status` filter (invalid value → 422) |
| `GET /api/v1/orders/{id}` | Owner or admin | Current state, items, totals, failure details, version, timestamps |
| `GET /api/v1/orders/{id}/history` | Owner or admin | Append-only, version-ordered transition timeline (single page; history is bounded at 7 entries by the state machine) |

*Planned in later milestones (not yet served):* `GET /orders/{id}/notifications`
(Milestone 3, needs persisted notifications), `GET /admin/orders` and
`GET /admin/summary` (Milestone 6). Until then they return 404/403 per the
role guards.

## Checkout: `POST /api/v1/orders`

Headers: `Authorization` (customer role), `Content-Type: application/json`,
**`Idempotency-Key` (required, 1–128 chars, clients should send a UUID)**.

Request body (only these fields — extra fields such as `price_amount_minor`,
`total_amount_minor` or `customer_id` are rejected with 422):

```json
{
  "restaurant_id": "rest_123",
  "delivery_address": "12 Lake Road, Bengaluru",
  "items": [{"menu_item_id": "item_biryani", "quantity": 2}]
}
```

Validation (all → 422 `VALIDATION_ERROR` with a machine-readable
`details.reason`, except unknown restaurant → 404):

| Rule | `details.reason` |
| --- | --- |
| Restaurant must exist (404) and be available | `restaurant_unavailable` |
| Address 1–500 chars after trimming | `invalid_delivery_address` |
| ≥ 1 requested line; at most **20 distinct items** | `too_many_distinct_items` |
| Quantity **1–20** per distinct item (duplicate lines are merged) | `quantity_out_of_bounds` |
| Every item exists, belongs to the order's restaurant, is available, shares the restaurant currency | `unknown_item`, `item_not_in_restaurant`, `item_unavailable`, `currency_mismatch` |
| Missing/blank `Idempotency-Key` | code `IDEMPOTENCY_KEY_REQUIRED` |
| Key longer than 128 chars | `idempotency_key_too_long` |

Accepted response:

```
HTTP/1.1 202 Accepted
Location: /api/v1/orders/order_abc123
{"order_id":"order_abc123","status":"PENDING","currency":"INR",
 "total_amount_minor":71000,"version":1,
 "message":"Order accepted for asynchronous processing."}
```

### Idempotency semantics

- Scope is **(authenticated customer, Idempotency-Key)** under a database
  UNIQUE constraint — the database arbitrates concurrent duplicates, not
  application luck.
- The canonical request hash is computed over the normalized payload
  (address trimmed, item lines sorted by id, duplicate lines merged), so line
  reordering and split lines describe the *same* request.
- **Same key + same payload** → the original acceptance body and `Location`
  are replayed verbatim, with **zero** new rows — even after the order's real
  status has advanced. The client then reads current state from
  `GET /api/v1/orders/{id}`.
- **Same key + different payload** → `409` `IDEMPOTENCY_CONFLICT`
  (`details.reason = "payload_mismatch"`), nothing written.
- **Concurrent identical submissions** → exactly one order + one outbox
  event; the losers roll back completely and replay the winner's response.
- One transaction commits all five record types: `orders` (PENDING, v1),
  `order_items` (server-priced snapshots), `order_status_history` (v1),
  `checkout_idempotency` (hash + stored response) and `outbox_events`
  (`order.created`). If the commit fails, an error is returned — never a
  false 202.
- Records are retained for the assignment lifetime (a production design would
  expire them after the client's retry window, documented in
  `docs/reliability.md` when written).

### Broker independence

Checkout performs **no RabbitMQ I/O**. During a broker outage the API returns
202 as usual, the order exists in PostgreSQL, and its outbox row stays
`PENDING` until the dispatcher (Milestone 3) recovers. `/health/ready` keeps
returning `200` with `status: "degraded"` because PostgreSQL is the gating
dependency — an accepted PENDING order may be waiting for messaging recovery.

## Order status machine (assignment §6)

```
PENDING -> PAID -> CONFIRMED -> DRIVER_ASSIGNED   (success terminal)
PENDING -> PAYMENT_FAILED                         (terminal)
PAID    -> FAILED      CONFIRMED -> FAILED        (terminal)
```

No backward transitions; every transition increments `version` and appends
exactly one `order_status_history` row per `(order_id, version)`.
Workers apply transitions from Milestone 3 onward (row lock / compare-and-set).

## Event envelope (`order.created`)

Committed to `outbox_events` in the same transaction as the order, published
later by the dispatcher with `AMQP message_id = event_id`:

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

`event_id` is the immutable idempotency identifier retained across
redeliveries; child events keep `correlation_id` and set `causation_id` to the
incoming `event_id`. No addresses or other personal data are copied into
events.

## Health probes

- `GET /health/live` — process liveness only.
- `GET /health/ready` — **PostgreSQL required** (503 + `SERVICE_NOT_READY`
  envelope when unavailable). RabbitMQ is reported `up`/`down` but does not
  gate readiness (see Broker independence above).
