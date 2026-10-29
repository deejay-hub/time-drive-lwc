#!/usr/bin/env python3
"""
Time Drive's AppExchange listing visuals, as SVG with a labelled placeholder
where each screenshot goes, built to match the Time Warp listing in Figma
(the same slide template, type and layout):

    python3 -I scripts/marketing/appexchange.py            # teal (Time Drive)
    python3 -I scripts/marketing/appexchange.py blue       # the sibling's blue

Writes marketing/appexchange/time-drive/<theme>/*.svg, a contact sheet and a
README. Drag the SVGs into Figma; swap each placeholder for a screenshot.
"""
import html
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "marketing", "appexchange", "time-drive")

THEMES = {
    "teal": dict(
        label="Deep Teal (Time Drive)",
        grad=("#CDE7DF", "#E3F1EC"), solid="#E6F3EE", shape="#0F6B58", shape_op=0.16,
        footer="#0B4D43", ink="#12201C", bezel="#F7FAF8", shadow="#0B4D43",
        ph_fill="#FFFFFF", ph_line="#0F6B58", ph_text="#0B4D43", cloud="#FFFFFF", bush=("#2F7D4F", "#1B4D2E"),
    ),
    "blue": dict(
        label="Blue (as Time Warp)",
        grad=("#B7E0FE", "#CEE9FF"), solid="#EAF4FF", shape="#66CDFF", shape_op=0.20,
        footer="#002775", ink="#000000", bezel="#F3F6FB", shadow="#1F3F73",
        ph_fill="#FFFFFF", ph_line="#2A5DB0", ph_text="#002775", cloud="#FFFFFF", bush=("#3C8F4E", "#256B3A"),
    ),
}

# The product's own logo (lwc/timeDrive/timeDrive.svg), at 100 x 100.
LOGO_BODY = """<rect width="100" height="100" rx="18" fill="#0B4D43"/>
<rect x="16" y="16" width="68" height="68" rx="8" fill="#FFFFFF"/>
<rect x="31" y="30" width="4" height="42" rx="2" fill="#0F6B58" fill-opacity="0.45"/>
<circle cx="33" cy="30" r="6" fill="#2F7D4F"/><circle cx="33" cy="50" r="6" fill="#E5532F"/><circle cx="33" cy="70" r="6" fill="#5B5FC7"/>
<rect x="45" y="27" width="26" height="5" rx="2.5" fill="#2A1A12"/><rect x="45" y="47" width="20" height="5" rx="2.5" fill="#2A1A12"/>
<rect x="45" y="67" width="23" height="5" rx="2.5" fill="#2A1A12" fill-opacity="0.35"/>"""

ORB = "Orbitron, 'Arial Black', sans-serif"
LATO = "Lato, 'Helvetica Neue', Arial, sans-serif"


def esc(s):
    return html.escape(s, quote=False)


