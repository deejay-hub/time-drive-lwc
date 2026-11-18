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
