# Time Trail (code name Time Shift) — project history and context

Time Trail is a Salesforce LWC + Apex timeline for Contact, Account and person
account record pages: CRM records (Tasks, Calls, Emails, Events, Cases,
Opportunities, any object) and Data 360 engagement DMOs, plotted by day,
vertically or horizontally, configured by custom metadata through the Timeline
Setup page.

## Name

The product is called **Time Trail** (renamed 2026-10-23, labels only). Every API
name, folder and tag still says `TimeShift` / `Time_Shift_*` / `c-time-shift`,
so a rename of those would install as a separate app. Only user-facing labels,
descriptions and docs say Time Trail.

## Where it came from

- Rebuilt on 2026-10-23 from the sibling project `../ProntoEngagementTimeline`
  (the "Pronto Engagement Timeline"), which stays as it is. Everything was
  copied and renamed; nothing here refers to Pronto, the Customer Card or the
  Pronto sample data model (`Order__c`, `Review__c`, `Storefront__c`). The
  component is independent: it needs no custom objects of its own.
- Rename map: `ProntoEngagementTimelineController` → `TimeShiftController`,
  `ProntoTimeline*` / `ProntoData360*` → `TimeShift*` / `TimeShiftData360*`,
  LWC `prontoEngagementTimeline` → `timeShift` (tag `c-time-shift`), other
  LWCs `timeShiftGroup`, `timeShiftFilters`, `timeShiftErrors`,
  `timeShiftRecordDetails`, `timeShiftSetup`, `timeShiftFieldPicker`,
  `timeShiftDoc*`; `Pronto_Timeline_*__mdt` → `Time_Shift_*__mdt`;
  permission sets `Time_Shift` and `Time_Shift_Setup`; static resources
  `timeShiftAssets`, `timeShiftSetupFonts`; cache partition `TimeShift`
  (`local.TimeShift`); CSS custom properties `--time-shift-*`; error codes
  `timeshift:<kind>`.
- Because every API name is new, deploying to an org that has the Pronto
  version installs a separate app with empty configuration.

## State when this folder was created

- Not a git repo yet: the user wants to check the structure first.
  Then `git init`, and work on branches (never push straight to main).
- Nothing deployed from here. Run `npm install` before Jest/ESLint.
- Jest: 9 suites, 114 tests pass. One timeline test can fail now and then
  under a full parallel run (timing); it passes alone and on rerun.
- ESLint: one known `no-await-in-loop` in the setup tests (also in the
  original). Prettier flags a few files for line wrapping only.
- Docs and scripts mention org aliases `time-shift-person` and
  `time-shift-scratch`; they don't exist yet (the original used
  `pronto-person` / `pronto-scratch`). Map one with
  `sf alias set time-shift-person=<username>`.
- The setup page's docs link points at GitHub `deejay-hub/time-shift-lwc`
  (not created yet).

## Orgs and deploying (carried over)

- The test org: deploy there freely, without asking.
- `data-ai` is "production" (a demo org with Data 360): ask before deploying;
  the user usually runs `CONFIRM_PROD=1 sf project deploy start ...` themselves,
  then the deploy report goes into `.sfdx/deploy-history/`. Being a demo org,
  it runs no tests during a deploy even with RunSpecifiedTests: run them
  separately. Two tests fail there because of how it's set up, not the code:
  `TimeShiftSetupControllerTest.eventsLinkThroughEveryContactOnThem`
  (EventWhoRelation vs EventRelation) and
  `TimeShiftControllerTest.unreadableData360ObjectsBecomeWarnings`
  (the real DMOs exist there). Make them org-independent when convenient.
- Never print or store login URLs.

## What was built most recently (in the original, carried over)

- Data 360 cost: identity lookups kept in Platform Cache (TimeShiftCache, 15
  minutes; with no partition capacity nothing is kept), and the timeline sends
  which days the summary found busy so quiet pages skip the count query.
- Heavy days are read in full: a read that hits its cap is re-read from its
  oldest period (`readInFull`); Data 360 DMO reads stay under 2,000 rows.
- Filters panel is its own component (`timeShiftFilters`); it closes on Apply.
- Today button (recentres on today); horizontal Refresh keeps your place;
  header buttons are separate (Today · Filters · Refresh), not a group.
- View all (`timeShiftGroup`, a `lightning__UrlAddressable` page): a busy
  day's grouped CRM row's title links to its items in a datatable like a
  standard list view. Keyset paging per source (date then Id) via
  `TimeShiftController.getGroupPage`, 50 a page as you scroll; columns from the
  object's compact layout (first field links to the record; lookups shown by
  name); whole page skeleton until the first page is in; "‹ Back to <record>"
  link; header stays put while the rows scroll. Data 360 grouped rows don't
  link yet.

## Open ideas

- View all for Data 360 grouped rows.
- Make the two org-dependent Apex tests work in any org.

## Labels and translations

- The timeline components' text is custom labels (`Time_Shift_*`) in en/es/ar, generated from
  `scripts/labels/catalogue.py` by `scripts/labels/generate.py` (also the `c/timeShiftLabels`
  module). Setup's own text is still English; it is the next pass.
- Jest resolves `@salesforce/label/c.*` to the English text (`jest-mocks/labelResolver.js`).
