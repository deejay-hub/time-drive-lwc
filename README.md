# Time Drive

A Lightning web component for **Contact**, **Account** and person account
record pages that shows a customer's engagement in time order: tasks, calls,
emails, events, cases, opportunities and any other Salesforce object, alongside
digital engagement from the standard Data 360 engagement data model objects
(DMOs). It needs no custom objects of its own.

## Layout

- **Vertical** in narrow regions: newest first, grouped by day, one coloured
  node per event, click a row (or **Expand all**) for its details and source
  object. The list is **Vertical Mode Height** (560px) tall and scrolls inside the
  card; loading, empty and error states keep that height, so nothing jumps. From two weeks of
  active days a **scrub tab** rides the list's right edge, tracking where you
  are. Grab it (finger or mouse) and an overlay opens with the whole history
  as heat bars, labelled by month (or by year on long histories), and a
  bubble naming the day and month (or month and year) under your finger. Let
  go to jump there; the overlay closes back to the tab. Focus the tab for the
  arrow, Page and Home/End keys. Wheel and touch over the list scroll the page until you click (or tap) inside it; then they scroll the list, finely, until the pointer leaves the card (a faint ring shows it's engaged, and a "Click to scroll the timeline" hint shows the first time the wheel passes over it). The tab, the wheel over it and the keyboard always move the list, landing as far into a day as the tab is into its bar. A week of days draws from where you land and
  more load as you scroll either way (up to four weeks drawn at once).
- **Horizontal** once the card is 640px wide or more: each day is a column
  along a time axis. From two weeks of active days a **seek bar** runs under
  the columns, its handle (in the palette's colour) over the days in view.
  Grab it and a larger overlay rises with the whole history as heat bars,
  months or years under them, and a bubble naming the day; the columns
  follow the pointer, and a click glides to a day. Focus the handle for the
  arrow, Page and Home/End keys.
- The **Layout** property can pin either one. In the **Salesforce mobile app on a phone** the card is always the vertical list, starts in Lite (titles only; the button after Today shows times and dates), has larger tap targets and a one-line header (Today, Filters and a ⋯ menu holding Refresh, Expand all and the Lite switch), and shows no activity buttons. The list fits the screen unless Phone Mode Height says otherwise.

Toolbar: timeline view (All, Marketing, Commerce, Digital, Service),
refresh, event types filter, and newest/oldest first. (How far back and
ahead it plots is set by the History and Future properties.)

### Long histories

History and Future reach up to ten years either way. The seek bar's and
scrub tab's overlays keep their bars readable however long the span: one
bar per active day while they fit (at least 6px wide across, 5px tall
down), then one per week, month, quarter or year, the finest that fits.
Long spans label years and the bubble reads the month and year; shorter
ones label months and the bubble reads the day and month.

### Language and direction

Dates follow the user's Salesforce **locale** (Setup > Personal Information >
Locale): day headers, months and years, "Today" / "Yesterday" ("Heute" /
"Gestern" in German), and event times in the user's Salesforce **time zone**
on that locale's clock. In right-to-left languages (Arabic, Hebrew, Farsi,
Urdu) the card mirrors: text, icons and rows read right to left, the scrub
tab sits on the left edge, panels open from the left. The horizontal time
axis and its seek bar keep time running left to right, as charts and seek
bars do; the text in each column still reads right to left.

## Where events come from

| Events                       | Source                                   | Mode              |
| ---------------------------- | ---------------------------------------- | ----------------- |
| Tasks, calls and emails      | `Task`, `EmailMessage`                   | Always real (CRM) |
| Events                       | `Event`                                  | Always real (CRM) |
| Cases                        | `Case`                                   | Always real (CRM) |
| Opportunities                | `Opportunity`                            | Always real (CRM) |
| Email sent, opened, clicked  | `ssot__EmailEngagement__dlm`             | Data 360          |
| Push and SMS                 | `ssot__MessageEngagement__dlm`           | Data 360          |
| Website page views           | `ssot__WebsiteEngagement__dlm`           | Data 360          |
| Web searches                 | `ssot__WebSearchEngagement__dlm`         | Data 360          |
| App sessions and screens     | `ssot__DeviceApplicationEngagement__dlm` | Data 360          |
| Add to cart, abandoned carts | `ssot__ShoppingCartEngagement__dlm`      | Data 360          |

Every active source runs, Data 360 ones included, like any other. Busy days
(over 50 events of a type) show one grouped row per type, its icon drawn as a
stack. Every event's detail names the object it came from.

### Data 360 data

Each engagement DMO is its own **Time Drive Source** record of Kind
**Data 360** (`Data_360_Email`, `_Message`, `_Website`, `_Web_Search`, `_App`,
`_Cart`), read by `TimeDriveData360Provider`. It:

