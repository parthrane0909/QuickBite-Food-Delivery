#!/usr/bin/env python3
"""Collect REAL food photography for the QuickBite demo UI.

For every seeded catalog entity (4 restaurants + 24 menu items) this script
searches Wikimedia Commons for a matching photograph, verifies the license is
reuse-friendly (CC0/PD/CC BY/CC BY-SA — no NC/Fair-use), downloads a 1280px
render, normalises it (RGB JPEG, <=1400px wide, quality 82) and stores it at
frontend/assets/food/<entity-id>.jpg. Every download is recorded in
frontend/assets/food/CREDITS.json (machine-readable) and CREDITS.md (human).

Manual curation:
  * scripts/food_photo_overrides.json maps an entity to a specific Commons
    file ({"commons_file": "File:..."} ) or a direct Unsplash photo id
    ({"unsplash": "photo-xxxx"} ) when the automatic first hit is a poor
    match — used after visual review.
  * --only <entity-id> re-fetches a single entity after editing overrides.

Usage (from the repo root):
    python3 scripts/fetch_food_photos.py            # fetch missing
    python3 scripts/fetch_food_photos.py --refetch  # re-download everything
    python3 scripts/fetch_food_photos.py --only item_margherita_pizza

Sources validated reachable from this environment (2026-07):
  * Wikimedia Commons API (license metadata embedded per file)
  * images.unsplash.com direct photo ids (Unsplash License)
"""
from __future__ import annotations

import argparse
import html
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent
OUT_DIR = REPO / "frontend" / "assets" / "food"
OVERRIDES = REPO / "scripts" / "food_photo_overrides.json"
CREDITS_JSON = OUT_DIR / "CREDITS.json"
CREDITS_MD = OUT_DIR / "CREDITS.md"

UA = {"User-Agent": "QuickBite-demo/1.0 (local dev; food photo collector)"}
MAX_W = 1400
JPEG_QUALITY = 82

# (entity id, search query) — queries tuned to the seeded catalog.
ENTITIES: list[tuple[str, str]] = [
    # --- restaurants (used as hero/wide imagery) ---
    ("rest_spice_route", "north indian thali food"),
    ("rest_coastal_catch", "grilled seafood platter"),
    ("rest_bella_napoli", "pizza wood fired oven"),
    ("rest_sweet_crumb", "patisserie cakes"),
    # --- Spice Route Kitchen ---
    ("item_dal_makhani", "dal makhani"),
    ("item_tandoori_chicken", "tandoori chicken"),
    ("item_hyderabadi_biryani", "biryani chicken"),
    ("item_paneer_tikka", "paneer tikka"),
    ("item_garlic_naan", "butter naan tandoor"),
    ("item_mango_lassi", "mango lassi"),
    # --- Coastal Catch ---
    ("item_fish_curry", "fish curry"),
    ("item_prawns_garlic", "garlic butter prawns"),
    ("item_grilled_pomfret", "grilled pomfret fish"),
    ("item_crab_masala", "chilli crab"),
    ("item_seafood_platter", "seafood platter"),
    ("item_coconut_kheer", "kheer pudding indian"),
    # --- Bella Napoli ---
    ("item_margherita_pizza", "margherita pizza"),
    ("item_pepperoni_pizza", "pepperoni pizza"),
    ("item_carbonara", "spaghetti carbonara"),
    ("item_tiramisu", "tiramisu"),
    ("item_garlic_bread", "garlic bread"),
    ("item_bbq_chicken_pizza", "barbecue chicken pizza"),
    # --- Sweet Crumb Patisserie ---
    ("item_chocolate_truffle", "chocolate cake slice"),
    ("item_red_velvet_slice", "red velvet cake"),
    ("item_baked_cheesecake", "cheesecake slice plate"),
    ("item_butter_croissant", "croissant"),
    ("item_fudge_brownie", "chocolate brownie"),
    ("item_matcha_latte", "matcha latte"),
]

OK_LICENCE = re.compile(
    r"^(cc0|cc[ -]by(?:[ -]sa)?(?:[ -]\d\.\d)?|public domain|pd|pd-self|"
    r"attribution|no restrictions)",
    re.I,
)
BAD_LICENCE = re.compile(r"(non.?commercial|nc\b|fair use|nonfree|non-free)", re.I)


