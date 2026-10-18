"""Capture and inspect a Flutter web route with Chrome's built-in CDP.

Uses only Python's standard library and the locally installed Chrome binary.
This is intentionally a read-only page-load probe; Android integration tests
cover authenticated interactions.
"""

from __future__ import annotations

import base64
import json
import os
import secrets
import socket
import subprocess
import time
import urllib.request
from pathlib import Path
from urllib.error import URLError
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/evidence/final"
PORT = 9234


def receive_exact(sock: socket.socket, size: int) -> bytes:
    data = bytearray()
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise ConnectionError("Chrome closed its CDP socket")
        data.extend(chunk)
    return bytes(data)


class DevTools:
    def __init__(self, endpoint: str) -> None:
        from urllib.parse import urlsplit

        target = urlsplit(endpoint)
        self.socket = socket.create_connection(
            (target.hostname, target.port), timeout=10
        )
        key = base64.b64encode(secrets.token_bytes(16)).decode()
        request = (
            f"GET {target.path} HTTP/1.1\r\nHost: {target.netloc}\r\n"
            "Upgrade: websocket\r\nConnection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
        )
        self.socket.sendall(request.encode())
        response = bytearray()
        while not response.endswith(b"\r\n\r\n"):
            response.extend(self.socket.recv(1))
        if b" 101 " not in response:
            raise ConnectionError(response.decode(errors="replace"))
        self.next_id = 0

    def send(self, payload: dict) -> None:
        body = json.dumps(payload).encode()
        mask = secrets.token_bytes(4)
        size = len(body)
        header = bytearray((0x81, 0x80 | min(126, size)))
        if size >= 126:
            header.extend(size.to_bytes(2, "big"))
        header.extend(mask)
        encoded = bytes(value ^ mask[index % 4] for index, value in enumerate(body))
        self.socket.sendall(header + encoded)

    def receive(self) -> dict:
        first, second = receive_exact(self.socket, 2)
        opcode, size = first & 0x0F, second & 0x7F
        if size == 126:
            size = int.from_bytes(receive_exact(self.socket, 2), "big")
        elif size == 127:
            size = int.from_bytes(receive_exact(self.socket, 8), "big")
        mask = receive_exact(self.socket, 4) if second & 0x80 else None
        body = receive_exact(self.socket, size)
        if mask:
            body = bytes(value ^ mask[index % 4] for index, value in enumerate(body))
        if opcode == 8:
            raise ConnectionError("Chrome ended the CDP WebSocket")
        if opcode == 9:
            return self.receive()
        return json.loads(body)

    def call(self, method: str, params: dict | None = None) -> dict:
        self.next_id += 1
        call_id = self.next_id
        self.send({"id": call_id, "method": method, "params": params or {}})
        while True:
            result = self.receive()
            if result.get("id") == call_id:
                if "error" in result:
                    raise RuntimeError(result["error"])
                return result.get("result", {})


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    profile = Path("/tmp/quickbite-cdp-profile")
    chrome = subprocess.Popen(
        [
            "google-chrome",
            "--headless",
            "--no-sandbox",
            "--disable-gpu",
            f"--remote-debugging-port={PORT}",
            f"--user-data-dir={profile}",
            "about:blank",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        version_url = f"http://127.0.0.1:{PORT}/json/version"
        for _ in range(100):
            try:
                with urllib.request.urlopen(version_url, timeout=1):
                    break
            except (OSError, URLError, TimeoutError):
                time.sleep(0.1)
        route = os.environ.get("QUICKBITE_WEB_ROUTE", "/")
        url = "http://localhost:8080" + route
        new_target = urllib.request.Request(
            f"http://127.0.0.1:{PORT}/json/new?{quote(url, safe=':/?=&%')}",
            method="PUT",
        )
        with urllib.request.urlopen(new_target, timeout=5) as response:
            target = json.load(response)
        cdp = DevTools(target["webSocketDebuggerUrl"])
        cdp.call("Page.enable")
        cdp.call("Runtime.enable")
        cdp.call(
            "Emulation.setDeviceMetricsOverride",
            {"width": 393, "height": 852, "deviceScaleFactor": 1, "mobile": True},
        )
        cdp.call("Page.navigate", {"url": url})
        time.sleep(7)
        cdp.call(
            "Runtime.evaluate",
            {
                "expression": "document.querySelector('[aria-label=\"Enable accessibility\"]')?.click()",
                "returnByValue": True,
            },
        )
        time.sleep(1)
        evaluation = cdp.call(
            "Runtime.evaluate",
            {
                "expression": "JSON.stringify({href:location.href,labels:[...document.querySelectorAll('flt-semantics')].map(e=>e.getAttribute('aria-label')).filter(Boolean).slice(0,80),inputs:[...document.querySelectorAll('input,textarea')].map(e=>({tag:e.tagName,type:e.type,aria:e.getAttribute('aria-label'),placeholder:e.getAttribute('placeholder'),outer:e.outerHTML.slice(0,180)}))})",
                "returnByValue": True,
            },
        )
        browser = json.loads(evaluation["result"]["value"])
        screenshot = cdp.call(
            "Page.captureScreenshot", {"format": "png", "captureBeyondViewport": False}
        )
        filename = "cold-root.png" if route == "/" else "cold-login.png"
        path = OUT / "after-web" / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(base64.b64decode(screenshot["data"]))
        report = {
            "requested_url": url,
            **browser,
            "screenshot": path.relative_to(OUT).as_posix(),
        }
        (OUT / "cold-web-route.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))
    finally:
        chrome.terminate()
        try:
            chrome.wait(timeout=5)
        except subprocess.TimeoutExpired:
            chrome.kill()


if __name__ == "__main__":
    main()
