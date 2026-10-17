#!/usr/bin/env bash
# Milestone 5: host-side screenshot watcher for the Android screenshot tour.
#
# The tour (frontend/integration_test/screenshot_tour_test.dart) runs inside
# the app sandbox, where it cannot reach the host filesystem. Instead it drops
# a `NN_<name>.request` marker in its cache dir and holds the screen still for
# ~2.6 s. This watcher polls for those markers over `adb run-as` and captures
# the device framebuffer with `adb exec-out screencap -p`, writing
# docs/evidence/m5/screens_android/NN_<name>.png.
#
# Usage:  ./scripts/watch_android_screens.sh &   (then run the tour; kill after)
set -uo pipefail
cd "$(dirname "$0")/.."

PKG=dev.quickbite.quickbite
REMOTE=code_cache/m5screens
OUT=docs/evidence/m5/screens_android
ADB="${ADB:-adb}"
SERIAL="${ADB_SERIAL:-}"
device_args=()
[[ -n "$SERIAL" ]] && device_args=(-s "$SERIAL")

mkdir -p "$OUT"
echo "watching for tour markers in $REMOTE -> $OUT (Ctrl-C to stop)"

while true; do
  # List marker files; the app is only installed while the tour runs.
  markers=$("$ADB" "${device_args[@]}" shell run-as "$PKG" ls "$REMOTE" 2>/dev/null | tr -d '\r' | grep '\.request$' || true)
  for m in $markers; do
    out="$OUT/${m%.request}.png"
    if [[ ! -f "$out" ]]; then
      # The test holds the frame still for ~2.6 s; screencap lands inside that.
      "$ADB" "${device_args[@]}" exec-out screencap -p > "$out" 2>/dev/null
      if [[ -s "$out" ]]; then
        echo "  captured ${out} ($(stat -c%s "$out") bytes)"
      else
        rm -f "$out"
      fi
    fi
  done
  sleep 0.2
done
