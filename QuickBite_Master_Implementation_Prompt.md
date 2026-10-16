# QUICKBITE — MASTER IMPLEMENTATION PROMPT

**Role:** Act as the lead software architect, senior FastAPI/PostgreSQL/RabbitMQ engineer, senior Flutter engineer, QA/reliability engineer, and technical writer for the **QuickBite: Full-Stack Food Delivery Order Processing System**, **Revised Assignment v2.0, 12 October 2026**.

**IMPORTANT:** This prompt is an implementation contract and planning guide, not permission to ignore the attached assignment. The attached document **`QuickBite - Revised Full-Stack Assignment.docx` is the source of truth**. At the beginning of a new chat, request the document if it is not attached; never claim to have read a document that is unavailable. The user will also supply three reference screenshots and the Dribbble design link `https://dribbble.com/shots/26644348-Food-Delivery-App-UI-Design`. Use those as *visual inspiration only*, not a replacement for required behavior or evidence of licensed assets. Implement faithfully and incrementally; do not expand the product without permission.

## 0. Non-negotiable operating instructions

1. **Before creating or changing code:** read the entire revised assignment (all 13 pages), extract its mandatory acceptance criteria, compare the existing repository against them if code already exists, and verify the planned implementation against **current official sources**. Record exact dependencies/image versions and platform/tooling prerequisites. If internet is not available, say so and distinguish unverified decisions rather than inventing citations or version claims.
2. Establish a concise **requirements traceability matrix** mapping document sections 1–21, especially sections 3–18, to source files, tests and demo evidence. Label requirements `REQUIRED`, `OPTIONAL`, and `OUT OF SCOPE`. Assignment requirements win over this prompt when wording differs. Do not replace the required architecture with microservices, Redis/Celery, Firebase, Supabase, a mock-only API, SQLite for final testing, Node.js, native Android/iOS UIs, WebSockets-only tracking, cloud services, or direct API-to-RabbitMQ checkout publishing.
3. Create a well-defined **implementation plan in the seven assignment milestones**, then implement one bounded milestone at a time. After each milestone, run checks, show changed files, test commands/results, remaining tasks and blockers. Never declare tests or platforms passed unless actually run. Preserve existing correct code; extend rather than needlessly rewrite.
4. Each concrete file below has one primary responsibility. If a better layout is justified, show a one-to-one responsibility mapping **before deviating**, and preserve all required behavior. Avoid placeholder handlers, duplicated domain logic, magical delays, unreachable UI, commented-out assertions and inert buttons.
5. Use **Docker Compose locally**, **PostgreSQL as authoritative state**, **FastAPI as the only Flutter-facing backend**, **RabbitMQ topic exchange and durable queues**, **transactional outbox**, **four independent Python workers**, **outbox dispatcher**, **retry scheduler**, **Flutter Web/Android/iOS**, and reproducible failure/load tests.
6. Respect the visual reference without copying copyrighted layouts/assets blindly. Use original Flutter widget composition and licensed/owned/demo food images. Keep the screenshots' warmth and feel while making all required order states, accessibility and desktop layouts unambiguous. A screenshot of “Order Confirmed” may only appear **after** the server reaches `CONFIRMED`; `202 Accepted/PENDING` is not a completed payment, restaurant acceptance or delivery.
7. Keep decisions and evidence in the repository. Do not introduce unrequested features (real payment methods, maps/GPS, actual delivery, tax calculations, social features, chat, AI recommendations, refunds, inventory management, push notifications, loyalty programs, app store publishing). If decorative UI hints at these, either omit the inactive control or clearly adapt it to required behavior.

## 1. Required end product and authoritative scope

Deliver a small but complete, runnable food-ordering system where a customer signs in, browses seeded restaurants/menus, adds items from **one restaurant per order**, checks out with server-priced totals and a delivery address, gets a rapid HTTP `202 Accepted`, watches asynchronous processing and its timeline, views persisted notifications and paginated history, and an admin can access a read-only cross-customer summary/list. Implement one Flutter codebase on web, Android and iOS; test all three when tooling exists (iOS requires macOS/Xcode). Real money, physical delivery, real restaurant partners, GPS, taxes/refunds, app-store publishing are outside scope. Poll visible active-order details approximately every two seconds; WebSockets are optional and **not necessary**.

**Terminal success** for this assignment is `DRIVER_ASSIGNED`, *not* `DELIVERED`. Legal successful flow: `PENDING -> PAID -> CONFIRMED -> DRIVER_ASSIGNED`. Legal failures: `PENDING -> PAYMENT_FAILED`; `PAID -> FAILED`; `CONFIRMED -> FAILED`. `PAYMENT_FAILED` and `FAILED` are terminal. Transient worker errors leave the last successful state intact. Notifications never change order business status. For a post-payment terminal failure do not claim a refund occurred (optional simulated refund is outside baseline).

The app must handle loading, invalid credentials, expiry, missing ownership, validation failure, no results, network outages and retries, rejected payment, restaurant/delivery failure, and pending orders awaiting RabbitMQ recovery.

## 2. Architecture contract

```text
            Flutter (Web, Android, iOS)
                     |
            HTTPS REST /api/v1
                     |
           +---------v----------+
           | FastAPI API         |---- authentication / ownership / validation
           +---------+----------+
                     |
             atomic PostgreSQL tx
                     |
   +-----------------v--------------------------------------------------+
   | PostgreSQL — sole authoritative source                             |
   | users, restaurants, menu_items, orders, order_items, history,       |
   | simulated_payments, driver_assignments, notifications,             |
   | checkout_idempotency, processed_events, outbox_events,             |
   | retry_jobs, quarantine_records                                     |
   +-----------------+--------------------------------------------------+
                     |
         leased outbox claim/publish (separate process)
                     |
              Outbox dispatcher
                     | durable messages, publisher confirms,
                     | mandatory routing and return detection
                     v
           RabbitMQ topic exchange `quickbite.orders`
             |             |              |                |
        order.created   order.paid   order.confirmed      order.#
             |             |              |                |
        payment.queue restaurant.queue delivery.queue notification.queue
             |             |              |                |
          Payment       Restaurant       Delivery        Notification
           worker        worker           worker            worker
             +-------------+--------------+----------------+
                     |
            locked PostgreSQL transaction:
         dedup + state/version + effects + history + next outbox event
                     |
          commit -> RabbitMQ manual ACK (NEVER ACK before commit)

   Retry scheduler -> eligible retry_jobs / targeted retry outbox ->
                      default RabbitMQ exchange -> ONLY failing worker queue
   Exhaustion/malformed -> quarantine_records + outbox ->
                      `quickbite.dead` (direct, routing `failed`) ->
                      `orders.dead-letter.queue`
```

**Critical boundaries:** Flutter never holds database/AMQP secrets and never publishes to RabbitMQ. FastAPI does not wait on background business workers during checkout. The HTTP success boundary is the committed order + outbox transaction. Workers share PostgreSQL and domain package for this training assignment: do not introduce individually owned microservice databases. RabbitMQ delivers work; PostgreSQL owns truth. Every domain state change and outgoing event commit in the *same* database transaction.

**Documented readiness choice:** Because committed orders may validly wait during a RabbitMQ outage, design `/health/ready` to require PostgreSQL (and other dependencies actually necessary for accepting orders). Surface broker/dispatcher degradation independently in operational reporting; be explicit that orders can remain PENDING until recovery. If a stricter readiness policy is selected, prove it doesn't contradict the requirement to accept during broker downtime. `/health/live` is process liveness and should not fail due to an external outage.

## 3. Concrete technology decisions and rationale