1. Treats the Contact Id as an Individual Id: the Sales Cloud connector maps
   Contact to `ssot__Individual__dlm`.
2. Finds the Unified Individual through the identity link DMO, then every
   source Individual merged into it (web, app, Marketing Cloud subscriber).
3. Queries the record's DMO with SOQL in user mode:
   `WHERE <Individual Field> IN :ids AND <Date Field> >= :since`, the Ids
   being the Contact's, its Unified Individual's and the merged Individuals'.

- **Identity link object.** Set it in **Time Drive Setting > Default**
  to your ruleset's link DMO (Data Cloud Setup > Data Model), for example
  `UnifiedLinkssotIndividualTimeDrive__dlm`. If the one set (default
  `IndividualIdentityLink__dlm`) isn't there, the ruleset's
  `UnifiedLinkssotIndividual…__dlm` is used, with `SourceRecordId__c` /
  `UnifiedRecordId__c`.
- **Fields.** Check each source record's Object Name, Individual Field, Date
  Field, Id Field and templates against your mappings. Rows also offer
  `{Action}`, the channel action read naturally ("opened", "clicked"), so
  titles read "Email {Action}".
- **Details.** Each DMO's expanded fields are its Time Drive Detail Field
  records (shipped: Channel action).
- **Access.** Users need read access to the DMOs (a Data Cloud permission set)
  in the data space the DMOs live in.
