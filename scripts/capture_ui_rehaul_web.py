#!/usr/bin/env python3
"""UI rehaul evidence: drive the QuickBite WEB app with Playwright and save
screenshots to docs/evidence/ui-rehaul/screens_web/ at BOTH a desktop
viewport (1280x900 — left rail + grid) and a phone viewport (375x780 —
bottom bar + list), proving the responsive adaptation is a real layout
change rather than a stretched phone.

Requires: the web service rebuilt from the rehauled source
(`./scripts/build_web.sh`), the API + workers running, and:
    uv run --with playwright python scripts/capture_ui_rehaul_web.py

Same technique as capture_web_screens.py (M5): enable Flutter's semantics
tree first so the script drives real accessible elements.
"""
import pathlib
import re
import sys

from playwright.sync_api import sync_playwright

BASE = "http://localhost:8080"
OUT = pathlib.Path(__file__).resolve().parent.parent / "docs" / "evidence" / "ui-rehaul" / "screens_web"
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


def wheel_down(page, amount=600):
    """Scroll the Flutter canvas (welcome pitch can sit below the fold on
    short viewports; the wheel event scrolls Flutter's own scrollables)."""
    page.mouse.move(400, 400)
    page.mouse.wheel(0, amount)
    page.wait_for_timeout(600)


def open_welcome_to_login(page):
    """From the signed-out landing page, reach the login form."""
    wheel_down(page)
    tap(
        page,
        lambda p: p.get_by_role("button", name="Sign in"),
        lambda p: p.locator("flt-semantics[flt-tappable]").filter(has_text="Sign in"),
    )
    page.wait_for_timeout(1500)
    enable_semantics(page)


def sign_in(page, email, password, lands_on="**/restaurants**"):
    def _fill_login():
        tap(
            page,
            lambda p: p.get_by_label("Email", exact=True),
            lambda p: p.get_by_role("textbox").first,
        )
        # The login page's entrance animation delays focus readiness — let
        # the field settle or the first typed character gets dropped.
        page.wait_for_timeout(400)
        page.keyboard.type(email)
        tap(page, lambda p: p.get_by_label("Password", exact=True))
        page.wait_for_timeout(400)
        page.keyboard.type(password)
        page.wait_for_timeout(300)
        tap(page, lambda p: p.get_by_role("button", name="Sign In"))

    _fill_login()
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


def note(errors, what, exc):
    errors.append(f"{what}: {exc}")
    print(f"  ! {what}: {exc}", file=sys.stderr)


