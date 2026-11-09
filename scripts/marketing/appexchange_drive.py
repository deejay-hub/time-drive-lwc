#!/usr/bin/env python3
"""
Time Drive's AppExchange visuals, in a style of its own (not the Time Warp
template): ten story slides built around what Time Drive is best at, plus the
hero, banner and title tile. Screens are labelled placeholders.

    python3 -I scripts/marketing/appexchange_drive.py          # night + mint
    python3 -I scripts/marketing/appexchange_drive.py night

Writes marketing/appexchange/time-drive-fresh/<theme>/.
"""
import html
import math
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "marketing", "appexchange", "time-drive-fresh")

THEMES = {
    "night": dict(
        label="Night (deep teal stage)",
        bg=("#0B4D43", "#062A25"), glow="#2FB89A", glow_op=0.28,
        head="#FFFFFF", sub="#BFE3D8", accent="#7FE0C2", chip_fill="#FFFFFF", chip_op=0.09, chip_line="#7FE0C2",
        chip_text="#E8FFF8", band="#052520", band_text="#E8FFF8",
        heat=["#0F3F37", "#165B4E", "#1F8A74", "#3FB89C", "#8FE6CB"],
        bezel="#071E1B", bezel_line="#2A6B5E", shadow="#000000", shadow_op=0.28,
        ph_fill="#0C3A33", ph_line="#7FE0C2", ph_text="#CFF5E8",
        nodes=("#3FB27F", "#FF7A50", "#8D90F2"),
    ),
    "mint": dict(
        label="Mint (light stage)",
        bg=("#F4FAF7", "#DDEFE8"), glow="#7FC2AC", glow_op=0.35,
        head="#0B2B26", sub="#44564F", accent="#0F6B58", chip_fill="#FFFFFF", chip_op=1.0, chip_line="#9CCBBD",
        chip_text="#0B4D43", band="#FFFFFF", band_text="#0B4D43",
        heat=["#E3F1EC", "#BFE0D4", "#7FC2AC", "#2E9E84", "#0F6B58"],
        bezel="#FFFFFF", bezel_line="#C5DDD4", shadow="#0B4D43", shadow_op=0.16,
        ph_fill="#FFFFFF", ph_line="#0F6B58", ph_text="#0B4D43",
        nodes=("#2F7D4F", "#E5532F", "#5B5FC7"),
    ),
}

LOGO_BODY = """<rect width="100" height="100" rx="18" fill="#0B4D43"/>
<rect x="16" y="16" width="68" height="68" rx="8" fill="#FFFFFF"/>
<rect x="31" y="30" width="4" height="42" rx="2" fill="#0F6B58" fill-opacity="0.45"/>
<circle cx="33" cy="30" r="6" fill="#2F7D4F"/><circle cx="33" cy="50" r="6" fill="#E5532F"/><circle cx="33" cy="70" r="6" fill="#5B5FC7"/>
<rect x="45" y="27" width="26" height="5" rx="2.5" fill="#2A1A12"/><rect x="45" y="47" width="20" height="5" rx="2.5" fill="#2A1A12"/>
<rect x="45" y="67" width="23" height="5" rx="2.5" fill="#2A1A12" fill-opacity="0.35"/>"""

SORA = "Sora, 'Helvetica Neue', Arial, sans-serif"
LATO = "Lato, 'Helvetica Neue', Arial, sans-serif"
TOTAL = 10


def esc(s):
    return html.escape(s, quote=False)