- **Counting.** Deploy `force-app-data360` too (see Deploy): it counts each
  DMO in Data 360 SQL (`GROUP BY` in the user's time zone), so the day list,
  minimap and totals cover every engagement record. Without it, or if a
  count's SQL isn't accepted, each DMO is read as rows: up to Max Records,
  newest first, with a warning when that cuts it short.
- **Volume.** Rows are only read for the days on screen; a busy day comes
  back as grouped counts. For very heavy histories, a calculated insight that
  pre-aggregates per day is still the cheapest summary.

Anything missing or unreadable shows as a warning on the timeline instead of
an error, and the CRM events still load.

## Configuring what's plotted

Like Time Warp, the timeline plots whatever **Time Drive Source** custom
metadata records say (Setup > Custom Metadata Types > Time Drive Source >
Manage Records). One record per kind of event, and every record, whatever its
Kind, plots the same way.

### One contract for every source

Each source returns **rows**; `TimeDrivePlotter` turns them into events
from the source record. Only where the rows come from differs:

| Kind       | Rows from                                           | Provider Class                     |
| ---------- | --------------------------------------------------- | ---------------------------------- |
| Salesforce | Any standard or custom object, queried in user mode | Blank (`TimeDriveSoqlProvider`)    |
| Data 360   | One engagement DMO for the Contact's Individuals    | Blank (`TimeDriveData360Provider`) |
| Apex       | Your class: an external system, a calculation       | Required                           |

### Source fields

| Field                                         | What it does                                                                                                                                                            |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Active, Sequence                              | Plot it or not; the order sources run in                                                                                                                                |
| Kind                                          | Salesforce, Data 360 or Apex (see above)                                                                                                                                |
| Parent Object                                 | The record page it serves (`Contact`)                                                                                                                                   |
| Provider Class                                | The Apex class, for Kind Apex                                                                                                                                           |
| Object Name                                   | Salesforce: the object; Data 360: the DMO; Apex: a name for the footer ("Loyalty")                                                                                      |
| Parent Field                                  | Salesforce: how records link to the page's record (`ContactId`)                                                                                                         |
| Junction Object / Parent Field / Record Field | Salesforce: indirect links, e.g. `OpportunityContactRole` / `ContactId` / `OpportunityId`                                                                               |
| Individual Field, Data Space                  | Data 360: the DMO's Individual Id field (`ssot__IndividualId__c`) and its data space                                                                                    |
| Date Field, Filter                            | Date or date/time to plot by; an optional SOQL condition (`IsClosed = true`); Setup's builder writes conditions joined by AND, and shows any other filter as fixed text |
| Id Field                                      | Unique per event. Blank: `Id` (`ssot__Id__c` for Data 360 DMOs that have it)                                                                                            |
| Record Id Field                               | A Salesforce record Id to link to and expand. Blank: `Id` for Salesforce, none otherwise                                                                                |
| Title, Subtitle                               | Templates with `{Field}` tokens, relationships included: `{Subject}`, `{Account.Name} · {Amount}`; separators around blank values drop out                              |
| Event Type, Event Label, Category             | Type key (filters, grouping), its plural label ("Case updates"), and the view it belongs to                                                                             |
| Icon, Icon Colour                             | SLDS icon (`utility:case`, `standard:case`) and its background colour (`#1F7A8C`)                                                                                       |
| Amount Field                                  | Currency summed as the day's spend                                                                                                                                      |
| Max Records                                   | Per-source cap, newest first (default 1000)                                                                                                                             |
| Use Compact Layout                            | Expand a linked Salesforce record with its object's compact layout                                                                                                      |

**Account pages and shared activities.** An account's activities come from `Task.AccountId` and
`Event.AccountId`, the same field the standard timeline rolls up by: the account's own, its
contacts', and those of its opportunities and contracts. An activity shared with a second contact of
the account (Shared Activities) carries another account's Id there, so with Shared Activities in
use, **Time Drive Setup > Fit to your org** switches each of Tasks, Calls, Emails and Events to its
`_Every` variant (`Fit_Account_Tasks_Every` and so on): one query through
`TaskRelation.AccountId` / `EventRelation.AccountId` that returns the account's own activities and
the shared ones together, in place of the main source. Without Shared Activities the main sources
stay. Cases with no contact are not part of the standard rollup either. A custom object joins an
Account page through the field that holds the account (the setup asks "Which field holds the
account?").

Shipped records: Tasks, Calls and Emails, and the `Fit_*` sources (Cases,
Events, Email Messages, Opportunities and more for Contacts, Accounts and
person accounts) that Time Drive Setup switches on to fit the org.

### Expanding records

An event expands with, in order of preference:

1. Its source's **Time Drive Detail Field** records (Source, Field,
   Label, Sequence, Format: Text, Date, Date/Time, Currency or Number). Blank
   labels use the field's label. Any source can have them; on a Salesforce
   source they replace the compact layout.
2. The linked record's compact layout (Use Compact Layout), through the
   `timeDriveRecordDetails` component: an admin changes the fields in
   Object Manager, and Lightning Data Service applies field-level security.
   It loads only when the event is opened.
3. The details an events provider builds itself.

### Writing an Apex source

Return rows; the record says how to plot them.

```apex
public with sharing class MyLoyaltyProvider implements TimeDriveRowProvider {
  public List<TimeDriveRow> getRows(TimeDriveContext context) {
    List<TimeDriveRow> rows = new List<TimeDriveRow>();
    // context.recordId, context.since, context.maxRecords(), context.priorEvents
    for (LoyaltyApi.Entry entry : LoyaltyApi.entriesFor(context.recordId, context.since)) {
      rows.add(
        new TimeDriveRow(
          new Map<String, Object>{
            'Id' => entry.id, // Id Field
            'EarnedAt' => entry.earnedAt, // Date Field (Datetime or Date)
            'Points' => entry.points, // {Points} in the title, or a detail field
            'Reason' => entry.reason
          }
        )
      );
    }
    // Report what couldn't be read with context.warn('...').
    return rows;
  }
}
```

Then add a Time Drive Source record: Kind **Apex**, Provider Class
`MyLoyaltyProvider`, Date Field `EarnedAt`, Title `Earned {Points} points`,
Subtitle `{Reason}`, an Event Type, Category, Icon and colour, and Detail
Field records for what the expanded event shows. `TimeDriveExampleProvider`
and its `Loyalty_Points_Example` record are a working example: activate the
record to see it.

A class that needs full control over every event (its own types and
details) can implement `TimeDriveProvider` and return
`TimeDriveController.EngagementEvent`s itself; the record's
icon and colour still apply through `context.styled(event)`.

## Diagnostics

**Time Drive Setup > Diagnostics** (admins with Customize Application) runs a Contact or Account's
timeline and shows what it did. Enter the Id, choose the layout and the History and Future years, and
the actual timeline draws, as it does on a record page. Three tabs:

- **Config**: the data sources for the page and what became of each (used, or ignored and why:
  inactive, a variant Fit to your org didn't pick, a setting this org lacks), with the user's rights on
  each source's object and any configured field they can't read; the page (record, which sources it
  uses, layout, History and Future); and the user's permissions (access to the record, Modify All Data,
  View All Data, the org features Shared Activities and the like need).
- **Performance**: four numbers in plain terms. **Load time (total)** is the wait from the card
  connecting to the page until its days are painted. It is the sum of **Server time (Apex)**, the
  server's own run for that request; **Network time (approx.)**, the answer getting there and back
  less the server's run (so it includes the platform handling the request); and **Browser time**,
  waiting to send the request and drawing the answer. Network and browser together are everything that
  isn't the server. A bar and a sentence say where the wait went. Under them: every query with its SOQL as run,
  binds, rows, when it started and how long it took (slow ones marked); the time each source took; what
  was left out or done differently (sources not queried because the summary found them empty, busy days
  not counted again); and everything the card logged.
- **Output**: the timeline itself. It is on the page whichever tab is showing, so its load is timed as
  it really is.

The card logs a line for each request and draw (also to the console, as `[Time Drive]`), and
`getTimeline` returns its own server time, so the split above is for the request the card made.
Recording of queries is off for every other request, so a timeline pays nothing for it.

## Sample Cases and Opportunities

Cases and Opportunities are plotted from the Contact's real records (cases by
`ContactId`; opportunities by `ContactId` or an Opportunity Contact Role). To
seed a few on the three Contacts with the most cases:

