# QuickBite UI Rehaul — Report

Scope: full Flutter UI/UX rehaul (mobile-first, web-compatible) per the
"QuickBite Complete UI Rehaul" brief, preceded by an audit. No backend
behaviour was added or changed; every flow (login, restaurants, menu, cart,
checkout, tracking, notifications, history, admin) works exactly as before.
Companion evidence lives in `docs/evidence/ui-rehaul/` (screenshots, before/
after pairs, test logs).

---

## 1. Audit summary (pre-rehaul state)

The M1–M5 UI was functional and test-driven, but visually generic and flat:

| Area | Finding |
|---|---|
| Brand | Stock Material indigo/blue; no palette, no wordmark, no personality |
| Imagery | **Zero food photography** — restaurant "cards" were text tiles; menu had a static brown gradient banner |
| Hierarchy | AppBar-title-then-list on every screen; all text weight 400; prices/statuses visually equal to labels |
| Loading | Spinner-only states; no skeletons, no content-shaped placeholders |
| Motion | No route transitions; screens popped in instantly; no pressed/hover/focus feedback |
| Entry | Signed-out users landed straight on the login form; no landing page; no account screen (sign-out hidden in the app bar) |
| Items | Menu rows could only "Add" — no way to see an item's photo/description before ordering |
| Web | Desktop = stretched phone: single column, bottom nav bar, no rail, no grid |
| Empty/error | Plain centered text + outlined buttons, inconsistent across screens |

## 2. Design system (new, `lib/app/theme/` + `lib/ui/`)

- **Palette** — coral-red `#DB3A1F` primary on warm cream `#FCF7F2`; warm
  charcoal `#1C1411` for text/dark surfaces; tinted semantic colors
  (success/warning/danger/info each with a `*Tint` background). All text
  colors chosen for AA contrast on their intended backgrounds (noted in
  `app_colors.dart` per token).
- **Typography** — bundled Inter (OFL, license file in `assets/fonts/`) for
  display + body with a real weight ladder (w400/600/700/800); Playfair
  Display reserved solely for the QuickBite wordmark
  (`AppTypography.wordmark`). No Google-Fonts network dependency.
- **Spacing / shape** — one token scale (`AppSpacing`: xs…xxxl, screen gutter,
  card gap, radius sm/md/lg/xl/pill, `controlHeight` for consistent 48px+
  touch targets).
- **Elevation** — warm-tinted shadow sets (`AppShadow.card`, `.raised`,
  `.floating`) replace hairline borders; CTA surfaces use the coral gradient.
- **Motion tokens** — `AppMotion` durations/curves (fast/base/slow,
  stagger step, emphasized curve); everything honors
  `MediaQuery.disableAnimations` (reduced motion).
- **Reusable components** — `PrimaryButton`/`SecondaryButton` (loading +
  disabled states), `Pressable` (tap-down scale + hover lift for web +
  semantics), `Shimmer` + skeleton family (`SkeletonBox/Circle/Image/
  RestaurantCard/DishTile/ListTile`), `Entrance`/`StaggeredEntrance`
  (staggered fade-up cascades), `ScreenFade`, `LivePulse` (live-status dot),
  `SuccessBurst` (order-accepted hero animation), `StatusChip`, `MoneyText`,
  `QuantityStepper`, `EmptyState/ErrorState/LoadingState`.
- **Page transitions** (`lib/app/transitions.dart`) — `fadeSlidePage` for
  shell tabs, `fadePage` for auth/landing, `risePage` for detail screens;
  all hand-rolled (no new packages).

## 3. Screen inventory (before → after)