def main():
    errors = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)

        # ---------- customer, DESKTOP viewport (rail + grid) ----------
        ctx = browser.new_context(viewport={"width": 1280, "height": 900})
        page = ctx.new_page()
        page.goto(BASE + "/", timeout=30000)
        page.wait_for_timeout(1500)
        enable_semantics(page)
        shot(page, "01_welcome_desktop")

        open_welcome_to_login(page)
        shot(page, "02_login_desktop")

        sign_in(page, *CUSTOMER)
        shot(page, "03_home_grid_desktop")

        open_bella_napoli(page)
        shot(page, "04_menu_desktop")

        # First menu row opens the NEW item detail screen. The row merges its
        # semantics into one labelled button, so match the label (with a
        # fallback to a filtered semantic node) rather than the bare text.
        tap(
            page,
            lambda p: p.get_by_label("Margherita Pizza, menu item, opens details"),
            lambda p: p.locator("flt-semantics[flt-tappable]").filter(
                has_text="Margherita Pizza"
            ),
        )
        page.wait_for_timeout(1500)
        enable_semantics(page)
        shot(page, "05_item_detail_desktop")

        tap(page, lambda p: p.get_by_role("button", name="Add to cart"))
        page.wait_for_timeout(700)
        shot(page, "06_item_detail_added_desktop")  # SnackBar confirmation

        tap(page, lambda p: p.get_by_role("button", name="Back"))
        page.wait_for_timeout(1500)
        shot(page, "07_menu_cart_bar_desktop")

        tap(page, lambda p: p.get_by_role("button", name="View cart"))
        page.wait_for_timeout(1500)
        enable_semantics(page)
        shot(page, "08_cart_desktop")

        tap(page, lambda p: p.get_by_role("button", name="Proceed to checkout"))
        page.wait_for_timeout(1500)
        enable_semantics(page)
        shot(page, "09_checkout_desktop")

        try:
            page.locator("textarea").first.click()
            page.keyboard.type("12 Lake Road, Bengaluru")
            page.wait_for_timeout(400)
            shot(page, "10_checkout_filled_desktop")
            tap(page, lambda p: p.get_by_role("button", name="Place order"))
            page.wait_for_timeout(3500)
            shot(page, "11_order_accepted_desktop")

            tap(page, lambda p: p.get_by_role("button", name="Track this order"))
            page.wait_for_timeout(6000)
            shot(page, "12_tracking_live_desktop")
            page.wait_for_timeout(9000)
            shot(page, "13_tracking_terminal_desktop")
        except Exception as exc:  # noqa: BLE001 — evidence script, keep going
            note(errors, "checkout flow", exc)

        # Tracking is reached with go() (no push stack) — its Back falls back
        # to the /orders history branch (rail visible there).
        try:
            tap(page, lambda p: p.get_by_role("button", name="Back"))
            page.wait_for_timeout(2500)
            enable_semantics(page)
            shot(page, "14_order_history_desktop")
        except Exception as exc:  # noqa: BLE001
            note(errors, "history nav", exc)

        try:
            tap(page, lambda p: p.get_by_role("button", name="Account"))
            page.wait_for_timeout(2500)
            shot(page, "15_account_desktop")

            tap(page, lambda p: p.get_by_role("button", name="Sign out"))
            page.wait_for_timeout(1200)
            shot(page, "16_sign_out_dialog_desktop")
            # Confirm on the dialog (rendered above the screen's own button).
            page.get_by_role("button", name="Sign out").last.click(timeout=10000)
            page.wait_for_timeout(2000)
            enable_semantics(page)
            shot(page, "17_welcome_after_signout_desktop")
        except Exception as exc:  # noqa: BLE001
            note(errors, "account/sign-out", exc)
        ctx.close()

        # ---------- customer, PHONE viewport (bottom bar + list) ----------
        mctx = browser.new_context(viewport={"width": 375, "height": 780})
        mobile = mctx.new_page()
        mobile.goto(BASE + "/", timeout=30000)
        mobile.wait_for_timeout(1500)
        enable_semantics(mobile)
        shot(mobile, "18_welcome_mobile")

        open_welcome_to_login(mobile)
        shot(mobile, "19_login_mobile")

        sign_in(mobile, *CUSTOMER)
        shot(mobile, "20_home_list_mobile")

        open_bella_napoli(mobile)
        shot(mobile, "21_menu_mobile")

        tap(
            mobile,
            lambda p: mobile.get_by_label(
                "Margherita Pizza, menu item, opens details"
            ),
            lambda p: mobile.locator("flt-semantics[flt-tappable]").filter(
                has_text="Margherita Pizza"
            ),
        )
        mobile.wait_for_timeout(1500)
        enable_semantics(mobile)
        shot(mobile, "22_item_detail_mobile")

        tap(mobile, lambda p: p.get_by_role("button", name="Add to cart"))
        mobile.wait_for_timeout(700)
        tap(mobile, lambda p: p.get_by_role("button", name="Back"))
        mobile.wait_for_timeout(1500)
        tap(mobile, lambda p: p.get_by_role("button", name="View cart"))
        mobile.wait_for_timeout(1500)
        enable_semantics(mobile)
        shot(mobile, "23_cart_mobile")

        try:
            # Cart and menu are detail routes (no bottom bar) — Back until
            # the shell's Account tab reappears. The AppBar's implicit
            # BackButton exposes only its text (no aria-label mirror), so
            # offer a text-based fallback for it. On mobile, NavigationBar
            # destinations are exposed as role=tab (desktop rail: role=button).
            def _back(mobile_page):
                return mobile_page.get_by_role("button", name="Back")

            def _back_text(mobile_page):
                return mobile_page.get_by_text("Back", exact=True)

            def _back_tappable(mobile_page):
                return mobile_page.locator(
                    "flt-semantics[flt-tappable]"
                ).filter(has_text=re.compile(r"^Back$"))

            def _account_tab(mobile_page):
                return mobile_page.get_by_role("tab", name="Account")

            def _account_btn(mobile_page):
                return mobile_page.get_by_role("button", name="Account")

            def _has_account(mobile_page):
                return _account_tab(mobile_page).count() > 0 or (
                    _account_btn(mobile_page).count() > 0
                )

            for _ in range(3):
                if _has_account(mobile):
                    break
                tap(mobile, _back, _back_text, _back_tappable)
                mobile.wait_for_timeout(1500)
                enable_semantics(mobile)
            if not _has_account(mobile):
                raise RuntimeError("Account tab not reachable via Back")
            tap(mobile, _account_tab, _account_btn)
            mobile.wait_for_timeout(2500)
            shot(mobile, "24_account_mobile")
        except Exception as exc:  # noqa: BLE001
            note(errors, "mobile account nav", exc)
        mctx.close()

        # ---------- admin, DESKTOP viewport ----------
        actx = browser.new_context(viewport={"width": 1280, "height": 900})
        admin = actx.new_page()
        try:
            # Hash URL strategy: routes live under /#/, not bare paths.
            admin.goto(BASE + "/#/login", timeout=30000)
            admin.wait_for_timeout(1500)
            enable_semantics(admin)
            sign_in(admin, *ADMIN, lands_on="**/#/admin**")
            admin.wait_for_timeout(2000)
            shot(admin, "25_admin_overview_desktop")
            tap(admin, lambda a: a.get_by_role("checkbox", name="Paid"))
            admin.wait_for_timeout(2000)
            shot(admin, "26_admin_filter_paid_desktop")
        except Exception as exc:  # noqa: BLE001
            note(errors, "admin", exc)
        actx.close()

        browser.close()

    if errors:
        print("PARTIAL CAPTURE — issues:")
        for e in errors:
            print(f"  - {e}")
        return 1
    print(f"web screenshots complete: {len(list(OUT.glob('*.png')))} files in {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
