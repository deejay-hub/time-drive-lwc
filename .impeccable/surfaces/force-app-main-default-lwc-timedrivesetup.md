---
version: 1
slug: "force-app-main-default-lwc-timedrivesetup"
primary_target: "force-app/main/default/lwc/timeDriveSetup"
related_targets: []
---

Scope: the Timeline Setup app (timeDriveSetup), a Lightning tab for admins, Operate mode throughout (the home page explains, then leads in). Success: a first-time admin adds a source in about a minute. Every page fills the tab, edge to edge and at least the window's height, and uses the full width. Fonts pinned by the user: Orbitron for headings, Lato for text (static resource timeDriveSetupFonts). No live previews anywhere (user removed them); Review sums the answers up instead.

## Direction contract
THESIS: Setup is a well-kept help desk, after the Kindred Support template (design-library 51-kindred-support, user-pinned: "change the design to be more like kindred support"): a home page that asks what the timelines should show, the record pages, each record page's sources as a ruled list, each source its own page, and adding one as a sub page asking one plain question at a time, under "Step n" rules across the full width that go back or forward. It refuses card grids, drawers, the sentence header, previews and glossy chrome.
OWN-WORLD: Warm desk paper (#f7f6f2) edge to edge, white only where something holds an action, ink text, one spruce green (#0f6b58) for actions, selection, done steps and healthy status (pills, the status dot), amber and rust only for state. 1px warm hairlines, no shadows on permanent surfaces, 6px buttons, 10-16px panels. Authored line art in one ink stroke with spruce accents. Source colour only in each source's chip.
STORY: Admin opens Setup, reads the question and the at-a-glance panel and status strip, presses Get started (or picks Contact directly), scans its sources (name, view, one line, a switch), adds one by answering short questions while the step rules fill with the answers and the So far panel collects them, checks the summary, saves, and lands back on Contact with the new source picked out.
FIRST VIEWPORT: Home: "What should your timelines show?" in Orbitron at up to 3rem, the lede, Get started (spruce) and How it works (outlined), "Or start from a record page" with Contact; at right a white panel with drawn timeline art and the record pages with "17 on" pills; under the hero the full-bleed status strip. Contact page: breadcrumb, "Contact timeline" over a full-width hairline, counts, Add a source at right, ruled white rows by type. A step: breadcrumb, title, ten "Step n" rules across the full width, the question in Orbitron with option rows at 44rem, the So far panel at right, Back and Next in a solid footer.
FORM: Help-desk site with sub pages; Kindred Support pinned by the user ("change the design to be more like kindred support"), structure from the user's "Site with sub pages" answer. No seed roll: user-pinned direction.
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