| Screen | Before | After |
|---|---|---|
| Splash | Spinner + logo | Branded coral gradient + animated wordmark |
| Welcome (new) | — | Landing page: real hero photo, 3 honest capability rows, "Sign in" CTA; split layout ≥900px |
| Login | Bare form on flat background | Cream page + raised white card, Playfair wordmark, back-to-welcome affordance, entrance cascade; identical logic/copy/labels |
| Home (restaurants) | "Restaurants" AppBar + text tiles | Time-of-day greeting w/ real name, availability pills, **photo cards**, responsive 1→2→3 column grid, shimmer skeletons, cart badge |
| Menu | Static brown banner + flat rows | Real restaurant photo hero + overlapping info card, 84px item photos, pressable rows → item detail, shimmer rows, desktop-capped column |
| Item detail (new) | — | 300px photo hero, description, quantity stepper (capped at 20-line headroom), "Add to cart" bar with live line total, not-found + skeleton states |
| Cart | Plain list + button | Raised cards with item photos, entrance cascade, emphasized subtotal, prominent CTA |
| Checkout | Form + button | Same idempotency logic byte-for-byte; visual hierarchy + entrance polish only |
| Order accepted | Static check circle | `SuccessBurst` celebration, w800 headline, "Track this order" CTA |
| Tracking | List of cards | Skeleton loading, `LivePulse` + "Updated" indicator, status/timeline typography emphasis; polling logic untouched |
| Order history | Plain cards | Skeleton loading, pressable cards w/ chevron + status chips |
| Account (new) | — | Identity card (initial avatar, real name/email/role), tab links, danger-styled "Sign out" with confirmation |
| Admin dashboard | Card grid + spinner | Skeleton loading, tinted stat icon wells, w700 headings, pressable order rows; **still fully read-only**, all labels preserved |
| Nav (mobile) | Restaurants/Orders | **Home / Orders / Account** bottom bar; cart in top bar |
| Nav (desktop) | Stretched bottom bar | Left rail (wordmark ≥1280), grid content, capped column widths |

Deliberately **not** invented (no backend support): search, categories,
promos/discounts, ratings, ETA/distance, "popular/featured" labels, maps,
chat, favorites, payments UI, sign-up.

## 4. File-by-file summary

**New — app/framework**
- `lib/features/welcome/welcome_screen.dart` — landing page (new route `/welcome`)
- `lib/features/account/account_screen.dart` — Account tab (new route `/account`)
- `lib/features/menu/item_detail_screen.dart` — item detail (new route `/menu/:id/item/:itemId`)
- `lib/features/cart/cart_add_actions.dart` — shared `handleCartAdd()` (all add/conflict/bulk cases in one place)
- `lib/app/transitions.dart` — page transition builders
- `lib/ui/motion/shimmer.dart`, `lib/ui/motion/entrance.dart` — skeleton + entrance/motion primitives
- `lib/ui/widgets/pressable.dart`, `lib/ui/widgets/success_burst.dart` — interaction + celebration components

**Modified — app**
- `lib/app/router.dart` — welcome/account/item-detail routes, redirect flow (`/`→`/welcome` signed-out; `?next=` deep links preserved), transition pages
- `lib/app/theme/app_colors.dart`, `app_theme.dart` — full design system (fonts, shadows, component themes, snackbar/CTA styling)
- `lib/features/shell/app_shell.dart` — Home/Orders/Account destinations, branded rail (wordmark ≥1280), extracted shared `confirmSignOut()`
- `lib/features/splash/splash_screen.dart` — branded splash
- `lib/features/auth/login_screen.dart` — restyled (logic untouched)
- `lib/features/restaurants/restaurant_list_screen.dart` + `widgets/restaurant_card.dart` — photo grid/list, skeletons, greeting
- `lib/features/menu/restaurant_menu_screen.dart` — photo hero, item rows → detail, skeletons, cart bar
- `lib/features/cart/cart_screen.dart` + `widgets/cart_line_tile.dart` — photos on lines, raised cards
- `lib/features/checkout/checkout_screen.dart` — visual-only polish (idempotency copy byte-stable)
- `lib/features/orders/order_ack_screen.dart`, `order_tracking_screen.dart`, `order_history_screen.dart` — motion/skeleton/typography; polling + labels preserved
- `lib/features/admin/admin_dashboard_screen.dart` — consistency pass (skeletons, tinted stat wells, pressable rows); read-only, labels preserved
- `lib/state/cart_controller.dart` — `CartLine.imageAsset` (UI-only, backward-compatible persistence key)
- `lib/ui/widgets/async_state_view.dart`, `paginated_list_view.dart` — branded loading/empty/error; grid-mode support
- `pubspec.yaml` — Inter font asset, `assets/food/` bundle

