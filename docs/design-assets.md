# Design assets — photography, illustration, fonts and reference material

Everything the QuickBite UI renders is either **generated in-repo**, **fetched
from a source with a recorded licence**, or is **original vector/icon work**.
There are no unlicensed stock photos, no AI-generated imagery and no assets
whose provenance is unknown.

## 1. Food photography (`frontend/assets/food/`, 28 files)

Real photographs of the exact dishes/venues seeded in PostgreSQL. Each file is
named after the catalog entity id and is returned by the API's `image_asset`
field, so a restaurant or dish always shows its own picture.

| Kind | Count | Naming |
| --- | --- | --- |
| Menu-item photos | 24 | `item_<slug>.jpg` (e.g. `item_margherita_pizza.jpg`) |
| Restaurant hero photos | 4 | `rest_<slug>.jpg` (e.g. `rest_bella_napoli.jpg`) |

**Source**: Wikimedia Commons, via `scripts/fetch_food_photos.py` (repository
root).

**Licences actually bundled** (author + licence + file page recorded per image
in [`assets/food/CREDITS.md`](../frontend/assets/food/CREDITS.md) and
`CREDITS.json`):

| Licence | Meaning here |
| --- | --- |
| CC BY 2.0 / 3.0 / 4.0 | attribution required — credited in `CREDITS.md` |
| CC BY-SA 2.0 / 3.0 / 4.0 | attribution + share-alike **on the image**, not on app code |
| CC0 / Public domain | no conditions; credited anyway |

Verification: the 28 files in `assets/food/` map 1:1 to the 28 rows of
`CREDITS.md` — no bundled image is missing an entry, and no entry is missing a
file. Dish↔photo matching was reviewed by hand (e.g. `item_dal_makhani` →
*Dal Makhani*, `item_hyderabadi_biryani` → *Chicken biriyani*). To replace one:

```bash
cd frontend
python3 scripts/fetch_food_photos.py --only item_margherita_pizza
```

**Reuse conditions.** CC BY / CC BY-SA require keeping the author + licence
with the image (done in `CREDITS.md`/`CREDITS.json`, which ship in the repo and
in the app bundle); they do **not** impose share-alike on the application
source. This is a demo/evaluation build, not a commercial product.

## 2. Generated placeholder art (`frontend/assets/images/`, 12 files)

Deterministic original artwork drawn by
`frontend/scripts/generate_food_images.py` (no third-party photography): ten
dish tiles (`dish_*.png`), `hero_banner.png` and `logo_mark.png`. Used as the
fallback whenever a catalog row has no `image_asset`, so an item never renders
an empty box. Original work of this repository — no attribution needed.

## 3. Fonts (`frontend/assets/fonts/`)

| Family | Role | Licence |
| --- | --- | --- |
| **Inter** (`Inter.ttf`) | every UI text role (display headlines through body) | SIL OFL 1.1 — `Inter-OFL.txt` |
| **Playfair Display** (`PlayfairDisplay[wght].ttf`) | the QuickBite wordmark only | SIL OFL 1.1 — `OFL.txt` |

Bundled (not fetched at runtime) so Android and web render identically.

## 4. Iconography

Material Symbols via Flutter's bundled `Icons` font (`uses-material-design:
true`). No third-party icon assets are vendored.

## 5. Reference material (not shipped in the app)

Three food-delivery template screenshots supplied by the requester
(`quickbitetemplate_landingpage.png`, `quickbitetemplate_loginpage.png`,
`quickbitetemplate_restaurantpage.png`) drove the layout/proportion work for
the landing, sign-in and restaurant pages. They are kept in the repository root
for review only, are excluded from release builds (`.gitignore`) and are **not**
a source of any asset, copy or data shown in the app. The Dribbble shot cited
in the original brief could not be retrieved from this environment, so the
three screenshots are the authority.

## 6. What the UI never shows

No ratings, review counts, delivery ETAs, delivery fees, discount badges,
cuisine chips, reward/loyalty programmes, social sign-in or fabricated driver
identities. The API contract (`docs/api.md`) has no such fields, so the UI
renders only server-provided values — `docs/ui-rehaul/REPORT.md` lists the
per-screen decisions.
