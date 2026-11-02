# Config Guide

How to put Time Drive on a record page, choose what it plots, and keep it fast. Time Drive Setup does most of this for you; this guide explains what it does and what you can change.

## Before you start

You need the **Customize Application** permission to add and change sources.

- Two permission sets come with the timeline.
- Data 360 is _optional_. Without it, the timeline plots your Salesforce records.
- Time Drive works on **Contact**, **Account** and **Lead** record pages, person accounts included.

## Assign the permission sets

1. In Setup, open **Permission Sets**.
2. Assign `Time Drive` to people who see the timeline.
3. Assign `Time Drive Setup` to admins who manage it.

> [!NOTE]
> What each person sees still depends on the objects and fields they can read. Every query runs as the person looking.

## Add the timeline to a page

Open a Contact, Account or Lead record, choose **Edit Page**, and drag **Time Drive** onto the page (it's under custom components). These properties can be set in Lightning App Builder:

- **Title** (default Time Drive): the timeline's name for screen readers. The lens's name is the visible heading.
- **Layout** (default Auto): Auto is vertical in narrow regions and horizontal from 640px wide. Vertical or Horizontal pins one.
- **Default Lens** (default All): the lens the timeline opens on. People can still pick another from the heading; a lens the org doesn't offer opens on All.
- **Open At** (default Today): today's slot (with a placeholder when it has nothing), the earliest item, or the latest.
- **Activity Actions** (default Inline): the record's New Task, New Event, Log a Call and Email, as the page layout's Activity composer offers them. None, One button (a + menu), Inline (a button each among the header buttons) or Full (a button each with its name).
- **Display Density** (default Auto): Auto follows each user's Comfy or Compact setting; Comfy or Compact overrides it.
- **History (years)** (default 0.5): how far back it plots, from 0.25 to 10 years.
- **Future (years)** (default None): how far ahead it plots future-dated records (scheduled orders, close dates). None is up to today; otherwise 0.25 to 10 years.
- **Vertical Mode Height (px)** (default 560, 320 to 1600): the list's greatest height. Past it, items scroll inside.
- **Horizontal Mode Height (px)** (default 260, 240 to 1000): the day columns' height. Busier days scroll inside their column.

## Add a source

Open **Customize**, choose the record page, then **Add a source**. The wizard asks what to show, how it links to the page, its date, title and subtitle, which records (a filter of conditions, matching all or any of them), and the fields an opened item shows, with a preview of real records as you go. See the [FAQs](faqs.md#why-does-saving-take-a-few-seconds) for why saving takes a moment.

Every source returns rows, and the timeline plots them the same way. Only where the rows come from differs:

- **Salesforce**: any standard or custom object linked to the page by a lookup or a junction, queried in user mode.
- **Data 360**: one engagement DMO, for the person's Individuals (see [Data 360 sources](#data-360-sources)).
- **Apex**: your class, for records further away or data from another system (see [Apex sources](#apex-sources)).

Sources are saved as **Time Drive Source** custom metadata records. Shipped records cover Tasks, Calls and Emails, plus the `Fit_*` sources that Fit to your org switches on: Cases, Events, Email Messages, Opportunities and Files for Contacts, Accounts and person accounts, Campaign Members for Contacts, and Tasks, Calls, Emails, Events, Files and Campaign Members for Leads.

## Fit to your org

**Time Drive Setup > Fit to your org** checks which features the org uses (Shared Activities, person accounts, contacts to multiple accounts) and switches on the shipped sources that suit it. Alternatives share a group, and only one in a group is ever active, so running it again never plots the same record twice.

#### Account pages and shared activities

An account's activities come from `Task.AccountId` and `Event.AccountId`, the field the standard timeline rolls up by: the account's own, its contacts', and those of its opportunities and contracts. An activity shared with a second contact (Shared Activities) carries another account's Id there.

So with Shared Activities in use, Fit to your org switches each of Tasks, Calls, Emails and Events to its `_Every` variant (`Fit_Account_Tasks_Every` and so on). That's one query through `TaskRelation.AccountId` or `EventRelation.AccountId`, returning the account's own activities and the shared ones together. Without Shared Activities the main sources stay.

Cases with no contact aren't part of the standard rollup either. A custom object joins an Account page through the field that holds the account (the wizard asks "Which field holds the account?").

## Lenses

A lens narrows the timeline to one area, such as Sales or Service. People switch lenses from the timeline's heading, and their choice is kept for them in the org.

- **All** is a lens like any other. It's where the timeline opens unless the page says otherwise.
- A source can be in several lenses. Leave a source out of All to show it only in the lenses you choose.
- The Lenses page shows the filter each source applies, so you can see what each one plots.

## Source fields

Each Time Drive Source record has these fields. Setup fills them in; you can also edit them in Setup > Custom Metadata Types > Time Drive Source > Manage Records.

- `Active__c`, `Sequence__c`: plot it or not, and the order sources run in.
- `Kind__c`: Salesforce, Data 360 or Apex.
- `Parent_Object__c`: the record page it serves (`Contact`).
- `Provider_Class__c`: for Kind Apex, a class extending `TimeDriveApexSource`.
- `Object_Name__c`: Salesforce, the object; Data 360, the DMO; Apex, a name for the footer ("Loyalty").
- `Parent_Field__c`: Salesforce, how records link to the page's record (`ContactId`).
- `Junction_Object__c`, `Junction_Parent_Field__c`, `Junction_Record_Field__c`: Salesforce, indirect links such as `OpportunityContactRole`, `ContactId` and `OpportunityId`.
- `Individual_Field__c`, `Data_Space__c`: Data 360, the DMO's Individual Id field (`ssot__IndividualId__c`) and its data space.
- `Date_Field__c`, `Filter__c`: the date or date/time to plot by, and an optional SOQL condition (`IsClosed = true`). Setup's builder writes conditions that must all hold (AND) or any of which may (OR), with "is one of" for picklists (`IN`). A filter that mixes AND and OR, or uses anything else, shows as fixed text.
- `Id_Field__c`: unique per event. Blank: `Id` (`ssot__Id__c` for Data 360 DMOs that have it).
- `Record_Id_Field__c`: a Salesforce record Id to link to and expand. Blank: `Id` for Salesforce, none otherwise.
- `Title__c`, `Subtitle__c`: templates with `{Field}` tokens, relationships included (`{Subject}`, `{Account.Name}`).
- `Event_Type__c`, `Event_Label__c`, `Category__c`: the type key (filters, grouping), its legend name ("Case updates", or a `$Label.Name` to translate), and its default lens.
- `Lenses__c`: the lenses it's in, separated by semicolons (`Sales;Service`). Blank: Category is its one lens.
- `Icon__c`, `Icon_Colour__c`: an SLDS icon (`utility:case`, `standard:case`) and its background colour (`#1F7A8C`).
- `History_Months__c`: how far back this source plots, when that's less than the timeline's own History.
- `Max_Records__c`: a per-source cap, newest first (default 1000), for sources that are read rather than counted.
- `Org_Fit__c`, `Requires__c`, `Variant_Group__c`, `Removed__c`: set by Time Drive Setup. Shipped sources Fit to your org turns on, the org features each needs, alternatives of which only one is active, and sources removed in Setup.

## Expanding records

An event expands with its source's **Time Drive Detail Field** records: Source, Field, Label, Sequence, and Format (Text, Date, Date/Time, Currency or Number). These are the fields you chose in the wizard.

- A blank label uses the field's own label, in the user's language.
- A label can be a custom label (`$Label.Points`), to translate it.
- An event with no detail fields opens on its title, subtitle and source alone.

## Data 360 sources

Each engagement DMO is its own Time Drive Source of Kind **Data 360**. The shipped ones are `Data_360_Email`, `_Message`, `_Website`, `_Web_Search`, `_App` and `_Cart`:

- Email sent, opened and clicked: `ssot__EmailEngagement__dlm`
- Push and SMS: `ssot__MessageEngagement__dlm`
- Website page views: `ssot__WebsiteEngagement__dlm`
- Web searches: `ssot__WebSearchEngagement__dlm`
- App sessions and screens: `ssot__DeviceApplicationEngagement__dlm`
- Add to cart and abandoned carts: `ssot__ShoppingCartEngagement__dlm`

To find a person's engagement, the Data 360 provider:

1. Treats the Contact Id as an Individual Id (the Sales Cloud connector maps Contact to `ssot__Individual__dlm`).
2. Finds the Unified Individual through the identity link DMO, then every source Individual merged into it (web, app, Marketing Cloud subscriber).
3. Queries the source's DMO in user mode for those Individuals and the days asked for.

Check these before you go live:

- **Identity link object.** Set it in **Time Drive Setting > Default** to your ruleset's link DMO (Data Cloud Setup > Data Model), for example `UnifiedLinkssotIndividualTimeDrive__dlm`. If the one set (default `IndividualIdentityLink__dlm`) isn't there, the ruleset's `UnifiedLinkssotIndividual…__dlm` is used, with `SourceRecordId__c` and `UnifiedRecordId__c`.
- **Fields.** Check each source's Object Name, Individual Field, Date Field, Id Field and templates against your mappings.
- **Details.** Each DMO's expanded fields are its detail fields (shipped: Channel action).
- **Access.** Users need read access to the DMOs (a Data Cloud permission set) in the data space they live in.
- **Counting.** Deploy `force-app-data360` too: it counts each DMO in Data 360 SQL, so the day list, overview and totals cover every engagement record. Without it, or if a count's SQL isn't accepted, each DMO is read as rows, up to Max Records, with a warning when that cuts it short.
- **Volume.** Rows are only read for the days on screen, and a busy day comes back as grouped counts. For very heavy histories, a calculated insight that pre-aggregates per day is still the cheapest summary.

Anything missing or unreadable shows as a warning on the timeline instead of an error, and the CRM events still load.

## Apex sources

Most sources need no code. Write an Apex source when Setup can't reach the data:

- **Records further away**, such as an Account's products on all its opportunities, two steps from the page.
- **Data from elsewhere**, such as an external system, a calculation or a forecast.

A source class extends `TimeDriveApexSource`. Time Drive asks it two things, and it answers each its own way:

- `rows(context)` (required): the items on the days in `context.spans()`. For a source that counts, that's only ever the days on screen, a few at a time.
- `counts(context, unit)` (optional): how many items each period of the window has, for the summary (the day list, overview and counts).

A source that counts covers any amount of history: the summary takes only its counts, and a busy day shows as one grouped row from its count. A source that doesn't count (leave `counts` out, or return null) is read in full for the summary, up to its Max Records, and the timeline says so when it reaches them. That's fine for a short history; anything that can grow should count.

### Say how to plot the rows

`rows` returns a `TimeDriveRow` for each item: a record (`new TimeDriveRow(record)`) or a map of values (`new TimeDriveRow(map)`). First thing in `rows`, say how to plot them:

```apex
context.plotBy('EarnedAt')               // the key holding each item's Date or Datetime
  .title('Earned {Points} points')       // {Key} is filled from each row
  .subtitle('{Reason}')                  // optional
  .opens('OrderId');                     // optional: the key holding the Salesforce record a click opens
```

Setup doesn't ask an Apex source for these, so without `plotBy` nothing is plotted. A key is a field path for record rows (`Product2.Name`) or a map key for value rows (`Points`). Everything else (icon, colour, lenses, the legend name and the fields an opened item shows) is chosen in Setup.

`opens` decides whether an item's title is a link. Call it when each row holds a Salesforce record to open. Leave it out when there's nothing to open (a weather forecast, an external system's entries): the title is plain text, with no link and no Edit or Delete menu. Such items also can't be highlighted or listed in View all.

### Count the items

`counts` returns a `TimeDriveContext.DayCount` for each period with items. Count by the period asked for (`unit`: hour, day, week or month) or by any shorter one: Time Drive adds daily totals up into weeks or months, and a day's total when asked by hour makes a busy day one grouped row. Counts outside the days asked for are left out. Two helpers build them:

- `context.countBy(objectType, dateField, condition, binds, unit)` for records: the condition that finds this record's items, written once. Time Drive groups them by the period in one query, in the user's time zone, in user mode, within the platform's limits.
- `context.counter(unit)` for data from elsewhere: `add(moment)` for each item, or `add(day, count)` for a day's total, then `counts()`.

### Records a query can reach

`TimeDriveOpportunityProducts` is the shipped example. It plots an Account's products on all its opportunities, and a click opens the Opportunity Product:

```apex
public with sharing class TimeDriveOpportunityProducts extends TimeDriveApexSource {
  private static final String CLOSE_DATE = 'Opportunity.CloseDate';
  private static final String THIS_ACCOUNT = 'Opportunity.AccountId = :accountId';

  public override List<TimeDriveContext.DayCount> counts(TimeDriveContext context, String unit) {
    if (context.recordId?.getSObjectType() != Account.SObjectType) {
      return new List<TimeDriveContext.DayCount>();
    }
    return context.countBy(
      OpportunityLineItem.SObjectType,
      CLOSE_DATE,
      THIS_ACCOUNT,
      new Map<String, Object>{ 'accountId' => context.recordId },
      unit
    );
  }

  public override List<TimeDriveRow> rows(TimeDriveContext context) {
    List<TimeDriveRow> rows = new List<TimeDriveRow>();
    if (context.recordId?.getSObjectType() != Account.SObjectType) {
      return rows;
    }
    context.plotBy(CLOSE_DATE).title('{Product2.Name}').subtitle('{Opportunity.Name}').opens('Id');
    Map<String, Object> binds = new Map<String, Object>{
      'accountId' => context.recordId,
      'most' => context.maxRecords()
    };
    String soql =
      'SELECT ' +
      String.join(context.fieldsToQuery(new List<String>{ 'Id', CLOSE_DATE }), ', ') +
      ' FROM OpportunityLineItem WHERE ' +
      THIS_ACCOUNT +
      context.dateCondition(OpportunityLineItem.SObjectType, CLOSE_DATE, binds) +
      ' ORDER BY ' +
      CLOSE_DATE +
      ' DESC, Id DESC LIMIT :most';
    for (SObject item : Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE)) {
      rows.add(new TimeDriveRow(item));
    }
    return rows;
  }
}
```

- `countBy` and `rows` share the condition, so the counts and the items always agree.
- `fieldsToQuery` adds the fields your title, subtitle and the source's detail fields name, so whatever an admin chooses in Setup is read.
- `dateCondition` keeps the query to the days the timeline asks for. It works out whether the field is a Date or a Date/Time.

### Data from elsewhere

Each row is a map, and its keys are what the title, subtitle and detail fields name. Give every row a unique `Id` key. Ask the service only for the days in `context.spans()`, and return only the items `context.wants`:

```apex
public with sharing class MyLoyaltySource extends TimeDriveApexSource {
  // The summary: one call for the window's daily totals.
  public override List<TimeDriveContext.DayCount> counts(TimeDriveContext context, String unit) {
    TimeDriveContext.Counter counter = context.counter(unit);
    for (LoyaltyApi.Total total : LoyaltyApi.dailyTotals(context.recordId, context.since, context.until)) {
      counter.add(total.day, total.entries);
    }
    return counter.counts();
  }

  // The days on screen.
  public override List<TimeDriveRow> rows(TimeDriveContext context) {
    context.plotBy('EarnedAt').title('Earned {Points} points').subtitle('{Reason}');
    List<TimeDriveRow> rows = new List<TimeDriveRow>();
    for (TimeDriveController.TimeWindow span : context.spans()) {
      for (LoyaltyApi.Entry entry : LoyaltyApi.entriesFor(context.recordId, span.since, span.until)) {
        if (context.wants(entry.earnedAt)) {
          rows.add(
            new TimeDriveRow(
              new Map<String, Object>{
                'Id' => entry.id,
                'EarnedAt' => entry.earnedAt, // a Datetime or a Date
                'Points' => entry.points,
                'Reason' => entry.reason
              }
            )
          );
        }
      }
    }
    return rows;
  }
}
```

How you count is yours to choose: a totals endpoint, as here; a cached copy; or counting the items of one fetch with `counter.add(entry.earnedAt)`. If the service can't help at all, leave `counts` out.

### What context gives you

- `recordId`: the record the timeline is on.
- `since`, `until`: the timeline's window. `until` is null for "up to now".
- `spans()`: the days asked for, either the window or the days on screen.
- `maxRecords()`: the source's record cap.
- `plotBy(key).title(…).subtitle(…).opens(…)`: how the rows are plotted.
- `fieldsToQuery(always)`: for record rows, the fields to SELECT.
- `dateCondition(objectType, field, binds)`: for record rows, the days asked for as a bound condition.
- `wants(dateOrDatetime)`: for data from elsewhere, whether the timeline asks for that moment.
- `countBy(objectType, field, condition, binds, unit)`: counts of records, grouped by the period in one query.
- `counter(unit)`: counts of items from elsewhere, added one at a time or by the day.
- `warn(message)`: a note the timeline shows, such as "Couldn't reach the loyalty service".

### Good practice

- **Count anything that can grow.** Without `counts`, every timeline load reads the source's whole window.
- **Query in user mode** (`AccessLevel.USER_MODE`), so people see only what they're allowed to.
- **Cache callouts.** The summary and each page are their own requests. Keep what a callout returns in Platform Cache (`TimeDriveCache`) for a while, so a page view doesn't call out several times. Set a short callout timeout.
- **Failures are contained.** A class that throws is named on the timeline, and the other sources still load. A `counts` that throws is read as rows instead. Prefer `warn` for problems you expect.

### Time zones and translations

The timeline shows every date, time and number in the viewer's own time zone, language and locale. Your rows get the same treatment as Setup's sources, as long as you hand over real values rather than text:

- **Dates and times.** Give a `Datetime` for a moment and a `Date` for a whole day (a day plots at midday, so it stays on its day in every time zone). When a service sends times as text, parse them with their zone (`2026-10-31T09:00:00Z` or `+11:00`), so they land at the right moment.
- **Numbers and money.** Give numbers as numbers (`Decimal`, `Integer`, `Double`), not formatted strings. They show grouped as the viewer's locale does (1,200.5 or 1.200,5). A detail field with the Currency format shows in the viewer's currency, or in a row's own when it has a `CurrencyIsoCode` key (records have it in multi-currency orgs; add it to the fields you query).
- **Picklists** on records show their labels in the viewer's language.
- **Words you write.** Text in `title` and `subtitle` is shown as you wrote it. For translated text, pass a custom label: `.title(System.Label.Points_Earned)`, whose text can hold tokens such as `{Points}`. A detail field's label can be `$Label.Points` too.
- **Text from elsewhere.** Ask the service for the viewer's language (`UserInfo.getLanguage()`, `UserInfo.getLocale()`) where it supports one.

### Test and add it

1. Test the class to at least 85%. Give it test data or an `HttpCalloutMock`, call `rows` and `counts` with a `TimeDriveContext`, and check what they return or the events `TimeDrivePlotter.run` makes of them.
2. In Time Drive Setup, add a source of kind **Apex** on the record page and choose the class. Pick its look and lenses, then type the fields an opened item shows: a field path, or a map key.
3. Saving asks you to confirm you've thought about how the class scales, because it runs every time a timeline with the source loads.

## How people use the timeline

#### Layout

- **Vertical** in narrow regions: newest first, grouped by day, one coloured node per event. Click a row (or **Expand all**) for its details and source object. The list is up to Vertical Mode Height tall and scrolls inside the card; loading, empty and error states keep that height, so nothing jumps.
- **Scrub tab.** From two weeks of active days a scrub tab rides the vertical list's edge. Grab it and an overlay opens with the whole history as heat bars, with a bubble naming the day and month (or month and year) under your finger. Let go to jump there. Focus the tab for the arrow, Page and Home/End keys.
- **Scrolling.** Wheel and touch over the list scroll the page until you click (or tap) inside it; then they scroll the list until the pointer leaves the card. A faint ring shows it's engaged, and a hint shows the first time the wheel passes over it. A week of days draws from where you land, and more load as you scroll (up to four weeks drawn at once).
- **Horizontal** once the card is 640px wide or more: each day is a column along a time axis. From two weeks of active days a **seek bar** runs under the columns. Grab it and an overlay shows the whole history as heat bars; the columns follow the pointer, and a click glides to a day.
- **Phone.** In the Salesforce mobile app on a phone the card is always the vertical list and fits the screen. It starts in Lite (titles only; the button after Today shows times and dates), has larger tap targets, a one-line header (Today, Filters and a ⋯ menu holding Refresh, Expand all and the Lite switch), and no activity buttons.

The header carries the lens as its heading, then **Today**, **Filters** (event types) and **Refresh**. Each user's lens and Lite choice are kept for them in the org.

Busy days (over 50 events of a type) show one grouped row per type, its icon drawn as a stack. For Salesforce sources its title links to all its items (View all). Every event's detail names the object it came from.

#### Long histories

History and Future reach up to ten years either way. The overlays keep their bars readable however long the span: one bar per active day while they fit, then one per week, month, quarter or year, the finest that fits. Long spans label years; shorter ones label months.

#### Language and direction

Dates follow the user's Salesforce **locale** and **time zone**: day headers, months and years, "Today" and "Yesterday", and event times on that locale's clock. Numbers and money follow the locale too, money in each record's own currency in multi-currency orgs.

In right-to-left languages (Arabic, Hebrew, Farsi, Urdu) the card mirrors: text, icons and rows read right to left, the scrub tab sits on the left edge, and panels open from the left. The horizontal time axis and its seek bar keep time running left to right, as charts do.

## Scale

The summary counts each source rather than reading it: an aggregate query per Salesforce object (a query row per day, not per record), SQL per Data 360 object, and `counts` for Apex sources.

- When History and Future make the window too long to count every source by day within 30,000 query rows, it counts by week (from 1 January: the 1st-7th, 8th-14th ...) or by month, and the list shows weeks or months.
- Rows are read only for the days (or weeks) on screen.
- A busy day (over 50 items) isn't read at all; it comes back as grouped counts.

## Diagnostics

**Time Drive Setup > Diagnostics** runs a Contact, Account or Lead's timeline and shows what it did. Enter the Id, choose the layout and the History and Future years, and the actual timeline draws, as it does on a record page. It has three tabs:

- **Config**: the sources for the page and what became of each (used, or ignored and why: inactive, a variant Fit to your org didn't pick, a setting this org lacks), with the user's rights on each source's object and any configured field they can't read. It also shows the page (record, the sources it uses, layout, History and Future) and the user's permissions (access to the record, Modify All Data, View All Data, and the org features sources need).
- **Performance**: **Load time (total)** is the wait from the card connecting to the page until its days are painted. It's the sum of **Server time (Apex)**, the server's own run; **Network time (approx.)**, the answer getting there and back less the server's run; and **Browser time**, waiting to send the request and drawing the answer. A bar and a sentence say where the wait went. Under them: every query with its SOQL as run, binds, rows, when it started and how long it took (slow ones marked); the time each source took; what was left out or done differently; and everything the card logged.
- **Output**: the timeline itself. It's on the page whichever tab is showing, so its load is timed as it really is.

The card logs a line for each request and draw (also to the console, as `[Time Drive]`). Recording of queries is off for every other request, so a timeline pays nothing for it.

## Translations

Every string of the timeline (the card, its filters, the View all page, record details and error messages) is a custom label (`Time_Drive_*`), in English with Spanish and Arabic translations. Setup's own text is English for now.

- To review or add translations, open Setup > Custom Labels (you need the Manage Translation permission).
- To see a language, turn on Translation Workbench and add the language, or set a user's language to Spanish or Arabic.
- The translations are drafts: have a native speaker review them. Arabic has singular, dual and plural forms; each count here uses one plural form.

For developers: `scripts/labels/catalogue.py` is the list of strings (a key, the English, the Spanish and the Arabic). Add or change a string there, then run `python3 -I scripts/labels/generate.py`. It writes `CustomLabels`, the translation files and the shared `c/timeDriveLabels` module. Fill in `{0}`, `{1}` ... with `format(LABELS.itemsMany, 12)`. In Jest the labels read as their English text.

## Sample data

Cases and Opportunities are plotted from the Contact's real records (cases by `ContactId`; opportunities by `ContactId` or an Opportunity Contact Role). To seed a few on the three Contacts with the most cases:

```
sf apex run --file scripts/apex/seed-timeline-samples.apex --target-org <alias>
```

Every seeded record's Description starts with `[Timeline sample]`.

To see a long quiet stretch, `scripts/apex/seed-two-year-sample.apex` adds a Contact, **Riley Span**, with two tasks two years apart (tagged `[Two-year sample]`). Set History to 2 years or more to plot the older one.

---

Questions? Read the [FAQs](faqs.md), or go back to [Before you start](#before-you-start).
