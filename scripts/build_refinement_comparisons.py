#!/usr/bin/env python3
"""UI-refinement evidence: build before/after and reference side-by-side sheets.

Inputs
  before : docs/evidence/ui-rehaul/screens_web/         (tracked rehaul baseline)
  after  : docs/evidence/ui-refinement/screens_web/     (this refinement)
  refs   : quickbitetemplate_{landing,login,restaurant}page.png (repo root)

Outputs (docs/evidence/ui-refinement/comparisons/)
  before_after_<screen>.png   one pair per key screen
  before_after_sheet.png      all pairs in one contact sheet
  reference_vs_quickbite.png  the three supplied references above the app

Run:  uv run --with pillow python scripts/build_refinement_comparisons.py
"""
from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
BEFORE = ROOT / "docs" / "evidence" / "ui-rehaul" / "screens_web"
AFTER = ROOT / "docs" / "evidence" / "ui-refinement" / "screens_web"
OUT = ROOT / "docs" / "evidence" / "ui-refinement" / "comparisons"
OUT.mkdir(parents=True, exist_ok=True)

FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
BG = (252, 247, 242)
INK = (28, 20, 17)
SOFT = (110, 95, 88)
CORAL = (219, 58, 31)

# (file name, human label)
PAIRS = [
    ("18_welcome_mobile.png", "Welcome / onboarding - phone"),
    ("19_login_mobile.png", "Sign in - phone"),
    ("20_home_list_mobile.png", "Home discovery - phone"),
    ("03_home_grid_desktop.png", "Home discovery - desktop"),
    ("21_menu_mobile.png", "Restaurant menu - phone"),
    ("04_menu_desktop.png", "Restaurant menu - desktop"),
    ("22_item_detail_mobile.png", "Item detail - phone"),
    ("23_cart_mobile.png", "Cart - phone"),
    ("09_checkout_desktop.png", "Checkout - desktop"),
    ("12_tracking_live_desktop.png", "Order tracking (live) - desktop"),
    ("25_admin_overview_desktop.png", "Admin overview - desktop"),
]

REFS = [
    (
        "quickbitetemplate_loginpage.png",
        "Reference: onboarding",
        "18_welcome_mobile.png",
        "QuickBite: welcome / onboarding",
        "Immersive red field, oversized brand type, real food photo, "
        "two pill controls. No reward program or social sign-in (not in the "
        "contract).",
    ),
    (
        "quickbitetemplate_landingpage.png",
        "Reference: home",
        "20_home_list_mobile.png",
        "QuickBite: home / discovery",
        "Dark photographic hero + real greeting + restaurant cards from "
        "PostgreSQL. No fabricated 15% offer, rating, ETA, fee or "
        "non-functional search / cuisine filter.",
    ),
    (
        "quickbitetemplate_restaurantpage.png",
        "Reference: restaurant",
        "21_menu_mobile.png",
        "QuickBite: restaurant menu",
        "Photographic hero, circular mark on the seam, raised info card, "
        "image-led item cards with server prices. No invented menu "
        "categories or delivery-time/charge panel.",
    ),
]