class Art:
    def __init__(self, name, w, h, t, glow=True):
        self.name, self.w, self.h, self.t = name, w, h, t
        self.defs, self.body = [], []
        self.defs.append(
            f'<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{t["bg"][0]}"/>'
            f'<stop offset="1" stop-color="{t["bg"][1]}"/></linearGradient>'
            f'<radialGradient id="glow"><stop offset="0" stop-color="{t["glow"]}" stop-opacity="{t["glow_op"]}"/>'
            f'<stop offset="1" stop-color="{t["glow"]}" stop-opacity="0"/></radialGradient>'
        )
        self.add(f'<rect id="background" width="{w}" height="{h}" fill="url(#bg)"/>')
        if glow:
            self.add(f'<circle id="glow" cx="{w * 0.78}" cy="{h * 0.3}" r="{h * 0.62}" fill="url(#glow)"/>')

    def add(self, s):
        self.body.append(s)

    def text(self, x, y, s, size, family=SORA, weight=400, fill=None, anchor="start", spacing=0, ident=None, op=None):
        fill = fill or self.t["head"]
        i = f' id="{ident}"' if ident else ""
        ls = f' letter-spacing="{spacing}"' if spacing else ""
        o = f' fill-opacity="{op}"' if op is not None else ""
        self.add(
            f'<text{i} x="{x}" y="{y}" font-family="{family}" font-size="{size}" font-weight="{weight}" '
            f'text-anchor="{anchor}"{ls} fill="{fill}"{o}>{esc(s)}</text>'
        )

    def lines(self, x, y, lines, size, lh, family=LATO, weight=400, fill=None, anchor="start", ident=None):
        for k, line in enumerate(lines):
            self.text(x, y + k * lh, line, size, family, weight, fill, anchor, ident=ident if k == 0 else None)

    def logo(self, x, y, size, ident="logo"):
        self.add(f'<g id="{ident}" transform="translate({x} {y}) scale({size / 100})">{LOGO_BODY}</g>')

    def lockup(self, x, y, size=44, font=26):
        self.logo(x, y, size)
        self.text(x + size + 14, y + size * 0.72, "Time Drive", font, SORA, 800, anchor="start", ident="wordmark")

    def pill(self, x, y, label, size=18, pad=18, h=40, strong=False, anchor="start", weight=700, spacing=0):
        t = self.t
        w = int(len(label) * size * 0.62 + 2 * pad)
        if anchor == "middle":
            x -= w / 2
        fill = t["accent"] if strong else t["chip_fill"]
        op = 1 if strong else t["chip_op"]
        line = t["accent"] if strong else t["chip_line"]
        ink = (t["bg"][1] if t["bg"][1].startswith("#0") else "#FFFFFF") if strong else t["chip_text"]
        if strong and t["accent"] == "#0F6B58":
            ink = "#FFFFFF"
        self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{h / 2}" fill="{fill}" fill-opacity="{op}" stroke="{line}" stroke-opacity="0.6"/>')
        self.text(x + w / 2, y + h / 2 + size * 0.35, label, size, SORA, weight, ink, "middle", spacing)
        return w

    def pills(self, x, y, labels, size=21, pad=24, h=46, gap=12, strong=None, max_x=None):
        """Chips end to end, each starting where the last one ended; wraps at max_x."""
        x0 = x
        for label in labels:
            w = int(len(label) * size * 0.62 + 2 * pad)
            if max_x and x + w > max_x:
                x, y = x0, y + h + gap
            self.pill(x, y, label, size, pad, h, strong=(label == strong))
            x += w + gap
        return x

    def eyebrow(self, x, y, label):
        t = self.t
        self.add(f'<circle cx="{x + 8}" cy="{y + 20}" r="6" fill="{t["accent"]}"/>')
        self.text(x + 26, y + 27, label, 20, SORA, 800, t["accent"], spacing=3, ident="kicker")

    def heat(self, x, y, cols, rows, cell=26, gap=7, seed=3, fade=None, peaks=()):
        """A heat map: a grid of days in five shades, a few busy spells."""
        pal = self.t["heat"]
        for c in range(cols):
            for r in range(rows):
                v = (math.sin(c * 0.55 + seed) + math.sin(r * 1.7 + c * 0.21 + seed * 2) + math.cos(c * 0.13 * (r + 1))) / 3
                v = (v + 1) / 2
                for pc, pr, boost in peaks:
                    v += boost * math.exp(-(((c - pc) ** 2) / 6 + ((r - pr) ** 2) / 3))
                shade = pal[min(4, max(0, int(v * 4.2)))]
                op = 1.0 if fade is None else max(0.08, fade(c, r, cols, rows))
                self.add(
                    f'<rect x="{x + c * (cell + gap)}" y="{y + r * (cell + gap)}" width="{cell}" height="{cell}" '
                    f'rx="{cell * 0.28}" fill="{shade}" fill-opacity="{op:.2f}"/>'
                )

    def rail(self, x, y1, y2, horizontal=False, with_nodes=True):
        """The logo's rail: a line with three nodes in the logo's colours."""
        t = self.t
        n = t["nodes"]
        if horizontal:
            self.add(f'<line x1="{y1}" y1="{x}" x2="{y2}" y2="{x}" stroke="{t["accent"]}" stroke-opacity="0.45" stroke-width="4" stroke-linecap="round"/>')
            if with_nodes:
                for k, c in enumerate(n):
                    self.add(f'<circle cx="{y1 + (y2 - y1) * (0.18 + 0.32 * k)}" cy="{x}" r="11" fill="{c}"/>')
        else:
            self.add(f'<line x1="{x}" y1="{y1}" x2="{x}" y2="{y2}" stroke="{t["accent"]}" stroke-opacity="0.45" stroke-width="4" stroke-linecap="round"/>')
            if with_nodes:
                for k, c in enumerate(n):
                    self.add(f'<circle cx="{x}" cy="{y1 + (y2 - y1) * (0.18 + 0.32 * k)}" r="11" fill="{c}"/>')

    def shadowed(self, x, y, w, h, r):
        t = self.t
        for grow, k in [(30, 0.35), (18, 0.55), (8, 0.8)]:
            self.add(
                f'<rect x="{x - grow}" y="{y - grow + 22}" width="{w + 2 * grow}" height="{h + 2 * grow}" rx="{r + grow}" '
                f'fill="{t["shadow"]}" fill-opacity="{t["shadow_op"] * k * 0.5:.3f}"/>'
            )

    def placeholder(self, key, x, y, w, h, title, note, radius=22):
        t = self.t
        size = f"{int(w)} x {int(h)}"
        visible_bottom = self.h - (70 if self.h >= 1000 else 0)
        cy = y + min(h, visible_bottom - y) / 2
        cx = x + w / 2
        self.add(
            f'<g id="screen-{key}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{t["ph_fill"]}" '
            f'stroke="{t["ph_line"]}" stroke-width="2.5" stroke-dasharray="12 9"/>'
        )
        big = 30 if w >= 560 else 22 if w >= 300 else 16
        small = 21 if w >= 560 else 17 if w >= 300 else 14
        self.text(cx, cy - big * 0.4, f"SCREEN {key}", big, SORA, 800, t["ph_text"], "middle", 1)
        self.text(cx, cy + small * 1.4, title, small + 3, LATO, 700, t["ph_text"], "middle")
        if note and h > 160:
            self.text(cx, cy + small * 2.9, note, small, LATO, 400, t["ph_text"], "middle")
        if h > 190:
            self.text(cx, cy + small * 4.4, size + " px (capture at 2x)", small - 3, LATO, 400, t["ph_text"], "middle", op=0.8)
        self.add("</g>")

    def tablet(self, x, y, w, h, key, title, note, inset=14):
        t = self.t
        self.shadowed(x, y, w, h, 38)
        self.add(f'<rect id="tablet-{key}" x="{x}" y="{y}" width="{w}" height="{h}" rx="38" fill="{t["bezel"]}" stroke="{t["bezel_line"]}" stroke-width="2"/>')
        self.placeholder(key, x + inset, y + inset, w - 2 * inset, h - 2 * inset, title, note, 26)

    def phone(self, x, y, w, h, key, title, note, inset=12):
        t = self.t
        self.shadowed(x, y, w, h, 54)
        self.add(f'<rect id="phone-{key}" x="{x}" y="{y}" width="{w}" height="{h}" rx="54" fill="{t["bezel"]}" stroke="{t["bezel_line"]}" stroke-width="2"/>')
        self.placeholder(key, x + inset, y + inset, w - 2 * inset, h - 2 * inset, title, note, 42)
        self.add(f'<rect x="{x + w / 2 - 44}" y="{y + inset + 12}" width="88" height="22" rx="11" fill="{t["bezel"]}"/>')

    def footer(self, n):
        t = self.t
        self.add(f'<rect id="footer" y="{self.h - 70}" width="{self.w}" height="70" fill="{t["band"]}" fill-opacity="0.94"/>')
        self.logo(96, self.h - 56, 40, "footer-logo")
        self.text(150, self.h - 28, "Time Drive", 24, SORA, 800, t["band_text"])
        self.text(self.w - 96, self.h - 28, f"{n} / {TOTAL}", 22, LATO, 700, t["band_text"], "end", op=0.8)

    def svg(self):
        return (
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" viewBox="0 0 {self.w} {self.h}">\n'
            f'<title>Time Drive: {esc(self.name)}</title>\n<defs>{"".join(self.defs)}'
            f'<clipPath id="canvas"><rect width="{self.w}" height="{self.h}"/></clipPath></defs>\n'
            f'<g clip-path="url(#canvas)">\n' + "\n".join(self.body) + "\n</g>\n</svg>\n"
        )


