# Change Log

## 1 Nov 2026 v0.1.0

**WHAT'S NEW**

- First version of Time Drive for Contact, Account and person account record pages, on Salesforce API v67.0
- Added vertical and horizontal layouts, with a scrub tab and seek bar over the whole history, and a phone layout in the Salesforce mobile app
- Added sources for any standard or custom object linked by a lookup or a junction (TaskRelation, OpportunityContactRole), Files included
- Added Data 360 engagement sources (email, messaging, web, search, app and cart DMOs), matched through identity resolution and counted in Data 360 SQL
- Added Apex sources: classes extend TimeDriveApexSource, return rows for the days asked for and count for the summary with countBy or counter
- Added the Opportunity Products example Apex source (Account › Opportunity › Opportunity Product)
- Added Time Drive Setup: a guided wizard, Fit to your org, lenses, detail fields, a filter builder, an org check and diagnostics
- Added lenses, with All as a lens and the filter each source applies shown on the Lenses page
- Added the Overdue formula checkbox on Activity (an open task due before today), highlighted on Tasks and used by the Overdue lens, and escalated highlights for Cases
- Added a second subtitle field, read after a dot; Tasks, Calls and Events show Assigned To · Related To
- Added links on an opened item's details that name a record (Related To, an Account), and Plot.links for Apex sources
- Added the Lenses page property: the lenses a page offers (All items and Overdue always)
- Added highlights for Apex sources (a checkbox field or a map key), and readable DayCount fields for Apex sources' own tests
- Documented that an org's own Apex sources are global and name the package's types with drvrckt. (a public class can't be seen from the package)
- Long text is shortened on the timeline (details 500 characters, titles and subtitles 150) and rich text shows as plain words
- Each lens keeps its own filter (the event types hidden in it), as a list view does
- An opened item's footer says where it's from the same way for every source: Salesforce · object, Data 360 · DMO, Apex · source name
- Email tasks' subtitle is Assigned To · Related To, as for tasks, calls and events
- The shipped sources are named by page and kind (Contact_Tasks, Account_Calls_Shared, Person_Overdue_Tasks), with _Shared for the Shared Activities versions; the Org Fit field is gone
- Lenses are listed All, then Overdue, then the rest alphabetically by their label
- Tasks, calls, emails and events are in the Sales, Service and Marketing lenses; Commerce and Digital start switched off
- The Filters panel's Back and Ahead are lightning-select base components
- Opening Filters no longer makes a horizontal timeline a pixel or two taller
- A source that can't be read shows the timeline's error page (naming it, with Try again) rather than a notice above the rest
- A source that counts but whose rows can't be read is reported the same way, rather than its items quietly missing
- The error and empty pages are as tall as the timeline was with items
- Problems are logged (Time Drive Log): one row per distinct problem, its count and when it was last seen, kept 30 days and never with record data; Guided setup lists them with the likely cause, a link to the source, and Clear
- A source someone can't see (its object, date field or a filter field unreadable to them) is left out of their timeline, and a field they can't read shows blank: neither is an error, and the source left out is logged, so admins can see why items are missing
- fieldsToQuery(objectType, always), for Apex sources: leaves out fields the user can't read
- The Time Drive Setup permission set includes the timeline itself, so admins need only it; Time Drive reads its own setup, so people need no access to it
- The Filters panel is a sheet inside the card, under its header and as tall as the timeline: at the card's end with the event types in up to three columns on a wide card, over the whole timeline in one column on a narrow one
- Added the Overdue lens, defined by its sources' filters, with an Overdue button in the header while the record has something overdue
- Added Edit and Delete from each item's menu
- Added View all for a busy day's grouped Salesforce items, paged as you scroll
- Added support for opening records in a new workspace tab in Console apps
- Added translatable custom labels for every timeline string, with Spanish and Arabic translations
- Added locale support for numbers and money (each record's own currency in multi-currency orgs), translated picklist labels, and $Label names for detail field labels
- Added right-to-left support for Arabic, Hebrew, Farsi and Urdu
- Performance improvements counting each source instead of reading it, so the summary covers up to ten years
- Performance improvements reading rows only for the days on screen, and grouping busy days from their counts
- Performance improvements keeping identity lookups and configuration in Platform Cache
- Each user's lens and item detail choice is kept for them in the org

**BUG FIXES**

- Fixed removed detail fields being kept when a source was saved
- Fixed Profile and Contact Point DMOs being offered as engagement sources
- Fixed Fit to your org switching on overlapping variants of the same source when run again
- Fixed lookup labels showing the " ID" that Apex adds
- Fixed Setup popups opening under the content that follows them
- Fixed delete giving no feedback while it ran
