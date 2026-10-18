# Changed-file manifest

This manifest covers the implementation and review artifacts across the finalization commits, including the final Compose rebuild verification. The eight root-level `quickbite_*` screenshot/reference files are user-provided, untouched, and intentionally remain outside the commits.

## Final Android release correction

| Path | Responsibility |
| --- | --- |
| `frontend/lib/features/checkout/checkout_screen.dart` | Invalidate the mounted order-history page after server acceptance so the new order appears when returning to History |
| `frontend/lib/features/restaurants/restaurant_list_screen.dart` | Replace cuisine chips with image-backed, horizontally scrolling category cards; keep the selected category visible and pause the one-time scroll hint after touch |
| `frontend/lib/features/restaurants/widgets/food_category_card.dart` | Accessible reusable cuisine image card with selected, tap, and image fallback states |
| `frontend/lib/features/shell/app_shell.dart` | Route the admin Home destination to discovery while keeping Cart separate |
| `frontend/test/widget/admin_test.dart` | Cover distinct Home and Cart destinations for admins |
| `frontend/test/widget/catalog_test.dart` | Cover image-backed server cuisine filtering |
| `frontend/test/widget/checkout_test.dart` | Cover refreshing the preserved order-history branch after successful checkout |
| `docs/evidence/final/android-release-runtime-final.txt` | Physical Android release install, networking, customer order, notification, and admin navigation record |
| `docs/evidence/final/android-release-build-final.txt` | Successful Android release build output |
| `docs/evidence/final/flutter-targeted-run.txt` | Current 34-test Flutter regression output |
| `docs/evidence/final/flutter-analyze-release-final.txt` | Current clean Flutter analysis output |
| `docs/evidence/final/after-android/release-final-orders-physical.png` | Physical-device release order-history capture |
| `scripts/build_final_evidence.py` | Build the review index with physical release evidence and artifact link |

The Android APK is generated under the ignored Flutter build directory at
`frontend/build/app/outputs/flutter-apk/app-release.apk`; its SHA-256 and
signing details are recorded in `REPORT.md` and the runtime log. It is
intentionally not committed as a binary build artifact.