def headline(a, x, y, lines, size=76, lh=86, anchor="start"):
    for k, line in enumerate(lines):
        a.text(x, y + k * lh, line, size, SORA, 800, a.t["head"], anchor, ident="headline" if k == 0 else None)
    return y + (len(lines) - 1) * lh


def sub(a, x, y, lines, size=30, lh=42, anchor="start"):
    a.lines(x, y, lines, size, lh, LATO, 400, a.t["sub"], anchor, ident="subtext")


def slide(t, n, name, kicker):
    a = Art(name, 1500, 1000, t)
    a.eyebrow(96, 120, kicker)
    return a


def build(theme):
    t = THEMES[theme]
    f = {}

    # 01 HERO ---------------------------------------------------------------------------------------
    a = Art("Every touchpoint, one timeline", 1500, 1000, t)
    a.lockup(96, 70)
    a.eyebrow(96, 190, "FOR SALESFORCE")
    headline(a, 96, 300, ["Every touchpoint.", "One timeline."], 92, 100)
    sub(a, 96, 520, ["A 360-degree view of a Contact, Account or Person Account:", "CRM records and Data 360 engagement, at a glance."], 30, 44)
    a.heat(1000, 90, 16, 6, 26, 7, seed=5, fade=lambda c, r, C, R: 0.15 + 0.5 * (c / C), peaks=((11, 2, 0.5),))
    a.tablet(560, 600, 880, 480, "1", "A Contact's timeline", "Horizontal, with the heat map")
    a.phone(1180, 450, 250, 540, "1b", "On mobile", "")
    a.footer(1)
    f["01-hero"] = a

    # 02 TWO WAYS -----------------------------------------------------------------------------------
    a = slide(t, 2, "Horizontal and vertical", "HORIZONTAL OR VERTICAL")
    headline(a, 96, 250, ["Two ways", "to see time."])
    sub(a, 96, 440, ["Run it across a wide region or", "down a narrow one. Auto picks the", "layout that fits; set it per page."])
    a.pills(96, 600, ["Horizontal", "Vertical", "Auto"], 20, 22, 44, strong="Auto")
    a.rail(668, 110, 880)
    a.tablet(760, 150, 680, 420, "2a", "Horizontal", "Days across, heat map beneath")
    a.tablet(980, 470, 460, 560, "2b", "Vertical", "Days down, in a narrow column")
    a.footer(2)
    f["02-two-ways"] = a

    # 03 HEAT MAP -----------------------------------------------------------------------------------
    a = slide(t, 3, "The heat map", "THE HEAT MAP")
    headline(a, 96, 250, ["See where", "it's busy."])
    sub(a, 96, 440, ["A heat map of the whole history sits", "under the timeline. Spot clusters and", "quiet spells, then jump to any day."])
    a.heat(700, 100, 21, 7, 30, 8, seed=2, fade=lambda c, r, C, R: 0.35 + 0.65 * (1 - abs(c - C / 2) / (C / 2)), peaks=((9, 3, 0.7), (16, 1, 0.5)))
    a.text(700, 410, "Quiet", 20, LATO, 700, t["sub"]); a.text(1404, 410, "Busy", 20, LATO, 700, t["sub"], "end")
    for k, c in enumerate(t["heat"]):
        a.add(f'<rect x="{960 + k * 38}" y="392" width="30" height="20" rx="6" fill="{c}"/>')
    a.tablet(740, 480, 700, 540, "3", "The timeline and its heat map", "A wide crop of the heat map")
    a.footer(3)
    f["03-heat-map"] = a

    # 04 MOBILE -------------------------------------------------------------------------------------
    a = Art("Mobile", 1500, 1000, t)
    a.eyebrow(940, 120, "ON MOBILE")
    a.phone(130, 140, 330, 700, "4a", "A timeline on a phone", "Vertical list")
    a.phone(520, 230, 330, 700, "4b", "An item, expanded", "Details and the menu")
    a.rail(76, 120, 880)
    headline(a, 940, 250, ["In your", "pocket."])
    sub(a, 940, 440, ["Built for the Salesforce mobile", "app: a one-line header, a menu", "for the rest, and a layout made", "for a phone."], 28, 40)
    a.pills(940, 640, ["Small screens", "Same setup"], 20, 22, 44, strong="Same setup", max_x=1440)
    a.footer(4)
    f["04-mobile"] = a

    # 05 SETUP --------------------------------------------------------------------------------------
    a = slide(t, 5, "Setup", "SET UP IN MINUTES")
    headline(a, 96, 250, ["Guided setup.", "No code."])
    sub(a, 96, 440, ["Choose an object, how it links,", "a date and a look, with a live", "preview of each item as you go."])
    steps = ["Source", "Records", "Date", "Name", "Words and style", "Interactions"]
    sx, sy = 96, 590
    for k, s in enumerate(steps):
        a.add(f'<circle cx="{sx + 20}" cy="{sy + k * 56 + 18}" r="16" fill="{t["accent"]}" fill-opacity="{0.25 + 0.15 * min(k, 3)}" stroke="{t["accent"]}"/>')
        a.text(sx + 20, sy + k * 56 + 24, str(k + 1), 17, SORA, 800, t["chip_text"], "middle")
        a.text(sx + 52, sy + k * 56 + 25, s, 24, SORA, 700, t["head"])
    a.tablet(780, 190, 660, 650, "5", "Setup, with its live preview", "Words and style: icon, title, subtitle")
    a.footer(5)
    f["05-setup"] = a

    # 06 DATA 360 -----------------------------------------------------------------------------------
    a = slide(t, 6, "Data 360", "DATA 360")
    a.tablet(60, 400, 820, 560, "6", "CRM and Data 360, one timeline", "Emails, visits and tasks together")
    headline(a, 940, 250, ["Salesforce", "and Data 360,", "side by side."], 62, 74)
    sub(a, 940, 500, ["Add engagement from the unified", "profile to the same timeline as", "your CRM records."], 28, 40)
    # two lanes feeding one rail
    a.pill(96, 200, "Salesforce CRM", 20, 22, 46); a.pill(96, 270, "Data 360", 20, 22, 46, strong=True)
    for yy in (223, 293):
        a.add(f'<path d="M 330 {yy} C 450 {yy}, 450 258, 560 258" fill="none" stroke="{t["accent"]}" stroke-opacity="0.6" stroke-width="3" stroke-dasharray="3 9" stroke-linecap="round"/>')
    a.add(f'<line x1="560" y1="258" x2="860" y2="258" stroke="{t["accent"]}" stroke-opacity="0.5" stroke-width="4" stroke-linecap="round"/>')
    for k, c in enumerate(t["nodes"]):
        a.add(f'<circle cx="{620 + 90 * k}" cy="258" r="12" fill="{c}"/>')
    a.footer(6)
    f["06-data-360"] = a

    # 07 LENSES -------------------------------------------------------------------------------------
    a = slide(t, 7, "Lenses", "LENSES")
    headline(a, 96, 250, ["Your lens on", "the relationship."], 58, 70)
    sub(a, 96, 400, ["Switch between Sales, Service,", "Marketing and more. Admins choose", "what belongs in each lens."], 28, 40)
    a.pills(96, 560, ["All", "Sales", "Service", "Marketing", "Commerce", "Digital"], 22, 24, 48, strong="Service", max_x=700)
    a.tablet(780, 190, 660, 700, "7", "The lens menu, open", "The timeline filtered to one lens")
    a.footer(7)
    f["07-lenses"] = a

    # 08 ACT ----------------------------------------------------------------------------------------
    a = slide(t, 8, "Interact", "INTERACT")
    a.tablet(60, 300, 800, 580, "8", "An item, expanded", "Its details, with the item menu open")
    a.phone(720, 420, 200, 460, "8b", "Menu", "")
    headline(a, 1000, 250, ["Open, edit,", "act."], 76, 86)
    sub(a, 1000, 440, ["Expand any item, edit or delete", "where you're allowed, preview a", "file in a click, or start a task", "and log a call."], 28, 40)
    a.footer(8)
    f["08-interact"] = a

    # 09 GLOBAL -------------------------------------------------------------------------------------
    a = Art("Global", 1500, 1000, t)
    a.eyebrow(96, 120, "GLOBALISE")
    headline(a, 750, 270, ["Speaks your users'", "language."], 76, 86, "middle")
    sub(a, 750, 430, ["English, Spanish and Arabic, left to right and right to left."], 30, 42, "middle")
    a.pill(600, 480, "Hola", 22, 28, 48, anchor="middle"); a.pill(750, 480, "مرحبًا", 22, 28, 48, anchor="middle", weight=400); a.pill(900, 480, "Hello", 22, 28, 48, anchor="middle")
    a.tablet(250, 570, 1000, 520, "9", "An Arabic timeline", "Right to left, on a Contact page")
    a.footer(9)
    f["09-global"] = a

    # 10 SECURE -------------------------------------------------------------------------------------
    a = slide(t, 10, "Secure", "SECURE BY DEFAULT")
    headline(a, 96, 250, ["People see", "only what", "they may."], 76, 86)
    sub(a, 96, 540, ["Time Drive runs as the user, so sharing", "rules and field-level security apply", "to every item."], 28, 40)
    a.pills(96, 660, ["Sharing rules", "Field-level security", "Permission sets"], 21, 24, 46, max_x=840)
    cx, cy = 1090, 480
    a.add(f'<g id="shield" transform="translate({cx} {cy}) scale(2.3)"><path d="M0 -120 L100 -80 V20 C100 90 40 130 0 150 C-40 130 -100 90 -100 20 V-80 Z" fill="{t["accent"]}" fill-opacity="0.18" stroke="{t["accent"]}" stroke-width="4"/>'
          f'<path d="M-42 8 L-12 40 L46 -28" fill="none" stroke="{t["head"]}" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/></g>')
    a.heat(900, 790, 14, 3, 22, 7, seed=7, fade=lambda c, r, C, R: 0.5)
    a.footer(10)
    f["10-secure"] = a

    # HERO 1280x720 ---------------------------------------------------------------------------------
    a = Art("hero", 1280, 720, t)
    a.lockup(72, 56, 44, 26)
    a.eyebrow(72, 150, "FOR SALESFORCE")
    headline(a, 72, 262, ["Every touchpoint.", "One timeline."], 50, 58)
    sub(a, 72, 384, ["Salesforce records and Data 360", "engagement, horizontal or vertical,", "on desktop and mobile."], 22, 32)
    a.pills(72, 500, ["Heat map", "Mobile", "Data 360"], 18, 18, 40, strong="Data 360")
    a.tablet(680, 170, 560, 480, "H", "A Contact's timeline", "Horizontal, with the heat map")
    a.phone(610, 360, 180, 380, "Hb", "Mobile", "")
    f["hero-1280x720"] = a

    # BANNER 1280x640 -------------------------------------------------------------------------------
    a = Art("banner", 1280, 640, t)
    a.lockup(468, 44, 44, 26)
    headline(a, 640, 180, ["Every touchpoint. One timeline."], 54, 60, "middle")
    sub(a, 640, 236, ["Horizontal or vertical. Desktop or mobile. Salesforce and Data 360."], 24, 32, "middle")
    a.tablet(140, 290, 1000, 520, "B", "A Contact's timeline, full width", "With the heat map along the bottom")
    f["banner-1280x640"] = a

    # TITLE TILE 448x328 ----------------------------------------------------------------------------
    a = Art("title tile", 448, 328, t)
    a.lockup(26, 24, 40, 24)
    headline(a, 26, 118, ["Every touchpoint.", "One timeline."], 29, 34)
    a.heat(316, 22, 4, 3, 14, 5, seed=4, fade=lambda c, r, C, R: 0.8)
    a.tablet(26, 178, 396, 300, "T", "A timeline crop", "", 10)
    f["title-tile-448x328"] = a

    # WORDMARK / LOGO -------------------------------------------------------------------------------
    a = Art("wordmark", 566, 81, t, glow=False)
    a.body.clear()
    a.logo(0, 0, 81)
    a.text(101, 58, "Time Drive", 52, SORA, 800, "#0B4D43", ident="wordmark")
    f["wordmark-566x81"] = a
    a = Art("logo", 100, 100, t, glow=False)
    a.body.clear()
    a.add(LOGO_BODY)
    f["logo-100x100"] = a
    return f