| Technology | Required? | Responsibility / reason |
|---|---|---|
| Python supported release | Yes | FastAPI, simulation, workers, operational scripts |
| FastAPI | Yes | Versioned REST endpoints, dependency-injected auth and OpenAPI |
| Pydantic | Yes | Typed request/response/event/config validation |
| SQLAlchemy 2.x | Yes | PostgreSQL mapping, async sessions and transactional domain operations |
| Alembic | Yes | Version-controlled migrations, no schema creation races |
| PostgreSQL supported release | Yes | Atomicity, row locks, uniqueness, `FOR UPDATE SKIP LOCKED`, durable authoritative state |
| RabbitMQ management-supported release | Yes | Persistent topic routing, durable queues, per-stage delivery, inspection |
| aio-pika | Yes | AMQP publisher confirmations, robust consumer connections, explicit ack/prefetch |
| Flutter stable + Dart | Yes | One cross-platform mobile/web UI |
| `http` Dart package | Choice | Cross-platform REST transport through a centralized client |
| Riverpod | Choice | Clear reactive auth/catalog/cart/order/admin state, testable providers; Provider/Bloc allowed if justified |
| go_router | Choice | Cross-platform route/navigation handling and web deep links |
| `flutter_secure_storage` | Choice | Encrypted/secure mobile token storage behind platform adapter |
| `shared_preferences` / platform persistence adapter | Choice | Persist non-secret pending checkout key **and exact request** until resolved; evaluate address handling/privacy |
| `intl` | Choice | Display localized INR currency and times; backend amounts remain integer minor units |
| Docker + Docker Compose | Yes | Reproducible API, workers, database, RabbitMQ, dispatcher/scheduler, web hosting |
| pytest and Flutter `flutter_test`/`integration_test` | Yes | Meaningful unit/integration, DB/broker and platform tests |
| HTTP load test (Python or approved tool) | Yes | 100+ orders; latency, worker scaling, backlog |

Choose exact versions only after checking *current compatibility* for the actual runtime and OS, pin runtime/container tags and project dependencies, and commit `pubspec.lock` plus the chosen Python lockfile (`uv.lock` if using `uv`, or a generated fully pinned requirements lock). Do not add extra infrastructure solely for convenience.

Helpful verified official references (re-check version-specific details while coding):
- FastAPI JWT/password hashing: https://fastapi.tiangolo.com/tutorial/security/oauth2-jwt/ (signed expiring bearer tokens; Argon2 via `pwdlib[argon2]` is a defensible choice)
- FastAPI CORS: https://fastapi.tiangolo.com/tutorial/cors/
- SQLAlchemy asyncio: https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html
- Alembic: https://alembic.sqlalchemy.org/en/latest/tutorial.html
- PostgreSQL locks/`SKIP LOCKED`: https://www.postgresql.org/docs/current/sql-select.html
- RabbitMQ topics: https://www.rabbitmq.com/tutorials/tutorial-five-python
- RabbitMQ publisher confirms/acks: https://www.rabbitmq.com/docs/confirms
- RabbitMQ dead-lettering/reliability: https://www.rabbitmq.com/docs/dlx and https://www.rabbitmq.com/docs/reliability
- aio-pika robust connections/ack behavior: https://docs.aio-pika.com/quick-start.html
- Docker Compose health-based readiness: https://docs.docker.com/compose/how-tos/startup-order
- Flutter adaptive design: https://docs.flutter.dev/ui/adaptive-responsive
- Flutter network client: https://docs.flutter.dev/cookbook/networking/fetch-data
- Flutter integration tests: https://docs.flutter.dev/testing/integration-tests
- Flutter iOS setup: https://docs.flutter.dev/platform-integration/ios/setup

**Implementation-specific researched guardrails:** aio-pika's `connect_robust` restores connections, but acknowledgements for deliveries from a *closed old channel* cannot be replayed onto the new channel; expect redelivery and deduplicate. Use a bounded finite `prefetch_count`, deliberate manual acknowledgement, and a separate publisher channel if necessary. Publisher confirms can acknowledge an *unroutable* publication; use mandatory routing and detect returned messages before marking an outbox row `SENT`. PostgreSQL `SKIP LOCKED` is appropriate for queue-like outbox/retry claiming, not for general end-user reads. Compose `depends_on` alone only establishes startup order; combine health checks, long-lived reconnection, and deliberately sequenced migrations/seeding.

## 4. Exact backend behavior: authentication, checkout and REST

### Authentication and authority
- Seed two or more fictional customer accounts and one fictional admin with **hashed** passwords. Registration, refresh token and password reset are optional and must not be treated as prerequisites.
- `POST /api/v1/auth/login`: JSON email/password -> signed, short-lived access token, expiry, role and user summary. `GET /api/v1/me`: authenticated user and role. Use expiring JWT or equivalent signed bearer tokens; validate signature, expiry and claims, then re-check active user/role server-side.
- Access rules: customer can only read their own orders/notifications/history; admins can see all via documented endpoints. `GET /orders/{id}` owner or admin. Unknown/another customer's order returns 404; absent/expired token 401; disallowed admin route 403. Never trust customer IDs from Flutter.
- Do not log tokens, passwords, full addresses; commit `.env.example` with placeholders only. HTTPS/WSS deployed; local HTTP debug exceptions documented. CORS explicit origins and allowed `Authorization`, `Content-Type`, `Idempotency-Key`; expose `Location` when browser needs it.

### Authoritative endpoint contract (use exactly these routes)

| Method | Route | Contract |
|---|---|---|
| POST | `/api/v1/auth/login` | public JSON email/password -> token, expiry, role, user |
| GET | `/api/v1/me` | signed in -> profile and role |
| GET | `/api/v1/restaurants` | signed in; paginated restaurant list |
| GET | `/api/v1/restaurants/{id}/menu` | signed in; paginated active/inactive menu and authoritative price fields |
| POST | `/api/v1/orders` | customer only; required `Idempotency-Key`; `202 Accepted`, stable acceptance/Location |
| GET | `/api/v1/orders` | customer's own orders; `page`, `page_size`, optional `status` |
| GET | `/api/v1/orders/{id}` | owner/admin; state/items/totals/failure/version/times |
| GET | `/api/v1/orders/{id}/history` | owner/admin; ordered transition history |
| GET | `/api/v1/orders/{id}/notifications` | owner/admin; paginated durable notification feed |
| GET | `/api/v1/admin/orders` | admin only; cross-customer pagination/status filter |
| GET | `/api/v1/admin/summary` | admin only; counts per status plus pending outbox/retry/quarantine |
| GET | `/health/live` | alive without external checks |
| GET | `/health/ready` | dependency readiness with bounded timeout, `503` when required dependency unavailable |

Pagination consistently uses `page>=1`, `page_size>=1`, max `page_size=100`, response `items`, `page`, `page_size`, `total`, with stable sorting. Error envelope always `{code, message, details, request_id}` including validation errors. UTC timezone-aware ISO-8601 timestamps. Document/export OpenAPI JSON. Expected statuses: 401 unauthenticated, 403 forbidden role, 404 unknown/other customer's order, 409 changed payload for reused idempotency key, 422 invalid input.

### Checkout invariants

Example request (do **not** accept a client-supplied price/total/customer ID):

```http
POST /api/v1/orders
Authorization: Bearer <token>
Idempotency-Key: <UUID generated once by Flutter>
Content-Type: application/json

{"restaurant_id":"rest_123","delivery_address":"12 Lake Road, Bengaluru","items":[{"menu_item_id":"item_biryani","quantity":2},{"menu_item_id":"item_lassi","quantity":1}]}
```

1. Obtain customer identity from validated auth. Normalize/validate address; require items from one restaurant, active menu items, positive quantities and documented limit **at most 20 distinct menu items** and **1–20 units per item**. Decide and document address boundaries. If duplicate menu item IDs appear, reject or normalize consistently; do not accidentally overrun quantity bounds.
2. Read authoritative prices/currency/availability from PostgreSQL **inside the checkout transaction**, calculate integer minor-unit totals, and snapshot menu ID/name/checkout price into `order_items`. Example INR 12.50 is `1250` minor units. Never use floating-point for stored money. Do not invent mandatory tax/delivery charges because the visual reference shows them.
3. Canonicalize normalized checkout payload; compute hash. Idempotency scope is `(customer_id, key)` under a unique constraint, retained for assignment lifetime. Same key+same payload returns the **original acceptance response and Location**, even if current order status has advanced; Flutter then fetches current status. Same key+different payload -> 409. Concurrent submissions create exactly one order and one `order.created` event. Use transaction/unique-conflict handling carefully to avoid a `500` on races.
4. Atomically commit: `orders(status=PENDING,version=1)`, `order_items`, `order_status_history(version=1)`, `checkout_idempotency` including original response, and `outbox_events(order.created)`. Commit failure -> error; never return accepted if commit failed. Broker state is not part of checkout's transaction.
5. Return `202 Accepted`, `Location: /api/v1/orders/{id}` and body `{order_id,status:"PENDING",currency,total_amount_minor,version:1,message:"Order accepted for asynchronous processing."}`. Order reads are authoritative and never infer success from elapsed time.

