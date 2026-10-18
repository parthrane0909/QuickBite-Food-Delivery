# QuickBite — Stage 1 implementation and review

Scope: welcome, login, restaurant discovery and restaurant menu, plus their
shared visual/navigation components. Baseline `ui-refinement` at `dd2b36d`.
No commit created. The eight pre-existing untracked user screenshots remain.

Open **index.html** for the offline visual review, or **contact-sheet.jpg**.
Reference/before/after images are labeled; screenshot aspect ratios are retained.
The supplied reference for login is actually onboarding; our email/password
screen is an adaptation, not reproduction of an unseen login form.

## Implementation

- Saturated #E51C0B brand with separate accessible #C92916 actions, white/neutral
  surfaces, dark photographic heroes, bundled Inter and existing OFL wordmark.
- Welcome: large two-line white display, original red rays, real transparent
  burger photography integrated into the field, bottom pills. Desktop is a
  bounded two-column adaptation. Short/large-text compositions scroll.
- Login: same brand/food language, substantial form sheet, existing API auth,
  validation/expiry/network states, password toggle. Keyboard focus collapses
  the decorative header and keeps the form/action reachable.
- Discovery: photographic dark editorial hero, actual exploration action,
  compact horizontal restaurant cards on phones, two-column wider layout.
  All four current records appear once; no invented ratings, offers or metrics.
- Menu: integrated red photographic restaurant identity, compact description
  and actual availability, natural-height image-first food cards, full dish
  descriptions and INR prices. Two columns on standard phones, one at narrow
  widths/large text, three/four at larger available widths. Existing cart
  restrictions and authoritative server pricing preserved.
- Customer navigation includes Home, Cart, Orders, Account; admin stays role
  separated/read-only. Cart remains a pushed screen with the existing flow.
- Shared card keyboard activation (Enter/Space), focus rings, hover/press
  feedback, quantity feedback, layout-matched shimmer and image placeholders.
  Reduced-motion preferences bypass entrance/route effects.

## Minimal routing compatibility work

Real browser reload testing exposed two existing problems. Protected screens
could start API requests before session restoration completed, and GoRouter's
imperative pushes did not reflect menu/item/cart destinations in the URL.
The router now holds protected restoration on splash with its return target,
then preserves that target through sign-in; pushed destinations expose their
reloadable URL. This is navigation compatibility, not a redesign of auth/state.

## Verification

- Flutter analysis: no issues (`logs/flutter-analyze.txt`).
- Flutter tests: **90 passed**; existing 80 retained, plus 10 Stage 1 tests.
  Coverage includes 360×640, 393×852, 768×1024, 1280×900, 1440×900,
  852×393 landscape, text scale 1.6, keyboard inset, reduced motion,
  card keyboard activation, and existing cart/checkout/order/admin behavior.
- Backend isolated regression: **136 passed in 69.70 seconds**
  (`logs/backend-tests.txt`). `quickbite_test` was confirmed absent before the
  run; the established conftest isolates PostgreSQL and `tst_` broker topology.
- Release web build succeeded (`logs/web-build.txt`).
- Final standalone Android debug APK built, installed and launched successfully
  (`logs/android-build.txt`, `logs/android-standalone-launch.txt`).
- Android smoke passed against FastAPI: welcome/login, actual restaurants/menu,
  dish details, add/cart, checkout review, back navigation, orders/account,
  sign-out. It never submits checkout. See `logs/android-runtime.txt`.
- Browser runtime evidence covers the same navigation and cold menu reload
  through sign-in. Per-viewport status/logs accompany the screenshot folders.
  Full journeys passed at all five widths with no recorded browser errors.
  Final capture completeness is listed in `logs/evidence-inventory.txt`.
- No iOS project/build/run claimed; this host is Linux.

Commands used (project Flutter SDK is `/home/parthrane/development/flutter`):

```sh
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter build web --release --no-pub --dart-define=API_BASE_URL=http://localhost:8000/api/v1
flutter build apk --debug --no-pub --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
flutter test --no-pub integration_test/stage1_visual_test.dart -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1 --reporter expanded
docker compose exec -T api pytest -q -p no:cacheprovider
python scripts/capture_ui_stage1.py
python3 scripts/capture_ui_stage1_android.py
python3 scripts/build_ui_stage1_review.py
```

The browser script uses an already installed cached Playwright environment;
no new packages/system SDKs were installed. Test expectations were updated for
new welcome copy, image-card skeletons and scrollable controls; business-rule
assertions remain. Early failures found/corrected the floating cart wrapper's
height, large-text headers, keyboard layout and cold navigation. Automation
locators were also updated for merged accessible names/offscreen cards.

## Environment interruption

During verification all QuickBite runtime containers were found exited cleanly
(exit 0, no OOM), while the unrelated MSSQL service remained running. Their
creation timestamps also changed outside this implementation's commands.
No cause is asserted. Only the existing QuickBite services were restarted.
Compose automatically restarted its migrate/topology-init dependencies; both
completed, the schema remains `0002`, and the seed service did not run as part
of this recovery. Catalogue remains **4 restaurants / 24 dishes**. No development
order was submitted by the Stage 1 tours. No volume/database deletion, pruning,
backend source edits, catalogue expansion or unrelated service edits occurred.

## Visual differences and remaining limits

- Not pixel-perfect. The licensed burger has different ingredients/proportions
  from the reference; we preserve real photography instead of copying artwork.
- Decorative shapes are original. QuickBite retains its own identity; no
  third-party restaurant branding, rewards, fake social sign-in or offers.
- Unsupported search/maps/favourites, ratings, distance, ETA, fees, discounts
  and category tabs are omitted. Real exploration/availability replaces them.
- Menu descriptions and 48px actions make cards taller than the tiny reference
  cards. This is deliberate for readable, complete descriptions and controls.
- Desktop/tablet are designed adaptations of mobile references.
- Existing catalogue photographs and their known dish-match limitations were
  preserved. Only the one new licensed hero photograph was introduced.
- Emulator uses software graphics; device frame-time profiling/physical-device
  performance is not claimed. Screenshots are captured after settling, not
  presented as proof of frame rate.
- Previously audited checkout persistence, customer-scoped draft/cache lifetime,
  and notification-refresh risks remain deferred. They were not claimed fixed.
- The broader cart/checkout/tracking/history/account/admin redesign, catalogue
  expansion, Milestones 6/7, and iOS verification have not been started.

## Approval boundary

Stage 1 is ready for visual review; the evidence inventory and local links passed.
No automatic commit or continuation to another stage. Review the four screens
and their comparisons before approving the direction.

## File-by-file change list

See `FILES.md` for the exact existing/new source, tests, asset and evidence paths.

Earlier failed attempts are retained as diagnostic logs; final results are in
flutter-analyze.txt, flutter-tests.txt, android-runtime.txt, web-runtime.json,
and the per-viewport runtime logs. No physical-device frame-rate claim is made.
