# UI rehaul evidence

Verification evidence for the QuickBite UI/UX rehaul (report:
`docs/ui-rehaul/REPORT.md`). Captured on 18 Oct 2026 against the live
Compose stack (API + workers + Postgres + RabbitMQ) and the `emulator-5554`
Pixel-class device, plus headless Chromium via Playwright.

## Layout

| Path | What it is |
|---|---|
| `screens_android/` | 20 on-device screenshots from `screenshot_tour_test.dart` (customer journey + sign-out + admin) |
| `screens_web/` | Playwright captures at **1280×900** (desktop: left rail + 3-col grid) and **375×780** (phone: bottom bar + list) |
| `before_m5/` | Pre-rehaul screenshots from `docs/evidence/m5/` — the "before" side of every before/after pair |
| `logs/` | Integration-test driver logs (flow proof) |

## Flow proof (logs/)

| Log | Result |
|---|---|
| `01_app_flow_integration.log` | `app_flow_test.dart` — **All tests passed** (00:18): welcome → sign-in → restaurant → menu → cart → checkout → order placed → tracking → history, against the live stack |
| `02_screenshot_tour_integration.log` | `screenshot_tour_test.dart` — **All tests passed** (02:47), 20/20 screenshots captured |
| `03_web_capture.log` | `capture_ui_rehaul_web.py` — all **26** Playwright captures saved (desktop + mobile, semantics-driven) |

Also green at capture time: `flutter analyze` (no issues), `flutter test`
(79/79 widget tests, including the new item-detail group, the 360px
no-overflow sweep, and the selected-chip contrast regressions), backend
`ruff check` + `ruff format --check`.

## Mobile screenshots (screens_android/)

| # | File | Screen |
|---|---|---|
| 01 | `01_welcome.png` | Signed-out landing (hero photo, CTA, capability rows) |
| 02 | `02_login.png` | Login card (wordmark, back arrow) |
| 03 | `03_restaurant_list.png` | Home — greeting, photo cards, bottom bar |
| 04 | `04_menu.png` | Menu — photo hero, overlapping info card, item rows |
| 05 | `05_item_detail.png` | **New** item detail — photo hero, stepper, add bar w/ live total |
| 06 | `06_item_detail_added.png` | Add-to-cart SnackBar confirmation |
| 07 | `07_menu_item_added.png` | Menu with floating "View cart" bar |
| 08 | `08_cart.png` | Cart — photo line cards, subtotal |
| 09 | `09_checkout.png` | Checkout form |
| 10 | `10_checkout_filled.png` | Filled address (idempotency copy intact) |
| 11 | `11_order_accepted.png` | `SuccessBurst` celebration |
| 12 | `12_tracking_early.png` | Live tracking (`LivePulse`) |
| 13 | `13_tracking_terminal.png` | Terminal tracking state |
| 14 | `14_tracking_notifications.png` | Tracking + in-app notification banner |
| 15 | `15_order_history.png` | Order history cards |
| 16 | `16_account.png` | **New** Account tab — identity card, role pill, sign-out |
| 17 | `17_sign_out_dialog.png` | Sign-out confirmation dialog |
| 18 | `18_welcome_after_signout.png` | Lands on the welcome page after sign-out |
| 19 | `19_admin_overview.png` | Admin dashboard (read-only, tinted stats) |
| 20 | `20_admin_filter_confirmed.png` | Admin status filter |

## Web screenshots (screens_web/)

Desktop 1280×900 — proves the desktop layout is a real adaptation
(left rail with wordmark, 3-column grid, capped content columns):