**Backend (data only)**
- `backend/scripts/seed_demo.py` — populates `image_asset` for the 4 restaurants + 24 items (`assets/food/<entity-id>.jpg`); re-seeded via `docker compose run --rm seed`

**Tests**
- `test/helpers/harness.dart` — `navTo()` (async GoRouter parse + transition settle); route pump fix
- `test/widget/login_test.dart` — login via `/login`; sign-out now via Account tab → welcome
- `test/widget/catalog_test.dart` — skeleton assertions; **new item-detail group** (render + stepper add + not-found)
- `test/widget/responsive_test.dart` — new nav labels; welcome + item-detail in the no-overflow sweep
- `test/widget/cart_test.dart`, `checkout_test.dart` — navigation via `navTo()`
- `integration_test/app_flow_test.dart` — welcome → login entry
- `integration_test/screenshot_tour_test.dart` — welcome, item detail, account, sign-out dialog, welcome-after-sign-out captures

**Assets / scripts**
- `assets/food/` — 28 licensed photos + `CREDITS.json`/`CREDITS.md`
- `assets/fonts/` — Inter.ttf + `Inter-OFL.txt`
- `scripts/fetch_food_photos.py`, `scripts/food_photo_overrides.json` — reproducible photo pipeline (4 override rounds, human-verified)
- `scripts/capture_ui_rehaul_web.py` — web evidence capture (desktop + phone viewports)
- `scripts/watch_android_screens.sh` — now honors `OUT_DIR`

## 5. Interaction improvements

- **Route transitions** — fade+slide for tabs, fade for auth, rise for details
- **Skeletons everywhere** — home, menu, item detail, cart-adjacent, history, tracking, admin (content-shaped, shimmer-animated, scroll-safe on short screens)
- **State feedback** — `Pressable` gives every card/row tap-down scale + web hover lift + semantics; buttons have loading/disabled states; quantity stepper respects bounds with disabled ends
- **Confirmations** — add-to-cart SnackBar, cart conflict dialog, clear-cart dialog, sign-out dialog
- **Celebration** — order-accepted `SuccessBurst` (reduced-motion aware)
- **Live signals** — `LivePulse` on tracking status + "Updated" row
- **Entrances** — staggered fade-up cascades on lists/grids/cards (capped 600ms delay)
- **Responsive** — home grid 1→2→3 columns (760/1040 breakpoints); desktop capped columns + left rail; welcome split layout; every screen verified overflow-free at 360px (widget test)
- **Accessibility** — semantics labels preserved/added (restaurant cards, order rows, stepper values), 48px+ targets, AA-contrast tokens, focus/hover parity on web, reduced-motion support

## 6. Image sourcing

- **28 real photographs** (4 restaurant heroes + 24 dishes) from Wikimedia
  Commons / Unsplash, fetched by `scripts/fetch_food_photos.py`, downscaled
  to `assets/food/<entity-id>.jpg`, **human-verified across 4 override
  rounds** (wrong-subject photos replaced until every dish matched its name)
- Licenses: CC0 / CC BY / CC BY-SA only — attribution recorded per image in
  `CREDITS.json` + `CREDITS.md` (author, license, source URL) alongside the
  assets, satisfying attribution requirements
- Served through the API's existing `image_asset` contract field (seed data
  change only; the endpoint/schema is untouched); UI falls back to the
  initial-letter tile when an image is missing

## 7. Bugs found & fixed during verification