README = """# Time Drive: AppExchange visuals, fresh style ({label})

Not the Time Warp template: a deep-teal stage (or mint, for the light version),
**Sora** headlines, Lato body text, the logo's rail and node colours as the
accent, and a heat-map motif. Each slide leads with a small caps kicker that
names its verb (VISUALISE, INTERACT, CUSTOMISE...), a nod to the sibling.

Built by `scripts/marketing/appexchange_drive.py`. Drag the SVGs into Figma;
each screenshot is a dashed panel named `screen-<n>`: delete it, place a PNG.

## The story, slide by slide

| # | Slide | What it sells | Screens to capture (2x) |
|---|---|---|---|
| 1 | Every touchpoint. One timeline. | The whole idea | 1: wide Contact timeline, horizontal, heat map in view; 1b: the same on a phone |
| 2 | Two ways to see time | Horizontal and vertical (Auto picks) | 2a: horizontal; 2b: vertical, in a narrow region |
| 3 | See where it's busy | The heat map | 3: a crop of the days and the heat map beneath |
| 4 | In your pocket | Mobile | 4a: a vertical timeline on a phone; 4b: an item expanded |
| 5 | Guided setup. No code. | Easy setup | 5: Setup, Words and style step with the live preview |
| 6 | Salesforce and Data 360, side by side | Data 360 | 6: CRM items with Data 360 engagement among them |
| 7 | Your lens on the relationship | Lenses | 7: the lens menu open, a lens applied |
| 8 | Open, edit, act | Interaction | 8: an expanded item with its menu; 8b: the menu on a phone |
| 9 | Speaks your users' language | English, Spanish, Arabic (RTL) | 9: an Arabic right-to-left timeline |
| 10 | People see only what they may | Security | none: illustration |

Also: hero (1280x720: H, Hb), banner (1280x640: B), title tile (448x328: T),
`wordmark-566x81`, `logo-100x100`.

Use a tidy Contact with believable names, in the same Lightning app on every
shot. Capture the phone shots in the Salesforce mobile app (or its simulator).

## Fonts

**Sora** (ExtraBold 800 for headlines and the wordmark, Bold 700 for chips,
ExtraBold 800 for kickers, 3px tracking) and **Lato** (Regular 30 for body).
Both are Google fonts that Figma has. If a weight imports wrong, set it again.

## To confirm before publishing

- Spanish and Arabic text is draft; have it reviewed.
- "Salesforce mobile app" and the phone shots: confirm on a device.
- Slide 6 says engagement "from the unified profile": adjust to the objects you show.
- Sora for the wordmark is a proposal (the sibling's is Orbitron); the logo itself is unchanged.
"""


