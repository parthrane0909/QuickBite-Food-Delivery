# UI refinement — reference fidelity pass (on top of the rehaul)

This document records the refinement pass applied **after** the UI rehaul was
checkpointed, so the two are reviewable separately:

| Stage | Commit | State |
| --- | --- | --- |
| M5 baseline | `37e1da4` | `master`, untouched |
| UI rehaul (round 1) | `5eb4068` | branch `ui-refinement`, reviewed as the "before" in the comparisons |
| **UI refinement (round 2)** | this commit | the "after" in the comparisons |

Nothing in the backend contract, the FastAPI service, PostgreSQL schema,
RabbitMQ topology, workers, checkout idempotency or any business rule changed in
this pass — the only backend-adjacent file still touched by the rehaul is
`backend/scripts/seed_demo.py` (adds the `image_asset` column value), which was
in the round-1 commit. This pass is frontend layout/motion/copy plus docs.

## 1. What the references asked for, and what was built

The three supplied screenshots are the visual authority
(`quickbitetemplate_{landing,login,restaurant}page.png`; note the file names are
shifted — `loginpage` is the onboarding screen and `landingpage` is the home
screen):

1. **Onboarding** — immersive saturated-red field, oversized brand type, one
   dominant food photo, two pill controls, bottom fine print.
2. **Home** — dark photographic hero band with a greeting, then a dense,
   image-led restaurant list.
3. **Restaurant** — photographic hero, round mark straddling hero/content seam,
   raised info card, image-led menu items with prices and an add affordance.

### Onboarding → welcome + sign in

Immersive brand-red gradient (`brandRedGradient` + `brandRedGlow`), 40 pt
display wordmark, the badge as a translucent pill, one real hero photograph,
and two stadium-radius controls: `FilledButton "Continue with email"` →
`/login`, `OutlinedButton "How it works"` → an honest capability sheet. Fine
print states that sign-up and social sign-in are not part of this build.

The reference's `Earn Crowns · Join Now` badge, `Order Delivery` secondary CTA
and "Powered by Google/Facebook/Apple" line were **not** reproduced: none of
those features exist in the contract, and inventing them would be exactly the
fabrication the design rules forbid. The fine print says so out loud.

The sign-in screen keeps **every** existing behaviour — validators, field
labels (`Email`, `Password`), the `Sign In` label, error copy, session handling
— and is restyled as the same red field with a raised white sheet: pill
(StadiumBorder) fields with prefix icons, coral `PrimaryButton`, back row.

### Home → discovery

`_HomeHeader` is a photographic dark band with the real session greeting
(`Good morning / Hi, Alice!`), the wordmark and the cart badge; the hero is
passed as a new `PaginatedListView.header` so it scrolls away with the list.
Below it, `All restaurants` and a responsive grid (2 columns ≥ 760, 3 ≥ 1040,
list below) of `RestaurantCard`s with a 156 px hero photo, an Open/Closed chip,
the real description and a `View menu` affordance.

Deliberately not reproduced: the `15% EXTRA DISCOUNT` banner, the star rating
and review count, the delivery-fee/time row, the search field and the cuisine
chips. The contract exposes no rating, ETA, fee, discount or cuisine field, and
a search box that silently does nothing is worse than no search box. Every
value on screen comes from the API.

### Restaurant → menu

The round-1 overlap bug is fixed structurally rather than with a
`Transform.translate`: the hero is a fixed-height sliver and the circular
restaurant mark is `Positioned` across the seam with `clipBehavior: Clip.none`,
so it can never collide with the info card at any width. The info card carries
the real name, the availability pill ("Accepting orders"), the description and
the section heading; items are image-led rows (`FoodImage` 92 px) with the
server price and a labelled `FilledButton "Add"` (or the quantity stepper, with
`Icons.add_rounded`). Two columns when the content box is ≥ 700 px. The entry
animation is staggered and every item is present once it settles.

Not reproduced: the reference's `Delivery Time / Charge / Min. Order` panel,
`50% off` coupons, `Famous · Assured` tags and the menu category tabs (the
contract has one flat item list with no category field).

### Item detail

The old page ended in a large empty tail. It now fills with real content: a
320 px photo hero with the availability state overlaid, name + authoritative
price, an **Availability / Kitchen** meta row, `About this dish` with the full
description, the contract's own `Quantities are capped at 20 per line.` note and
a `More from <restaurant>` horizontal strip built from the same menu payload
with the current item excluded. The sticky add bar keeps the quantity stepper
(server cap aware) and the labelled `Add to cart` CTA with the live line total.
Unknown ids still render the honest `Item not found` state with a way back.