### Domain state and uniqueness
- Status values: `PENDING`, `PAID`, `CONFIRMED`, `DRIVER_ASSIGNED`, `PAYMENT_FAILED`, `FAILED`; preserve strict transitions and monotonic `version`. Use row-level `FOR UPDATE` or atomic compare-and-set with version, inside a DB transaction. Append status history once per `(order_id, version)` and never delete old history.
- Required models: `users`, `restaurants`, `menu_items`, `orders`, `order_items`, `order_status_history`, `simulated_payments`, `driver_assignments`, `notifications`, `processed_events`, `outbox_events`, `retry_jobs`, `quarantine_records`. Add `checkout_idempotency` or equivalent to meet explicit deduplication contract. Unique payment per order, driver assignment per order, notification per customer/event, processed `(consumer_name,event_id)`, history `(order_id,version)`, retry `(consumer_name,event_id,attempt)`, publication identity unique.
- Seed deterministic menus, prices, currency (INR is fine), fictional drivers; do not depend on remote food APIs or real secrets.

## 5. Messaging, outbox, consumer and retry contracts

### RabbitMQ topology — declare **before** publishing

| Exchange / queue | Type | Binding/routing | Purpose |
|---|---|---|---|
| `quickbite.orders` | durable topic exchange | — | all normal business events |
| `payment.queue` | durable queue | `order.created` | payment worker |
| `restaurant.queue` | durable queue | `order.paid` | restaurant worker |
| `delivery.queue` | durable queue | `order.confirmed` | delivery worker |
| `notification.queue` | durable queue | **`order.#`** | all supported order events, including `order.payment.failed` and `order.driver.assigned` |
| `quickbite.dead` | durable direct exchange | routing `failed` | quarantine output |
| `orders.dead-letter.queue` | durable queue | bind to `quickbite.dead` with `failed` | inspect failed envelopes |

Main queues are durable, **non-exclusive**, **not auto-delete**; persistence is required for messages and RabbitMQ's Compose volume. Declare bindings idempotently during a deliberate topology-init service/startup step before outbox dispatch, so consumer shutdown never causes an event to have zero queues. Manual consumer acknowledgements, bounded prefetch, reconnect backoff and graceful shutdown are mandatory. Scale worker *process instances* on the same logical queue rather than creating one queue per worker replica.

### Event envelope (required fields)

```json
{
  "event_id":"evt_created_abc123",
  "schema_version":1,
  "event_type":"order.created",
  "order_id":"order_abc123",
  "order_version":1,
  "occurred_at":"2026-10-12T09:00:00Z",
  "correlation_id":"req_checkout_123",
  "causation_id":null,
  "data":{"customer_id":"user_1","restaurant_id":"rest_123"}
}
```

Required types: `order.created`, `order.paid`, `order.payment.failed`, `order.confirmed`, `order.driver.assigned`, `order.failed`. Set AMQP `message_id=event_id`, content type `application/json`, durable/persistent delivery, immutable identity across redeliveries. Child events keep original `correlation_id` and set `causation_id` to parent event ID. Avoid PII/secrets in events; workers query current PostgreSQL state. Unsupported schema versions or malformed events -> safe quarantine, **not** infinite retry. A valid future notification event intentionally ignored can be logged and acknowledged, if appropriate. Store retry attempts in delivery metadata/DB, **not** by changing domain event ID.

### Outbox dispatcher
- `outbox_events` stores exact payload, destination exchange/routing key, immutable publication identity, availability, `PENDING/CLAIMED/SENT` (or equivalent), claim/lease and timestamps. Claim batches using PostgreSQL row locks/leases safe with multiple dispatchers (`FOR UPDATE SKIP LOCKED` is appropriate for claim selection). Ensure leases can expire and recover from crashes.
- Publish via aio-pika with publisher confirms **and mandatory routing/unroutable return handling**; mark `SENT` only after positive publish result *and* no mandatory return. Failures keep event eligible for later attempt. Do not hold a DB transaction open unnecessarily while awaiting network IO; use a lease and carefully persist the result, proving no loss. A crash after broker publish but before `SENT` may duplicate publish: **assume at-least-once and rely on worker idempotency**.
- Do not make HTTP checkout synchronously publish events. Do not use RabbitMQ as the authority for order status.

### Consumer transaction order
1. Receive and parse envelope; validate schema/type. Identify **logical consumer name** (`payment`, `restaurant`, `delivery`, `notification`), never instance hostname, for deduplication.
2. Begin DB transaction and lock order row as needed. Check unique `(consumer_name,event_id)`; if processed, no-op then ACK. Compare order version/state and reject regression. When prerequisites are unexpectedly not ready, perform **bounded** deferred retry/quarantine, not silent loss.
3. Apply the single permitted simulated effect: insert payment/assignment/notification, update order status/version if needed, append history, persist **new outgoing event to outbox**, and processed-event marker **in the same DB transaction**. Commit.
4. **Only after DB commit**, ACK RabbitMQ. If commit fails, never ACK as successful or mark processed. If channel closes after commit before ACK, redelivery must safely no-op. Process duplicates, competing workers, and reordered events without backwards transition.
5. Respect permanent simulation failure: payment -> `PAYMENT_FAILED` + `order.payment.failed`; restaurant/delivery -> `FAILED` + `order.failed`; notification failure never turns the order into failed payment.

### Deterministic retry/quarantine
- Default **initial attempt + three delayed retries** at approximately `2s`, `10s`, `30s` after corresponding failures; configurable through environment and documented.
- On transient failure, roll back business effect, then in **another atomic DB transaction** create unique `retry_jobs(consumer,event,attempt)` plus scheduled targeted outbox publication **before ACK of original**. If the transaction to store retry fails, leave original unacknowledged and back off/reconnect: never ACK away its only copy.
- Retry scheduler makes due retries publishable. Directly route a retry to **only the failing queue** using RabbitMQ's default exchange with routing key equal to the original target queue name (e.g. `payment.queue`) and mandatory routing; never re-publish to `quickbite.orders`, which would awaken unrelated subscribers.
- Preserve event ID; durable delivery attempts are incremented. Ensure a duplicate failure handling cannot generate a second retry for the same attempt; a successfully processed duplicate does not repeat effects.
- After max attempts, atomically insert a `quarantine_records` row and outbox event destined to `quickbite.dead` routing `failed`. Preserve original envelope, consumer/queue, attempts, reason, timestamps. Set terminal order state according to failing stage and emit appropriate domain failure event. Notification quarantine leaves order business state unchanged. A malformed event without valid order cannot mutate an unrelated order. ACK only after durable quarantine transaction commit.
- TTL/DLX retry alternative is allowed by assignment only if the same per-consumer targeting, safety, counters and demonstrated at-least-once behavior are met; prefer the explicit DB retry scheduler baseline above.
- No tight `nack(requeue=true)` loop. Graceful shutdown must stop accepting new messages and finish/abandon in-flight safely. Do not overpromise single-node RabbitMQ durability against total disk loss or full cluster high availability.

### Deterministic demo controls
- Demo modes are selected through protected script/dev/test configuration only: payment always succeeds, fails twice then succeeds, always fails, crash after a chosen checkpoint; restaurant terminal failure; delivery terminal failure; notification worker failure. Never allow an ordinary checkout body to select processing outcome. Stable IDs and structured logs make scenarios reproducible. Real payment integration is explicitly not required.

## 6. Flutter product and design rules

**Design reference:** `https://dribbble.com/shots/26644348-Food-Delivery-App-UI-Design` (Sujon Hossain for Oripio) plus user-uploaded reference screenshots. Reference shows warm off-white surfaces, high-contrast black serif-style headings, vivid coral-red/orange call-to-action elements, soft peach quantity controls, pill buttons, round food photography, rounded white cards, airy spacing, and clean compact mobile hierarchy. Dribbble's listed palette includes `#EFEBE9`, `#B3B6B2`, `#E72512`, `#0C0C07`, `#544329`, `#B5A44A`, `#B15120`; define actual accessible Flutter color tokens based on visual inspection, not arbitrary hardcoded colors in individual widgets. Use an appropriately licensed serif headline font or a system fallback; readable sans-serif body; sufficient contrast and semantic labels. Do not assume use rights to the Dribbble artwork/photographs. Use local licensed demo food images and record credits/rights in docs.