```sh
sf apex run --file scripts/apex/seed-timeline-samples.apex --target-org <alias>
```

Every seeded record's Description starts with `[Timeline sample]`.

To see a long quiet stretch, `scripts/apex/seed-two-year-sample.apex` adds a
Contact, **Riley Span**, with two tasks two years apart (tagged
`[Two-year sample]`). Set History to 2 years or more to plot the older one.

## Deploy

```sh
npm install
sf project deploy start --source-dir force-app --target-org <alias>
# Orgs with Data 360 only: count Data 360 sources in Data 360 SQL.
sf project deploy start --source-dir force-app-data360 --target-org <alias>
```

`force-app-data360` holds `TimeDriveData360SqlRunner`, which calls
`ConnectApi.CdpQuery` and so only compiles where Data 360 is provisioned.

**Scale.** The summary counts each source rather than reading it: an
aggregate query per Salesforce object (a query row per day, not per record)
and SQL per Data 360 object. When History and Future make the window too long
to count every source by day within 30,000 query rows (`COUNT_ROWS`), it
counts by week (from 1 January: the 1st-7th, 8th-14th ...) or by month, and
the list shows weeks or months. Rows are read only for the days (or weeks)
on screen, and not at all for a busy one (over 50 items), which comes back as
grouped counts.

In Lightning App Builder, open a Contact record page and drag
**Time Drive** onto it.

## App Builder properties

| Property               | Default    | Effect                                                                                                                                                                                                                                           |
| ---------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Title                  | Time Drive | Card title                                                                                                                                                                                                                                       |
| Layout                 | Auto       | Auto (vertical below 640px, horizontal above), Vertical or Horizontal                                                                                                                                                                            |
| Activity Actions       | Inline     | The record's New Task, New Event, Log a Call and Email: None; One button (a + menu); Inline (a round button each among the tools); Full (a button each with its name, on a line above the header, or beside the tools in a wide horizontal card) |
| Item Detail            | Max        | Max shows each item's time and date; Lite only its title and subtitle. A button after Today switches, and the choice is remembered per browser                                                                                                   |
| Display Density        | Auto       | Auto follows each user's Comfy or Compact setting; Comfy or Compact overrides it for this component                                                                                                                                              |
| Show Age               | Off        | Each item says how long ago it was ("3 days ago") beside its time                                                                                                                                                                                |
| History (years)        | 0.5        | How far back to plot: 0.25, 0.5, 1, 2 ... 10 years                                                                                                                                                                                               |
| Future (years)         | None       | How far ahead to plot future-dated records: None (up to today), or 0.25 ... 10 years                                                                                                                                                             |
| Vertical Mode Height   | 560        | Vertical only: the list's height before it scrolls (320 to 1600)                                                                                                                                                                                 |
| Phone Mode Height | (blank) | Salesforce mobile app on a phone only: the list's greatest height in pixels. Blank fits the screen, whatever the phone, and follows rotating it (240 to 1600) |
| Horizontal Mode Height | 260        | Horizontal only: the day columns' height (240 to 1000)                                                                                                                                                                                           |

## Develop

```sh
npm run lint
npm run test:unit
```

Apex tests: `TimeDriveControllerTest`.

## Translations

Every string of the timeline (the Time Drive card, its filters, the View all page,
record details and error messages) is a custom label, in English with Spanish
(`es`) and Arabic (`ar`) translations. Setup's own text is not translated yet.

- `scripts/labels/catalogue.py` is the list: a key, the English, the Spanish and the
  Arabic. Add or change a string there, then run `python3 -I scripts/labels/generate.py`.
  It writes `CustomLabels`, the `es` and `ar` translation files and the shared
  `c/timeDriveLabels` module the components import.
- Fill in `{0}`, `{1}` ... with `format(LABELS.itemsMany, 12)`.
- The translations are drafts: have a native speaker review them. Arabic has
  singular, dual and plural forms; each count here uses one plural form.
- To see a language, turn on Translation Workbench in the org and add the language,
  or set a user's language to Spanish or Arabic.
- In Jest the labels read as their English text (`jest-mocks/labelResolver.js`).