### Order tracking

A compact horizontal progress track (`Placed → Paid → Confirmed → Driver`) now
heads the status card, derived strictly from the parsed status — failure
terminals stop the track at the stage that failed and mark it with a cross.
Driver details render only when the server actually assigned one
(`driverId != null`), as a tinted "Your driver" tile. The persisted notification
feed highlights the newest server event with a tinted card and a `Latest` pill.
The whole polling contract is untouched: ~2 s while visible, stop on dispose /
terminal / auth loss, exponential backoff to 30 s, immediate refresh on resume,
manual refresh, and status text that always comes from the server.

### Admin

Read-only behaviour is unchanged (same endpoints, same verbatim labels and
values). The polish is typography and density: `Summary` and
`Orders (all customers)` now use the same `headlineSmall/w800` heading as the
customer side, the stat cards became a responsive 1–4 column grid that fills the
row instead of leaving a ragged fixed-width tail, and a `Read-only` pill plus a
one-line explainer state the mode explicitly.

### Global

`app_colors.dart` gains the brand-red set (`brandRed`, `brandRedDeep`,
`brandRedDark`, `onBrandRed*`, `brandRedGradient`, `brandRedGlow`, `heroBand`).
Entrance/shimmer motion, press/hover/focus/disabled states, mobile bottom
navigation, desktop rail and the reduced-motion no-ops were already in place and
are unchanged; this pass added a 768 px responsive case so the three required
widths (360 / 768 / 1280) are all asserted by tests.

## 2. File-by-file change report

```
 docs/evidence/m5/README.md                          |   2 +-   annotate the M5 75-test snapshot vs today's 80
 docs/frontend.md                                    |  20 +-   fonts (Inter, not Roboto), motion layer, test count 75→80, photo credits
 docs/platforms.md                                   |   8 +-   iOS: frontend/ios/ is genuinely absent (not "generated scaffolding")
 frontend/assets/food/CREDITS.md                     |   5 +-   drop the stale "Unsplash License" bullet (no Unsplash files bundled)
 frontend/integration_test/app_flow_test.dart        |   8 +-   welcome copy is now textContaining + "Continue with email" CTA
 frontend/lib/app/theme/app_colors.dart              |  32 ++   brand-red tokens + gradient/glow/heroBand
 frontend/lib/features/admin/admin_dashboard_screen.dart | 152 ++++--  headings, Read-only pill, responsive stat grid
 frontend/lib/features/auth/login_screen.dart        | 389 ++++++---- red immersive field + raised white sheet, pill fields
 frontend/lib/features/menu/item_detail_screen.dart  | 567 ++++++++-- hero, meta row, description, cap note, "More from" strip
 frontend/lib/features/menu/restaurant_menu_screen.dart | 519 ++++++-- seam-straddling mark, hero card, image-led tiles, 2-col
 frontend/lib/features/orders/order_tracking_screen.dart | 357 ++++++-- progress track, driver tile, Latest notification
 frontend/lib/features/restaurants/restaurant_list_screen.dart | 443 ++++-- dark hero header, section heading, responsive grid
 frontend/lib/features/restaurants/widgets/restaurant_card.dart |  54 +-  272 px card, Open/Closed chip, View menu
 frontend/lib/features/welcome/welcome_screen.dart   | 556 ++++++-- immersive onboarding, badge/type/photo/pills, capability sheet
 frontend/lib/ui/widgets/food_image.dart             |  52 +-   `expand` flag + fallback fill
 frontend/lib/ui/widgets/paginated_list_view.dart    |  81 +-   optional `header` sliver (hero scrolls with the list)
 frontend/test/widget/catalog_test.dart              |   9 +    ensureVisible before menu Add/stepper taps (cart bar shrinks the body)
 frontend/test/widget/login_test.dart                |   7 +-   landing copy assertion follows the new welcome screen
 frontend/test/widget/responsive_test.dart           |  37 +-   new 768 px tablet case + welcome/login copy
 docs/design-assets.md                               | new     photography licences, fonts, reference material, what is never shown
 docs/evidence/ui-refinement/                        | new     26 web screenshots + 11 before/after pairs + reference sheet
 scripts/capture_ui_refinement_web.py                | new     Playwright driver for the refinement captures
 scripts/build_refinement_comparisons.py             | new     builds the before/after and reference sheets
```

