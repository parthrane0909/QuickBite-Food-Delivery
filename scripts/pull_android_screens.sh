#!/usr/bin/env bash
# Milestone 5: pull the on-device screenshots written by
# frontend/integration_test/screenshot_tour_test.dart into
# docs/evidence/m5/screens_android/.
#
# The tour runs inside the app process (flutter test integration_test), so
# PNGs land in the app's cache dir: /data/user/0/dev.quickbite.quickbite/cache/m5screens
# `adb exec-out run-as … cat` reads them back (debug builds only).
set -euo pipefail
cd "$(dirname "$0")/.."

PKG=dev.quickbite.quickbite
REMOTE=code_cache/m5screens
OUT=docs/evidence/m5/screens_android
ADB="${ADB:-adb}"
SERIAL="${ADB_SERIAL:-}"

device_args=()
[[ -n "$SERIAL" ]] && device_args=(-s "$SERIAL")

mkdir -p "$OUT"
rm -f "$OUT"/*.png

mapfile -t files < <("$ADB" "${device_args[@]}" shell run-as "$PKG" ls "$REMOTE" 2>/dev/null | tr -d '\r')
if [[ ${#files[@]} -eq 0 ]]; then
  echo "no screenshots found in $REMOTE (did the tour run?)" >&2
  exit 1
fi

for f in "${files[@]}"; do
  [[ "$f" == *.png ]] || continue
  "$ADB" "${device_args[@]}" exec-out run-as "$PKG" cat "$REMOTE/$f" > "$OUT/$f"
  echo "pulled $OUT/$f ($(stat -c%s "$OUT/$f") bytes)"
done

echo "==> $(ls -1 "$OUT"/*.png | wc -l) screenshots in $OUT/"