**Screens that MUST exist and function:**
1. **Sign-in:** email/password, progress state, invalid credentials, network failure, token expiry; visually consistent with reference but no unnecessary onboarding blocker. Seeded accounts; no registration requirement.
2. **Restaurant list:** fetch authenticated paginated restaurants; attractive restaurant/food cards; empty/loading/errors, desktop grid and narrow mobile list. Optional purely visual category chips should not act like unsupported filtering; don't add nonworking search bar/buttons.
3. **Menu/detail:** restaurant title and paginated menu with **name, price, currency, availability**; rounded food cards and food photography; quantity/add-to-cart controls; prevent unavailable item checkout; one-restaurant cart enforcement.
4. **Cart:** remove/update quantities, subtotal from displayed server-origin menu snapshot (estimated only), empty state, one restaurant, address entry; actual accepted amount still determined by backend.
5. **Checkout:** delivery address validation, optional read-only simulated payment explanation **not** actual payment provider selection; local durable pending `(idempotency_key,canonical_request)` saved before sending; disable duplicate taps; on timeout/unknown result retry **same key and request**; do not automatically generate a new order. Keep draft cart where practical.
6. **Acknowledgement:** on `202`, show server order ID, authoritative INR total and `PENDING` status, *not* false “paid/confirmed”. Link to tracking; handle pending due to broker downtime clearly.
7. **Order details/tracking:** timeline of server state transitions, current state, optional assigned driver, persisted notifications, readable permanent failure reason, manual refresh. Poll roughly every 2 seconds only while active screen is visible/foreground; stop/reduce when backgrounded/disposed/terminal, backoff network failures and refresh when resumed. No invented driver GPS map.
8. **History:** paginated customer's own orders, refresh independent of details polling, navigate to details, terminal/failed order readability.
9. **Admin:** only authenticated admin, read-only all-orders list, pagination/status filters and summary counts including outbox/retry/quarantine; customer gets forbidden.

**UI behavior:** use reusable widgets, typed Dart models, centralized HTTP client and strongly separated presentation/state/repositories/models. Adapt at phone/tablet/desktop widths via LayoutBuilder/breakpoints without overflow; web keyboard navigation, logical focus traversal, text scaling, visible labels, semantic controls, accessible touch targets. Do not copy the reference's tax line, interactive map, real payment options, follow/chat, AI suggestion, loyalty/rewards or delivery-completed wording as actual capabilities. You may present food imagery and modern styling on required screens. For desktop, use wider max-width content, card grid and perhaps a cart/order side panel; never simply stretch a 390px mobile design to full 1440px width.

**Cross-platform storage/network:** expose `API_BASE_URL` via `--dart-define`; never bundle secrets. Android emulator usually reaches local host via `10.0.2.2`; Chrome/iOS simulator commonly use appropriate host `localhost`; physical phones require LAN-reachable HTTPS/dev endpoint. Web token may stay **in memory** and require re-login after page reload; mobile persisted tokens should use platform-appropriate secure storage. Never persist passwords. Pending checkout key/request must survive expected timeout/reload until outcome known, through a documented non-secret checkout storage adapter (mind address privacy). Flutter web must not import mobile-only libraries unconditionally. Use HTTPS for deployments and debug-only cleartext exceptions. Support web deep links after refresh with SPA fallback.

## 7. Mandatory repository blueprint — each file's responsibility

The following is a **concrete planned file inventory**. Create packages' `__init__.py`, generated Flutter platform files and assets as needed; don't create empty speculative modules merely to inflate file count. The owner/responsibility annotation is authoritative for implementing this blueprint. If a listed responsibility can be implemented more simply in an existing file, first explain the one-to-one mapping. Avoid business logic in route handlers/widgets and avoid putting all database models in one uncontrolled monolith.

### 7A. Root and infrastructure

| File | Responsibility / must contain |
|---|---|
| `README.md` | Accurate prerequisites, architecture, demo credentials, environment, exact setup/run/seed/test/build commands, platform URLs, expected output, recovery/troubleshooting, and honest limitations. |
| `.env.example` | Placeholder `DATABASE_URL`, `AMQP_URL`, JWT issuer/algorithm/secret/expiry, CORS origins, API/management ports, simulation delays, protected failure flags, retry delays/attempts, logs, polling where applicable. Never real secrets. |
| `.gitignore` | Ignore `.env`, keys, build outputs, caches and local DB data; **do not** ignore dependency lockfiles or intentional evidence. |
| `compose.yaml` | Services `postgres`, `rabbitmq`, `api`, `payment-worker`, `restaurant-worker`, `delivery-worker`, `notification-worker`, `outbox-dispatcher`, `retry-scheduler`, `web`, plus deliberate one-shot migrations/seed/topology initialization as applicable. Health checks, private networking, data volumes, `--scale payment-worker=3` compatible, no fixed `container_name`, no fixed worker host ports. |
| `backend/Dockerfile` | Pinned Python runtime build and dependency install; reusable image to run API/workers/dispatcher/scheduler with differing commands and health setup. |
| `infra/web.Dockerfile` | Multi-stage pinned Flutter toolchain web build and small pinned web server runtime (document pin decision). |
| `infra/nginx.conf` | Serve Flutter SPA, fallback to `index.html` for deep links, cache/static handling, health route as chosen; no embedded API secrets. |
| `infra/rabbitmq.conf` | Supported RabbitMQ management/local broker configuration, persist broker data, restrict management exposure locally. Do not use accidental public production ports. |
| `backend/.dockerignore` and `infra/.dockerignore` | Exclude local secrets, artifacts, caches and irrelevant copied files from actual Docker build contexts; add a root `.dockerignore` if building at repository root. |
| `docs/requirements-matrix.md` | Assignment section -> feature -> implementation files -> test -> evidence; explicit optional/out-of-scope exclusions. |
| `docs/architecture.md` | Authoritative client/API/DB/outbox/RabbitMQ/worker/retry/quarantine diagram with boundaries and state/event sequence. |
| `docs/data-model.md` | Every table, column, constraint, relationships, migrations, indexes, snapshot money, UTC and versioning. |
| `docs/api-contract.md` | Exact REST request/response, auth, statuses, pagination, standardized errors, CORS, `Location`, OpenAPI export instructions. |
| `docs/event-contract.md` | Exchange/queue/binding definitions; six event names, JSON schema versioning, immutable identity, causation/correlation and retries. |
| `docs/reliability.md` | Transaction/ACK/publish boundaries, leases, idempotency, crash windows, retry/quarantine policy, broker outages and limitations. |
| `docs/platforms.md` | Actual Chrome, Android emulator/device, iOS simulator commands, required host URLs, security, build evidence and limitations. |
| `docs/testing.md` | Exact backend/Flutter/integration test commands, external-service fixtures, acceptance matrix, reproducible failure injections. |
| `docs/performance-report.md` | Raw load conditions, 100+ orders, p50/p95, total time, orders/s, backlog, one vs three payment workers repeated twice, bottlenecks and honest misses. |
| `docs/demo.md` | Timed executable live-demo checklist matching all 10 required demo steps. |
| `docs/engineering-report.md` | Design choices, outbox/ack/retry/dedup proof, security tradeoffs, measured scaling, known limitations and test evidence. |
| `docs/design-assets.md` | Dribbble credit as inspiration, source/license/attribution for fonts and food images, theme tokens, no claim of licensed reuse. |
| `docs/evidence/README.md` | Index to screenshots, terminal output, logs, platform screenshots/videos, links and dates; do not invent artifacts. |

### 7B. Backend configuration, persistence and models

