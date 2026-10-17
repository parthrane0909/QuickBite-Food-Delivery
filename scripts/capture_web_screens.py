#!/usr/bin/env python3
"""Milestone 5 evidence: drive the QuickBite WEB app with Playwright and
save screenshots to docs/evidence/m5/screens_web/.

Requires: the web service up (`./scripts/build_web.sh`), the API running,
and `uv run --with playwright python scripts/capture_web_screens.py`.

The app renders on a canvas; we enable Flutter's semantics tree first so
the script can drive real elements (which doubles as accessibility
evidence: every control is reachable by its semantic label). Selectors
are retried against several candidate locators because Flutter re-emits
its semantics tree on every route change.
"""
import pathlib
import sys

from playwright.sync_api import sync_playwright

BASE = "http://localhost:8080"
OUT = pathlib.Path(__file__).resolve().parent.parent / "docs" / "evidence" / "m5" / "screens_web"
OUT.mkdir(parents=True, exist_ok=True)

ADMIN = ("admin@quickbite.dev", "quickbite!admin1")
CUSTOMER = ("alice@quickbite.dev", "quickbite!alice1")


def shot(page, name):
    page.wait_for_timeout(400)
    path = OUT / f"{name}.png"
    page.screenshot(path=str(path))
    print(f"  saved {path.name}")


def enable_semantics(page, attempts=5):
    """Flutter draws semantics lazily; click the off-screen toggle via JS and
    wait until the semantic tree actually renders (the engine may boot slowly)."""
    for _ in range(attempts):
        page.wait_for_timeout(2000)
        page.evaluate(
            """() => { const b = document.querySelector('[aria-label="Enable accessibility"]');
                       if (b) b.click(); }"""
        )
        page.wait_for_timeout(1500)
        nodes = page.evaluate("document.querySelectorAll('flt-semantics').length")
        if nodes > 3:
            return
    print("  warning: semantics tree did not render", file=sys.stderr)


def tap(page, *locators, timeout=20000):
    """Try each locator (in order) until one clicks successfully."""
    last = None
    for make in locators:
        loc = make(page)
        try:
            loc.first.click(timeout=timeout)
            return
        except Exception as exc:  # noqa: BLE001 — try the next candidate
            last = exc
    raise last if last else RuntimeError("tap(): no locators given")


def sign_in(page, email, password, lands_on="**/restaurants**"):
    def _fill_login():
        tap(
            page,
            lambda p: p.get_by_label("Email", exact=True),
            lambda p: p.get_by_role("textbox").first,
        )
        page.keyboard.type(email)
        tap(page, lambda p: p.get_by_label("Password", exact=True))
        page.keyboard.type(password)
        page.wait_for_timeout(300)
        tap(page, lambda p: p.get_by_role("button", name="Sign In"))

    _fill_login()
    # Land on the role-based home; retry the sign-in once if it flaked.
    try:
        page.wait_for_url(lands_on, timeout=10000)
    except Exception:  # noqa: BLE001 — retry once
        enable_semantics(page)
        _fill_login()
        page.wait_for_url(lands_on, timeout=15000)
    enable_semantics(page)


def open_bella_napoli(page):
    tap(
        page,
        lambda p: p.get_by_label("Bella Napoli restaurant, open"),
        lambda p: p.locator("flt-semantics[flt-tappable]").filter(has_text="Bella Napoli"),
        lambda p: p.get_by_text("Bella Napoli", exact=True),
    )
    page.wait_for_timeout(2500)
    enable_semantics(page)


def main():
    errors = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)

        # ---------- customer, desktop viewport ----------
        page = browser.new_page(viewport={"width": 1280, "height": 900})
        page.goto(f"{BASE}/login", timeout=30000)
        enable_semantics(page)
        shot(page, "01_login_desktop")

        sign_in(page, *CUSTOMER)
        shot(page, "02_restaurant_list_desktop")

        open_bella_napoli(page)
        shot(page, "03_menu_desktop")

        # Add the first available item.
        tap(page, lambda p: p.get_by_role("button", name="Add"))
        page.wait_for_timeout(800)
        shot(page, "04_menu_added_desktop")

        tap(page, lambda p: p.get_by_role("button", name="View cart"))
        page.wait_for_timeout(1500)
        enable_semantics(page)
        shot(page, "05_cart_desktop")

        tap(page, lambda p: p.get_by_role("button", name="Proceed to checkout"))
        page.wait_for_timeout(1500)
        enable_semantics(page)
        shot(page, "06_checkout_desktop")

        # Fill the address and place the order (real 202 against the stack).
        try:
            # Flutter web renders the TextFormField as a real <textarea>.
            page.locator("textarea").first.click()
            page.keyboard.type("12 Lake Road, Bengaluru")
            page.wait_for_timeout(400)
            shot(page, "07_checkout_filled_desktop")
            tap(page, lambda p: p.get_by_role("button", name="Place order"))
            page.wait_for_timeout(3000)
            shot(page, "08_order_accepted_desktop")

            tap(page, lambda p: p.get_by_role("button", name="Track this order"))
            page.wait_for_timeout(6000)
            shot(page, "09_tracking_live_desktop")
            # Give the workers time to reach the terminal state.
            page.wait_for_timeout(9000)
            shot(page, "10_tracking_terminal_desktop")
        except Exception as exc:  # noqa: BLE001 — evidence script, keep going
            errors.append(f"checkout flow: {exc}")

        # Order history via the shell nav (the tracking back button lands
        # on the history shell, which has the nav tabs).
        try:
            tap(
                page,
                lambda p: p.get_by_role("button", name="Orders"),
                lambda p: p.locator("flt-semantics[flt-tappable]").filter(
                    has_text="Orders"
                ),
            )
            page.wait_for_timeout(2500)
            shot(page, "11_order_history_desktop")
        except Exception as exc:  # noqa: BLE001
            errors.append(f"history nav: {exc}")
        page.close()

        # ---------- customer, narrow phone viewport ----------
        mobile = browser.new_page(viewport={"width": 375, "height": 780})
        mobile.goto(f"{BASE}/login", timeout=30000)
        enable_semantics(mobile)
        sign_in(mobile, *CUSTOMER)
        shot(mobile, "12_restaurant_list_narrow")
        open_bella_napoli(mobile)
        shot(mobile, "13_menu_narrow")
        mobile.close()

        # ---------- admin, desktop viewport ----------
        admin = browser.new_page(viewport={"width": 1280, "height": 900})
        admin.goto(f"{BASE}/login", timeout=30000)
        enable_semantics(admin)
        sign_in(admin, *ADMIN, lands_on="**/admin**")
        admin.wait_for_timeout(1500)
        shot(admin, "14_admin_overview_desktop")
        # Cross-customer status filter (chips expose role=checkbox).
        try:
            tap(admin, lambda a: a.get_by_role("checkbox", name="Paid"))
            admin.wait_for_timeout(2000)
            shot(admin, "15_admin_filter_paid_desktop")
        except Exception as exc:  # noqa: BLE001
            errors.append(f"admin filter: {exc}")
        admin.close()

        browser.close()

    if errors:
        print("PARTIAL CAPTURE — issues:")
        for e in errors:
            print("  -", e)
        return 1
    print("web screenshots complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
