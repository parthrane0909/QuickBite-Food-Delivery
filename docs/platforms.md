# QuickBite platform guide (Milestone 5)

One Flutter codebase (`frontend/`) targets **Web**, **Android** and **iOS**.
This document is the clean-install sequence plus the exact per-platform
commands, and it states honestly which platforms were validated on this
machine.

## Validation status (honest)

| Target | Build validated | Runtime validated | Evidence |
| --- | --- | --- | --- |
| Web (Chrome + nginx) | ✅ `flutter build web --release` | ✅ SPA served by the `web` Compose service, deep-link reload checked | `docs/evidence/m5/` |
| Android (emulator) | ✅ `flutter build apk --debug` | ✅ integration flow on AVD `quickbite` (API 36, x86_64) | `docs/evidence/m5/` |
| iOS (simulator/device) | ⛔ **pending — no macOS/Xcode on this Linux host** | ⛔ pending | Build plan below |

iOS is **not** claimed complete. The `frontend/ios/` platform directory has
**not** been generated in this repository (the platform tooling requires macOS
with Xcode, which this Linux host does not have — the folder is absent, not
merely unbuilt). The procedure below is the documented plan for a Mac or
hosted macOS runner; `flutter create --platforms=ios .` is the first step.

## Clean-install sequence (any platform)

```bash
# 1. Environment
cp .env.example .env                      # edit the placeholders
docker compose up -d --build              # images + migrations + seed (one-shots)

# 2. Verify the API is up
curl -s http://127.0.0.1:8000/health/ready | python3 -m json.tool

# 3. Frontend tooling
cd frontend && flutter pub get && flutter analyze && flutter test

# 4. Run the target of your choice (sections below)
```

Rebuild the backend image after changing backend code:
`docker compose build api`.

## Platform API addresses

The app reads **one** compile-time value, `API_BASE_URL` (full absolute URL
including `/api/v1`, no trailing slash). The default baked into
`lib/core/config/app_config.dart` targets the Android emulator:

| Where the app runs | API_BASE_URL | Why |
| --- | --- | --- |
| Android emulator | `http://10.0.2.2:8000/api/v1` (default) | `10.0.2.2` is the emulator's alias for the host loopback |
| Android physical device | `http://<host-LAN-IP>:8000/api/v1` | The device must reach the host network |
| Web dev / nginx service | `http://localhost:8000/api/v1` | The browser calls the API directly (CORS allows `http://localhost:8080`) |
| iOS simulator | `http://localhost:8000/api/v1` | The simulator shares the Mac's network stack |

No broker/database address or credential is ever embedded in a Flutter
build — the app only ever speaks HTTP(S) to `API_BASE_URL`.

## Web

```bash
# Development against Chrome
cd frontend
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/api/v1

# Release build + nginx hosting in one step (from the repo root)
./scripts/build_web.sh
#   -> builds frontend/build/web, recreates the `web` service (nginx:1.30.6-alpine)
#   -> UI at http://localhost:8080
```

Notes:

- nginx serves the SPA with a `try_files … /index.html` fallback
  (`infra/web-nginx.conf`), so deep links such as
  `http://localhost:8080/orders/order_123` survive a hard reload.
- The web target stores the session token in memory only (no Web Crypto
  persistent store); closing the tab ends the session. Passwords are never
  stored anywhere.
- CORS: the API allows only the origins listed in `CORS_ORIGINS`
  (default `http://localhost:8080,http://127.0.0.1:8080`), including the
  `Idempotency-Key` header needed by checkout.

## Android

Prerequisites: Android SDK (command-line tools are enough), an emulator or
device with API 33+. `scripts/setup_android_sdk.sh` installs the minimal
SDK + creates the `quickbite` AVD used in this repository's evidence.

```bash
cd frontend

# Emulator (host with KVM; -no-window keeps it headless)
emulator -avd quickbite -no-window -no-audio -no-boot-anim \
  -gpu swiftshader_indirect -no-snapshot -no-metrics

# Debug APK (default API_BASE_URL already targets the emulator)
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
#  -> build/app/outputs/flutter-apk/app-debug.apk

# Install + open
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n dev.quickbite.quickbite/.MainActivity

# End-to-end integration test (stack must be running on the host)
adb shell pm clear dev.quickbite.quickbite   # cold start, no stale session
flutter test integration_test/app_flow_test.dart -d emulator-5554
```

Cleartext HTTP is permitted **only** to `10.0.2.2`, `localhost` and
`127.0.0.1` via `android/app/src/main/res/xml/network_security_config.xml`
(the local training endpoints); every other origin must use HTTPS.

## iOS (validation pending — documented build plan)

This repository was produced on Linux; macOS with Xcode is required to
compile, run or sign anything for iOS. The following is the exact procedure
to validate on a Mac:

```bash
# On macOS with Xcode 16+ and CocoaPods
cd frontend
flutter pub get

# Simulator run (API is the Mac's localhost — the simulator shares it)
flutter run -d ios --dart-define=API_BASE_URL=http://localhost:8000/api/v1

# Debug build for the simulator
flutter build ios --debug --dart-define=API_BASE_URL=http://localhost:8000/api/v1

# Release build (requires choosing a development team in Xcode for signing;
# simulator release builds do not need a signing identity)
flutter build ios --release --dart-define=API_BASE_URL=https://api.example.test

# End-to-end test on a booted simulator
open -a Simulator
flutter test integration_test/app_flow_test.dart -d <simulator-udid>
```

Additional iOS-only notes:

- The secure token storage path (Keychain via
  `flutter_secure_storage`) is compiled on iOS exactly as on Android; the
  web build uses the in-memory implementation. No code change is needed.
- App Store/TestFlight publication is optional and out of scope; it needs an
  Apple Developer account and signing configuration that this project does
  not include.

Until the above is executed on macOS, iOS remains **explicitly unvalidated**
and must not be reported as complete.

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Android app shows "Cannot reach the server" | Stack not running, or `API_BASE_URL` points somewhere the device cannot reach. Physical devices need the host's LAN IP, not `10.0.2.2`. |
| Web app shows "Cannot reach the server" | API not running, or the browser origin is not in `CORS_ORIGINS` (default allows `http://localhost:8080`). |
| Emulator `adb devices` says `offline` | Cold boot is slow on software graphics; wait, or restart with `-no-snapshot` after deleting `$HOME/.android/avd/<avd>.avd/snapshots/default_boot`. |
| `flutter build apk` fails on SDK licenses | `yes \| sdkmanager --licenses` (or re-run `scripts/setup_android_sdk.sh`). |
| Web deep link 404s after reload | nginx SPA fallback missing — use the committed `infra/web-nginx.conf` via the `web` service. |
| Checkout button disabled twice | Intended: the in-flight request disables resubmission; the persisted idempotency key is reused on retry. |