| File | Responsibility / must contain |
|---|---|
| `backend/pyproject.toml` | Python project metadata, explicit pinned-compatible first-order dependencies including FastAPI, Pydantic, SQLAlchemy, Alembic, aio-pika, Postgres async driver, password hash/JWT, pytest. Choose one package manager. |
| `backend/uv.lock` **or** `backend/requirements.lock` | Commit generated exact dependency lock from chosen tool; use same lock in container/CI; do not manually invent transitive hashes. |
| `backend/alembic.ini` | Alembic config without embedded real credentials; DB URL supplied from validated runtime config. |
| `backend/migrations/env.py` | Alembic environment, import all model metadata and use configured PostgreSQL connection and naming conventions. |
| `backend/migrations/script.py.mako` | Standard reproducible Alembic migration script template. |
| `backend/migrations/versions/0001_initial.py` | Initial normalized schema, explicit FK, unique constraints, indexes, types, checkout idempotency, event/outbox/retry/quarantine tables; reversible migration. Additional numbered migrations only when needed. |
| `backend/app/__init__.py` | Python package marker, no side effects. |
| `backend/app/main.py` | FastAPI factory/lifespan, router mounting, middleware, exception handlers and OpenAPI; never embed worker loops or synchronous broker publish during checkout. |
| `backend/app/core/config.py` | Pydantic-validated `Settings` for URLs, JWT, allowed origins, retry/deadline/simulation parameters; fail fast on unsafe/missing settings. |
| `backend/app/core/security.py` | Password hashing/verification, signed short-lived token creation/validation and claim rules. |
| `backend/app/core/errors.py` | Domain exception types/status mapping and consistent `code/message/details/request_id` response. |
| `backend/app/core/logging.py` | Structured logs with service, correlation/request ID, order/event ID, attempt, transition, elapsed/result; redact sensitive values. |
| `backend/app/core/middleware.py` | Request/correlation ID, timing, logging/redaction and consistent tracing context. |
| `backend/app/db/base.py` | Declarative SQLAlchemy Base, naming conventions and metadata assembly. |
| `backend/app/db/session.py` | Async engine/sessionmaker, bounded pool, request session dependency and safe transaction lifecycle; never share `AsyncSession` across concurrent tasks. |
| `backend/app/db/models/__init__.py` | Import models into Alembic metadata and expose well-named model classes. |
| `backend/app/db/models/user.py` | User ID, email uniqueness, password hash, customer/admin role, active status, UTC timestamps. |
| `backend/app/db/models/restaurant.py` | Seeded restaurant name/description/availability/currency and menu relationship. |
| `backend/app/db/models/menu_item.py` | Restaurant relation, name, price integer minor, currency, available flag and image/description metadata. |
| `backend/app/db/models/order.py` | Customer/restaurant/address, currency/total minor, enum status, monotonic version, failure code, nullable driver reference, UTC times. |
| `backend/app/db/models/order_item.py` | FK order/menu item, snapshot name/price minor, quantity and order snapshot total contribution. |
| `backend/app/db/models/order_status_history.py` | Append-only transitions with order/version uniqueness, status, timestamp, optional failure code. |
| `backend/app/db/models/simulated_payment.py` | One simulated payment effect per order, stable idempotency/payment reference, status and failure details. |
| `backend/app/db/models/driver_assignment.py` | One assignment per order, seeded driver ID/display name and assignment time. If a separate `drivers` table is added, document why. |
| `backend/app/db/models/notification.py` | Customer + event dedup unique key, order FK, message/type/time, sequence for stable display. |
| `backend/app/db/models/checkout_idempotency.py` | Unique `(customer_id,key)`, canonical hash, original accepted HTTP body/Location and creation time. |
| `backend/app/db/models/processed_event.py` | Unique `(logical_consumer_name,event_id)`, recorded processing outcome/time, no instance-local-only dedup. |
| `backend/app/db/models/outbox_event.py` | Immutable publication payload+identity, exchange/routing key, state, available_at, lease/claim, published timestamp and errors. |
| `backend/app/db/models/retry_job.py` | `(consumer,event,attempt)` unique, original event reference, target queue, due time, state and diagnostic failure. |
| `backend/app/db/models/quarantine_record.py` | Original envelope, failing queue/consumer, attempts, code/reason, timestamps and publication reference. |

### 7C. Backend schemas, repositories, domain services and API

| File | Responsibility / must contain |
|---|---|
| `backend/app/schemas/common.py` | UTC timestamps, pagination models, standardized error envelope and common fields. |
| `backend/app/schemas/auth.py` | Login input, token/expiry/role/user response and self-profile models. |
| `backend/app/schemas/catalog.py` | Restaurant/menu list item and paginated response schemas (money in minor units). |
| `backend/app/schemas/orders.py` | Checkout item/request, acceptance, detail, history, notification, order list, status enums and input bounds. |
| `backend/app/schemas/admin.py` | Admin order list and status/backlog summary types. |
| `backend/app/schemas/events.py` | Pydantic event envelope, `schema_version`, event types/data and quarantine envelope types. |
| `backend/app/repositories/users.py` | Find user by email/ID; no authentication decisions in raw SQL layer. |
| `backend/app/repositories/catalog.py` | Paginated restaurant/menu queries, availability and authoritative menu lookup for checkout. |
| `backend/app/repositories/orders.py` | Locked order fetch, ownership-scoped list/read, append-only history and associated data reads. |
| `backend/app/repositories/idempotency.py` | Unique checkout key/hash storage/read and conflict/concurrency-safe lookup. |
| `backend/app/repositories/messaging.py` | Transactional processed-event/outbox/retry/quarantine DB operations, publish claims, dedup queries. |
| `backend/app/services/auth_service.py` | Validate credential against hashed secret, issue token, produce customer/admin summary. |
| `backend/app/services/catalog_service.py` | Restaurant/menu pagination and availability semantics. |
| `backend/app/services/checkout_service.py` | **Sole** order-acceptance transaction: server pricing, validation, customer+key hash/idempotency, PENDING order, snapshot, history and `order.created` outbox. |
| `backend/app/services/order_query_service.py` | Owner/admin read authorization, current state, status history, notification feed and paginated history. |
| `backend/app/services/order_state_machine.py` | Central allowed-transition map, lock/CAS version increment, append-only history and prevention of regressions. |
| `backend/app/services/payment_service.py` | Deterministic simulation, once-only payment record, PENDING -> PAID / permanent PAYMENT_FAILED, child outbox event. |
| `backend/app/services/restaurant_service.py` | Deterministic restaurant decision, PAID -> CONFIRMED/FAILED, child outbox event. |
| `backend/app/services/delivery_service.py` | Assign seeded driver once, CONFIRMED -> DRIVER_ASSIGNED/FAILED, emit success/failure event. |
| `backend/app/services/notification_service.py` | Render and persist one customer notification per logical event, regardless of notification worker replica; no business-status effects. |
| `backend/app/services/retry_service.py` | Classify transient/permanent/stale/precondition errors, bounded delayed targeted retry transactions and counters. |
| `backend/app/services/quarantine_service.py` | Atomic quarantine plus dead-exchange outbox, terminal order status and failure event where applicable. |
| `backend/app/services/admin_service.py` | Cross-customer read-only pagination and status/outbox/retry/quarantine aggregates. |
| `backend/app/api/deps.py` | Session, token parsing, current active user, customer-only/admin-only and request ID dependencies. |
| `backend/app/api/v1/router.py` | Aggregate exact `/api/v1` route modules, avoiding duplicated prefixes. |
| `backend/app/api/v1/auth.py` | `POST /api/v1/auth/login` and `GET /api/v1/me` using exact route registration (not `/api/v1/auth/me`); thin typed handlers. |
| `backend/app/api/v1/restaurants.py` | `GET /restaurants`, `GET /restaurants/{id}/menu`; pagination and typed responses. |
| `backend/app/api/v1/orders.py` | `POST /orders`, `GET /orders`, `GET /orders/{id}`, `/history`, `/notifications`; owner checks delegated to services; correct 202/Location. |
| `backend/app/api/v1/admin.py` | `GET /admin/orders`, `GET /admin/summary`, strict admin dependency, no writes. |
| `backend/app/api/health.py` | `/health/live` and `/health/ready`, dependency timeouts and explicit readiness semantics. |

### 7D. Messaging runtime and worker processes

| File | Responsibility / must contain |
|---|---|
| `backend/app/messaging/topology.py` | Durable topic/direct exchange and named queue declarations/bindings, idempotent topology init, `order.#` notification binding, dead exchange/queue. |
| `backend/app/messaging/envelope.py` | Build/parse/version-check six domain event envelopes, immutable IDs, UTC times, AMQP message properties and no PII. |
| `backend/app/messaging/publisher.py` | aio-pika robust AMQP publish adapter with confirms, mandatory routing/returned-message handling, persistent delivery and failure results. |
| `backend/app/messaging/outbox_dispatcher.py` | Separate process loop: claim/lease available records, publish/confirm, update sent/failure, lease expiration, graceful stop, structured metrics. |
| `backend/app/messaging/retry_scheduler.py` | Separate process: claim due retry jobs, release/activate targeted outbox messages, prevent duplication under multiple scheduler replicas; a committed retry job/outbox link must survive scheduler crash. |
| `backend/app/messaging/consumer_runtime.py` | Shared worker connection, queue consume loop, explicit ACK after DB commit, prefetch, reconnect, shutdown, exception classification and bounded retries. |
| `backend/workers/__init__.py` | Worker package, no side effects. |
| `backend/workers/payment.py` | Entrypoint consuming `payment.queue`, invoke payment service under shared runtime; logical consumer `payment`. |
| `backend/workers/restaurant.py` | Entrypoint for `restaurant.queue`, invoke restaurant service; logical consumer `restaurant`. |
| `backend/workers/delivery.py` | Entrypoint for `delivery.queue`, invoke delivery service; logical consumer `delivery`. |
| `backend/workers/notification.py` | Entrypoint for `notification.queue`, event-type awareness and idempotent persisted notifications; logical consumer `notification`. |
| `backend/scripts/init_topology.py` | Deliberate one-shot queue/exchange/binding initialization before outbox processing; fail clearly if unavailable. |
| `backend/scripts/seed_demo.py` | Repeatable idempotent seed with hashed fictional customers/admin, restaurants, menus, drivers; reset only by explicitly documented dev command. |
| `backend/scripts/export_openapi.py` | Deterministically export FastAPI OpenAPI contract to committed docs file after routes are assembled. |

