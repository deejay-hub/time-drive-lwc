# FAQs

## Who can use Time Drive Setup?

Admins with the **Customize Application** permission. Everyone else sees the timeline on record pages.

## Will people see records they can't access?

No. Every query runs as the person looking.

## Why does saving take a few seconds?

Sources are custom metadata, so saving deploys them. See [Add a source](config-guide.md#add-a-source) in the Config Guide.

## How do I choose the fields an opened item shows?

In Time Drive Setup, on each source's detail fields step. They're saved as **Time Drive Detail Field** records, in order. Time Drive doesn't use compact layouts. See [Expanding records](config-guide.md#expanding-records).

## Does it support languages other than English?

Yes. It follows each user's locale, language and time zone, and every timeline string is a custom label you can translate. Spanish and Arabic translations come with it, and right-to-left languages mirror the card. Setup's own text is English for now. See [Translations](config-guide.md#translations).

## Does it support mobile?

Yes. In the Salesforce mobile app on a phone the card is the vertical list, fitted to the screen, with larger tap targets and a one-line header.

## Does it support person accounts?

Yes. A person account's page plots the account's records and its own Contact's.

## Does it support Files?

Yes. Files linked to the record (ContentDocumentLink) can be a source, and a click opens the file preview.

## Does it support junction objects?

Yes. Setup offers junction objects such as TaskRelation and OpportunityContactRole, with the related record's fields by path.

## Why don't an account's shared activities show?

With Shared Activities, an activity shared with a second contact carries another account's Id, so it isn't on this account's `Task.AccountId`. Run **Fit to your org**: it switches the activity sources to the variants that read through TaskRelation and EventRelation. See [Fit to your org](config-guide.md#fit-to-your-org).

## Does it support Data 360?

Yes, in orgs with Data 360 provisioned. Engagement DMOs are matched to the person through identity resolution. Deploy `force-app-data360` as well, so they're counted rather than read. See [Data 360 sources](config-guide.md#data-360-sources).

## Can it plot data from outside Salesforce?

Yes, with an Apex source: a class extending `TimeDriveApexSource` that returns rows for the days asked for and, ideally, counts for the summary. See [Apex sources](config-guide.md#apex-sources).

## How far back can it go?

Up to ten years back and ten ahead, set by the History and Future properties. Each source can look back less far than the timeline does.

## Why does the timeline say only some items are plotted (its Max Records)?

That source is read rather than counted, and it reached its Max Records. Salesforce and Data 360 sources count; an Apex source counts when its class implements `counts`. See [Scale](config-guide.md#scale).

## Why is a timeline slow?

Open **Time Drive Setup > Diagnostics**, enter the record's Id, and look at the Performance tab. It splits the wait into server, network and browser time, and lists every query with how long it took. See [Diagnostics](config-guide.md#diagnostics).
