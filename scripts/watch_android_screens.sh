#!/usr/bin/env bash
# Milestone 5 / UI-rehaul: host-side screenshot watcher for the Android
# screenshot tour (frontend/integration_test/screenshot_tour_test.dart).
#
# The tour runs inside the app sandbox, where it cannot reach the host
# filesystem. Instead it idles ~1.2 s (letting the surface finish
# compositing), drops a `NN_<name>.request` marker in its cache dir and holds
# the screen still for ~6 s. This watcher polls for markers over `adb run-as`
# and captures the device framebuffer with `adb exec-out screencap -p`.
#
# Because `screencap` on the emulator occasionally reads a stale or
# partially-rasterised frame (SwiftShader), each marker gets MULTIPLE frames:
#   OUT/NN_<name>.png     first frame
#   OUT/_alt/NN_<name>.png  later frame(s), overwriting (freshest last)
# Compare and keep the sharper one when curating evidence.
# A capture whose marker disappeared mid-flight is discarded — the tour had
# already moved on, so the frame would show the wrong screen.
#
# Usage:  OUT_DIR=... ./scripts/watch_android_screens.sh &   (run tour; kill after)
set -uo pipefail
cd "$(dirname "$0")/.."

PKG=dev.quickbite.quickbite
REMOTE=code_cache/m5screens
OUT="${OUT_DIR:-docs/evidence/m5/screens_android}"
ADB="${ADB:-adb}"
SERIAL="${ADB_SERIAL:-}"
device_args=()
[[ -n "$SERIAL" ]] && device_args=(-s "$SERIAL")

mkdir -p "$OUT/_alt"
echo "watching for tour markers in $REMOTE -> $OUT (Ctrl-C to stop)"

markers_on_device() {
  "$ADB" "${device_args[@]}" shell run-as "$PKG" ls "$REMOTE" 2>/dev/null |
    tr -d '\r' | grep '\.request$' || true
}

# capture <dest> <marker> — skipped (rc 1) if the marker is already gone.
capture() {
  local dest="$1" marker="$2"
  markers_on_device | grep -qx "$marker" || return 1
  "$ADB" "${device_args[@]}" exec-out screencap -p > "$dest.tmp" 2>/dev/null
  if [[ -s "$dest.tmp" ]]; then
    mv "$dest.tmp" "$dest"
    echo "  captured $dest ($(stat -c%s "$dest") bytes)"
  else
    rm -f "$dest.tmp"
    echo "  EMPTY capture for $dest (kept previous)" >&2
  fi
}

while true; do
  markers=$(markers_on_device)
  for m in $markers; do
    base="${m%.request}"
    out="$OUT/$base.png"
    alt="$OUT/_alt/$base.png"
    # Fully processed already? (_alt is written last.)
    [[ -f "$alt" ]] && continue
    echo "  marker $m — taking frames"
    sleep 0.3
    capture "$out" "$m" || continue
    sleep 1.1
    capture "$alt" "$m" || continue
    sleep 1.1
    capture "$alt" "$m" || true # freshest alternate; marker may be gone
  done
  sleep 0.2
done