def main():
    names = sys.argv[1:] or ["night", "mint"]
    for theme in names:
        folder = os.path.join(OUT, theme)
        os.makedirs(folder, exist_ok=True)
        files = build(theme)
        for name, art in files.items():
            with open(os.path.join(folder, name + ".svg"), "w", encoding="utf-8") as fh:
                fh.write(art.svg())
        with open(os.path.join(folder, "README.md"), "w", encoding="utf-8") as fh:
            fh.write(README.format(label=THEMES[theme]["label"]))
        sheet = [f"<!doctype html><meta charset='utf-8'><title>Time Drive fresh: {theme}</title>",
                 "<link href='https://fonts.googleapis.com/css2?family=Lato:wght@400;700&family=Sora:wght@400;700;800&display=swap' rel='stylesheet'>",
                 "<style>body{margin:0;padding:24px;background:#d9dedb;font-family:Lato,system-ui,sans-serif;color:#17201d}h1{margin:0 0 4px}p{margin:0 0 20px;color:#47524d}"
                 "figure{margin:0}figcaption{font-weight:700;margin:0 0 6px}.row{display:flex;flex-wrap:wrap;gap:24px;align-items:flex-start}"
                 "svg{width:560px;height:auto;box-shadow:0 1px 4px rgba(0,0,0,.25)}</style>",
                 f"<h1>Time Drive: fresh style, {THEMES[theme]['label']}</h1><p>Placeholders are dashed. Needs a network connection for Sora and Lato.</p><div class='row'>"]
        for name, art in files.items():
            if name.startswith(("logo", "wordmark")):
                continue
            sheet.append(f"<figure><figcaption>{name} ({art.w} x {art.h})</figcaption>{art.svg()}</figure>")
        sheet.append("</div>")
        with open(os.path.join(folder, "contact-sheet.html"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(sheet))
        print(f"{theme}: {len(files)} SVGs in {os.path.relpath(folder, ROOT)}")


if __name__ == "__main__":
    main()
