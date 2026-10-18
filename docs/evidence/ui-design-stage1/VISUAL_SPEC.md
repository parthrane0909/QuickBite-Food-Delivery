# Stage 1 visual specification

Baseline: ui-refinement, dd2b36d. Eight untracked user screenshots preserved.
References are local 255 × 527 phone mockups. Geometry below is measured
approximately inside the phone frame, excluding the orange surround.

## Welcome
- Content width approximately 230 px, side gutters 12 px (5%).
- Red field fills the phone; white display begins at y≈105 (20%).
- Heading is two lines, approximately 90 px high (17%), tight leading.
- Burger overlaps the heading and occupies y≈180–360 (34%); no photo card.
- Pale primary pill at y≈375 and outline secondary at y≈420; width ≈220,
  height ≈37. Actions sit in bottom fifth with compact supporting copy.
- Original warm-red rays/shapes, no copied third-party artwork or reward badge.
- Adapt at 360×640: display 52 px, hero about 240 px, actions 50 px.
  At 393×852: larger hero and more air, with capped headline size.
  The mobile cutout receives a 1.25× photographic emphasis; the field clips
  only its outer edge, while desktop retains the original full composition.
- Short/landscape/large-text: natural scrolling, no compressed or clipped text.
- Desktop: bounded 1100 px two-column composition, oversized cutout, action
  column capped at 420 px. No rectangular photograph.

## Login adaptation
- Same red, typography, real burger and decorative language.
- Mobile branded upper panel about 30–38% of initial viewport, white form
  sheet below, 24 px gutters; compact form, real validation and submit.
- Desktop: food/display left, substantial form panel right; max 1080 px.
- Keyboard reduces viewport; the decorative title/food collapses to a compact
  welcome heading, and scrolling keeps form/action reachable.

## Discovery
- Reference dark hero extends to y≈220 (42%); food frames central copy.
- Utility row at top, compact wordmark; central editorial headline.
- Replace unsupported discount/search/map with real exploration CTA.
- Below: compact introductory heading/availability context, horizontal
  restaurant cards with image ≈60% of card height. Four API records once
  each, not duplicated to fabricate a larger collection.
- Navigation white with rounded top, red active state, elevated cart action.
- Desktop: 2×2 compact cards, bounded hero/copy, deliberate content gutters.

## Restaurant/menu
- Reference hero y≈10–125 (22%), restaurant information to y≈230;
  two-column menu begins around y≈335. Unsupported offers/metrics omitted.
- QuickBite adaptation: photographic red header about 200 px; restaurant
  name integrated into hero. Compact white description/availability section.
  No initials badge or oversized detached information card.
- 12–16 px gutters, 12 px gaps. Two image-first cards at ordinary 360/393 px;
  cards have 4:3 photography, natural text height, full descriptions, INR
  prices and integrated 48 px add control. Large text/narrow constraints
  select one column; desktop 3–4 columns, no fixed text-height clipping.
- Persistent bounded cart action uses real count and estimated subtotal.

## Shared tokens and behavior
- Decorative brand #E51C0B; accessible action #C92916; dark #151515;
  white surfaces; neutral #F6F6F6; ink #171717; muted #656565.
- Inter bundled OFL; heavy display 48–72, headings 22–32, body 14–16.
- Cards 16 px radius, buttons full pills, soft neutral shadows.
- Press 140 ms; routes 280 ms; entrance up to 420 ms. No navigation delays.
- Focus ring, Enter/Space actions, pointer hover, disabled/loading states.
- Reduced motion renders settled entrances and route content immediately.
- Static screenshots establish no exact motion behavior: these are deliberate
  QuickBite adaptations, not claims about unseen reference interactions.

## Image provenance
hero_burger.png: real photograph, Renee Comet; National Cancer Institute
image 2652. Existing transparent-background edit credited to Wikimedia user
Download. Source https://commons.wikimedia.org/wiki/File:Cheeseburger.png
Original https://upload.wikimedia.org/wikipedia/commons/1/11/Cheeseburger.png
Public Domain Mark / US federal work per Commons file page, reviewed
2026-10-18. Downloaded unchanged; no AI generation or background synthesis.
Flutter only scales/positions the existing transparent photograph.
