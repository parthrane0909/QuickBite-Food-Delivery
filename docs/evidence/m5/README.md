# Milestone 5 — evidence index

Complete Flutter frontend (Android + web integration), backend admin endpoints,
and the read-only admin dashboard. Every file below was produced by the command
it names, against the live Compose stack (`docker compose up -d`: api :8000,
rabbitmq :15672, postgres :5433, **web :8080**), on 2026-10-17.

Regenerate everything with:

```bash
./scripts/capture_m5_evidence.sh          # 01–08
./scripts/build_web.sh                    # web bundle served by nginx (05)
uv run --with playwright python scripts/capture_web_screens.py   # screens_web/
adb shell pm clear dev.quickbite.quickbite
./scripts/watch_android_screens.sh &      # host screencap watcher
(cd frontend && flutter test integration_test/screenshot_tour_test.dart -d emulator-5554)
./scripts/pull_android_screens.sh         # screens_android/
```

## Evidence files

| File | Demonstrates | Key result |
|---|---|---|
| `01_backend_pytest.txt` | Full backend suite incl. new admin tests | **136 passed** in 96s |
| `02_admin_endpoints_admin.txt` | `GET /admin/orders` (status filter) + `GET /admin/summary` as admin | 200, six statuses + outbox/retry/quarantine counts, server-clock `generated_at` |
| `03_admin_access_control.txt` | Admin endpoints are admin-only | customer → 403 `FORBIDDEN`, anonymous → 401 (orders **and** summary) |
| `04_cors.txt` | Explicit CORS | allow-origin echoed for `http://localhost:8080`; **no** header for `http://evil.example` |
| `05_web_spa.txt` | Flutter web build served by nginx 1.30.6-alpine | `/`, deep link `/orders/order_probe`, unknown routes → 200 (SPA fallback); compiled API base URL present; bundle secret scan all 0; correct cache headers |
| `06_flutter_tests.txt` | Frontend quality gates | `flutter analyze` → **No issues found!**; `flutter test` → **75 passed**; both integration suites noted |
| `07_android_apk.txt` | Android build | `flutter build apk --debug` artifact + install/launch + scoped cleartext config |
| `08_integration_flow.txt` | End-to-end customer journey on the emulator | **All tests passed!** (14s): sign-in → menu → cart → checkout (persisted key) → 202 → live 2s polling to terminal `DRIVER_ASSIGNED` → notifications → history |
| `09_screenshot_tour.txt` | Android screenshot tour run | **All tests passed!** (15 framebuffer captures) |
| `10_ui_server_consistency.txt` | UI renders server truth only | order readback, v1→v4 history, notification messages, admin rows/summary identical to what the screenshots show |
| `11_checkout_idempotency.txt` | Idempotency contract (live) | 1st POST → 202; same key + same body → **identical order_id/total**; same key + different body → **409 `IDEMPOTENCY_CONFLICT`** |
| `12_ui_checkout_tracking_behaviour.txt` | Checkout + tracking UX from the widget suite (22 named tests) | timeout keeps the key & re-sends identical request; 409 conflict UI; definite 4xx auto-discards; 401 keeps attempt for resume; terminal/backoff/dispose polling stops; failed orders readable via server `failure_reason` |
| `13_orders_api_notifications.txt` | Orders API + per-order notifications + pagination | pages, `has_more`, notification list, 4-transition history |
| `14_auth_edge_cases.txt` | Auth edge cases | wrong password → 401 `INVALID_CREDENTIALS`; garbage token → 401 `TOKEN_INVALID`; missing header → 401 `UNAUTHENTICATED` |
| `15_ios_status.txt` | iOS status honesty | **PENDING** (Linux host), documented macOS procedure, platform-independent coverage |
| `16_openapi_regenerated.txt` | OpenAPI regenerated | 12 paths incl. both admin paths; diff vs live server identical |
| `17_scope_and_limitations.txt` | Scope adherence | out-of-scope features absent from `frontend/` (0 hits each), no fabricated ratings/fees, no secrets in the Flutter app, admin write methods **NONE**, known limitations |

## Screenshots

`screens_web/` — 14 Playwright captures of the nginx-hosted web app
(desktop 1280×900 + narrow 375×780), driven through Flutter's semantics tree
(itself accessibility evidence: every control reachable by label):

- `01_login_desktop`, `02_restaurant_list_desktop`, `03_menu_desktop`,
  `04_menu_added_desktop`, `05_cart_desktop`, `06_checkout_desktop`,
  `07_checkout_filled_desktop`, `08_order_accepted_desktop`,
  `09_tracking_live_desktop`, `10_tracking_terminal_desktop`
- `12_restaurant_list_narrow`, `13_menu_narrow` (phone layout, bottom nav)
- `14_admin_overview_desktop`, `15_admin_filter_paid_desktop` (admin filter)

`screens_android/` — 15 device-framebuffer captures from the emulator tour
(1080×2400, real pixel output — not test harness fonts):

- `01_login`, `02_restaurant_list`, `03_menu`, `04_menu_item_added`, `05_cart`,
  `06_checkout`, `07_checkout_filled`, `08_order_accepted`, `09_tracking_early`,
  `10_tracking_terminal`, `11_tracking_notifications`, `12_order_history`,
  `13_sign_out_dialog`, `14_admin_overview`, `15_admin_filter_confirmed`

## Coverage of the milestone's required demonstrations

1. Sign in through Flutter and browse the seeded restaurant menu → **08, 09, screens (01–04)**
2. Place an order, 202 acceptance, transitions, notifications, history → **08, 10, 09, screens (07–12)**
3. Same idempotency key returns the same order → **11** (+ widget tests in **12**)
4. Safe network retry / uncertain-outcome resume → **11, 12** (timeout-keeps-key, 409, 401 resume)
5. Web target build + hosted SPA with deep-link reload → **05, screens_web/**
6. Android target build + emulator run → **07, 08, screens_android/**
7. Narrow/phone layout → **screens_web/12–13, screens_android/02 (bottom NavigationBar)**
8. iOS validation status (pending, documented) → **15**
9. Admin sign-in, cross-customer list, status filtering → **02, 14_admin / 15_admin shots**
10. Customer denied the admin endpoints → **03**
11. Auth edge cases → **14**
12. Backend + frontend full suites green → **01, 06**
13. Docs/OpenAPI regenerated and in sync → **16**
14. No fabricated data / no secrets / scope discipline → **17, 05 (bundle scan), 10**

## Environment incident (reported honestly)

During M5 development the host disk reached 100%. RabbitMQ's free-disk alarm
then blocked publishers (`publish_failed:confirm_timeout`), leaving demo orders
in `PENDING`. After space was reclaimed (~7.6 GB: pip/gradle caches) the alarm
cleared and the **stuck orders self-recovered through the normal worker
pipeline to `DRIVER_ASSIGNED`** — no data loss, no manual status edits. The
recurring risk note lives in `docs/platforms.md` (troubleshooting).
