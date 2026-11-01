<div align="center">
	<img
	width="50"
	src="/force-app/main/default/lwc/timeDrive/timeDrive.svg">
	<h1>Time Drive</h1>
</div>

<h4 align="center">
	<a href="#overview">Overview</a> |
	<a href="#installation-instructions">Install Me</a> |
	<a href="#how-it-works">How it Works</a> |
	<a href="#faqs">FAQs</a> |
	<a href="#contributing">Contribute</a>
</h4>

<h3 align="center">
	A customer's engagement in time order, on any Contact or Account page<br><br>
	<a href="https://github.com/deejay-hub/time-shift-lwc/network/members">
    		<img alt="forks on github"
		src="https://img.shields.io/github/forks/deejay-hub/time-shift-lwc?style=flat-square&logoColor=blue">
  	</a>
  	<a href="https://github.com/deejay-hub/time-shift-lwc/stargazers">
    		<img alt="stars on github"
		src="https://img.shields.io/github/stars/deejay-hub/time-shift-lwc?style=flat-square">
  	</a>
  	<a href="https://github.com/deejay-hub/time-shift-lwc/watchers">
    		<img alt="watchers"
		src="https://img.shields.io/github/watchers/deejay-hub/time-shift-lwc?style=flat-square">
  	</a>
  	<a href="https://github.com/deejay-hub/time-shift-lwc/issues">
    		<img alt="issues"
		src="https://img.shields.io/github/issues-raw/deejay-hub/time-shift-lwc?style=flat-square">
  	</a>
</h3>

## Overview

A Lightning web component for **Contact**, **Account** and person account record pages that shows a customer's engagement in time order: tasks, calls, emails, events, cases, opportunities and any other Salesforce object, alongside digital engagement from the standard Data 360 engagement data model objects (DMOs).

- **Any object.** Plot standard and custom objects linked to the page by a lookup or a junction (TaskRelation, OpportunityContactRole), Files included.
- **Data 360 engagement.** Email, messaging, web, search, app and cart engagement DMOs, matched to the person through identity resolution.
- **Apex sources.** Bring in records further away or data from another system with a small class that counts and returns rows.
- **Built to scale.** The summary counts each source instead of reading it, rows load only for the days on screen, and busy days fold into one grouped row with View all.
- **Vertical and horizontal layouts.** A scrub tab or seek bar over the whole history, up to ten years each way, and a phone layout in the Salesforce mobile app.
- **Guided setup.** Time Drive Setup adds sources step by step, fits the timeline to your org, and has lenses, detail fields and diagnostics.
- **Multi language support.** Every string is a custom label (English, Spanish and Arabic); dates, numbers and money follow the user's locale and time zone; right-to-left languages mirror the card.
- **Console ready.** Records open in a workspace tab in Console apps.

## Installation Instructions

Install the component from source control into a scratch org using the instructions below:

