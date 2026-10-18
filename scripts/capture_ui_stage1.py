"""Read-only live UI tour: signs in and edits only the local cart, never submits an order."""

import json
import os
import re
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(
    os.environ.get(
        "QUICKBITE_CAPTURE_DIR", ROOT / "docs/evidence/ui-design-stage1/after-web"
    )
)
OUT.mkdir(parents=True, exist_ok=True)
BASE = "http://localhost:8080"


def semantics(page):
    for attempt in range(20):
        page.wait_for_timeout(1000)
        page.evaluate(
            "document.querySelector('[aria-label=\"Enable accessibility\"]')?.click()"
        )
        if page.evaluate("document.querySelectorAll('flt-semantics').length") > 3:
            page.wait_for_timeout(600)
            return
    raise RuntimeError(
        "Flutter semantics did not become ready; refusing a blank capture"
    )


def snap(page, name):
    page.wait_for_timeout(1600)
    page.screenshot(path=str(OUT / f"{name}.png"))
    print(name, flush=True)


def button(page, name):
    loc = page.get_by_role(
        "button",
        name=re.compile("^" + re.escape(name)) if name == "Add to cart" else name,
        exact=name != "Add to cart",
    ).first
    loc.scroll_into_view_if_needed()
    loc.click()
    page.wait_for_timeout(800)


def type_field(page, name, value):
    page.get_by_label(name, exact=True).click(force=True)
    page.wait_for_timeout(400)
    page.keyboard.press("Control+a")
    page.keyboard.type(value, delay=25)
    page.wait_for_timeout(300)


def login(page):
    type_field(page, "Email", "alice@quickbite.dev")
    type_field(page, "Password", "quickbite!alice1")
    button(page, "Sign In")
    page.wait_for_url("**/restaurants**")
    semantics(page)


def main():
    report = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        sizes = [(360, 640), (393, 852), (768, 1024), (1280, 900), (1440, 900)]
        if len(sys.argv) > 1:
            sizes = [(w, h) for w, h in sizes if str(w) in sys.argv[1:]]
        for width, height in sizes:
            ctx = browser.new_context(
                viewport={"width": width, "height": height}, device_scale_factor=1
            )
            page = ctx.new_page()
            errors = []
            page.on(
                "pageerror",
                lambda e, errors=errors: (
                    errors.append(str(e)),
                    print("browser error", str(e), flush=True),
                ),
            )
            page.on(
                "response",
                lambda r: (
                    print("auth response", r.status, flush=True)
                    if "/auth/login" in r.url
                    else None
                ),
            )
            page.goto(BASE)
            semantics(page)
            snap(page, f"{width}_welcome")
            button(page, "Continue with email")
            semantics(page)
            snap(page, f"{width}_login")
            login(page)
            snap(page, f"{width}_discovery")
            button(page, "Explore the kitchens")
            snap(page, f"{width}_discovery_restaurants")
            page.get_by_role("button", name=re.compile("Bella Napoli")).first.click()
            semantics(page)
            snap(page, f"{width}_menu")
            page.mouse.wheel(0, 600)
            snap(page, f"{width}_menu_scrolled")
            if "--visual-only" in sys.argv:
                ctx.close()
                continue
            # Deep-link reload must preserve target through the in-memory-token login.
            page.reload()
            semantics(page)
            assert "/login" in page.url, page.url
            login_target = page.url
            print("cold login target", login_target, flush=True)
            type_field(page, "Email", "alice@quickbite.dev")
            type_field(page, "Password", "quickbite!alice1")
            button(page, "Sign In")
            try:
                page.wait_for_url("**/menu/rest_bella_napoli**", timeout=12000)
            except Exception:
                snap(page, f"{width}_deep_link_failure")
                print("deep link failure URL", page.url, flush=True)
                raise
            semantics(page)
            # Open real dish details, add locally, check cart/checkout reachability.
            page.mouse.wheel(0, -1000)
            page.wait_for_timeout(800)
            page.get_by_role(
                "button", name=re.compile("View Margherita Pizza")
            ).first.click()
            semantics(page)
            button(page, "Add to cart")
            button(page, "Back")
            semantics(page)
            page.get_by_role("button", name="View cart", exact=False).first.click()
            semantics(page)
            assert "/cart" in page.url
            snap(page, f"{width}_cart_smoke")
            button(page, "Proceed to checkout")
            assert "/checkout" in page.url
            # Do not place an order.
            page.goto(BASE + "/#/orders")
            semantics(page)
            # Browser hash routing: goto triggers auth restoration; sign in to requested target.
            if "/login" in page.url:
                type_field(page, "Email", "alice@quickbite.dev")
                type_field(page, "Password", "quickbite!alice1")
                button(page, "Sign In")
            semantics(page)
            account = page.get_by_role("button", name=re.compile("Account")).or_(
                page.get_by_role("tab", name=re.compile("Account"))
            )
            account.first.click()
            semantics(page)
            button(page, "Sign out")
            page.get_by_role("button", name="Sign out", exact=True).last.click()
            semantics(page)
            assert "/welcome" in page.url
            snap(page, f"{width}_signed_out")
            report.append(
                {
                    "viewport": [width, height],
                    "browser_errors": errors,
                    "deep_link_login": login_target,
                    "smoke": "welcome/login/catalogue/menu/item/add/cart/checkout/orders reachable; no order submitted",
                }
            )
            ctx.close()
        browser.close()
    target = OUT.parent / "web-runtime.json"
    previous = json.loads(target.read_text()) if target.exists() else []
    widths = {r["viewport"][0] for r in report}
    target.write_text(
        json.dumps(
            [r for r in previous if r["viewport"][0] not in widths] + report, indent=2
        )
    )


if __name__ == "__main__":
    main()
