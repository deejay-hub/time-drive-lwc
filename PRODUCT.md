# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Salesforce admins in a customer's org. They decide what each record page's
Time Trail shows (which objects, linked how, dated by which field),
occasionally and without writing code. The people who read the timeline are
the org's users on record pages (Contact today): service, sales and marketing
staff looking at a customer's history.

## Product Purpose

Time Trail plots everything that happened to a record,
CRM records (orders, cases, opportunities, any standard or custom object) and
Data 360 digital engagement (email, web, app, cart), as one timeline on the
record page. Time Trail Setup is where an admin chooses those sources.

Success for setup: a first-time admin adds a source in about a minute
(pick the record page, answer a few plain questions, check the summary,
save) without help. Editing, switching off and removing sources are secondary.

## Positioning

One timeline for CRM and Data 360 engagement, configured by sources an admin
adds without code, that scales from a few records to millions (counts first,
details only for what's on screen) and respects each user's access.

## Operating Context

Runs inside Lightning Experience: the timeline is a Lightning Web Component
on record pages; Time Trail Setup is a Lightning tab (`Timeline_Setup`) for
admins. Configuration is stored as custom metadata (Time Trail Source,
Time Trail Detail Field), deployed by the wizard through the Metadata
API. Scratch org `time-shift-scratch` is the test org; `data-ai` is production.

## Capabilities and Constraints

- Source kinds: Salesforce objects (linked by a lookup or through a
  junction), Data 360 DMOs (through the Contact's unified Individual), and
  Apex providers.
- Parent objects: Contact today; others planned.
- Every query runs in user mode; a source a user can't read is skipped and
  named, never breaking the rest of the timeline.
- Admin-entered names and all built-in text must become translatable for
  global deployments (designed, not yet built).
- Undecided: which other parent objects ship next; the translation storage
  choice (translation records, Custom Labels, or both).

## Brand Commitments

Time Trail Setup follows the Kindred Support template (design-library
51-kindred-support), pinned by the user: warm paper, white panels, one
spruce green for actions and healthy status, light only. Headings in
Orbitron, text in Lato (user-pinned, self-hosted). It runs inside the
Lightning shell and fills its tab edge to edge. Time Trail's own colour belongs
to the timeline's stripe and heatmap, not to setup.

## Product Principles

- One thing at a time: each step asks one plain question.
- Say it plainly: no live previews in setup (removed by the user); the last
  step sums the answers up, each a click from its question.
- Plain words over field names; API names only where an admin needs them.
- Never break the rest: a bad source is contained and explained.
