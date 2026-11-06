# FAQs

Short answers to the questions admins and developers ask most. The [Config Guide](config-guide.md) has the detail.

## Getting started

### What do I need before I start?

The **Customize Application** permission, to add and change sources. Assign the `Time Drive` permission set to people who see the timeline, and `Time Drive Setup` to admins who manage it. Data 360 is optional. See [Before you start](config-guide.md#before-you-start).

### Which record pages does it work on?

Contact, Account and Lead record pages, person accounts included. A person account's page plots the account's records and its own Contact's.

### Who can use Time Drive Setup?

Admins with the **Customize Application** permission and the `Time Drive Setup` permission set. Everyone else sees the timeline on record pages.

### How do I put the timeline on a record page?

Open a record, choose **Edit Page**, and drag **Time Drive** (under custom components) onto the page. Its properties in Lightning App Builder set the layout, the lens it opens on, how far back and ahead it looks, and the activity actions it shows. See [Add the timeline to a page](config-guide.md#add-the-timeline-to-a-page).

### Can I put more than one timeline on a page?

Yes, each with its own properties, such as a horizontal one in the main column and a vertical one in the sidebar. The lens and date range a person chooses are remembered for them, not for each timeline, so every timeline opens with their last choice.

## Sources

### What is a source?

One kind of item the timeline plots: an object, how it links to the page's record, the date that places each item, what each item says, and the lenses it's in. Each source is a **Time Drive Source** custom metadata record, and the setup wizard writes it for you.

### Why does saving take a few seconds?

Sources are custom metadata, so saving one deploys it. The wizard tells you when it's done.

### How do I show only some records, such as closed cases?

On the wizard's **Records** step, choose **Only some** and add conditions, matching all of them or any of them. Picklists offer "is one of". The conditions are saved as the source's filter, which you can also edit by hand.

### When should I use a junction object?

When the records you want aren't linked to the page's record directly, or can be linked to several records: a Contact's cases through Case Contact Role, opportunities through Opportunity Contact Role, campaigns through Campaign Member. On the **Records** step, choose the option that goes **through** the junction. See [A junction object](config-guide.md#a-junction-object).

### Can I plot a custom object?

Yes. Choose **A custom object** on the wizard's first step. Any custom object with a lookup to the page's record, or linked through another object, is listed.

### How do I choose the fields an opened item shows?

On the wizard's **Interactions** step: add the fields, in order, and how each is formatted. They're saved as **Time Drive Detail Field** records. Time Drive doesn't use compact layouts. See [Expanding records](config-guide.md#expanding-records).

### What does Check your org (Fit to your org) do?

It checks how your org works (Shared Activities, contacts to multiple accounts, person accounts, Enhanced Email, Data 360) and switches on the shipped sources that suit it. Alternatives share a group, and only one in a group is ever active, so running it again never plots the same record twice. See [Fit to your org](config-guide.md#fit-to-your-org).

### Why don't an account's shared activities show?

With Shared Activities, an activity shared with a second contact carries another account's Id, so it isn't on this account's `Task.AccountId`. Run **Check your org**: it switches the activity sources to the variants that read through TaskRelation and EventRelation.

### How do lenses work?

A lens narrows the timeline to one area, such as Sales or Service. Each source is in one or more lenses, set in the wizard or on **Time Drive Setup > Lenses**. People pick a lens from the timeline's heading, and Time Drive remembers it for them. Leave a source out of **All items** to show it only in the lenses you choose.

### Can I move sources from a sandbox to production?

Yes. Sources, their detail fields and lenses are custom metadata records (`Time_Drive_Source__mdt`, `Time_Drive_Detail_Field__mdt`, `Time_Drive_View__mdt`), so they deploy with change sets, the Salesforce CLI or your pipeline like any other metadata.

## Using the timeline

### Will people see records they can't access?

No. Every query runs as the person looking, with their sharing and field access. An Edit or Delete in an item's menu is offered only when they may.

### Why do some days show a grouped row instead of the items?

A day with more than 50 items of a type shows one grouped row for that type, with its count, so busy days stay readable and fast. For Salesforce sources, its title opens **View all**: every item behind it, as a list that loads as you scroll.

### Can people see less than the page's date range?

Yes. Unless the admin turns off **Let People Narrow the Date Range**, Filters offers **Back** and **Ahead**: how far either side of today to show, each up to the page's History or Future. The choice is remembered for each person and shows in the header. Nobody can widen the range past what the admin set.

### Does it work on mobile?

Yes. In the Salesforce mobile app on a phone the timeline is the vertical list, fitted to the screen, with larger tap targets and a one-line header. It starts with titles only.

### Does it support Files?

Yes. Files linked to the record (ContentDocumentLink) can be a source, and a click opens the file preview.

## Languages

### Which languages does it come in?

English, Spanish, Arabic, Danish, Finnish, French, German, Japanese, Korean, Swedish, Yiddish, and Chinese Simplified and Traditional. Dates, times and numbers follow each person's locale and time zone, and right-to-left languages mirror the card. Setup's own text is English for now. The translations are drafts: have a native speaker review them. See [Translations](config-guide.md#translations).

### Why are some names still in English?

Make the language **Active** in Setup > **Translation Language Settings**. The timeline's own labels show their translation either way, but Salesforce only translates the labels that Apex reads once the language is Active: warnings, Yes and No, and any `$Label` you use in a source's name. Field and picklist names need it too.

## Performance

### How far back can it go?

Up to ten years back and ten ahead, set by the History and Future properties. Each source can look back less far than the timeline does.

### Will a record with a huge history be slow?

No. The timeline counts each source first, with an aggregate query, and reads only the items for the days on screen. A busy day comes back as grouped counts rather than being read. So a record with a million items opens about as fast as one with a hundred. See [Scale](config-guide.md#scale).

### Why does the timeline say only some items are plotted (its Max Records)?

That source is read rather than counted, and it reached its Max Records (1,000 by default). Salesforce and Data 360 sources count. An Apex source counts when its class implements `counts`.

### Why is a timeline slow?

Open **Time Drive Setup > Diagnostics**, enter the record's Id, and look at the **Performance** tab. It splits the wait into server, network and browser time, and lists every query with how long it took. See [Diagnostics](config-guide.md#diagnostics).

## Data 360

### Does it support Data 360?

Yes, in orgs with Data 360. Each engagement DMO is its own source, matched to the person through identity resolution: Time Drive finds the Contact's unified profile, then reads the engagement of every individual in it. Set the identity link object in **Time Drive Setting > Default**, and deploy `force-app-data360` too, so DMOs are counted rather than read. See [Data 360 sources](config-guide.md#data-360-sources).

## For developers

### Can it plot data from outside Salesforce, or records further away?

Yes, with an Apex source: a class extending `TimeDriveApexSource`. Its `rows` method returns the items for the days asked for, and it says how they're dated and titled with `context.plotBy(...)`. Then add it in the wizard as **An Apex class**. `TimeDriveOpportunityProducts` is the shipped example. See [Apex sources](config-guide.md#apex-sources).

### Does my Apex source need to implement counts?

If its data can grow, yes. With `counts`, the summary takes only your counts, and the timeline reads rows just for the days on screen. Without it, every load reads the source's whole window up to its Max Records. Use `context.countBy(...)` for records, or `context.counter(unit)` for data from elsewhere.

### What happens if my Apex source fails?

The timeline names the source as one it couldn't read, and the other sources still load. If `counts` throws, the source is read as rows instead. For problems you expect, such as a service being down, call `context.warn(...)` to show a note instead of failing.

---

Can't find your question? Read the [Config Guide](config-guide.md).
