# QuickBite Flutter frontend (Milestone 5)

One Flutter `3.47.7` codebase for Android, Web and (pending validation)
iOS. This document explains the architecture, the state layer, the
networking contract, and the checkout-idempotency behaviour that the
assignment treats as safety-critical.

## Layout

```
frontend/lib/
  main.dart               entry: locale init + ProviderScope
  app/
    app.dart              QuickBiteApp (theme, router)
    router.dart           GoRouter 18: role-aware redirects, auth guard
    theme/                palette (coral/cream/peach), Inter (UI) + Playfair Display (wordmark)
  core/
    config/app_config.dart    API_BASE_URL (--dart-define, no secrets)
    network/                  ApiClient (native http), ApiException envelope
    utils/                    money (integer minor units), validation, dates
  state/                  Riverpod 3 controllers (below)
  features/               screens by domain (auth, restaurants, menu, cart,
                          checkout, orders, admin, shell)
  ui/widgets/             shared widgets (buttons, banners, empty/error states,
                          money text, status chips, paginated list)
  ui/motion/              Entrance (staggered fade+slide), Shimmer skeletons,
                          LivePulse — all no-ops under reduced motion
```

Design reference: the three supplied food-delivery screenshots and the
coral/cream direction — palette in `app_colors.dart`, pill controls, rounded
cards, oversized display type. Food photography is 28 licensed, attributed
CC0/PD/CC-BY photos in `assets/food/` (see `docs/design-assets.md`); the
bundled **Inter** (OFL) and **Playfair Display** (OFL) fonts ship with their
license files in `assets/fonts/`.

## State management (Riverpod 3)

Controllers are `Notifier`/`AsyncNotifier`-style classes exposed as
providers; screens watch derived state and call `ref.read(...notifier)`
for actions. No widget performs HTTP directly.

| Provider | Responsibility |
| --- | --- |
| `authControllerProvider` | sign-in/out, token restore (secure storage / in-memory on web), role, session-expiry signalling |
| `restaurantsProvider` / `menuProvider(id)` | paginated catalog reads |
| `cartControllerProvider` | draft cart (lines, quantity 1..20, single-restaurant lock), persisted to `shared_preferences` (non-secret) |
| `checkoutControllerProvider` | address, idempotent submit state machine, retry/conflict handling |
| `orderListProvider` / `orderWatchProvider(id)` | history with filters + live tracking (poll engine) |
| `adminSummaryProvider` / `adminOrdersProvider` | read-only admin dashboard |

Riverpod 3 rule learned the hard way: `build()` must not mutate `state`
synchronously — controllers schedule their first refresh with
`Future.microtask(refresh)`.

## Networking

- `ApiClient` uses the **native `http` package** (no Dio), a 15 s timeout
  per request, and parses the backend's error envelope
  (`{error:{code,message,details,request_id}}`) into `ApiException`
  (with `isTimeout` / `isNetwork` helpers).
- The bearer token is injected via a mutable `tokenProvider` hook wired by
  `SessionStore`; a 401 fires `onUnauthorized` → session-expiry banner +
  redirect to login (`?next=` preserved).
- Token storage: `flutter_secure_storage` (Keychain/Keystore) on mobile,
  in-memory on web (platform-conditional import). Passwords are never
  stored. No broker/database addresses or secrets exist in the app.

## Checkout idempotency (safety-critical behaviour)

The assignment requires that an uncertain outcome never double-charges.
`CheckoutController` persists a `PendingCheckout` record (key + payload
fingerprint) in `shared_preferences` **before** the request is sent, then:

| Server outcome | UI behaviour |
| --- | --- |
| 202 accepted | clear pending record; acceptance screen with order id + server total |
| timeout / network / 5xx (**uncertain**) | keep the SAME key; button becomes "Retry same order (safe)"; banner explains why |
| 4xx (other than 401/409, **definite**) | discard the record; normal "Place order" again |
| 401 | keep the record; after re-login the retry reuses it |
| 409 idempotency conflict | keep the record; conflict banner + explicit "Discard attempt & start over" |

Additional guarantees: the in-flight request disables the submit button
(no double-tap); totals and currency always come from the server response
(the client never invents fees, taxes or delivery charges); a "preview"
label on the cart/checkout subtotal states that the server computes the
final amount.

## Live tracking (polling policy)

`OrderTrackingScreen` + `OrderWatchController` poll
`GET /orders/{id}` every **2 s while the screen is visible**, with:

- immediate stop on terminal status (`DRIVER_ASSIGNED`, `PAYMENT_FAILED`,
  `FAILED`), on dispose, on app-background (`AppLifecycleListener`), and
  on auth loss;
- exponential backoff on consecutive errors: `2s × 2^min(errors, 4)`,
  capped at 30 s; a successful response resets to 2 s;
- a manual "Refresh now" action, and an honest on-screen note describing
  the cadence and the stop conditions.

`GET /orders/{id}/notifications` renders the per-order notification feed
inside the same screen (paginated, "Load more (N more)").

## Roles and navigation

- Router redirect logic: customers use `/restaurants`, `/orders`
  (history) and the full-screen `/menu/:id`, `/cart`, `/checkout`,
  `/orders/:id/accepted`, `/orders/:id`; admins land on `/admin` and are
  actively redirected away from customer-only surfaces (the API would
  answer 403 for those calls).
- Shell: `NavigationRail` ≥ 900 px wide, `NavigationBar` below; the admin
  branch has a single destination, so it renders without a nav bar
  (`NavigationBar` asserts ≥ 2 destinations).
- Back exits are explicit: tracking/menu/checkout guard `pop()` with a
  `canPop` check and fall back to a sensible route — deep-link reloads
  (web) start with an empty stack and must not dead-end.

## Responsive & accessibility

- Phone (360 px) through desktop: no overflow (widget-tested at the
  narrowest width); app-bar actions collapse to icon-only below 480 px;
  wide screens center content in constrained columns.
- Text scaling to 200% without clipping; minimum touch targets 48 px.
- Every interactive control has a semantic label/tooltip (steppers,
  cart/clear/remove actions, refresh); status is conveyed by text, not
  color alone; palette checked for WCAG AA contrast on body text.

## Platform builds

See [`docs/platforms.md`](platforms.md) for exact commands, the
`API_BASE_URL` matrix, the nginx SPA hosting setup and the iOS pending
status.

## Tests

- `test/widget/` — 80 widget tests over the REAL app (router, theme,
  controllers) with fake repositories at the data boundary: login
  validation/errors, catalog, cart (1..20 clamp, single-restaurant lock,
  clear-confirmation), checkout idempotency (same-key retry, 409, 401,
  discard flow), tracking (2 s cadence, terminal stop, backoff, manual
  refresh, notifications, failure reason), history filters, admin
  dashboard (summary counts, cross-customer rows, filter, 403 error
  state), responsive checks at 360px / 768px / 1200px, welcome and login
  copy/landing checks.
- `test/data/dto_contract_test.dart` — JSON ⇄ DTO contract pinned to the
  server field sets (money as integer minor units, unknown status →
  `FormatException`).
- `integration_test/app_flow_test.dart` — full journey on a real
  emulator against the live Compose stack: sign-in → menu → cart →
  checkout → acceptance → live tracking to terminal → history + persisted
  notifications.
