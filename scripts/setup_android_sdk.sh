#!/usr/bin/env bash
# Milestone 5: minimal Android SDK bootstrap for QuickBite (Linux host, KVM).
# Installs ONLY what the assignment's Android build/run workflow needs:
# cmdline-tools, platform-tools, one platform + build-tools matching the
# Flutter target, the emulator, and ONE x86_64 system image for the CI/dev
# AVD. Idempotent: re-running skips completed steps.
set -euo pipefail

ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
CMDLINE_ZIP_URL="https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip"
PLATFORM="android-36"
BUILD_TOOLS="36.0.0"
SYSTEM_IMAGE="system-images;android-36;google_apis;x86_64"
AVD_NAME="quickbite"

mkdir -p "$ANDROID_HOME/cmdline-tools"
export ANDROID_HOME

sdkmanager() { "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "$@"; }
avdmanager() { "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" "$@"; }

if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo "[setup] installing cmdline-tools..."
  curl -fsSL -o /tmp/cmdline-tools.zip "$CMDLINE_ZIP_URL"
  unzip -q -o /tmp/cmdline-tools.zip -d /tmp/cmdline-tools-extract
  rm -rf "$ANDROID_HOME/cmdline-tools/latest"
  mv /tmp/cmdline-tools-extract/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest"
  rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools-extract
fi

echo "[setup] accepting licenses..."
yes | sdkmanager --licenses >/dev/null 2>&1 || true

echo "[setup] installing platform-tools, $PLATFORM, build-tools;$BUILD_TOOLS..."
sdkmanager --install "platform-tools" "platforms;$PLATFORM" "build-tools;$BUILD_TOOLS" >/dev/null

echo "[setup] installing emulator + $SYSTEM_IMAGE (this is the big one)..."
sdkmanager --install "emulator" "$SYSTEM_IMAGE" >/dev/null

if ! avdmanager list avd -c 2>/dev/null | grep -q "^${AVD_NAME}$"; then
  echo "[setup] creating AVD '$AVD_NAME'..."
  echo no | avdmanager create avd -n "$AVD_NAME" -k "$SYSTEM_IMAGE" -d pixel_6 --force >/dev/null
fi

echo "[setup] done. ANDROID_HOME=$ANDROID_HOME"
sdkmanager --list_installed | sed -n '1,30p'