| # | File | Screen |
|---|---|---|
| 01 | `01_welcome_desktop.png` | Welcome, split layout + rail-less signed-out page |
| 02 | `02_login_desktop.png` | Login, centered card |
| 03 | `03_home_grid_desktop.png` | Home **3-column photo grid** + left rail |
| 04 | `04_menu_desktop.png` | Menu, capped column, item rows w/ photos |
| 05 | `05_item_detail_desktop.png` | Item detail |
| 06 | `06_item_detail_added_desktop.png` | Add-to-cart SnackBar |
| 07 | `07_menu_cart_bar_desktop.png` | Menu + cart bar |
| 08 | `08_cart_desktop.png` | Cart |
| 09 | `09_checkout_desktop.png` | Checkout |
| 10 | `10_checkout_filled_desktop.png` | Filled address |
| 11 | `11_order_accepted_desktop.png` | Order accepted |
| 12 | `12_tracking_live_desktop.png` | Live tracking |
| 13 | `13_tracking_terminal_desktop.png` | Terminal tracking |
| 14 | `14_order_history_desktop.png` | Order history |
| 15 | `15_account_desktop.png` | Account |
| 16 | `16_sign_out_dialog_desktop.png` | Sign-out dialog |
| 17 | `17_welcome_after_signout_desktop.png` | Back on welcome |
| 25 | `25_admin_overview_desktop.png` | Admin overview |
| 26 | `26_admin_filter_paid_desktop.png` | Admin filter (Paid) |

Phone viewport 375×780 — proves mobile-first stays intact (bottom bar,
list mode, scrollable welcome):

| # | File | Screen |
|---|---|---|
| 18 | `18_welcome_mobile.png` | Welcome, stacked hero + content |
| 19 | `19_login_mobile.png` | Login |
| 20 | `20_home_list_mobile.png` | Home **list mode** (no grid below 760px) |
| 21 | `21_menu_mobile.png` | Menu |
| 22 | `22_item_detail_mobile.png` | Item detail |
| 23 | `23_cart_mobile.png` | Cart |
| 24 | `24_account_mobile.png` | Account |

Every control was driven through Flutter's **semantics tree** (the capture
enables accessibility first), so each screenshot doubles as accessibility
evidence: all interactive elements are reachable by label/role.

## Before → after mapping (before_m5/ ↔ new)

| Before (`before_m5/screens_android/…`) | After (`screens_android/…`) |
|---|---|
| `01_login.png` | `01_welcome.png` + `02_login.png` (new landing, restyled login) |
| `02_restaurant_list.png` | `03_restaurant_list.png` (photo cards, greeting, nav bar) |
| `03_menu.png` | `04_menu.png` (photo hero, item photos, row → detail) |
| — | `05_item_detail.png` (new screen) |
| `04_menu_item_added.png` | `07_menu_item_added.png` |
| `05_cart.png` | `08_cart.png` |
| `06_checkout.png` / `07_checkout_filled.png` | `09_checkout.png` / `10_checkout_filled.png` |
| `08_order_accepted.png` | `11_order_accepted.png` |
| `09_tracking_early.png` / `10_tracking_terminal.png` | `12_tracking_early.png` / `13_tracking_terminal.png` |
| `11_tracking_notifications.png` | `14_tracking_notifications.png` |
| `12_order_history.png` | `15_order_history.png` |
| — | `16_account.png` (new screen) |
| `13_sign_out_dialog.png` | `17_sign_out_dialog.png` + `18_welcome_after_signout.png` |
| `14_admin_overview.png` | `19_admin_overview.png` |
| `15_admin_filter_confirmed.png` | `20_admin_filter_confirmed.png` |

Web equivalents pair the same way (`before_m5/screens_web/01_login_desktop.png`
↔ `screens_web/02_login_desktop.png`, etc.).

## Reproduce

```bash
# 1. Stack up + re-seeded (image_asset wired)
docker compose up -d && docker compose run --rm seed

# 2. Widget tests + analyze
cd frontend && flutter analyze && flutter test

# 3. Mobile flow proof + tour (emulator running, app data cleared)
adb shell pm clear dev.quickbite.quickbite
flutter test integration_test/app_flow_test.dart -d emulator-5554
# The tour idles ~1.2s per screen, then signals a host-side screencap with a
# marker it holds for 6s. The watcher takes several frames per marker
# (primary + `_alt/` alternates) because `adb screencap` on the SwiftShader
# emulator occasionally returns a stale frame — keep the sharper one:
OUT_DIR=docs/evidence/ui-rehaul/screens_android ./scripts/watch_android_screens.sh &
flutter test integration_test/screenshot_tour_test.dart -d emulator-5554
kill %1
# (a shot missing or blank? re-run — it is a capture-timing flake, not an app bug)

# 4. Web captures (web service rebuilt from rehauled source)
./scripts/build_web.sh
uv run --with playwright python scripts/capture_ui_rehaul_web.py
```
