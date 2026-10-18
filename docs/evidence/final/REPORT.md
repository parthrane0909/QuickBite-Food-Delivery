# QuickBite full-project finalization report

The interrupted work was recovered without resetting Git, Compose volumes, or
the development database. The project now contains the management API and
portal, searchable catalogue, session/checkout fixes, a repeatable 2,000-store
seed, licensed food imagery, and refreshed test evidence. Source-level checks
and the Android emulator journey pass. The API image was rebuilt after a
transient Docker Hub DNS failure, and the refreshed web bundle and API are now
running through the normal Compose services on ports 8080 and 8000.

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
| Orders | 45 (including the Android release verification order below) |
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
| Current Compose deployment | API readiness reports PostgreSQL and RabbitMQ up; authenticated catalogue search and admin summary passed; nginx returns HTTP 200 for SPA routes; final catalogue counts and migration head rechecked (`compose-final-runtime.txt`) |
| Chrome mobile-web authentication | Passed: seeded customer sign-in reached live discovery at 393×852 (`web-interactive-smoke.txt`) |
| Source API search/categories | Ready; 16 cuisine values, dish-name and combined cuisine/search requests return 200 (`http-routes-final.txt`) |
| Android release APK | Passed: Flutter regenerated the stale plugin registrant during normal dependency resolution; release APK built, signature-verified and installed in place on physical CPH2793 (`android-release-build-final.txt`, `android-release-runtime-final.txt`) |

The earlier emulator integration flow used the real API, PostgreSQL catalogue,
and seeded accounts. The final release was then installed on the connected
physical CPH2793 (Android 16) with `adb install -r`, preserving the existing
application data. Using the USB reverse tunnel (`adb reverse tcp:8000 tcp:8000`)
and local FastAPI endpoint, the app authenticated, loaded the catalogue and
images, opened a restaurant and menu, added two items, accepted one real test
order, and displayed its tracking progress and order-history record. The
persisted order is `order_c0948ac9d1ae42fdb4d375870b653764`, total 47,000 INR
minor units, current state `DRIVER_ASSIGNED`; four persisted notifications
cover order creation, payment, restaurant confirmation, and driver assignment.
The journey screenshot is `after-android/release-final-orders-physical.png`.

On the same physical release build, admin sign-in, the live dashboard,
restaurant listing, customer shopping navigation, and final discovery screen
were exercised. The admin editor was opened and canceled without saving a
change; the full admin mutation journey was not repeated on device. Management
mutation and authorization remain covered by backend tests and prior API
evidence. The final category-card presentation and admin Home destination were
also checked on device.

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
CDP captured the welcome and login screens, then drove a real demo sign-in to
restaurant discovery. The final web bundle was rebuilt for the normal Compose
API origin on port 8000. After a transient Docker Hub DNS failure on the first
attempt, the API image rebuild succeeded; only the API and nginx services were
recreated, and the API readiness check reports PostgreSQL and RabbitMQ up.
Nginx returned HTTP 200 for the root, login, and admin SPA paths. The full
menu-to-checkout browser journey remains unverified because Python Playwright
is not installed. The physical Android release journey used the active USB
reverse tunnel to reach the local API; the APK is not configured for standalone
Wi-Fi/deployed access and needs a reachable HTTPS API URL for that use. No
Docker volume, database, or unrelated container was removed or reset.

`frontend/ios/` and macOS/Xcode are unavailable on this Linux host, so iOS
builds and simulator tests remain unverified. The Android release APK uses the
repository's debug signing certificate: it is installable for internal review,
but not store-ready. Store distribution needs a protected upload key. The
physical-device verification used the local API over ADB reverse; deployed
networking remains unverified.

## Final Android release artifact

- APK: `frontend/build/app/outputs/flutter-apk/app-release.apk` (71.4 MB).
- SHA-256: `830309bebb7960e53e4fa6dbae828c67ed6fe8d3ed06a32094380a2b7daaf01c`.
- Package/version: `dev.quickbite.quickbite`, version `1.0.0` (code 1).
- Android: min SDK 24, compile/target SDK 36; merged manifest includes
  `android.permission.INTERNET`.
- Signing: APK signature v2 verified with the Android Debug certificate. This
  is a release-mode internal test APK, not a production/store-signed artifact.
- API: built with `--dart-define=API_BASE_URL=http://localhost:8000/api/v1`.
  For USB-local testing, start the project API and run
  `adb reverse tcp:8000 tcp:8000`; for independent use, rebuild with a reachable
  HTTPS endpoint.
- Build command from `frontend/`:
  `flutter build apk --release --dart-define=API_BASE_URL=http://localhost:8000/api/v1`.
- Installation: `adb install -r frontend/build/app/outputs/flutter-apk/app-release.apk`.

The initial failure came from a stale generated plugin registrant referencing
the SDK `integration_test` plugin during release compilation. Normal Flutter
dependency resolution regenerated plugin registration without that test-only
entry; the release build then succeeded. No generated source was hand-edited,
no test dependency was removed, and `flutter clean` was not needed. Final
analysis output is saved in `flutter-analyze-release-final.txt`.

The focused Flutter regression run covered admin navigation, catalogue cards,
and checkout history invalidation (34 tests; `flutter-targeted-run.txt`); all
passed. Flutter analysis is clean. The previous full Flutter run (93 tests) and backend run
(145 passed, one skipped) predate these presentation-only edits; complete
suites were not repeated because backend sources were unchanged. The earlier
400-order scaling evidence remains applicable; this task did not change
checkout or worker behavior.

Web screenshots and the full Android contact sheet are available from
`index.html`. Local development credentials are documented in the project
README and are not embedded in production UI.
