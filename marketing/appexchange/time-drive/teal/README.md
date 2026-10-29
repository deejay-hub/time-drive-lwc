# Time Drive: AppExchange visuals (Deep Teal (Time Drive))

Built from `scripts/marketing/appexchange.py` to match the Time Warp listing in
Figma (the same 1500 x 1000 slide template, type and layout). Each screenshot
is a **dashed placeholder** named `screen-<n>`: delete it and place a PNG there.

## Files

| File | Size | Use |
|---|---|---|
| 01-visualise.svg | 1500 x 1000 | slide: the timeline, wide |
| 02-interact.svg | 1500 x 1000 | slide: filters/lenses and an expanded item, side by side |
| 03-customise.svg | 1500 x 1000 | slide: guided Setup, words at the right |
| 04-globalise.svg | 1500 x 1000 | slide: English, Spanish, Arabic (right to left) |
| 05-connect.svg | 1500 x 1000 | slide: Data 360 beside CRM (the sibling's CONTRIBUTE slot) |
| hero-1280x720.svg | 1280 x 720 | listing hero |
| banner-1280x640.svg | 1280 x 640 | banner |
| title-tile-448x328.svg | 448 x 328 | the listing card |
| wordmark-566x81.svg, logo-100x100.svg | | logo lockup, and the logo alone |

## Importing into Figma

1. Drag the SVGs onto the canvas (or File > Place image). Each becomes a frame
   with editable text and shapes.
2. Fonts are **Orbitron** (Black 45 for the name, ExtraBold 70 for the verb,
   Bold 75 on INTERACT) and **Lato Regular 40**. Both are Google fonts that
   Figma has; if a style imports as the wrong weight, set it again.
3. The background gradient, shapes and footer are separate layers named
   `background`, `footer` and so on; the text layers are `headline` and
   `wordmark`.

## Screenshots to capture (at 2x; PNG)

| Placeholder | Size | Capture |
|---|---|---|
| screen-1 | 1143 x 465 | A Contact's timeline in the Sales app, horizontal, with the heat map |
| screen-2a | 600 x 453 | Filters panel open, with the lens menu showing |
| screen-2b | 600 x 453 | An item expanded (or View all for a busy day) |
| screen-3 | 826 x 696 | Setup, Words and style step with its live preview |
| screen-4 | 1143 x 462 | An Arabic (right to left) timeline |
| screen-5 | 1143 x 465 | Data 360 engagement beside CRM records, with Files & Notes |
| screen-H | 1113 x 233 | The top of the timeline (hero, cropped by the edge) |
| screen-B | 928 x 378 | A full-width timeline (banner) |
| screen-T | 356 x 108 | A small timeline crop (title tile) |

Use a tidy Contact with believable names (not a test record), in the same
Lightning app on every shot.

## Copy

- **Tagline options:** "Every touchpoint, on one timeline." / "See the whole
  relationship, day by day." / "Salesforce and Data 360 activity, side by side."
- **VISUALISE.** See every touchpoint on one interactive timeline. Plot Salesforce and Data 360 records side by side.
- **INTERACT.** Filter by type, switch lens and jump to Today. / Expand any item, open a busy day or preview a file in one click.
- **CUSTOMISE.** Set up in minutes with guided Setup, then tune each page in App Builder.
- **GLOBALISE.** English, Spanish and Arabic, left to right and right to left.
- **CONNECT.** Bring Data 360 engagement and Files & Notes onto the same timeline as your CRM records.

## To confirm before publishing

- The Spanish and Arabic text is draft; have it reviewed.
- If Time Drive is open source, restore the sibling's CONTRIBUTE slide.
- The theme: `python3 -I scripts/marketing/appexchange.py blue` regenerates this set in the sibling's blue.