### 7E. Required backend tests (pytest; real infrastructure where necessary)

| File | Responsibility / must contain |
|---|---|
| `backend/tests/conftest.py` | Isolated test DB/broker fixtures, seeded IDs, no production secrets; fixture cleanup and reproducible environment. |
| `backend/tests/test_auth_and_access.py` | Valid/invalid/expired JWT, admin denial, cross-customer 404, token failures. |
| `backend/tests/test_catalog_and_checkout_validation.py` | Menu inactive, invalid/mixed restaurants, bad address/qty, no trusted client total, rollback without orphan order/outbox. |
| `backend/tests/test_checkout_idempotency.py` | Same key/payload replay, conflict 409, concurrent same-key submissions, client timeout replay; one order/event. |
| `backend/tests/test_api_contract.py` | `202/Location`, pagination max 100, UTC timestamps, standardized 401/403/404/409/422, versioned docs. |
| `backend/tests/test_state_machine.py` | All legal statuses, no backwards transitions, version/history uniqueness, terminal protection. |
| `backend/tests/test_rabbitmq_routing.py` | Real topic exchange bindings, `order.#` notification coverage, queue persistence across consumer shutdown. |
| `backend/tests/test_worker_happy_path.py` | Real Postgres/RabbitMQ processing through all workers with unique payment/assignment/notifications/history. |
| `backend/tests/test_processed_event_dedup.py` | Repeated event, two concurrent workers and post-commit-before-ack redelivery: committed effect once. |
| `backend/tests/test_outbox_recovery.py` | Broker down after acceptance and dispatcher crash after publish/before mark sent; eventual processing without missing events. |
| `backend/tests/test_retry_and_quarantine.py` | Fail-twice-succeed, approx configured delays, always fail -> once-logical quarantine, targeted queue no fanout. |
| `backend/tests/test_notification_isolation.py` | Stop notification worker and verify order completes, backlog drains, no duplicate notifications. |
| `backend/tests/test_ordering_and_concurrency.py` | Duplicate/out-of-order/future-state deliveries cannot regress or repeat effects. |
| `backend/tests/test_worker_shutdown.py` | Process kill/shutdown around commit and ACK, bounded in-flight handling and recovery. |
| `backend/tests/test_health_and_config.py` | DB readiness, broker-degraded acceptance semantics, CORS, invalid config, no logs with credentials. |

Use pytest unit tests with transaction isolation plus **actual PostgreSQL and actual RabbitMQ integration tests**. Mock-only tests are insufficient evidence for ACK, redelivery and concurrent uniqueness. Tests may use Compose-provisioned services or a documented fixture setup. Do not hide skips or mark unavailable integration tests as passed.

### 7F. Flutter root, theme, client, cross-platform services and reusable UI

| File | Responsibility / must contain |
|---|---|
| `frontend/pubspec.yaml` | Flutter SDK constraints, pinned-compatible `http`, state management, routing, secure storage, non-secret pending storage, intl, assets/fonts and test deps. |
| `frontend/pubspec.lock` | Commit resolved Flutter dependency versions. |
| `frontend/analysis_options.yaml` | Lints/type/style, require analyzer pass. |
| `frontend/lib/main.dart` | `WidgetsFlutterBinding`, config/bootstrap, Riverpod root (or chosen state approach) and `runApp`. |
| `frontend/lib/app/app.dart` | MaterialApp theme/localization/navigation wiring, authenticated shell and initial state. |
| `frontend/lib/app/router.dart` | Named routes, auth/admin redirects, web deep links, order URL parsing and unknown routes. |
| `frontend/lib/app/theme/app_colors.dart` | Named semantic colors from Dribbble-inspired palette with WCAG-readable contrast variants. |
| `frontend/lib/app/theme/app_theme.dart` | Light theme, serif display/sans body type styles, controls, card radius, buttons and responsive spacing. |
| `frontend/lib/core/config/app_config.dart` | `const String.fromEnvironment('API_BASE_URL')` and safe public runtime configuration validation; no secrets. |
| `frontend/lib/core/network/api_client.dart` | Centralized `http.Client`, base URL, timeout, JSON parsing, bearer auth, `Idempotency-Key`, `Location`, request IDs, cancellation-aware requests and standard error mapping. |
| `frontend/lib/core/network/api_exception.dart` | Typed network/validation/401/403/404/409/422/retry-unknown exceptions. |
| `frontend/lib/core/storage/token_store.dart` | Interface for token lifecycle; never save a password. |
| `frontend/lib/core/storage/mobile_token_store.dart` | Mobile secure token persistence via compatible package; no browser assumptions. |
| `frontend/lib/core/storage/web_token_store.dart` | In-memory access token on web, with expected re-login on reload. |
| `frontend/lib/core/storage/token_store_factory.dart` | Platform-safe selection and conditional import strategy; prevent unconditional mobile-only imports in web build. |
| `frontend/lib/core/storage/pending_checkout_store.dart` | Persist `(UUID key, exact checkout request, creation time)` before submit, read/reuse after timeout/reload and clear only after known outcome; document safe handling of stored address. |
| `frontend/lib/core/utils/money.dart` | Format integer minor-unit amounts with currency (INR), no floating authoritative calculations. |
| `frontend/lib/core/utils/date_time.dart` | Parse UTC ISO timestamps and render consistent local display timestamps. |
| `frontend/lib/core/widgets/responsive_scaffold.dart` | Narrow phone / tablet / desktop layout constraints and focus/keyboard support. |
| `frontend/lib/core/widgets/primary_button.dart` | Accessible coral CTA, loading/disabled states and semantics. |
| `frontend/lib/core/widgets/async_state_panel.dart` | Reusable loading/empty/error/offline/expired state components with real retry actions. |
| `frontend/lib/core/widgets/food_image.dart` | Licensed local food image with fallback, clip shape and accessibility description. |
| `frontend/lib/core/widgets/quantity_stepper.dart` | Accessible plus/minus with min/max and disabled states. |
| `frontend/lib/core/widgets/status_chip.dart` | Color+text status badge distinguish PENDING/PAID/CONFIRMED/ASSIGNED/FAILURE. |
| `frontend/lib/core/widgets/app_top_bar.dart` | Reusable navigation/account/order controls; no inert decorative interactions. |

### 7G. Flutter feature-specific files