def _get(url: str, timeout: int) -> bytes:
    """GET with pacing: Wikimedia rate-limits anonymous bursts (429), so we
    throttle between calls and back off exponentially on 429/403."""
    last_exc: Exception | None = None
    for attempt, delay in enumerate((0.0, 6.0, 15.0, 30.0)):
        if delay:
            time.sleep(delay)
        elif _get._last_call:
            gap = time.monotonic() - _get._last_call
            if gap < 2.0:  # keep <= ~30 requests/minute
                time.sleep(2.0 - gap)
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                body = resp.read()
            _get._last_call = time.monotonic()
            return body
        except urllib.error.HTTPError as exc:
            last_exc = exc
            if exc.code in (429, 403) and attempt < 3:
                continue
            raise
    raise last_exc  # pragma: no cover — all retries exhausted


_get._last_call = 0.0


def _json(url: str) -> dict:
    return json.loads(_get(url, 30))


def _download(url: str) -> bytes:
    return _get(url, 60)


def _strip_html(value: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", "", value or "")).strip()


def commons_search(query: str, limit: int = 8) -> list[dict]:
    params = urllib.parse.urlencode(
        {
            "action": "query",
            "generator": "search",
            "gsrsearch": f"{query} filetype:bitmap",
            "gsrnamespace": "6",
            "gsrlimit": str(limit),
            "prop": "imageinfo",
            "iiprop": "url|mime|size|extmetadata",
            "iiurlwidth": "1600",
            "format": "json",
            "formatversion": "2",
        }
    )
    data = _json(f"https://commons.wikimedia.org/w/api.php?{params}")
    results = []
    for page in data.get("query", {}).get("pages", []):
        info = (page.get("imageinfo") or [{}])[0]
        meta = info.get("extmetadata", {})
        licence = _strip_html(meta.get("LicenseShortName", {}).get("value", ""))
        width, height = info.get("width") or 0, info.get("height") or 0
        if info.get("mime") not in ("image/jpeg", "image/png"):
            continue
        if BAD_LICENCE.search(licence) or not OK_LICENCE.search(licence):
            continue
        thumb = info.get("thumburl")
        if not thumb:
            continue
        results.append(
            {
                "source": "wikimedia_commons",
                "title": page.get("title", ""),
                "page": f"https://commons.wikimedia.org/wiki/"
                f"{urllib.parse.quote(page.get('title', '').replace(' ', '_'))}",
                "thumb": thumb,
                "artist": _strip_html(
                    meta.get("Artist", {}).get("value", "")
                ) or "Unknown",
                "licence": licence or "Unknown",
                "licence_url": _strip_html(
                    meta.get("LicenseUrl", {}).get("value", "")
                ),
                "query": query,
                "orig_w": width,
                "orig_h": height,
            }
        )
    return results


def unsplash_download(photo_id: str) -> bytes:
    url = (
        f"https://images.unsplash.com/{photo_id}"
        f"?w=1600&q=85&fm=jpg&fit=max"
    )
    return _download(url)


def save_image(raw: bytes, dest: Path) -> tuple[int, int]:
    from io import BytesIO

    img = Image.open(BytesIO(raw))
    img = img.convert("RGB")
    if img.width > MAX_W:
        height = round(img.height * MAX_W / img.width)
        img = img.resize((MAX_W, height), Image.LANCZOS)
    dest.parent.mkdir(parents=True, exist_ok=True)
    img.save(dest, "JPEG", quality=JPEG_QUALITY, optimize=True, progressive=True)
    return img.size


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refetch", action="store_true", help="re-download all")
    parser.add_argument("--only", help="fetch a single entity id")
    parser.add_argument(
        "--candidates",
        action="store_true",
        help="print candidate search results (with size) instead of downloading",
    )
    args = parser.parse_args()

    overrides = {}
    if OVERRIDES.exists():
        overrides = json.loads(OVERRIDES.read_text())

    entities = ENTITIES
    if args.only:
        entities = [e for e in entities if e[0] == args.only]
        if not entities:
            print(f"unknown entity: {args.only}", file=sys.stderr)
            return 1

    credits: dict[str, dict] = {}
    if CREDITS_JSON.exists():
        credits = json.loads(CREDITS_JSON.read_text())

    fetched = skipped = failed = 0
    for entity_id, query in entities:
        dest = OUT_DIR / f"{entity_id}.jpg"
        if (
            dest.exists()
            and not args.refetch
            and not args.candidates
            and entity_id not in overrides
        ):
            skipped += 1
            continue

        if args.candidates:
            print(f"\n{entity_id}  <- {query}")
            for i, c in enumerate(commons_search(query, limit=8)):
                print(f"   [{i}] {c['title']}  ({c.get('orig_w', '?')}x{c.get('orig_h', '?')})  {c['licence']}")
            continue

        record = None
        raw = None
        override = overrides.get(entity_id, {})

        try:
            if "unsplash" in override:
                raw = unsplash_download(override["unsplash"])
                record = {
                    "source": "unsplash",
                    "title": override["unsplash"],
                    "page": f"https://unsplash.com/photos/{override['unsplash']}",
                    "artist": override.get("artist", "Unsplash contributor"),
                    "licence": override.get("licence", "Unsplash License"),
                    "licence_url": "https://unsplash.com/license",
                    "query": query,
                }
            else:
                candidates = commons_search(query)
                if "commons_file" in override:
                    matched = [
                        c for c in candidates if c["title"] == override["commons_file"]
                    ]
                    if matched:
                        candidates = matched
                        override = {**override, "index": 0}
                if not candidates:
                    print(f"  ! {entity_id}: no licensed candidate for {query!r}")
                    failed += 1
                    continue
                pick = candidates[override.get("index", 0)]
                raw = _download(pick["thumb"])
                record = pick
        except Exception as exc:  # noqa: BLE001 — report and continue
            print(f"  ! {entity_id}: {exc}")
            failed += 1
            continue

        try:
            width, height = save_image(raw, dest)
        except Exception as exc:  # noqa: BLE001
            print(f"  ! {entity_id}: invalid image ({exc})")
            failed += 1
            continue

        record["bytes"] = dest.stat().st_size
        record["width"] = width
        record["height"] = height
        credits[entity_id] = record
        fetched += 1
        print(f"  + {entity_id}.jpg  {width}x{height}  "
              f"[{record['licence']}] {record['title'][:60]}")

    CREDITS_JSON.write_text(json.dumps(credits, indent=2, sort_keys=True) + "\n")
    _write_credits_md(credits)
    print(f"\nfetched={fetched} skipped={skipped} failed={failed}")
    return 0 if failed == 0 else 1


def _write_credits_md(credits: dict[str, dict]) -> None:
    lines = [
        "# QuickBite food photography — credits & licenses",
        "",
        "Real photographs collected by `scripts/fetch_food_photos.py` for the",
        "QuickBite demo UI. File names match the catalog entity ids and are",
        "served through the API's `image_asset` field.",
        "",
        "| Entity | Photo | Author | License | Source |",
        "|---|---|---|---|---|",
    ]
    for entity_id in sorted(credits):
        rec = credits[entity_id]
        title = rec.get("title", "").removeprefix("File:")
        lines.append(
            f"| `{entity_id}` | {title} | {rec.get('artist', '?')[:60]} | "
            f"{rec.get('licence', '?')} | [source]({rec.get('page', '')}) |"
        )
    lines += [
        "",
        "## License summary",
        "",
        "- **CC BY / CC BY-SA (Wikimedia Commons)**: attribution required —",
        "  the table above and `CREDITS.json` record author, license and file",
        "  page per image. ShareAlike applies to the images themselves, not to",
        "  the application code.",
        "- **Unsplash License**: free to use; attribution appreciated.",
        "",
        "Replace any photo by editing `scripts/food_photo_overrides.json` and",
        "re-running `python3 scripts/fetch_food_photos.py --only <entity-id>`.",
        "",
    ]
    CREDITS_MD.write_text("\n".join(lines))


if __name__ == "__main__":
    raise SystemExit(main())
