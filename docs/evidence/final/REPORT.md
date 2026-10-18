# QuickBite full-project finalization report

The interrupted work was recovered without resetting Git, Compose volumes, or
the development database. The project now contains the management API and
portal, searchable catalogue, session/checkout fixes, a repeatable 2,000-store
seed, licensed food imagery, and refreshed test evidence. Source-level checks
and the Android emulator journey pass. The local Docker API image could not be
rebuilt because Docker Hub DNS timed out; the verified source API is running on
host port 8001 for the current local web bundle.

## Architecture and data safety

Flutter continues to use the shared API client, Riverpod, and GoRouter. FastAPI
and SQLAlchemy remain the only application-data interface to PostgreSQL.
Checkout still writes an order and its outbox record transactionally, while
the existing RabbitMQ workers, retry scheduler, deduplication, and quarantine
flow remain in place. No payment, GPS, or status-transition behavior was
fabricated.

Alembic is at `0004` (`0003` adds admin management/audit fields and the driver
roster; `0004` adds partial-search trigram indexes). Before the final additive
catalogue completion, a custom-format backup of the restaurant and menu tables
was written to `catalogue-before-20k.dump` (SHA-256
`b52c91dff0f54d0a189cccd8a24bab15c9ef9d4c62660e5d1065e99d9156277a`). The
failed first attempt exceeded asyncpg's bind-parameter limit and rolled back;
counts were checked before retrying with bounded batches. The successful seed
added only missing deterministic IDs. A second run inserted zero rows.

The preserved development database now contains:

| Data | Count |
| --- | ---: |
| Restaurants | 2,000 |
| Menu items | 19,992 |
| Menu items per restaurant | 8–10 |
| Users | 4 |
| Orders | 44 |
| Drivers | 6 |
| Alembic head | `0004` |

All 45 local food-image assets have complete author, source URL, license,
license URL, local path, dimensions, checksum, and modification metadata in
`frontend/assets/food/CREDITS.json`. Sixteen cuisine-family photographs are
reused across suitable catalogue items, with exact dish images for selected
items. This is a curated local bundle, not one unique photograph per menu row
or a hosted media service.

## Implemented behavior

The admin API provides server-side paging/search for restaurants, menu items,
customers, drivers, and orders. Admin-only create/edit/deactivate operations
are protected by backend role checks. Restaurant and menu changes use stable
IDs and do not rewrite historical order-item price snapshots. Customer records
can be deactivated without deleting order history. Administrative mutations
write an append-only log of admin, action, target, time, and changed field
names, without credentials or full sensitive payloads.

The dashboard reads restaurant, customer, driver-roster, and order counts from
PostgreSQL, gives a compact order-status view, and retains outbox/retry/
quarantine health. Restaurant and customer lists include order/customer
activity aggregates. “Total drivers” is the number of rows in the driver
roster (six here); assigned-order counts are displayed separately. Order
inspection remains read-only.

An authenticated admin can browse, add to their own cart, and use the customer
routes under the same identity. Customer order reads remain scoped to the
current account. Development login buttons only prefill the seeded customer or
admin credentials in debug builds; authentication remains a real API request.

Discovery offers server-backed cuisine selection and debounced partial search
across restaurant names, cuisines, dish names, and descriptions. Cuisine and
text filters combine, and search results remain paginated. The large seed is
an explicit command; ordinary API and worker startup does not run it.

Checkout persists the idempotency request before submission and retains it
when the outcome is uncertain. Cart state is identity-scoped. Order tracking
refreshes notifications while active and stops polling at terminal states.
Tracking shows server order progress and assigned-driver details; it does not
claim live GPS coordinates.

## Verification