1. **`Entrance`/`Shimmer`/`LivePulse`/`SuccessBurst`** read `MediaQuery` in
   `initState` (illegal inherited lookup — threw on every mounted animation).
   Moved to guarded `didChangeDependencies`.
2. **Item-detail add bar ate the whole screen**: its `Center` filled the
   screen-bounded height Scaffold gives `bottomNavigationBar`, starving the
   body to 0px (invisible content, SnackBar off-screen assertion). Fixed
   with `heightFactor: 1.0`; regression covered by the new widget test +
   the 360px overflow sweep.
3. **Welcome page overflowed short viewports** — content pane now scrolls.
4. **Menu status pill overflowed at 360px** — pill text now `Flexible` +
   ellipsis.
5. **Home skeleton overflowed short screens** — skeleton list is now
   scroll-safe.
6. **Explicit sign-out landed on `/login?next=/account`** — sign-out now
   navigates to the welcome landing (token-expiry 401s still land on the
   login banner, by design).
7. **Order-history tour shots looked empty** (blank body or chip background
   without its label, despite a passing test) — diagnosed with on-device
   widget-state dumps at several time points (provider state, render-box
   sizes, entrance fade opacities — all correct: cards laid out at real
   positions, skeleton shimmer verified painting on the emulator GPU) and a
   host screencap after ~1s of idle time, which produced a perfect frame
   (66% card pixels). Root cause: the emulator's `adb exec-out screencap`
   can read the Flutter surface mid-composite right after new content
   appears, yielding stale or torn frames — and, in one run, a capture that
   outlived its marker hold landed after the tour had moved on (a welcome
   screen under the history filename). Fixed test-side: `_snap` waits for
   the screen's card content and idles ~1.2s before signalling, holds each
   marker for 6s, and the watcher now takes several frames per marker while
   discarding any capture whose marker disappeared mid-flight (i.e. the tour
   had advanced). No app defect.
8. **Web capture: Flutter's semantics shapes differ per widget** (tooling
   notes for `scripts/capture_ui_rehaul_web.py`): mobile `NavigationBar`
   destinations are exposed as `role="tab"` with aria-labels (desktop rail:
   `role="button"`), and the AppBar's implicit `BackButton` carries its
   label as element text only (no `aria-label` mirror). Locators try both
   shapes; screen readers get correct names either way (name from contents).
9. **Selected filter chips had an invisible label** — the customer history
   and admin dashboards styled a selected `ChoiceChip` label in
   `AppColors.primary` while the theme fills the selected pill with the same
   coral (`chipTheme.selectedColor`): coral-on-coral text, invisible on every
   platform (caught in the Android tour + web captures). Labels are now
   `AppColors.onPrimary` (white on coral, AA); covered by new widget tests
   in `orders_test.dart` and `admin_test.dart`.
10. **Opaque hover/focus overlays washed out state on web** — the theme's
    `hoverColor`/`focusColor` were opaque `AppColors.primaryTint`, so
    hovering a selected chip (web-only state) painted a flat pink fill over
    the coral pill, leaving white text on near-white (caught in the web
    admin capture). They now use translucent `primary` tints matching the
    existing button overlays (hover 0.10 / focus 0.14).

## 8. Verification

- `flutter analyze` — **No issues found** (after every batch)
- `flutter test` — **79/79 widget tests pass** (75 updated + 4 new, incl. the
  selected-chip contrast regressions)
- `ruff check` + `ruff format --check` (backend) — clean
- `integration_test/app_flow_test.dart` on emulator — **pass** (sign-in →
  menu → checkout → tracking → history against the live stack)
- `integration_test/screenshot_tour_test.dart` on emulator — see
  `docs/evidence/ui-rehaul/` for the captured run
- Web: Playwright capture at 1280×900 (rail + grid) and 375×780 (bottom bar
  + list) proving genuine responsive adaptation

## 9. Evidence

See `docs/evidence/ui-rehaul/README.md` for the full index: mobile +
desktop/mobile web screenshots, before/after pairs (M5 vs rehaul), and
integration flow logs.