| File | Responsibility / must contain |
|---|---|
| `frontend/lib/features/auth/models/user.dart` | Typed customer/admin user and role. |
| `frontend/lib/features/auth/models/login_result.dart` | Expiring access token, role, expiry and user summary JSON mapping. |
| `frontend/lib/features/auth/data/auth_api.dart` | Login/me requests through only the central API client. |
| `frontend/lib/features/auth/state/auth_controller.dart` | Login/logout/expiry, current user/role, token-store integration, safe authenticated route refresh. |
| `frontend/lib/features/auth/ui/login_screen.dart` | Dribbble-inspired branded sign-in form with loading, 401, offline, semantic labels. |
| `frontend/lib/features/catalog/models/restaurant.dart` | Typed restaurant record and availability. |
| `frontend/lib/features/catalog/models/menu_item.dart` | Typed menu item, price integer minor, currency, availability and image reference. |
| `frontend/lib/features/catalog/data/catalog_api.dart` | Paginated GET restaurant/menu calls. |
| `frontend/lib/features/catalog/state/catalog_controller.dart` | Paginated loading/refresh/cache/error states for restaurant and menu views. |
| `frontend/lib/features/catalog/ui/restaurants_screen.dart` | Restaurant browse, responsive grid/list and navigable actual cards. |
| `frontend/lib/features/catalog/ui/menu_screen.dart` | Required restaurant menu details and add-to-cart, unavailable feedback, cross-restaurant guard. |
| `frontend/lib/features/catalog/ui/restaurant_card.dart` | Reusable photo/text responsive restaurant presentation. |
| `frontend/lib/features/catalog/ui/menu_item_card.dart` | Reusable Dribbble-inspired food item card with price/availability and working add control. |
| `frontend/lib/features/cart/models/cart_line.dart` | Menu item snapshot, restaurant ID, quantity and display-only subtotal helper. |
| `frontend/lib/features/cart/state/cart_controller.dart` | Add/update/remove, one-restaurant guard, 1–20 qty and <=20 unique items, cart draft persistence if feasible. |
| `frontend/lib/features/cart/ui/cart_screen.dart` | Cart rows, removal/stepper, subtotal and navigate to validated checkout. |
| `frontend/lib/features/cart/ui/checkout_screen.dart` | Address input, durable pending exact request/key, one active submit, timeout/retry same key, distinguish unknown outcome from confirmed failure, safe server acceptance routing. |
| `frontend/lib/features/cart/ui/cart_line_tile.dart` | Food row, photo, quantity, price and removal control. |
| `frontend/lib/features/orders/models/order.dart` | Typed order details: current status, total, currency, failure, version, driver, items, timestamps. |
| `frontend/lib/features/orders/models/order_history_entry.dart` | Versioned status transition timeline record. |
| `frontend/lib/features/orders/models/order_notification.dart` | Persisted event-based notification model. |
| `frontend/lib/features/orders/data/orders_api.dart` | POST checkout, GET own orders/details/history/notifications with typed decoding. |
| `frontend/lib/features/orders/state/order_list_controller.dart` | Paginated history loading/refresh and optional status filter. |
| `frontend/lib/features/orders/state/order_detail_controller.dart` | Current order/history/notifications, server truth and refresh. |
| `frontend/lib/features/orders/state/order_polling_controller.dart` | ~2s foreground active polling, pause/background/dispose/terminal stop, exponential error backoff and resume refresh. |
| `frontend/lib/features/orders/ui/order_accepted_screen.dart` | `202/PENDING` acknowledgement with stable order ID, accepted total and tracking CTA; **not** misleading confirmation. |
| `frontend/lib/features/orders/ui/order_details_screen.dart` | Current status, full versioned timeline, optional driver, persisted notifications and permanent failure details. |
| `frontend/lib/features/orders/ui/order_history_screen.dart` | Paginated current-customer orders, manual refresh and navigation. |
| `frontend/lib/features/orders/ui/order_timeline.dart` | Accessible reusable chronological status timeline widget. |
| `frontend/lib/features/orders/ui/notification_feed.dart` | Persisted order notifications, empty/error states and stable display order. |
| `frontend/lib/features/admin/models/admin_summary.dart` | Typed aggregate counts/backlogs for read-only admin. |
| `frontend/lib/features/admin/data/admin_api.dart` | GET admin orders/summary only; no write endpoints. |
| `frontend/lib/features/admin/state/admin_controller.dart` | Admin filters, pagination, loading/error and summary refresh. |
| `frontend/lib/features/admin/ui/admin_orders_screen.dart` | Responsive read-only aggregate cards, filtered orders, pagination, explicit forbidden handling. |
| `frontend/assets/images/README.md` | Assets manifest; list all fictional restaurant/food images and their licenses. Actual image files belong beside it with meaningful names. |
| `frontend/assets/fonts/README.md` | Font/license manifest if bundling permitted font files; otherwise use platform fonts and document. |
| `frontend/web/index.html` | Flutter generated browser entry; inspect/update base path only where required, keep SPA behavior. |
| `frontend/web/manifest.json` | Generated web app branding metadata; do not store secrets. |
| `frontend/android/app/src/main/AndroidManifest.xml` | Platform Internet permission, safe deep links/cleartext debug policy if explicitly needed. |
| `frontend/android/app/build.gradle.kts` | Flutter-generated Android configuration; verified SDK settings and build identity, not manual generated overhaul. |
| `frontend/ios/Runner/Info.plist` | Flutter-generated iOS supported network permissions/ATS debug exceptions if needed, no production insecure exception. |
| `frontend/ios/Podfile` | Flutter-generated CocoaPods platform integration consistent with tested toolchain. |

All other Flutter-generated `android/`, `ios/`, `web/` build scaffolding remains under version control as customary and should not be hand-recreated file by file. The planned files above cover all custom app logic; generated native internals are owned by Flutter/Gradle/Xcode.

### 7H. Flutter tests and demo/load scripts

| File | Responsibility / must contain |
|---|---|
| `frontend/test/auth/login_screen_test.dart` | Invalid credentials, loading/offline/expired states, form semantics. |
| `frontend/test/catalog/catalog_screen_test.dart` | Restaurant/menu loading, errors, prices, availability, narrow/desktop layouts. |
| `frontend/test/cart/cart_controller_test.dart` | One-restaurant invariant, quantity/item limits, changes and subtotal. |
| `frontend/test/cart/checkout_screen_test.dart` | Disable multiple taps, validation, unknown timeout and same-key retry. |
| `frontend/test/orders/order_detail_test.dart` | Timeline/status/failure/driver/notifications and terminal polling stop. |
| `frontend/test/orders/order_history_test.dart` | Pagination, refresh and current user only. |
| `frontend/test/admin/admin_screen_test.dart` | Admin filters/summary; blocked customer route. |
| `frontend/test/core/responsive_layout_test.dart` | No overflow at representative phone/desktop widths, text scaling, keyboard focus and labels. |
| `frontend/integration_test/customer_flow_test.dart` | Real integrated sign-in -> restaurant/menu -> cart -> checkout -> tracking -> history plus error/timeout where controlled. |
| `frontend/integration_test/admin_flow_test.dart` | Admin login and overview/filter against backend. |
| `frontend/test_driver/integration_test.dart` | Web ChromeDriver bridge **if** required by pinned Flutter testing approach; omit if unsupported/unneeded and document replacement. |
| `scripts/setup-local.sh` | Validated clean install commands, prerequisites, config, images, migrations, topology, seed and startup; no destructive default. |
| `scripts/run-backend-tests.sh` | Run pytest and real integration suites with explicit required services; preserve exit codes. |
| `scripts/run-flutter-tests.sh` | Analyzer, unit/widget and documented integration commands. |
| `scripts/demo-happy-path.py` | Create/order poll/history verification and print correlated IDs. |
| `scripts/demo-idempotency.py` | Same key duplicate, changed payload 409 and concurrent request once-only output. |
| `scripts/demo-failures.py` | Protected deterministic fail-twice-succeed/always-fail, terminal reasons, retries and quarantine evidence. |
| `scripts/demo-worker-recovery.sh` | Stop/restart worker, crash before/after DB commit before ACK, check dedup/queue. |
| `scripts/demo-broker-recovery.sh` | Broker outage after acceptance, pending outbox, restart and eventual processing; never delete volumes mid-test. |
| `scripts/demo-notification-isolation.sh` | Stop notification consumer, create multiple orders, verify order success and backlog drain after resume. |
| `scripts/load_orders.py` | Authenticated HTTP load generator for >=100 distinct checkout requests, adjustable concurrency, p50/p95, accepted IDs, total processing time, orders/sec and CSV/JSON raw samples. |
| `scripts/compare_workers.sh` | Same fixed successful simulation workload on one vs three payment workers, two or more repetitions, record container limits and backlog. |
| `scripts/inspect_state.py` | Read-only inspection of PostgreSQL order/effect uniqueness, outbox/retry/quarantine and state timeline (no production secrets). |

## 8. Docker Compose, execution and environment specifics

Build the same Python image for API, 4 workers, dispatcher, scheduler; they remain separate process services. Use supported, pinned PostgreSQL/RabbitMQ management images, persistent named volumes, RabbitMQ management UI for local demonstration, and internal-only DB/broker ports in deployed configurations. Management UI should be locally bound for training. Ensure Compose scaling works for payment worker instances: **no fixed `container_name` and no per-worker static host port**. Use health checks with actual dependency probes and bounded timeouts. Topology init must finish before dispatcher; migration/seed should be deliberate one-off processes/commands, not simultaneously attempted by every worker. App/worker restarts must reconnect/back off; startup ordering is not sufficient for recovery.

Example *intent* for documented commands (replace placeholders with verified real commands; never claim untested commands succeed):