| Check | Result |
| --- | --- |
| Backend regression | 145 passed, 1 skipped (`backend-pytest-final.txt`) |
| Opt-in load/scaling benchmark | 1 passed; four 100-order runs (`load-test-pytest.txt`, `load-test.json`) |
| Backend Ruff | Passed; 107 Python files formatted (`backend-ruff-final.txt`) |
| Flutter analyzer | No issues (`flutter-analyze-final.txt`) |
| Flutter tests | 93 passed (`flutter-test-final.txt`) |
| Focused admin/catalogue seed tests | 7 passed against real PostgreSQL (`catalogue-seed-test.txt`) |
| Android debug build and emulator run | Passed; authenticated read-only customer/admin tour (`android-runtime.txt`) |
| Flutter web release build | Passed for port 8000 and for the current port-8001 source API (`flutter-web-build-final.txt`, `flutter-web-build-runtime.txt`) |
| Web HTTP paths | `/`, `/welcome`, `/login`, `/restaurants`, `/admin` return nginx SPA HTML (`http-routes-final.txt`) |
| Chrome mobile-web authentication | Passed: seeded customer sign-in reached live discovery at 393×852 (`web-interactive-smoke.txt`) |
| Source API search/categories | Ready; 16 cuisine values, dish-name and combined cuisine/search requests return 200 (`http-routes-final.txt`) |
| Android release APK | Not built; Gradle fails on Flutter SDK `integration_test` generated plugin registration (`android-release-build.txt`) |

The Android integration flow used the real source API, PostgreSQL catalogue,
and seeded accounts. It covered welcome, sign-in, restaurant search, menu,
dish details, cart, checkout route, history, sign-out, admin dashboard,
restaurant/menu lists, customer order inspection, admin shopping mode, and
return to the admin dashboard. It intentionally did not place an order or save
admin changes. Backend integration tests cover
management mutations and authorization. A physical Android device was not
connected.

M2–M5 contain prior assignment evidence, including idempotent checkout,
concurrency, owner-only reads, worker crash recovery, broker restart recovery,
retry exhaustion, and quarantine (`docs/evidence/m2/` through
`docs/evidence/m5/`). The complete current backend suite passed after the
catalogue changes. The opt-in M7 benchmark separately accepted and completed
all 400 generated orders in four 100-order runs. Checkout p95 ranged from
191.882 to 245.255 ms. One payment consumer measured 7.971 and 7.661 orders/s;
three measured 7.657 and 7.739 orders/s. Three consumers did not improve this
zero-delay test, which is dominated by other single-consumer/database work.
Current 19,992-item read-only p95s were 15.872 ms for page 1, 29.982 ms for
name search, 20.270 ms for cuisine filtering, 35.385 ms for admin restaurant
paging, and 24.491 ms for fixture-menu paging. These are local regression
measurements, not production capacity claims.

## Runtime and remaining limitations

The latest release web files are served by the project nginx container. Chrome
CDP captured the current welcome and login screens, then drove a real demo
sign-in to restaurant discovery and captured that page. The full menu-to-
checkout browser journey remains unverified because Python Playwright is not
installed. The Android real-API journey and Flutter responsive widget tests
passed. The web bundle used for the current capture points to host API port
8001; the normal port-8000-targeted web release also compiled successfully.

`docker compose build api` was attempted after the suite passed but failed while
resolving the Dockerfile frontend because `auth.docker.io` DNS timed out. The
Compose API image on port 8000 is therefore the pre-change image; source API
port 8001 is healthy and was used for live API and Android verification. No
Docker volume, database, or unrelated container was removed or reset. Once the
registry is reachable, rebuild the API image and regenerate the normal web
bundle for port 8000 before treating the Compose deployment as refreshed.

`frontend/ios/` and macOS/Xcode are unavailable on this Linux host, so iOS
builds and simulator tests remain unverified. No physical Android device was
available. Android release APK generation also remains blocked by the
generated `integration_test` plugin registration; debug APK/runtime passed.

Web screenshots and the full Android contact sheet are available from
`index.html`. Local development credentials are documented in the project
README and are not embedded in production UI.