1. Set up your environment. Follow the steps in the [Quick Start: Lightning Web Components](https://trailhead.salesforce.com/content/learn/projects/quick-start-lightning-web-components/) Trailhead project. The steps include:

- Enable Dev Hub in your Trailhead Playground
- Install Salesforce CLI
- Install Visual Studio Code
- Install the Visual Studio Code Salesforce extensions, including the Lightning Web Components extension

2. If you haven't already done so, authenticate with your hub org and provide it with an alias (**myhuborg** in the command below):

```
sf org login web -d -a myhuborg
```

3. Clone the time-shift-lwc repository:

```
gh repo clone https://github.com/deejay-hub/time-shift-lwc
cd time-shift-lwc
```

4. Create a scratch org and provide it with an alias (**time-drive** in the command below). Use `config/person-accounts-scratch-def.json` instead to try person accounts:

```
sf org create scratch -d -f config/project-scratch-def.json -a time-drive -y 30
```

5. Deploy the app to your scratch org:

```
sf project deploy start --source-dir force-app
```

6. Optional, for orgs with Data 360 only: deploy the Data 360 counting class (it calls `ConnectApi.CdpQuery`, so it only compiles where Data 360 is provisioned):

```
sf project deploy start --source-dir force-app-data360
```

7. Assign the permission sets to the default user (**Time_Drive** to use the timeline, **Time_Drive_Setup** to configure it):

```
sf org assign permset --name Time_Drive --name Time_Drive_Setup
```

8. Load sample data: a few Cases and Opportunities on the three Contacts with the most cases (each seeded record's Description starts with `[Timeline sample]`):

```
sf apex run --file scripts/apex/seed-timeline-samples.apex
```

9. Open the scratch org:

```
sf org open
```

10. Optional: Run npm install to support linting, prettification and test runs

```
npm install
```

11. Open a Contact record, select **Edit Page** in Setup, and drag the **Time Drive** component onto the page (found under custom components). Account pages work the same way.

12. Open the **Time Drive Setup** tab to add sources, fit the timeline to your org and run diagnostics.

## How it Works

#### Object Support

Time Drive is installed as a custom component available in the App Builder component palette for **Contact** and **Account** record pages, person accounts included. It plots whatever its sources say: any standard or custom object, Data 360 engagement, and Apex sources.

#### Layout

- **Vertical** in narrow regions: newest first, grouped by day, one coloured node per event; click a row (or **Expand all**) for its details and source object. The list is **Vertical Mode Height** (560px) tall and scrolls inside the card; loading, empty and error states keep that height, so nothing jumps. From two weeks of active days a **scrub tab** rides the list's right edge, tracking where you are. Grab it (finger or mouse) and an overlay opens with the whole history as heat bars, labelled by month (or by year on long histories), and a bubble naming the day and month (or month and year) under your finger. Let go to jump there; the overlay closes back to the tab. Focus the tab for the arrow, Page and Home/End keys. Wheel and touch over the list scroll the page until you click (or tap) inside it; then they scroll the list, finely, until the pointer leaves the card (a faint ring shows it's engaged, and a "Click to scroll the timeline" hint shows the first time the wheel passes over it). The tab, the wheel over it and the keyboard always move the list, landing as far into a day as the tab is into its bar. A week of days draws from where you land and more load as you scroll either way (up to four weeks drawn at once).
- **Horizontal** once the card is 640px wide or more: each day is a column along a time axis. From two weeks of active days a **seek bar** runs under the columns, its handle (in the palette's colour) over the days in view. Grab it and a larger overlay rises with the whole history as heat bars, months or years under them, and a bubble naming the day; the columns follow the pointer, and a click glides to a day. Focus the handle for the arrow, Page and Home/End keys.
- The **Layout** property can pin either one. In the **Salesforce mobile app on a phone** the card is always the vertical list and fits the screen, starts in Lite (titles only; the button after Today shows times and dates), has larger tap targets and a one-line header (Today, Filters and a ⋯ menu holding Refresh, Expand all and the Lite switch), and shows no activity buttons.

The header carries the lens as its heading, then **Today**, **Filters** (event types) and **Refresh**. How far back and ahead it plots is set by the History and Future properties. Each user's lens and Lite choice are kept for them in the org.

#### Long Histories

History and Future reach up to ten years either way. The seek bar's and scrub tab's overlays keep their bars readable however long the span: one bar per active day while they fit (at least 6px wide across, 5px tall down), then one per week, month, quarter or year, the finest that fits. Long spans label years and the bubble reads the month and year; shorter ones label months and the bubble reads the day and month.

#### Language and Direction

Dates follow the user's Salesforce **locale** (Setup > Personal Information > Locale): day headers, months and years, "Today" / "Yesterday" ("Heute" / "Gestern" in German), and event times in the user's Salesforce **time zone** on that locale's clock. Numbers and money follow the locale too, money in each record's own currency in multi-currency orgs. In right-to-left languages (Arabic, Hebrew, Farsi, Urdu) the card mirrors: text, icons and rows read right to left, the scrub tab sits on the left edge, panels open from the left. The horizontal time axis and its seek bar keep time running left to right, as charts and seek bars do; the text in each column still reads right to left.

#### Component Properties

The component has the following properties that can be set at design time in App Builder by an administrator

| Property                      | Description                                                                                                                                                                                                                    | Validation                                   |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------- |
| `Title`                       | The timeline's name for screen readers (the lens's name is the visible heading). Default Time Drive                                                                                                                            | String                                       |
| `Layout`                      | Auto is vertical in narrow regions and horizontal from 640px wide. Default Auto                                                                                                                                                | Picklist (Auto, Vertical, Horizontal)        |
| `Default Lens`                | The lens the timeline opens on. People can still pick another from the heading; a lens the org doesn't offer opens on All. Default All                                                                                         | Dynamic Picklist (the org's lenses)          |
| `Open At`                     | Where the timeline opens: today's slot (with a placeholder when it has nothing), its earliest item or its latest. Default Today                                                                                                | Picklist (Today, Earliest item, Latest item) |
| `Activity Actions`            | The record's New Task, New Event, Log a Call and Email, as the page layout's Activity composer offers them: none, folded into a + menu, a button each among the header buttons, or a button each with its name. Default Inline | Picklist (None, One button, Inline, Full)    |
| `Display Density`             | Auto follows each user's Comfy or Compact setting; Comfy or Compact overrides it for this component. Default Auto                                                                                                              | Picklist (Auto, Comfy, Compact)              |
| `History (years)`             | How far back the timeline plots. Default 0.5                                                                                                                                                                                   | Picklist (0.25 - 10)                         |
| `Future (years)`              | How far ahead it plots future-dated records (scheduled orders, close dates); None is up to today. Default None                                                                                                                 | Picklist (None, 0.25 - 10)                   |
| `Vertical Mode Height (px)`   | Vertical only: the list's greatest height; past it, items scroll inside. Default 560                                                                                                                                           | Integer min 320 max 1600                     |
| `Horizontal Mode Height (px)` | Horizontal only: the day columns' height; busier days scroll inside their column. Default 260                                                                                                                                  | Integer min 240 max 1000                     |