```bash
cp .env.example .env
# configure fictional local secrets in .env (never commit)
docker compose build
# perform one-shot migrations, broker topology init and repeatable seed in documented order
docker compose up -d
# independent API/browser health checks and management inspection

docker compose up -d --scale payment-worker=3

cd frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
flutter run -d <android-device> --dart-define=API_BASE_URL=http://10.0.2.2:8000
flutter build web --dart-define=API_BASE_URL=https://api.example.test
flutter build apk --dart-define=API_BASE_URL=https://api.example.test
# iOS run/build ONLY on a Mac with correct Xcode setup and a valid simulator
```

The example `https://api.example.test` is a placeholder, **not** an actual deployed API. `localhost` is context-sensitive, and Compose service DNS (`api`, `postgres`) is **not** reachable from browser/mobile by default. Document confirmed reachable addresses per platform. Native mobile apps are not Docker Compose containers. Support web refresh/deep-link SPA route fallback.

## 9. Testing, observability, acceptance and scaling — no shortcuts

Backend requires pytest, Postgres integration and real RabbitMQ integration. Frontend requires widget and integration tests. Expose structured logs/metrics for request/correlation ID, order ID, event ID, attempt, transitions, elapsed and outcome; RabbitMQ queue depth, unacked deliveries, consumer instances, quarantines; pending outbox age, retry backlog in admin summary or scripts. Do not leak PII/tokens in logs.

**Run and capture evidence for ALL required acceptance checks:**
- Invalid/mixed/unavailable items, bad qty/address, authoritative server total, no partial order/outbox transaction.
- Missing/expired credentials, customer ownership, forbidden admin access.
- Same checkout key+payload, concurrent identical submissions and timeout safe retry -> one order; changed payload 409.
- Happy-path PENDING -> PAID -> CONFIRMED -> DRIVER_ASSIGNED, unique payment, driver assignment, notifications/history per relevant event.
- Notification `order.#` sees `order.payment.failed`, `order.driver.assigned` and two-segment events.
- Worker kill mid-process and after DB commit before ACK, restart -> no lost work/repeated committed effect.
- Broker outage after acceptance and crash after publish/before mark sent -> no missing events; duplicates harmless.
- Two transient failures then success; always-fail reaches terminal status and inspectable quarantine; delays and finite attempts observed.
- Notification worker stopped -> order stages unaffected, notification backlog drains without duplicates after restart.
- Multiple payment worker replicas + duplicate and out-of-order events -> monotonic order states, single committed effects.
- Flutter sign-in -> restaurant/menu -> checkout -> tracking -> history, token/connection errors and same-key retry.
- Web browser, Android emulator/device, iOS simulator/device evidence plus small/desktop layouts; if no Mac, label iOS validation **pending**, provide build plan and never claim completion.
- Secure CORS/public base URLs; no client credentials for DB/broker, no real secrets.
- Web deep-link refresh works.

**Load exercise:** At least **100 orders**, fixed successful simulation and documented per-stage delays/hardware; record total accepted, p50/p95 HTTP create-order latency, final processing time, orders/sec, queue depth peaks/unacked, machine/container resources. Aim for `POST /orders` p95 below **500 ms** in the documented local environment, but report actual misses honestly. Compare **one vs three payment workers**, same workload, **at least two repetitions each**; isolate/document payment bottleneck or explain downstream limitations. Do not imply three workers guarantee 3x end-to-end throughput. API response latency should be decoupled from simulated payment delay.

## 10. Milestone execution and approval gates

**Milestone 1 — Foundation.** Verify all prerequisites/versions, create repo structure, Dockerfiles/Compose/health, PostgreSQL models+Alembic, seeded fictional users/menus/drivers, FastAPI auth and initial Flutter app. Gate: migrations repeat, user login, seeded menu API, clean Compose boot and independent worker process scaffolding.

**Milestone 2 — Checkout contract.** Implement all catalog/order read endpoints, authorization, server-priced checkout and single-transaction idempotency/outbox. Gate: Postgres tests including race/rollback/409, `202+Location`, OpenAPI, order remains PENDING until worker system processes it.

**Milestone 3 — RabbitMQ and workers.** Declare exchange/queues first; implement event envelopes, dispatcher/confirmed publication, all four independent workers and processed-event uniqueness. Gate: successful order path with persisted notification/history and duplicated-message idempotency.

**Milestone 4 — Failure safety.** Implement retry jobs, scheduler/targeted delayed publication, terminal statuses, quarantine, fault injection, shutdown/reconnect and crash recovery. Gate: repeatable broker-down, worker-kill, two-fail-then-succeed, permanent failure and notification isolation tests.

**Milestone 5 — Flutter.** Apply user-provided Dribbble design to required responsive sign-in/catalog/menu/cart/checkout/acceptance/tracking/history/admin UI. Connect only through API; durable pending checkout, active-only polling, token security, accessibility, errors, web/Android/iOS platform compatibility. Gate: browser and Android workflow evidence, iOS on Mac or formally pending.

**Milestone 6 — Tests and evidence.** Run real DB/broker tests, race/recovery, Flutter widgets/integration, deep-link, platform tests and clean-install checks; fix defects and attach authentic outputs.

**Milestone 7 — Load and delivery.** 100+ orders, one vs three payment worker tests repeated twice, honest metrics/report, source/build artifacts, web hosting, Android debug APK, iOS evidence or explicit gap, architecture docs and repeatable full live-demo sequence.

Every milestone report should include: **what was built; exact changed files; commands executed; test results; unresolved limitations; mapping to acceptance criteria; and next milestone**. Ask for clarification only for an actually blocking question such as unavailable iOS/macOS environment or missing original repository. Do not pause for minor aesthetic choices; choose accessible professional defaults consistent with the reference.

## 11. Exact required live demo sequence

1. From a clean checkout, document and run stack setup; sign into Flutter and browse seeded menu.
2. Place an order and demonstrate fast `202`, PENDING then PAID then CONFIRMED then DRIVER_ASSIGNED, history and persisted notifications.
3. Repeat exact same checkout key/payload -> same order ID, no duplicate effects; show changed payload conflict 409.
4. Stop notification processing, place multiple orders, show notification queue backlog with otherwise completed orders; restart and drain once-only.
5. Run payment fails twice then succeeds, then payment always fails; inspect retry timestamps, failure UI, quarantine DB/dead queue.
6. Kill a selected worker at a DB/ACK crash boundary; restart; verify unique simulated payment/assignment/history records.
7. Stop RabbitMQ, accept an order into PostgreSQL outbox, restart broker; show eventual processing without losing it.
8. Run identical 100+ order loads with one and three payment workers; repeat at least twice; report p50/p95/backlog/throughput.
9. Show the common customer flow in web, Android and iOS and no layout overflow; show safe network-timeout same-key retry. If iOS unavailable, state exactly why and don't pretend evidence exists.
10. Sign in as admin, view cross-customer orders/summary and status filters; show customer access to admin API returns 403.

## 12. Grading priorities and scope protection

Weighting from the assignment: **reliability/data integrity 25%; Flutter functionality/usability 20%; FastAPI/domain correctness 15%; RabbitMQ/workers 15%; testing/scaling 15%; packaging/documentation/demo 10%**. Optional polish cannot substitute for any required test. Do not spend time on unsupported features before completing outbox, retry, dedup, auth, responsive Flutter, platform checks and scaling evidence.

Maintain a running `docs/requirements-matrix.md` where *every* required requirement points to file(s), test(s), demo step and status. When a decision deviates from a recommendation above, record why, verify against document and official docs, and keep acceptance tests intact.

## 13. First response and handoff contract for the coding agent

When I provide the assignment DOCX, screenshots and project/repository, **do not immediately generate all source files**. First:
1. Confirm the actual assignment version and summarize REQUIRED vs OPTIONAL vs OUT OF SCOPE, citing the document.
2. Inspect repository state without destroying work; list existing implementation and gaps. If no repository exists, state that.
3. Check the official technical documentation linked above and the design reference; provide a **verified** version/tool compatibility table and a short research note with primary-source links. Do not claim copyrighted Dribbble assets are free to reuse.
4. Present final architecture, state machine, RabbitMQ topology, relational schema, complete file responsibility inventory and milestone checklist, with any conflicts or uncertainties identified.
5. Then implement **Milestone 1 only** (unless I explicitly authorize more), with actual code, migrations, run commands, tests and a checkpoint. Continue milestone-by-milestone to a reproducible, fully tested, documented submission; never detour from QuickBite Revised v2.0.

**The objective is not a mock UI or a conceptual explanation. It is a correctly functioning, reliable, testable, reproducible food-ordering application satisfying the exact revised assignment.**