class Canvas:
    def __init__(self, name, w, h, t, background="gradient"):
        self.name, self.w, self.h, self.t = name, w, h, t
        self.defs, self.body = [], []
        self.n = 0
        fill = "url(#bg)" if background == "gradient" else t["solid"]
        if background == "gradient":
            self.defs.append(
                f'<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{t["grad"][0]}"/>'
                f'<stop offset="1" stop-color="{t["grad"][1]}"/></linearGradient>'
            )
        self.add(f'<rect id="background" width="{w}" height="{h}" fill="{fill}"/>')

    def add(self, s):
        self.body.append(s)

    def text(self, x, y, s, size, family, weight=400, fill=None, anchor="middle", ident=None):
        fill = fill or self.t["ink"]
        i = f' id="{ident}"' if ident else ""
        self.add(
            f'<text{i} x="{x}" y="{y}" font-family="{family}" font-size="{size}" font-weight="{weight}" '
            f'text-anchor="{anchor}" fill="{fill}">{esc(s)}</text>'
        )

    def diamond(self, cx, cy, size, rx=None):
        rx = rx if rx is not None else size * 0.22
        t = self.t
        self.add(
            f'<rect x="{cx - size / 2}" y="{cy - size / 2}" width="{size}" height="{size}" rx="{rx}" '
            f'transform="rotate(45 {cx} {cy})" fill="{t["shape"]}" fill-opacity="{t["shape_op"]}"/>'
        )

    def sparkle(self, x, y, r, op=0.95):
        self.add(
            f'<path d="M{x} {y - r}Q{x} {y} {x + r} {y}Q{x} {y} {x} {y + r}Q{x} {y} {x - r} {y}Q{x} {y} {x} {y - r}Z" '
            f'fill="#FFFFFF" fill-opacity="{op}"/>'
        )

    def dot(self, x, y, r, op=0.8):
        self.add(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#FFFFFF" fill-opacity="{op}"/>')

    def logo(self, x, y, size):
        self.add(f'<g id="logo" transform="translate({x} {y}) scale({size / 100})">{LOGO_BODY}</g>')

    def wordmark(self, x, y, size, weight=900, name="TIME DRIVE", anchor="start"):
        self.text(x, y, name, size, ORB, weight, anchor=anchor, ident="wordmark")

    def lockup(self, x, y, size=80, font=45):
        """Logo and wordmark, as in the sibling: icon, a gap, then the name."""
        self.logo(x, y, size)
        self.wordmark(x + size + 20, y + size * 0.74, font)

    def device(self, x, y, w, h, radius=78, inset=36):
        """A tablet's front: soft shadow, bezel, then the screen's placeholder."""
        t = self.t
        for i, (grow, op) in enumerate([(26, 0.05), (16, 0.07), (8, 0.09)]):
            self.add(
                f'<rect x="{x - grow}" y="{y - grow + 14}" width="{w + 2 * grow}" height="{h}" rx="{radius + grow}" '
                f'fill="{t["shadow"]}" fill-opacity="{op}"/>'
            )
        self.add(f'<rect id="device" x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{t["bezel"]}"/>')

    def placeholder(self, key, x, y, w, h, title, note, radius=44, size=None):
        """The screen to replace: a dashed white panel saying what goes there."""
        t = self.t
        size = size or f"{int(w)} x {int(h)}"
        cx, cy = x + w / 2, min(y + h / 2, self.h - 160) if y + h > self.h else y + h / 2
        small = 20 if w < 600 else 26
        self.add(
            f'<g id="screen-{key}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{t["ph_fill"]}" '
            f'stroke="{t["ph_line"]}" stroke-width="{3 if w >= 400 else 2}" stroke-dasharray="{"14 10" if w >= 400 else "8 6"}"/>'
        )
        if w < 400:
            # The title tile's: room for a line and its size, no more.
            self.text(cx, y + 38, f"SCREEN {key}", 18, ORB, 800, t["ph_text"])
            self.text(cx, y + 62, f"{title} \u00b7 {size} px", 14, LATO, 700, t["ph_text"])
            self.add("</g>")
            return
        self.text(cx, cy - 18, f"SCREEN {key}", 34 if w >= 600 else 26, ORB, 800, t["ph_text"])
        self.text(cx, cy + 22, title, small + 4, LATO, 700, t["ph_text"])
        self.text(cx, cy + 22 + small + 10, note, small, LATO, 400, t["ph_text"])
        self.text(cx, cy + 22 + 2 * (small + 10), size + " px (capture at 2x)", small - 4, LATO, 400, t["ph_text"])
        self.add("</g>")

    def footer(self, h=50):
        self.add(f'<rect id="footer" y="{self.h - h}" width="{self.w}" height="{h}" fill="{self.t["footer"]}"/>')

    def clouds(self, spots):
        for x, y, s in spots:
            for dx, dy, r in [(0, 0, 60), (55, -20, 75), (120, 0, 60), (60, 30, 70), (-10, 35, 45), (130, 40, 48)]:
                self.add(
                    f'<circle cx="{x + dx * s}" cy="{y + dy * s}" r="{r * s}" fill="{self.t["cloud"]}" fill-opacity="0.55"/>'
                )

    def bushes(self, spots):
        a, b = self.t["bush"]
        for x, y, s in spots:
            for dx, dy, r, c in [(0, 0, 46, a), (50, 10, 56, b), (105, 0, 44, a), (52, -34, 40, a)]:
                self.add(f'<circle cx="{x + dx * s}" cy="{y + dy * s}" r="{r * s}" fill="{c}"/>')

    def svg(self):
        return (
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" viewBox="0 0 {self.w} {self.h}">\n'
            f'<title>Time Drive: {esc(self.name)}</title>\n<defs>{"".join(self.defs)}'
            f'<clipPath id="canvas"><rect width="{self.w}" height="{self.h}"/></clipPath></defs>\n'
            f'<g clip-path="url(#canvas)">\n' + "\n".join(self.body) + "\n</g>\n</svg>\n"
        )


def stage(c, spots=None):
    """The slide's background shapes and sparkles (as in the sibling slides)."""
    for cx, cy, s in spots or [(310, 330, 255), (96, 350, 130), (1600, 130, 255)]:
        c.diamond(cx, cy, s)


def headline(c, text, y=267, x=750, size=70, weight=800):
    c.text(x, y, text, size, ORB, weight, ident="headline")


def slide(t, key, verb, lines, device="wide", screens=None, size=70, weight=800):
    c = Canvas(f"{key}: {verb}", 1500, 1000, t)
    stage(c)
    c.lockup(114, 92)
    return c


def build(theme):
    t = THEMES[theme]
    files = {}

    # ---- 01 VISUALISE (the full-width timeline) -----------------------------------------------------
    c = Canvas("VISUALISE", 1500, 1000, t)
    stage(c)
    for x, y, r in [(1352, 460, 28), (1395, 408, 14), (96, 828, 20), (130, 760, 12)]:
        c.sparkle(x, y, r)
    c.dot(1332, 438, 5); c.dot(1392, 444, 4)
    c.lockup(114, 92)
    headline(c, "VISUALISE.")
    c.text(750, 349, "See every touchpoint on one interactive timeline.", 40, LATO)
    c.text(750, 397, "Plot Salesforce and Data 360 records side by side.", 40, LATO)
    c.device(143, 452, 1215, 925, 90)
    c.placeholder("1", 179, 485, 1143, 465, "A Contact's timeline, wide", "Horizontal layout with the heat map", radius=48)
    c.footer()
    files["01-visualise"] = c

    # ---- 02 INTERACT (two devices, a line each) -----------------------------------------------------
    c = Canvas("INTERACT", 1500, 1000, t)
    stage(c, [(1430, 190, 255), (60, 290, 130), (1360, 330, 130)])
    for x, y, r in [(718, 380, 14), (782, 440, 26), (748, 500, 22)]:
        c.sparkle(x, y, r)
    c.lockup(114, 92)
    headline(c, "INTERACT.", size=75, weight=700)
    c.text(354, 368, "Filter by type, switch lens", 40, LATO); c.text(354, 418, "and jump to Today.", 40, LATO)
    c.text(1156, 368, "Expand any item, open a busy day", 40, LATO); c.text(1156, 418, "or preview a file in one click.", 40, LATO)
    c.device(30, 470, 650, 700, 56, 25); c.device(820, 470, 650, 700, 56, 25)
    c.placeholder("2a", 55, 497, 600, 453, "Filters and lenses", "The filter panel open, lens menu showing", radius=34)
    c.placeholder("2b", 845, 497, 600, 453, "An item, expanded", "Details open (or View all for a busy day)", radius=34)
    c.footer()
    files["02-interact"] = c

    # ---- 03 CUSTOMISE (screen at the left, words at the right) ----------------------------------------
    c = Canvas("CUSTOMISE", 1500, 1000, t)
    stage(c, [(1330, 130, 255), (1470, 170, 255), (1260, 880, 160), (1380, 905, 120)])
    for x, y, r in [(1322, 160, 14), (1378, 222, 28), (860, 580, 14), (880, 640, 26), (820, 700, 12)]:
        c.sparkle(x, y, r)
    c.lockup(114, 92)
    c.device(-110, 222, 890, 1000, 76, 32)
    c.placeholder("3", -78, 254, 826, 696, "Guided Setup", "The Words and style step with its live preview", radius=40)
    headline(c, "CUSTOMISE.", y=420, x=1116, size=70)
    for i, line in enumerate(["Set up in minutes with", "guided Setup, then tune", "each page in App Builder."]):
        c.text(1116, 500 + 48 * i, line, 40, LATO)
    c.footer()
    files["03-customise"] = c

    # ---- 04 GLOBALISE ------------------------------------------------------------------------------
    c = Canvas("GLOBALISE", 1500, 1000, t)
    stage(c, [(1400, 210, 255), (1350, 330, 140), (120, 560, 255)])
    for x, y, r in [(118, 168, 26), (166, 226, 14), (1360, 376, 26), (1395, 420, 14), (1480, 500, 12)]:
        c.sparkle(x, y, r)
    c.lockup(114, 92)
    headline(c, "GLOBALISE.", y=270, size=70)
    c.text(750, 345, "English, Spanish and Arabic, left to right and right to left.", 40, LATO)
    for x, word in [(400, "Hola"), (750, "مرحبًا"), (1100, "Hello")]:
        c.text(x, 414, word, 40, LATO, 400)
    c.device(143, 455, 1215, 925, 90)
    c.placeholder("4", 179, 488, 1143, 462, "An Arabic timeline", "Right to left, on a Contact page", radius=48)
    c.footer()
    files["04-globalise"] = c

    # ---- 05 CONNECT (the sibling's CONTRIBUTE slot; swap if Time Drive is open source) ---------------
    c = Canvas("CONNECT", 1500, 1000, t)
    stage(c)
    for x, y, r in [(1350, 470, 26), (1395, 420, 14), (100, 830, 20)]:
        c.sparkle(x, y, r)
    c.lockup(114, 92)
    headline(c, "CONNECT.")
    c.text(750, 349, "Bring Data 360 engagement and Files & Notes", 40, LATO)
    c.text(750, 397, "onto the same timeline as your CRM records.", 40, LATO)
    c.device(143, 452, 1215, 925, 90)
    c.placeholder("5", 179, 485, 1143, 465, "Data 360 engagement beside CRM", "Emails opened, web visits, files, tasks", radius=48)
    c.footer()
    files["05-connect"] = c

    # ---- the hero (1280 x 720): the sibling's with clouds ---------------------------------------------
    c = Canvas("hero", 1280, 720, t, background="solid")
    c.clouds([(30, 330, 1.2), (1100, 40, 1.4), (-40, 120, 0.8)])
    c.lockup(445, 90, 80, 45)
    c.text(640, 237, "See every touchpoint on one interactive timeline.", 38, LATO)
    c.text(640, 283, "Plot Salesforce and Data 360 records side by side.", 38, LATO)
    c.device(133, 455, 1300, 700, 80)
    c.placeholder("H", 167, 487, 1113, 233, "A Contact's timeline", "Top of the timeline, cropped by the edge", radius=44)
    files["hero-1280x720"] = c

    # ---- the banner (1280 x 640) ----------------------------------------------------------------------
    c = Canvas("banner", 1280, 640, t, background="solid")
    c.clouds([(30, 250, 0.9), (1080, 30, 1.3), (-20, 90, 0.7)])
    c.lockup(452, 52, 80, 45)
    c.text(640, 196, "View every touchpoint on one beautiful, interactive timeline", 36, LATO)
    c.device(140, 232, 1000, 700, 72)
    c.placeholder("B", 176, 262, 928, 378, "A Contact's timeline, full width", "With the heat map along the bottom", radius=40)
    c.bushes([(70, 628, 0.9), (1080, 612, 1.1)])
    files["banner-1280x640"] = c

    # ---- the title tile (448 x 328) -------------------------------------------------------------------
    c = Canvas("title tile", 448, 328, t)
    c.diamond(60, 240, 120); c.diamond(430, 40, 120)
    c.sparkle(356, 48, 12); c.sparkle(384, 78, 8)
    c.logo(30, 28, 64)
    c.wordmark(108, 76, 33)
    c.text(32, 140, "View every touchpoint on one,", 24, LATO, 700, anchor="start")
    c.text(32, 172, "beautiful, interactive timeline.", 24, LATO, 700, anchor="start")
    c.device(32, 198, 384, 400, 34, 14)
    c.placeholder("T", 46, 212, 356, 108, "A timeline crop", "", radius=22, size="356 x 108")
    c.footer(8)
    files["title-tile-448x328"] = c

    # ---- the logo and the wordmark on their own ---------------------------------------------------------
    c = Canvas("wordmark", 566, 81, t, background="none")
    c.body.clear()
    c.logo(0, 0, 81)
    c.wordmark(101, 60, 45)
    files["wordmark-566x81"] = c
    lg = Canvas("logo", 100, 100, t, background="none")
    lg.body.clear()
    lg.add(LOGO_BODY)
    files["logo-100x100"] = lg
    return files


READ = """# Time Drive: AppExchange visuals ({label})

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
"""


def main():
    themes = sys.argv[1:] or ["teal", "blue"]
    for theme in themes:
        folder = os.path.join(OUT, theme)
        os.makedirs(folder, exist_ok=True)
        files = build(theme)
        for name, canvas in files.items():
            with open(os.path.join(folder, name + ".svg"), "w", encoding="utf-8") as f:
                f.write(canvas.svg())
        with open(os.path.join(folder, "README.md"), "w", encoding="utf-8") as f:
            f.write(READ.format(label=THEMES[theme]["label"]))
        sheet = ["<!doctype html><meta charset='utf-8'><title>Time Drive: AppExchange visuals ({})</title>".format(theme),
                 "<link href='https://fonts.googleapis.com/css2?family=Lato:wght@400;700&family=Orbitron:wght@700;800;900&display=swap' rel='stylesheet'>",
                 "<style>body{margin:0;padding:24px;background:#e8e6df;font-family:Lato,system-ui,sans-serif;color:#17201d}h1{margin:0 0 4px}"
                 "p{margin:0 0 20px;color:#47524d}figure{margin:0 0 28px}figcaption{font-weight:700;margin:0 0 6px}"
                 ".row{display:flex;flex-wrap:wrap;gap:24px;align-items:flex-start}svg{max-width:100%;height:auto;box-shadow:0 1px 4px rgba(0,0,0,.2)}"
                 "figure svg{width:560px}figure.small svg{width:448px}</style>",
                 f"<h1>Time Drive: AppExchange visuals, {THEMES[theme]['label']}</h1><p>Placeholders are dashed. Needs a network connection for Orbitron and Lato.</p><div class='row'>"]
        for name, canvas in files.items():
            if name.startswith(("logo", "wordmark")):
                continue
            cls = "small" if "tile" in name else ""
            sheet.append(f"<figure class='{cls}'><figcaption>{name} ({canvas.w} x {canvas.h})</figcaption>{canvas.svg().split('?>')[-1]}</figure>")
        sheet.append("</div>")
        with open(os.path.join(folder, "contact-sheet.html"), "w", encoding="utf-8") as f:
            f.write("\n".join(sheet))
        print(f"{theme}: {len(files)} SVGs in {os.path.relpath(folder, ROOT)}")


if __name__ == "__main__":
    main()