Only three test assertions changed, all copy-driven and all updated in the same
commit that changed the copy: the welcome sentence is now asserted with
`find.textContaining`, the onboarding CTA is `Continue with email`, and the menu
Add/stepper taps scroll the control into view first (once the floating cart bar
appears the body is ~514 px tall on an 800×600 test surface, so the stepper sits
just below the fold — a real scroll, not a workaround for a layout bug).

## 3. Verification actually run (this commit)

| Check | Command | Result |
| --- | --- | --- |
| Static analysis | `flutter analyze` | **No issues found!** |
| Widget suite | `flutter test` | **80 passed** (was 79; +1 tablet case) |
| Backend regression | `docker compose run --rm -T api pytest -q` | **136 passed** in 111.38s |
| Android end-to-end | `flutter test integration_test/app_flow_test.dart -d emulator-5554` | **All tests passed** (AVD `quickbite`, API 36 x86_64): sign-in → menu → cart → checkout → 202 → live tracking to `DRIVER_ASSIGNED` → notifications → history |
| Web release build | `./scripts/build_web.sh` | built, nginx SPA recreated, `http://localhost:8080` → 200, API `/health/ready` → 200 |
| Web end-to-end | `uv run --with playwright python scripts/capture_ui_refinement_web.py` | 26 screenshots driven through the real UI against the live stack (welcome → login → home → menu → item → cart → checkout → acceptance → live tracking → terminal → history → account → sign-out → admin), desktop 1280×900 + phone 375×780 |
| Android debug APK | `flutter build apk --debug` | ✓ `app-debug.apk` (234,480,296 bytes) |
| Comparison sheets | `uv run --with pillow python scripts/build_refinement_comparisons.py` | 11 before/after pairs + 1 reference sheet |

iOS remains **PENDING**, unchanged and honestly labelled: no macOS/Xcode on this
Linux host, and `frontend/ios/` does not exist.

## 4. Screenshot index

`docs/evidence/ui-refinement/screens_web/` — the settled "after" set (captured
only after entrance animations finished):

`01`–`17` desktop (1280×900), `18`–`24` phone (375×780),
`25`–`26` admin. The customer sequence is a real order: `11_order_accepted`,
`12_tracking_live`, `13_tracking_terminal`.

`docs/evidence/ui-refinement/comparisons/`:

- `before_after_<screen>.png` — round-1 rehaul vs this refinement, for welcome,
  sign in, home (phone + desktop), menu (phone + desktop), item detail, cart,
  checkout, tracking and admin. "Before" images come from
  `docs/evidence/ui-rehaul/screens_web/`.
- `reference_vs_quickbite.png` — each supplied reference above the matching
  QuickBite screen with a note naming what was intentionally **not** fabricated.

The torn mid-animation Android captures
(`docs/evidence/ui-rehaul/screens_android/03_restaurant_list.png`,
`04_menu.png`) are left as the historical round-1 record; the settled visuals for
those screens are the phone-viewport captures in this set.

## 5. Design decisions worth defending

- **Layout bugs are fixed structurally, not visually.** The menu overlap is a
  `Positioned` mark on a seam with `Clip.none`, so it holds at every width
  instead of being tuned per breakpoint.
- **No fabricated data, ever.** No rating, review count, ETA, delivery fee,
  discount, coupon, cuisine chip, loyalty programme, social sign-in or invented
  driver identity appears anywhere — the reference has all of these and the
  contract has none of them. The UI renders server values only.
- **Honest absence.** The onboarding fine print and the `Read-only` pill state
  what the build does *not* do rather than implying capability.
- **Motion is restrained and accessible.** Staggered entrance fades, skeletons
  and the live pulse all degrade to nothing under `MediaQuery.disableAnimations`.
- **Evidence over assertion.** Every claim above is backed by a captured log,
  screenshot or sheet in this directory, produced by re-runnable scripts.

## 6. Known limitations

- iOS is unvalidated (no macOS/Xcode) and the platform folder is absent.
- Android visual evidence for this pass is the end-to-end integration flow; the
  settled per-screen visuals are captured on the web target at a 375×780 phone
  viewport (identical Flutter rendering), not re-captured per-screen on Android.
- The seeded catalog has no category field, so the reference's menu tabs and
  cuisine filter remain impossible without a contract change.
- `docs/` still lacks `requirements-matrix.md`, `data-model.md`, `testing.md`,
  `performance-report.md`, `demo.md`, `engineering-report.md` and
  `evidence/README.md`, and `scripts/` still lacks `load_orders.py`,
  `compare_workers.sh` and the demo runners. These are outside this pass and
  were not attempted.
- Milestones 6 and 7 are **not started**, as instructed.