#### Where Events Come From

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

Every active source runs, Data 360 ones included, like any other. Busy days (over 50 events of a type) show one grouped row per type, its icon drawn as a stack; for Salesforce sources its title links to all its items (View all). Every event's detail names the object it came from.

##### Data 360 Data

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
- **Counting.** Deploy `force-app-data360` too (see [Installation Instructions](#installation-instructions), step 6): it counts each
  DMO in Data 360 SQL (`GROUP BY` in the user's time zone), so the day list,
  minimap and totals cover every engagement record. Without it, or if a
  count's SQL isn't accepted, each DMO is read as rows: up to Max Records,
  newest first, with a warning when that cuts it short.
- **Volume.** Rows are only read for the days on screen; a busy day comes
  back as grouped counts. For very heavy histories, a calculated insight that
  pre-aggregates per day is still the cheapest summary.

Anything missing or unreadable shows as a warning on the timeline instead of
an error, and the CRM events still load.

#### Configuring What's Plotted

Like Time Warp, the timeline plots whatever **Time Drive Source** custom metadata records say (Setup > Custom Metadata Types > Time Drive Source > Manage Records). Time Drive Setup writes them for you. One record per kind of event, and every record, whatever its Kind, plots the same way: each source returns **rows**, and `TimeDrivePlotter` turns them into events from the source record. Only where the rows come from differs:

| Kind       | Rows from                                           | Provider Class                                     |
| ---------- | --------------------------------------------------- | -------------------------------------------------- |
| Salesforce | Any standard or custom object, queried in user mode | Blank (`TimeDriveSoqlProvider`)                    |
| Data 360   | One engagement DMO for the Contact's Individuals    | Blank (`TimeDriveData360Provider`)                 |
| Apex       | Your class: an external system, a calculation       | Required (a class extending `TimeDriveApexSource`) |

When populating the metadata type the following is a description of the columns and their purpose

| Field Name                                                                   | Description                                                                                                                                                                 |
| ---------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Active__c`, `Sequence__c`                                                   | Plot it or not; the order sources run in                                                                                                                                    |
| `Kind__c`                                                                    | Salesforce, Data 360 or Apex (see above)                                                                                                                                    |
| `Parent_Object__c`                                                           | The record page it serves (`Contact`)                                                                                                                                       |
| `Provider_Class__c`                                                          | The Apex class, for Kind Apex                                                                                                                                               |
| `Object_Name__c`                                                             | Salesforce: the object; Data 360: the DMO; Apex: a name for the footer ("Loyalty")                                                                                          |
| `Parent_Field__c`                                                            | Salesforce: how records link to the page's record (`ContactId`)                                                                                                             |
| `Junction_Object__c`, `Junction_Parent_Field__c`, `Junction_Record_Field__c` | Salesforce: indirect links, e.g. `OpportunityContactRole` / `ContactId` / `OpportunityId`                                                                                   |
| `Individual_Field__c`, `Data_Space__c`                                       | Data 360: the DMO's Individual Id field (`ssot__IndividualId__c`) and its data space                                                                                        |
| `Date_Field__c`, `Filter__c`                                                 | Date or date/time to plot by; an optional SOQL condition (`IsClosed = true`); Setup's builder writes conditions joined by AND, and shows any other filter as fixed text     |
| `Id_Field__c`                                                                | Unique per event. Blank: `Id` (`ssot__Id__c` for Data 360 DMOs that have it)                                                                                                |
| `Record_Id_Field__c`                                                         | A Salesforce record Id to link to and expand. Blank: `Id` for Salesforce, none otherwise                                                                                    |
| `Title__c`, `Subtitle__c`                                                    | Templates with `{Field}` tokens, relationships included: `{Subject}`, `{Account.Name}`                                                                                      |
| `Event_Type__c`, `Event_Label__c`, `Category__c`                             | Type key (filters, grouping), its legend name ("Case updates", or a `$Label.Name` to translate), and its default lens                                                       |
| `Lenses__c`                                                                  | The lenses it is in, separated by semicolons (`Sales;Service`). Blank: Category is its one lens                                                                             |
| `Icon__c`, `Icon_Colour__c`                                                  | SLDS icon (`utility:case`, `standard:case`) and its background colour (`#1F7A8C`)                                                                                           |
| `History_Months__c`                                                          | How far back this source plots, when that's less than the timeline's own History                                                                                            |
| `Max_Records__c`                                                             | Per-source cap, newest first (default 1000), for sources read rather than counted                                                                                           |
| `Org_Fit__c`, `Requires__c`, `Variant_Group__c`, `Removed__c`                | Set by Time Drive Setup: shipped sources that Fit to your org turns on, the org features each needs, alternatives of which only one is active, and sources removed in Setup |

**Account pages and shared activities.** An account's activities come from `Task.AccountId` and `Event.AccountId`, the same field the standard timeline rolls up by: the account's own, its contacts', and those of its opportunities and contracts. An activity shared with a second contact of the account (Shared Activities) carries another account's Id there, so with Shared Activities in use, **Time Drive Setup > Fit to your org** switches each of Tasks, Calls, Emails and Events to its `_Every` variant (`Fit_Account_Tasks_Every` and so on): one query through `TaskRelation.AccountId` / `EventRelation.AccountId` that returns the account's own activities and the shared ones together, in place of the main source. Without Shared Activities the main sources stay. Cases with no contact are not part of the standard rollup either. A custom object joins an Account page through the field that holds the account (the setup asks "Which field holds the account?").

Shipped records: Tasks, Calls and Emails, and the `Fit_*` sources (Cases, Events, Email Messages, Opportunities and more for Contacts, Accounts and person accounts) that Time Drive Setup switches on to fit the org.

#### Expanding Records

An event expands with its source's **Time Drive Detail Field** records (Source, Field, Label, Sequence, Format: Text, Date, Date/Time, Currency or Number), the fields the admin chose in Setup. Blank labels use the field's label, and a label can be a `$Label.Name` to translate. An event with none opens on its title, subtitle and source alone.

#### Writing an Apex Source

Most sources need no code: Setup plots any object linked to the page by a
lookup or a junction. Write an Apex source when that isn't enough:

- **Records further away**, such as an Account's products on all its
  opportunities, two steps from the page.
- **Data from elsewhere**, such as an external system, a calculation or a
  forecast.

**The contract.** Extend `TimeDriveApexSource`. Time Drive asks it two
things, and it answers each its own way:

| Method                             | Time Drive asks                              | When                                           |
| ---------------------------------- | -------------------------------------------- | ---------------------------------------------- |
| `rows(context)` (required)         | The items on the days in `context.spans()`   | The days on screen, a few at a time            |
| `counts(context, unit)` (optional) | How many items each period of the window has | The summary: the day list, overview and counts |

A source that counts covers any amount of history. The summary takes only
its counts, `rows` is asked only for the days on screen, and a busy day shows
as one grouped row from its count. A source that doesn't count (leave
`counts` out, or return null) is read in full for the summary, up to its Max
Records, and the timeline says so when it reaches them. That's fine for a
short history; anything that can grow should count.

`rows` returns a `TimeDriveRow` for each item: a record
(`new TimeDriveRow(record)`) or a map of values (`new TimeDriveRow(map)`).
First thing in `rows`, say how to plot them:

```apex
context.plotBy('EarnedAt')               // the key holding each item's Date or Datetime
  .title('Earned {Points} points')       // {Key} is filled from each row
  .subtitle('{Reason}')                  // optional
  .opens('OrderId');                     // optional: the key holding the Salesforce record a click opens
```

`opens` decides whether an item's title is a link. Call it when each row
holds a Salesforce record to open, as the products example does with
`.opens('Id')`. Leave it out when there's nothing to open (a weather
forecast, an external system's entries) and the title is plain text, with
no link and no Edit or Delete menu.

Setup doesn't ask an Apex source for these, so without `plotBy` nothing is
plotted. A key is a field path for record rows (`Product2.Name`) or a map key
for value rows (`Points`). Everything else (icon, colour, lenses, the legend
name and the fields an opened item shows) is chosen in Setup.

`counts` returns a `TimeDriveContext.DayCount` for each period with items.
Count by the period asked for (`unit`: hour, day, week or month) or by any
shorter one: Time Drive adds up daily totals into weeks or months, and a
day's total when asked by hour makes a busy day one grouped row. Counts
outside the days asked for are left out. Two helpers build them:

- `context.countBy(objectType, dateField, condition, binds, unit)` for
  records: the condition that finds this record's items, written once. Time
  Drive groups them by the period in one query (in the user's time zone, in
  user mode, within the platform's limits).
- `context.counter(unit)` for data from elsewhere: `add(moment)` for each
  item, or `add(day, count)` for a day's total, then `counts()`.

**The steps**

1. Write the class, using one of the two patterns below.
2. Test it, to at least 85%. Give it test data or an `HttpCalloutMock`, call
   `rows` and `counts` with a `TimeDriveContext`, and check what they return
   or the events `TimeDrivePlotter.run` makes of them.
3. In Time Drive Setup, add a source of kind **Apex** on the record page and
   choose the class. Pick its look and lenses. Then type the fields an opened
   item shows: a field path, or a map key. Saving asks you to confirm you've
   thought about how the class scales, because it runs every time a timeline
   with the source loads.

##### Records a query can reach

`TimeDriveOpportunityProducts` is the shipped example. It plots an Account's
products on all its opportunities:

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

- `countBy` and `rows` share the condition, so the counts and the items
  always agree.
- `fieldsToQuery` adds the fields your title, subtitle and the source's detail
  fields name, so whatever an admin chooses in Setup is read.
- `dateCondition` keeps the query to the days the timeline asks for. It works
  out whether the field is a Date or a Date/Time.

##### Data from elsewhere

Each row is a map, and its keys are what the title, subtitle and detail fields
name. Give every row a unique `Id` key. Ask the service only for the days in
`context.spans()`, and return only the items `context.wants`:

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

How you count is yours to choose: a totals endpoint, as here; a cached copy;
or counting the items of one fetch with `counter.add(entry.earnedAt)`. If the
service can't help at all, leave `counts` out.

Leave out `opens` here: these items have nothing in Salesforce to open, so
their titles are plain text. They also can't be highlighted or listed in View
all.

##### What `context` gives you

|                                                      |                                                                         |
| ---------------------------------------------------- | ----------------------------------------------------------------------- |
| `recordId`                                           | The record the timeline is on                                           |
| `since`, `until`                                     | The timeline's window. `until` is null for "up to now"                  |
| `spans()`                                            | The days asked for: the window, or the days on screen                   |
| `maxRecords()`                                       | The source's record cap                                                 |
| `plotBy(key).title(…).subtitle(…).opens(…)`          | How the rows are plotted                                                |
| `fieldsToQuery(always)`                              | Record rows: the fields to SELECT                                       |
| `dateCondition(objectType, field, binds)`            | Record rows: the days asked for, as a bound condition                   |
| `wants(dateOrDatetime)`                              | Data from elsewhere: whether the timeline asks for that moment          |
| `countBy(objectType, field, condition, binds, unit)` | Counts of records, grouped by the period in one query                   |
| `counter(unit)`                                      | Counts of items from elsewhere, added one at a time or by the day       |
| `warn(message)`                                      | A note the timeline shows, such as "Couldn't reach the loyalty service" |

##### Good practice

- **Count anything that can grow.** Without `counts`, every timeline load
  reads the source's whole window.
- **Query in user mode** (`AccessLevel.USER_MODE`), so people see only what
  they're allowed to.
- **Cache callouts.** The summary and each page are their own requests. Keep
  what a callout returns in Platform Cache (`TimeDriveCache`) for a while, so
  a page view doesn't call out several times. Set a short callout timeout.
- **Failures are contained.** A class that throws is named on the timeline
  and the other sources still load. A `counts` that throws is read as rows
  instead. Prefer `warn` for problems you expect.

##### Time zones and translations

The timeline shows every date, time and number in the viewer's own time zone,
language and locale. Your rows get the same treatment as Setup's sources, as
long as you hand over real values rather than text:

- **Dates and times.** Give a `Datetime` for a moment and a `Date` for a whole
  day (a day plots at midday, so it stays on its day in every time zone). When
  a service sends times as text, parse them with their zone
  (`2026-10-31T09:00:00Z` or `+11:00`), so they land at the right moment.
- **Numbers and money.** Give numbers as numbers (`Decimal`, `Integer`,
  `Double`), not formatted strings. They show grouped as the viewer's locale
  does (1,200.5 or 1.200,5). A detail field with the Currency format shows in
  the viewer's currency, or in a row's own when it has a `CurrencyIsoCode` key
  (records have it in multi-currency orgs; add it to `always` when you query).
- **Picklists** on records show their labels in the viewer's language.
- **Words you write.** Text in `title` and `subtitle` is shown as you wrote
  it. For translated text, pass a custom label:
  `.title(System.Label.Points_Earned)`, whose text can hold tokens such as
  `{Points}`. A detail field's label can be `$Label.Points` too.
- **Text from elsewhere.** Ask the service for the viewer's language
  (`UserInfo.getLanguage()`, `UserInfo.getLocale()`) where it supports one.

#### Diagnostics

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

#### Scale

The summary counts each source rather than reading it: an aggregate query per Salesforce object (a query row per day, not per record), SQL per Data 360 object, and `counts` for Apex sources. When History and Future make the window too long to count every source by day within 30,000 query rows (`COUNT_ROWS`), it counts by week (from 1 January: the 1st-7th, 8th-14th ...) or by month, and the list shows weeks or months. Rows are read only for the days (or weeks) on screen, and not at all for a busy one (over 50 items), which comes back as grouped counts.

#### Custom Labels

Every string of the timeline (the Time Drive card, its filters, the View all page, record details and error messages) is a custom label (`Time_Drive_*`), in English with Spanish (`es`) and Arabic (`ar`) translations. Navigate to Setup -> Custom Labels to review or add translations for your chosen languages (you will need the Manage Translation permission). Setup's own text is not translated yet.

- `scripts/labels/catalogue.py` is the list: a key, the English, the Spanish and the Arabic. Add or change a string there, then run `python3 -I scripts/labels/generate.py`. It writes `CustomLabels`, the `es` and `ar` translation files and the shared `c/timeDriveLabels` module the components import.
- Fill in `{0}`, `{1}` ... with `format(LABELS.itemsMany, 12)`.
- The translations are drafts: have a native speaker review them. Arabic has singular, dual and plural forms; each count here uses one plural form.
- To see a language, turn on Translation Workbench in the org and add the language, or set a user's language to Spanish or Arabic.
- In Jest the labels read as their English text (`jest-mocks/labelResolver.js`).

#### Sample Data

Cases and Opportunities are plotted from the Contact's real records (cases by `ContactId`; opportunities by `ContactId` or an Opportunity Contact Role). To seed a few on the three Contacts with the most cases:

```
sf apex run --file scripts/apex/seed-timeline-samples.apex --target-org <alias>
```

Every seeded record's Description starts with `[Timeline sample]`.

To see a long quiet stretch, `scripts/apex/seed-two-year-sample.apex` adds a Contact, **Riley Span**, with two tasks two years apart (tagged `[Two-year sample]`). Set History to 2 years or more to plot the older one.

## FAQs

#### How do I choose the fields an opened item shows?

In Time Drive Setup, on each source's detail fields step. They are saved as **Time Drive Detail Field** records, in order. Time Drive doesn't use compact layouts.

#### Does it support multiple languages other than English?

Yes - Supports a user's locale, language and time zone, and has custom labels for translation available. Default translations are available for Spanish and Arabic, and right-to-left languages mirror the card. Setup's own text is English for now.

#### Does it support Mobile?

Yes. In the Salesforce mobile app on a phone the card is the vertical list, fitted to the screen, with larger tap targets and a one-line header.

#### Does it support Person Accounts?

Yes. A person account's page plots the account's records and its own Contact's.

#### Does it support Files?

Yes. Files linked to the record (ContentDocumentLink) can be a source; a click opens the file preview.

#### Does it support Junction Objects?

Yes. Setup offers junction objects such as TaskRelation and OpportunityContactRole, with the related record's fields by path.

#### Does it support Data 360?

Yes, in orgs with Data 360 provisioned. Engagement DMOs are matched to the person through identity resolution. Deploy `force-app-data360` as well so they are counted rather than read.

#### Can it plot data from outside Salesforce?

Yes, with an Apex source: a class extending `TimeDriveApexSource` that returns rows for the days asked for and, ideally, counts for the summary. See [Writing an Apex Source](#writing-an-apex-source).

#### How far back can it go?

Up to ten years back and ten ahead, set by the History and Future properties. Each source can look back less far than the timeline does.

#### Why does the timeline say "only 1000 items are plotted (its Max Records)"?

That source is read rather than counted, and it reached its Max Records. Salesforce and Data 360 sources count; an Apex source counts when its class implements `counts`.

## Contributing

Contributions are what make the trailblazer community such an amazing place. I regard this component as a way to inspire and learn from others. Any contributions you make are **greatly appreciated**.

See [contributing.md](/contributing.md) for Time Drive principles, and [changelog.md](/changelog.md) for what changed in each version.

## Utilities and Dependencies

#### Dependencies

- None. Time Drive uses no third-party JavaScript libraries.

#### Code formatting

[Prettier](https://prettier.io/) is a code formatter used to ensure consistent formatting across your code base. To use Prettier with Visual Studio Code, install [this extension](https://marketplace.visualstudio.com/items?itemName=esbenp.prettier-vscode) from the Visual Studio Code Marketplace. The [.prettierignore](/.prettierignore) and [.prettierrc](/.prettierrc) files are provided as part of this repository to control the behavior of the Prettier formatter. Run `npm run prettier` to format, or `npm run prettier:verify` to check.

#### Code linting

[ESLint](https://eslint.org/) is a popular JavaScript linting tool used to identify stylistic errors and erroneous constructs. To use ESLint with Visual Studio Code, install [this extension](https://marketplace.visualstudio.com/items?itemName=salesforce.salesforcedx-vscode-lwc) from the Visual Studio Code Marketplace. The [eslint.config.js](/eslint.config.js) file is provided as part of this repository. Run `npm run lint`.

#### Code quality

[Salesforce Code Analyzer](https://developer.salesforce.com/docs/platform/salesforce-code-analyzer/guide/code-analyzer.html) scans Apex, LWC and stylesheets for security, performance and best practice issues (PMD, ESLint, CPD, RetireJS and the SLDS rules). The [code-analyzer.yml](/code-analyzer.yml) file is provided as part of this repository. Run `sf code-analyzer run --rule-selector Recommended`.

#### Tests

LWC tests run with Jest (`npm run test:unit`). Apex tests are the `TimeDrive*Test` classes; run them in an org with `sf apex run test --test-level RunLocalTests --code-coverage`. Coverage is kept at 85% or more.