def font(size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(FONT_PATH, size)
    except OSError:  # pragma: no cover - font always present in this image
        return ImageFont.load_default()


def scaled(path: pathlib.Path, height: int) -> Image.Image:
    img = Image.open(path).convert("RGB")
    width = max(1, round(img.width * height / img.height))
    return img.resize((width, height), Image.LANCZOS)


def wrap(draw: ImageDraw.ImageDraw, text: str, f, max_width: int) -> list[str]:
    """Greedy word-wrap so footnotes stay readable instead of being cut off."""
    lines: list[str] = []
    current = ""
    for word in text.split():
        candidate = f"{current} {word}".strip()
        if draw.textlength(candidate, font=f) <= max_width or not current:
            current = candidate
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def labelled(img: Image.Image, caption: str, width: int, accent=CORAL) -> Image.Image:
    band = Image.new("RGB", (width, 34), BG)
    draw = ImageDraw.Draw(band)
    text = caption
    f = font(17)
    while draw.textlength(text, font=f) > width - 12 and len(text) > 4:
        text = text[:-2]
    draw.text((6, 8), text, font=f, fill=accent)
    out = Image.new("RGB", (width, img.height + 34), BG)
    out.paste(band, (0, 0))
    out.paste(img, ((width - img.width) // 2, 34))
    return out


def frame(img: Image.Image, pad: int = 10) -> Image.Image:
    out = Image.new("RGB", (img.width + pad * 2, img.height + pad * 2), BG)
    out.paste(img, (pad, pad))
    return out


def pair_sheet(
    out_name: str,
    label: str,
    left: tuple[pathlib.Path, str],
    right: tuple[pathlib.Path, str],
    footer: str = "",
    height: int = 700,
) -> None:
    l_img, l_cap = left
    r_img, r_cap = right
    left_panel = frame(labelled(scaled(l_img, height), l_cap, scaled(l_img, height).width + 12))
    right_panel = frame(labelled(scaled(r_img, height), r_cap, scaled(r_img, height).width + 12))

    gap = 16
    margin = 16
    head = 54
    foot = 34 if footer else 0
    width = margin * 2 + left_panel.width + gap + right_panel.width
    body_h = max(left_panel.height, right_panel.height)
    canvas = Image.new("RGB", (width, head + body_h + foot + margin), BG)

    draw = ImageDraw.Draw(canvas)
    draw.text((margin, 14), label, font=font(24), fill=INK)
    canvas.paste(left_panel, (margin, head))
    canvas.paste(right_panel, (margin + left_panel.width + gap, head))

    if footer:
        f = font(14)
        lines = wrap(draw, footer, f, width - margin * 2)[:3]
        for index, line in enumerate(lines):
            draw.text((margin, head + body_h + 8 + index * 20), line, font=f, fill=SOFT)

    canvas.save(OUT / out_name)
    print(f"  {out_name}  {canvas.width}x{canvas.height}")


def main() -> int:
    built: list[pathlib.Path] = []
    for name, label in PAIRS:
        before, after = BEFORE / name, AFTER / name
        if not before.exists() or not after.exists():
            print(f"  skip {name} (missing side)")
            continue
        out_name = f"before_after_{name}"
        pair_sheet(
            out_name,
            label,
            (before, "BEFORE - rehaul baseline"),
            (after, "AFTER - this refinement"),
        )
        built.append(OUT / out_name)

    # Reference-vs-app rows (3), stacked into one sheet.
    rows = []
    for ref_name, ref_cap, after_name, after_cap, note in REFS:
        left = frame(labelled(scaled(ROOT / ref_name, 700), ref_cap, scaled(ROOT / ref_name, 700).width + 12))
        right = frame(labelled(scaled(AFTER / after_name, 700), after_cap, scaled(AFTER / after_name, 700).width + 12))
        gap, margin = 16, 16
        width = margin * 2 + left.width + gap + right.width
        row = Image.new("RGB", (width, 54 + max(left.height, right.height) + 56), BG)
        draw = ImageDraw.Draw(row)
        f = font(13)
        lines = wrap(draw, note, f, width - margin * 2)[:3]
        row.paste(left, (margin, 54))
        row.paste(right, (margin + left.width + gap, 54))
        base = 54 + max(left.height, right.height) + 8
        for index, line in enumerate(lines):
            draw.text((margin, base + index * 18), line, font=f, fill=SOFT)
        rows.append(row)

    if rows:
        width = max(row.width for row in rows)
        total_h = sum(row.height + 14 for row in rows) + 60
        sheet = Image.new("RGB", (width, total_h), BG)
        draw = ImageDraw.Draw(sheet)
        draw.text((16, 14), "Supplied references vs QuickBite (phone viewport)", font=font(24), fill=INK)
        y = 60
        for row in rows:
            sheet.paste(row, (0, y))
            y += row.height + 14
        sheet.save(OUT / "reference_vs_quickbite.png")
        print(f"  reference_vs_quickbite.png  {sheet.width}x{sheet.height}")

    # The individual before/after pairs are the deliverable; a redundant
    # multi-megabyte contact sheet would only bloat the repository.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
