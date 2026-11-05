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
	A customer's engagement in time order, on any Contact, Account or Lead page<br><br>
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

A Lightning web component for **Contact**, **Account**, person account and **Lead** record pages that shows a customer's engagement in time order: tasks, calls, emails, events, cases, opportunities and any other Salesforce object, alongside digital engagement from the standard Data 360 engagement data model objects (DMOs).

- **Any object.** Plot standard and custom objects linked to the page by a lookup or a junction (TaskRelation, OpportunityContactRole), Files included.
- **Data 360 engagement.** Email, messaging, web, search, app and cart engagement DMOs, matched to the person through identity resolution.
- **Apex sources.** Bring in records further away or data from another system with a small class that counts and returns rows.
- **Built to scale.** The summary counts each source instead of reading it, rows load only for the days on screen, and busy days fold into one grouped row with View all.
- **Vertical and horizontal layouts.** A scrub tab or seek bar over the whole history, up to ten years each way, and a phone layout in the Salesforce mobile app.
- **Guided setup.** Time Drive Setup adds sources step by step, fits the timeline to your org, and has lenses, detail fields and diagnostics.
- **Multi language support.** Every string is a custom label (English, Spanish, Arabic, French, German, Japanese, and Chinese Simplified and Traditional); dates, numbers and money follow the user's locale and time zone; right-to-left languages mirror the card.
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

Time Drive plots whatever its **sources** say. Each source returns rows (Salesforce records linked by a lookup or a junction, a Data 360 engagement DMO, or your own Apex class), and the timeline plots them all the same way. Time Drive Setup adds sources step by step, fits them to your org and groups them into lenses.

It's built for long, busy histories. The summary counts each source rather than reading it, rows load only for the days on screen, and a busy day folds into one grouped row.

The [Config Guide](docs/config-guide.md) covers it all. It's also the guide Time Drive Setup shows in the app.

- [Add the timeline to a page](docs/config-guide.md#add-the-timeline-to-a-page): the App Builder properties
- [Add a source](docs/config-guide.md#add-a-source), [Fit to your org](docs/config-guide.md#fit-to-your-org) and [Lenses](docs/config-guide.md#lenses)
- [Source fields](docs/config-guide.md#source-fields) and [Expanding records](docs/config-guide.md#expanding-records)
- [Data 360 sources](docs/config-guide.md#data-360-sources)
- [Apex sources](docs/config-guide.md#apex-sources): records further away, or data from another system
- [How people use the timeline](docs/config-guide.md#how-people-use-the-timeline): layouts, long histories, language and direction
- [Scale](docs/config-guide.md#scale), [Diagnostics](docs/config-guide.md#diagnostics), [Translations](docs/config-guide.md#translations) and [Sample data](docs/config-guide.md#sample-data)

## FAQs

Answers to common questions, from who can use Setup to why a timeline is slow, are in the [FAQs](docs/faqs.md).

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