| Path | Responsibility |
| --- | --- |
| `README.md` | Developer setup and project overview |
| `backend/app/api/deps.py` | FastAPI routes and authorization |
| `backend/app/api/v1/admin.py` | FastAPI routes and authorization |
| `backend/app/api/v1/orders.py` | FastAPI routes and authorization |
| `backend/app/api/v1/restaurants.py` | FastAPI routes and authorization |
| `backend/app/db/models/__init__.py` | SQLAlchemy entities and audit/driver records |
| `backend/app/db/models/admin_audit_log.py` | SQLAlchemy entities and audit/driver records |
| `backend/app/db/models/driver.py` | SQLAlchemy entities and audit/driver records |
| `backend/app/db/models/driver_assignment.py` | SQLAlchemy entities and audit/driver records |
| `backend/app/db/models/restaurant.py` | SQLAlchemy entities and audit/driver records |
| `backend/app/main.py` | Project configuration/support |
| `backend/app/repositories/admin.py` | Database query and pagination layer |
| `backend/app/repositories/admin_management.py` | Database query and pagination layer |
| `backend/app/repositories/catalog.py` | Database query and pagination layer |
| `backend/app/schemas/admin.py` | Validated request/response contracts |
| `backend/app/schemas/admin_management.py` | Validated request/response contracts |
| `backend/app/schemas/catalog.py` | Validated request/response contracts |
| `backend/app/services/admin_management_service.py` | Business/service logic |
| `backend/app/services/admin_service.py` | Business/service logic |
| `backend/app/services/catalog_service.py` | Business/service logic |
| `backend/migrations/versions/0003_admin_management.py` | Additive Alembic schema changes |
| `backend/migrations/versions/0004_catalogue_search.py` | Additive Alembic schema changes |
| `backend/scripts/seed_demo.py` | Backend seed/bootstrap behavior |
| `backend/scripts/seed_large_catalogue.py` | Repeatable, batched showcase catalogue seed |
| `backend/tests/test_admin_management.py` | Backend API, reliability, seeding, and load coverage |
| `backend/tests/test_api_contract.py` | Backend API, reliability, seeding, and load coverage |
| `backend/tests/test_load_scaling.py` | Backend API, reliability, seeding, and load coverage |
| `backend/tests/test_retry_scheduler.py` | Backend API, reliability, seeding, and load coverage |
| `docs/admin.md` | Architecture, API, management, and performance documentation |
| `docs/api.md` | Architecture, API, management, and performance documentation |
| `docs/architecture.md` | Architecture, API, management, and performance documentation |
| `docs/evidence/final/REPORT.md` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-android/01_welcome.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-android/02_login.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-android/03_login_keyboard.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-android/04_discovery.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-android/05_discovery_restaurants.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-android/06_menu.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-android/06b_dish_smoke.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-android/07_menu_added.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-android/08_cart_smoke.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-android/09_signed_out.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-android/10_admin_dashboard.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-android/11_admin_restaurants.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-android/12_admin_menu.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-android/13_admin_customers.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-android/14_admin_customer_orders.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-android/15_admin_shopping_mode.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-android/16_return_to_admin.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-android/diagnostic_failure.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-web/1280_welcome.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-web/393_discovery.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-web/393_welcome.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-web/cold-login.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/after-web/cold-root.png` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/android-debug-build.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/android-release-build.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/android-runtime.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/backend-pytest-final.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/backend-pytest.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/backend-ruff-final.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/catalogue-20k-rerun.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/catalogue-20k-seed.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/catalogue-before-20k.dump` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/catalogue-seed-test.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/catalogue-seed.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/catalogue-supplements.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/cold-web-route.json` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/contact-sheet.jpg` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/flutter-analyze-final.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/flutter-analyze.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/flutter-focused-tests.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/flutter-test-final.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/flutter-tests.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/flutter-web-build-final.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/docker-build-api.txt` | Successful API image rebuild after transient registry DNS failure |
| `docs/evidence/final/compose-final-runtime.txt` | Post-rebuild API readiness, SPA route, and database count verification |
| `docs/evidence/final/web-interactive-smoke.txt` | Chrome mobile-web sign-in and live discovery smoke evidence |
| `docs/evidence/final/flutter-web-build-runtime.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/flutter-web-build.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/http-routes-final.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/index.html` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/load-test-pytest.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/load-test.json` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/migration-upgrade.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/web-cdp-login-final.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/web-cdp-welcome-final.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/web-route-inspection.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/web-runtime.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/final/web-visual-runtime-final.txt` | Final screenshots, comparisons, logs, seed backup, and reports |
| `docs/evidence/ui-design-stage1/FILES.md` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/REPORT.md` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/VISUAL_SPEC.md` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-android/01_welcome.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-android/02_login.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-android/03_login_keyboard.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-android/04_discovery.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-android/05_discovery_restaurants.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-android/06_menu.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-android/06b_dish_smoke.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-android/07_menu_added.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-android/08_cart_smoke.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-android/09_signed_out.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/1280_cart_smoke.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/1280_discovery.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/1280_discovery_restaurants.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/1280_login.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/1280_menu.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/1280_menu_scrolled.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/1280_signed_out.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/1280_welcome.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/1440_cart_smoke.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/1440_discovery.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/1440_discovery_restaurants.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/1440_login.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/1440_menu.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/1440_menu_scrolled.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/1440_signed_out.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/1440_welcome.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/360_cart_smoke.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/360_discovery.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/360_discovery_restaurants.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/360_login.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/360_menu.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/360_menu_scrolled.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/360_signed_out.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/360_welcome.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/393_cart_smoke.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/393_discovery.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/393_discovery_restaurants.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/393_login.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/393_menu.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/393_menu_scrolled.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/393_signed_out.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/393_welcome.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/768_cart_smoke.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/768_discovery.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/768_discovery_restaurants.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/768_login.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/768_menu.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/768_menu_scrolled.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/768_signed_out.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/after-web/768_welcome.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/before/01_welcome_desktop.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/before/02_login_desktop.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/before/03_home_grid_desktop.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/before/04_menu_desktop.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/before/18_welcome_mobile.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/before/19_login_mobile.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/before/20_home_list_mobile.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/before/21_menu_mobile.png` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/comparisons/discovery.jpg` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/comparisons/login-adaptation.jpg` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/comparisons/restaurant-menu.jpg` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/comparisons/welcome.jpg` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/contact-sheet.jpg` | Stage 1 reference comparisons and visual notes |
| `docs/evidence/ui-design-stage1/index.html` | Stage 1 reference comparisons and visual notes |
| `docs/openapi.json` | Architecture, API, management, and performance documentation |
| `docs/performance.md` | Architecture, API, management, and performance documentation |
| `frontend/android/app/src/main/AndroidManifest.xml` | Android app network configuration |
| `frontend/assets/food/CREDITS.json` | Optimized food photography and provenance manifest |
| `frontend/assets/food/CREDITS.md` | Optimized food photography and provenance manifest |
| `frontend/assets/food/family_bakery.jpg` | Optimized food photography and provenance manifest |
| `frontend/assets/food/family_biryani.jpg` | Optimized food photography and provenance manifest |
| `frontend/assets/food/family_burgers.jpg` | Optimized food photography and provenance manifest |
| `frontend/assets/food/family_chinese.jpg` | Optimized food photography and provenance manifest |
| `frontend/assets/food/family_desserts.jpg` | Optimized food photography and provenance manifest |
| `frontend/assets/food/family_healthy_bowls.jpg` | Optimized food photography and provenance manifest |
| `frontend/assets/food/family_indo_chinese.jpg` | Optimized food photography and provenance manifest |
| `frontend/assets/food/family_italian.jpg` | Optimized food photography and provenance manifest |
| `frontend/assets/food/family_japanese_inspired.jpg` | Optimized food photography and provenance manifest |
| `frontend/assets/food/family_korean_inspired.jpg` | Optimized food photography and provenance manifest |
| `frontend/assets/food/family_mediterranean.jpg` | Optimized food photography and provenance manifest |
| `frontend/assets/food/family_north_indian.jpg` | Optimized food photography and provenance manifest |
| `frontend/assets/food/family_sandwiches.jpg` | Optimized food photography and provenance manifest |
| `frontend/assets/food/family_seafood.jpg` | Optimized food photography and provenance manifest |
| `frontend/assets/food/family_south_indian.jpg` | Optimized food photography and provenance manifest |
| `frontend/assets/food/family_thai.jpg` | Optimized food photography and provenance manifest |
| `frontend/assets/food/hero_burger.png` | Optimized food photography and provenance manifest |
| `frontend/integration_test/app_flow_test.dart` | Real-device customer/admin smoke journey |
| `frontend/integration_test/stage1_visual_test.dart` | Real-device customer/admin smoke journey |
| `frontend/lib/app/router.dart` | App routing, theme, and transitions |
| `frontend/lib/app/theme/app_colors.dart` | App routing, theme, and transitions |
| `frontend/lib/app/theme/app_theme.dart` | App routing, theme, and transitions |
| `frontend/lib/app/transitions.dart` | App routing, theme, and transitions |
| `frontend/lib/core/network/api_client.dart` | Shared networking and platform primitives |
| `frontend/lib/data/dto/admin_dto.dart` | Typed API data/repositories |
| `frontend/lib/data/dto/catalog_dto.dart` | Typed API data/repositories |
| `frontend/lib/data/repositories/admin_management_repository.dart` | Typed API data/repositories |
| `frontend/lib/data/repositories/catalog_repository.dart` | Typed API data/repositories |
| `frontend/lib/features/account/account_screen.dart` | Customer screen presentation and navigation |
| `frontend/lib/features/account/image_credits_screen.dart` | Customer screen presentation and navigation |
| `frontend/lib/features/admin/admin_dashboard_screen.dart` | Admin dashboard and management presentation |
| `frontend/lib/features/admin/admin_management_screen.dart` | Admin dashboard and management presentation |
| `frontend/lib/features/auth/login_screen.dart` | Customer screen presentation and navigation |
| `frontend/lib/features/menu/item_detail_screen.dart` | Customer screen presentation and navigation |
| `frontend/lib/features/menu/restaurant_menu_screen.dart` | Customer screen presentation and navigation |
| `frontend/lib/features/menu/widgets/menu_item_card.dart` | Customer screen presentation and navigation |
| `frontend/lib/features/restaurants/restaurant_list_screen.dart` | Customer screen presentation and navigation |
| `frontend/lib/features/restaurants/widgets/restaurant_card.dart` | Customer screen presentation and navigation |
| `frontend/lib/features/shell/app_shell.dart` | Customer screen presentation and navigation |
| `frontend/lib/features/welcome/welcome_screen.dart` | Customer screen presentation and navigation |
| `frontend/lib/main.dart` | Project configuration/support |
| `frontend/lib/state/cart_controller.dart` | Riverpod state and session/cart/checkout lifecycle |
| `frontend/lib/state/catalog_providers.dart` | Riverpod state and session/cart/checkout lifecycle |
| `frontend/lib/state/checkout_controller.dart` | Riverpod state and session/cart/checkout lifecycle |
| `frontend/lib/state/orders_providers.dart` | Riverpod state and session/cart/checkout lifecycle |
| `frontend/lib/state/providers.dart` | Riverpod state and session/cart/checkout lifecycle |
| `frontend/lib/ui/layout/adaptive_layout.dart` | Reusable responsive UI, image, and motion components |
| `frontend/lib/ui/motion/shimmer.dart` | Reusable responsive UI, image, and motion components |
| `frontend/lib/ui/widgets/brand_stage.dart` | Reusable responsive UI, image, and motion components |
| `frontend/lib/ui/widgets/food_image.dart` | Reusable responsive UI, image, and motion components |
| `frontend/lib/ui/widgets/pressable.dart` | Reusable responsive UI, image, and motion components |
| `frontend/lib/ui/widgets/quantity_stepper.dart` | Reusable responsive UI, image, and motion components |
| `frontend/pubspec.lock` | Flutter dependencies and asset registration |
| `frontend/pubspec.yaml` | Flutter dependencies and asset registration |
| `frontend/test/helpers/fakes.dart` | Flutter widget, responsive, interaction, and contract tests |
| `frontend/test/widget/admin_test.dart` | Flutter widget, responsive, interaction, and contract tests |
| `frontend/test/widget/catalog_test.dart` | Flutter widget, responsive, interaction, and contract tests |
| `frontend/test/widget/login_test.dart` | Flutter widget, responsive, interaction, and contract tests |
| `frontend/test/widget/responsive_test.dart` | Flutter widget, responsive, interaction, and contract tests |
| `frontend/test/widget/stage1_design_test.dart` | Flutter widget, responsive, interaction, and contract tests |
| `frontend/web/index.html` | Web shell/bootstrap configuration |
| `infra/web-nginx.conf` | Web hosting, cache, and SPA routing |
| `scripts/build_final_evidence.py` | Image processing and final visual/runtime evidence tools |
| `scripts/build_ui_stage1_review.py` | Image processing and final visual/runtime evidence tools |
| `scripts/capture_ui_stage1.py` | Image processing and final visual/runtime evidence tools |
| `scripts/capture_ui_stage1_android.py` | Image processing and final visual/runtime evidence tools |
| `scripts/fetch_food_photos.py` | Image processing and final visual/runtime evidence tools |
| `scripts/food_photo_overrides.json` | Image processing and final visual/runtime evidence tools |
| `scripts/inspect_web_runtime.py` | Image processing and final visual/runtime evidence tools |
| `docs/evidence/final/web-interactive-smoke.txt` | Chrome CDP demo login and live discovery verification. |
| `docs/evidence/final/FILES.md` | This changed-file manifest. |
