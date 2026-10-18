"""Run a real Android API smoke test and capture settled emulator frames."""

from __future__ import annotations

import os
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/evidence/final/after-android"
OUT.mkdir(parents=True, exist_ok=True)
ADB = shutil.which("adb") or "/home/parthrane/Android/Sdk/platform-tools/adb"
FLUTTER = shutil.which("flutter") or "/snap/bin/flutter"
API_BASE_URL = os.environ.get("API_BASE_URL", "http://10.0.2.2:8000/api/v1")
REMOTE = "code_cache/stage1screens"


def main() -> int:
    log_path = OUT.parent / "android-runtime.txt"
    with log_path.open("w") as log:
        proc = subprocess.Popen(
            [
                FLUTTER,
                "test",
                "--no-pub",
                "integration_test/stage1_visual_test.dart",
                "-d",
                "emulator-5554",
                f"--dart-define=API_BASE_URL={API_BASE_URL}",
                "--reporter",
                "expanded",
            ],
            cwd=ROOT / "frontend",
            stdout=log,
            stderr=subprocess.STDOUT,
        )
        seen: set[str] = set()
        while proc.poll() is None:
            markers = subprocess.run(
                [ADB, "shell", "run-as", "dev.quickbite.quickbite", "ls", REMOTE],
                capture_output=True,
                text=True,
                check=False,
            ).stdout.split()
            for marker in markers:
                if not marker.endswith(".request") or marker in seen:
                    continue
                time.sleep(1.8)
                current = subprocess.run(
                    [ADB, "shell", "run-as", "dev.quickbite.quickbite", "ls", REMOTE],
                    capture_output=True,
                    text=True,
                    check=False,
                ).stdout
                if marker not in current:
                    continue
                frame = subprocess.run(
                    [ADB, "exec-out", "screencap", "-p"],
                    capture_output=True,
                    check=False,
                ).stdout
                if frame.startswith(b"\x89PNG"):
                    (OUT / f"{marker.removesuffix('.request')}.png").write_bytes(frame)
                    seen.add(marker)
                    print(f"captured {marker}", flush=True)
            time.sleep(0.3)
    print(f"device test exit {proc.returncode}", flush=True)
    return int(proc.returncode or 0)


if __name__ == "__main__":
    raise SystemExit(main())
