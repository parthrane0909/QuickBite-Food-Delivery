#!/usr/bin/env bash
# Milestone 5 evidence capture — run from the repo root with the Compose
# stack up and (for the Android parts) the `quickbite` emulator booted.
#
#   ./scripts/capture_m5_evidence.sh
#
# Writes docs/evidence/m5/*.txt. The Flutter steps need the Flutter SDK on
# PATH; Android/emulator steps are skipped with a note when no device is
# connected so the script never fabricates evidence.
set -uo pipefail

cd "$(dirname "$0")/.."
OUT=docs/evidence/m5
mkdir -p "$OUT"

API=http://127.0.0.1:8000/api/v1

login() { # $1 email $2 password -> token on stdout
  curl -s -X POST "$API/auth/login" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" |
    python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])'
}

echo "==> 01 backend suite (admin endpoints included)"
docker compose run --rm api pytest -q 2>&1 | tail -5 | tee "$OUT/01_backend_pytest.txt"

echo "==> 02 admin endpoints: summary + cross-customer orders (as admin)"
ADMIN_TOKEN=$(login admin@quickbite.dev 'quickbite!admin1')
{
  echo "GET /admin/summary (admin)"
  curl -s "$API/admin/summary" -H "Authorization: Bearer $ADMIN_TOKEN" | python3 -m json.tool
  echo
  echo "GET /admin/orders?status=PAID (admin)"
  curl -s "$API/admin/orders?status=PAID&page_size=5" -H "Authorization: Bearer $ADMIN_TOKEN" | python3 -m json.tool
} > "$OUT/02_admin_endpoints_admin.txt" 2>&1

echo "==> 03 access control: customer is denied the admin endpoints"
ALICE_TOKEN=$(login alice@quickbite.dev 'quickbite!alice1')
# NOTE: never use `curl -o /dev/stdout` here — it interleaves NUL bytes into
# grouped evidence files (observed during M5 capture). Temp file + cat.
tmp=$(mktemp)
{
  echo "GET /admin/summary as customer -> expect 403"
  curl -s -w '\nHTTP %{http_code}\n' "$API/admin/summary" \
    -H "Authorization: Bearer $ALICE_TOKEN" > "$tmp"; cat "$tmp"
  echo
  echo "GET /admin/orders as customer -> expect 403"
  curl -s -w '\nHTTP %{http_code}\n' "$API/admin/orders" \
    -H "Authorization: Bearer $ALICE_TOKEN" > "$tmp"; cat "$tmp"
  echo
  echo "GET /admin/summary anonymous -> expect 401"
  curl -s -w '\nHTTP %{http_code}\n' "$API/admin/summary" > "$tmp"; cat "$tmp"
  echo
  echo "GET /admin/orders anonymous -> expect 401"
  curl -s -w '\nHTTP %{http_code}\n' "$API/admin/orders" > "$tmp"; cat "$tmp"
} > "$OUT/03_admin_access_control.txt" 2>&1
rm -f "$tmp"

echo "==> 04 CORS: preflight from the web origin (incl. Idempotency-Key)"
{
  echo "OPTIONS $API/auth/login from Origin http://localhost:8080"
  curl -s -D - -o /dev/null -X OPTIONS \
    -H "Origin: http://localhost:8080" \
    -H "Access-Control-Request-Method: POST" \
    -H "Access-Control-Request-Headers: content-type,authorization,idempotency-key" \
    "http://127.0.0.1:8000/api/v1/auth/login"
  echo
  echo "GET $API/restaurants from a DISALLOWED origin (expect no allow-origin header)"
  curl -s -D - -o /dev/null -H "Origin: http://evil.example" "$API/restaurants" | grep -i "access-control" || echo "(no CORS headers — correct)"
} > "$OUT/04_cors.txt" 2>&1

echo "==> 05 web SPA: build + nginx hosting + deep-link reload"
if command -v flutter >/dev/null 2>&1; then
  {
    echo "flutter build web --release (API_BASE_URL as compiled in)"
    ./scripts/build_web.sh --build-only 2>&1 | tail -4
    docker compose up -d --force-recreate web >/dev/null 2>&1
    sleep 3
    echo
    echo "GET / (index)            -> $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/)"
    echo "GET /orders/order_probe  -> $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/orders/order_probe)  (SPA fallback after reload)"
    echo "GET /main.dart.js        -> $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/main.dart.js)"
    echo "bundle mentions API URL: $(grep -c 'localhost:8000/api/v1' frontend/build/web/main.dart.js 2>/dev/null || echo '?') hit(s)"
    echo "bundle contains broker/DB secrets: $(grep -ciE 'amqp://|postgres://|quickbite!alice|quickbite!admin' frontend/build/web/main.dart.js 2>/dev/null || echo 0) (must be 0)"
  } > "$OUT/05_web_spa.txt" 2>&1
else
  echo "flutter not on PATH — skipped (run manually)" > "$OUT/05_web_spa.txt"
fi

echo "==> 06 frontend analyzer + widget/DTO suite"
if command -v flutter >/dev/null 2>&1; then
  (cd frontend && flutter analyze 2>&1 | tail -2 && flutter test 2>&1 | tail -3) > "$OUT/06_flutter_tests.txt" 2>&1
else
  echo "flutter not on PATH — skipped" > "$OUT/06_flutter_tests.txt"
fi

echo "==> 07 Android APK build"
if command -v flutter >/dev/null 2>&1; then
  (cd frontend && flutter build apk --debug \
     --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1 2>&1 | tail -3;
   ls -la build/app/outputs/flutter-apk/app-debug.apk 2>/dev/null) \
   > "$OUT/07_android_apk.txt" 2>&1
else
  echo "flutter not on PATH — skipped" > "$OUT/07_android_apk.txt"
fi

echo "==> 08 integration flow on the emulator"
if command -v adb >/dev/null 2>&1 && adb devices 2>/dev/null | grep -q "device$"; then
  adb shell pm clear dev.quickbite.quickbite >/dev/null 2>&1
  (cd frontend && flutter test integration_test/app_flow_test.dart -d "$(adb devices | awk '/device$/{print $1; exit}')" 2>&1 | tail -6) \
    > "$OUT/08_integration_flow.txt" 2>&1
else
  echo "no booted emulator/device — skipped (run manually, see docs/platforms.md)" \
    > "$OUT/08_integration_flow.txt"
fi

echo "==> done — files in $OUT/"
echo "    (09–17 + screenshots_web/ + screenshots_android/ are captured by the"
echo "     supplementary commands listed in docs/evidence/m5/README.md)"
ls -1 "$OUT"
