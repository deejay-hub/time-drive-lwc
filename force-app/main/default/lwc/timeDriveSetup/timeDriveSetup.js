import { LightningElement, wire } from "lwc";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import TimeDriveConfirm from "c/timeDriveConfirm";
import TimeDriveOrgCheck from "c/timeDriveOrgCheck";
import { loadStyle } from "lightning/platformResourceLoader";
import FONTS from "@salesforce/resourceUrl/timeDriveSetupFonts";
import ASSETS from "@salesforce/resourceUrl/timeDriveAssets";
import getProgress from "@salesforce/apex/TimeDriveSetupController.getProgress";
import saveProgress from "@salesforce/apex/TimeDriveSetupController.saveProgress";
import getSources from "@salesforce/apex/TimeDriveSetupController.getSources";
import getSource from "@salesforce/apex/TimeDriveSetupController.getSource";
import getObjects from "@salesforce/apex/TimeDriveSetupController.getObjects";
import getDataSpaces from "@salesforce/apex/TimeDriveSetupController.getDataSpaces";
import getData360Status from "@salesforce/apex/TimeDriveSetupController.getData360Status";
import getApexProviders from "@salesforce/apex/TimeDriveSetupController.getApexProviders";
import getLinks from "@salesforce/apex/TimeDriveSetupController.getLinks";
import getFields from "@salesforce/apex/TimeDriveSetupController.getFields";
import getTemplates from "@salesforce/apex/TimeDriveSetupController.getTemplates";
import applyTemplate from "@salesforce/apex/TimeDriveSetupController.useTemplate";
import getLabelText from "@salesforce/apex/TimeDriveSetupController.getLabelText";
import getViewDrafts from "@salesforce/apex/TimeDriveSetupController.getViewDrafts";
import saveViews from "@salesforce/apex/TimeDriveSetupController.saveViews";
import getVolumes from "@salesforce/apex/TimeDriveSetupController.getVolumes";
import saveDraft from "@salesforce/apex/TimeDriveSetupController.save";
import setSourceActive from "@salesforce/apex/TimeDriveSetupController.setActive";
import removeSource from "@salesforce/apex/TimeDriveSetupController.remove";
import setSourceLenses from "@salesforce/apex/TimeDriveSetupController.setLenses";
import { describeError, fitIllustrations, illustrationName } from "c/timeDriveErrors";
import { lookupLabel, lookupTarget } from "c/timeDriveFieldPicker";
import { ICON_SETS } from "./iconCatalog";
import { PALETTE } from "./colourPalette";

/**
 * The Time Drive Setup app, as a small help-desk style site: a home page (what
 * it does, the timelines at a glance, how it works), the record pages to choose from, each record page's
 * sources as a plain list (made active or inactive in place), each source its own
 * page, and adding or editing one as a sub page that asks one question at a
 * time. A breadcrumb says where you are; in a source's steps, a thread of
 * knots (filled with each answer) goes back or forward, and the last step
 * sums the answers up. Saving deploys custom metadata, so it takes a few
 * seconds; the result arrives as a platform event.
 */

// The legend order's stand-in for the source being set up (it may have no
// name yet); the controller places it.
const THIS_SOURCE = "__this__";
// A legend name that's a custom label: $Label.Timeline_Follow_ups.
const LABEL_PREFIX = "$Label.";
// A legend name that is another object's (translated) name: $Object.Task.
const OBJECT_PREFIX = "$Object.";
// Objects whose own name says little, and the custom label a source of theirs
// starts out named with (see TimeDriveConfig.DEFAULT_LEGEND_LABELS).
const DEFAULT_LEGEND_LABELS = {
  contentdocumentlink: "Time_Drive_Legend_Files",
  emailmessage: "Time_Drive_Legend_Emails"
};
// A Task filtered to one kind of activity starts on that kind's label.
const TASK_SUBTYPE_LEGENDS = { call: "Time_Drive_Legend_Calls", email: "Time_Drive_Legend_Emails" };
// The filter builder's last field choice: one on a related record, picked object first.
const RELATED_FIELD = "__related__";
// A lookup row in the date list (it leads on to the related record's dates).
const LOOKUP_ROW = "__lookup__:";
const DATE_TYPES = ["date", "datetime"];
// A new source's colour until one is picked: SLDS Blue 30.
const DEFAULT_COLOUR = "#014486";
// Sample record names for the previews, by object.
const SAMPLE_NAMES = {
  Account: "Acme Ltd",
  Campaign: "Summer Launch 2026",
  Case: "Can't sign in to the portal",
  Contact: "Sam Lee",
  Lead: "Alex Morgan",
  Opportunity: "Acme renewal 2026",
  Order: "00001042",
  Product2: "Trail Runner 2",
  Asset: "Trail Runner 2 · Size 9",
  default: "Sample record"
};
// WCAG 2.2 non-text contrast (1.4.11): the white icon on its colour.
const MIN_CONTRAST = 3;
// How long reading an object (its fields and links) may take before the step says so.
const SCHEMA_PATIENCE = 20000;
// Results a search list renders at once; typing narrows the rest.
const RESULTS_SHOWN = 50;

const KINDS = [
  {
    value: "standard",
    label: "A standard object",
    slot: "a standard object",
    detail: "Objects Salesforce comes with, like Cases, Opportunities or Tasks.",
    icon: "utility:standard_objects"
  },
  {
    value: "custom",
    label: "A custom object",
    slot: "a custom object",
    detail: "Objects your org added, like Memo__c or Log__c.",
    icon: "utility:custom_apps"
  },
  {
    value: "dmo",
    label: "A Data 360 DMO",
    slot: "a Data 360 DMO",
    detail: "Engagement from a Data 360 data model object (DMO), like email opens or website visits.",
    icon: "utility:data_cloud"
  },
  {
    value: "apex",
    label: "An Apex class",
    slot: "an Apex class",
    detail: "Code that returns the items to plot.",
    icon: "utility:apex"
  }
];
// The record pages the timeline can sit on. Person Account shows once the
// timeline uses Person Accounts (see pages).
const PARENTS = [
  {
    value: "Contact",
    label: "Contact",
    detail: "Time Drive on Contact record pages.",
    icon: "utility:people"
  },
  {
    value: "Account",
    label: "Account",
    detail: "The timeline on business Account record pages.",
    icon: "utility:company"
  },
  {
    // An Account with its own Contact: its records link by either.
    value: "PersonAccount",
    label: "Person Account",
    detail: "The timeline on person account pages. Records link by the Account or its Contact.",
    icon: "utility:user"
  },
  {
    value: "Lead",
    label: "Lead",
    detail: "Time Drive on Lead record pages.",
    icon: "utility:lead"
  }
];

// The home page's groups: a source's type.
const TYPES = [
  { value: "standard", label: "Standard objects", short: "Standard", icon: "utility:standard_objects" },
  { value: "custom", label: "Custom objects", short: "Custom", icon: "utility:custom_apps" },
  { value: "dmo", label: "Data 360 DMOs", short: "Data 360 DMO", icon: "utility:data_cloud" },
  { value: "apex", label: "Apex classes", short: "Apex", icon: "utility:apex" }
];
// The loading mark stays at least this long, so it reads as a moment
// rather than a flicker.

// How far back is the record page's History (App Builder); a source's own
// shorter history, where it has one, is kept as it was saved.
const FLOWS = {
  // Salesforce objects choose how they link on the same screen as the object.
  standard: ["parent", "kind", "object", "date", "lenses", "name", "look", "open"],
  custom: ["parent", "kind", "object", "date", "lenses", "name", "look", "open"],
  dmo: ["parent", "kind", "object", "date", "lenses", "name", "look", "open"],
  // An Apex class says itself which record an item opens.
  apex: ["parent", "kind", "apex", "lenses", "name", "look", "open"]
};
// The how-to video, on YouTube. Blank until it's published: Watch video then
// says it's on its way instead of opening a broken link.
const HOW_TO_VIDEO_URL = "";

// The Setup page: a guided checklist. Steps Setup can see for itself tick
// themselves off; the rest have "I am done with this step", remembered for
// the org (Time Drive Setup). The panel beside the steps says what each does and why.
const GUIDED_STEPS = [
  {
    key: "orgcheck",
    manual: true,
    auto: true,
    title: "Check your org",
    text: "Time Drive looks at how your org works, tells you what it found and adds the sources that suit.",
    what: "Runs a few quick checks: Shared Activities, Contacts to Multiple Accounts, Person Accounts, Enhanced Email and Einstein Activity Capture. It explains what each means for the timeline, then adds the recommended sources.",
    why: "The right sources depend on how your org works. With Shared Activities on, a task belongs to every contact on it, so the timeline needs the sources that follow that. The other pages open once this is done."
  },
  {
    key: "video",
    manual: true,
    title: "Watch the how-to video",
    text: "A short walk through setting up a timeline, start to finish.",
    what: "Plays the how-to video on YouTube, in a new tab.",
    why: "It shows the whole flow once, so each step here makes sense before you start."
  },
  {
    key: "perms",
    manual: true,
    title: "Assign the included permission sets",
    text: "Give Time Drive to the people who use the timeline, and Time Drive Setup to the admins who manage it.",
    what: "Opens permission sets in Setup. Open each one, choose Manage Assignments, then add the users. Both permission sets come with the timeline.",
    why: "Without Time Drive, the component can't load its items and the timeline stays empty. Time Drive Setup opens this tab for other admins."
  },
  {
    key: "views",
    manual: true,
    title: "Review the categories for your lenses",
    text: "Have you reviewed the categories for your lenses?",
    what: "Opens Lenses: each lens's name (a custom label you can translate), the sources in it, and whether the timeline's picker offers it.",
    why: "People pick a lens to see only some of a record's items, like Service. Putting each source in the right lens, and offering only the lenses your org uses, keeps the picker short and useful.",
    checkLabel: "I have reviewed my lenses"
  },
  {
    key: "review",
    manual: true,
    title: "Review what's set up",
    text: "See every record page's sources in Customize: what each plots, and whether it's active.",
    what: "Opens Customize: each record page (Contact, Account, Person Account) and the sources already on its timeline.",
    why: "The timeline comes with a source or two. Knowing what's there tells you what to add, change or make inactive."
  },
  {
    key: "users",
    manual: true,
    title: "Check your users can read the records",
    text: "People see only the records and fields they can read.",
    what: "Opens permission sets in Setup. Make sure the people who use the timeline can read the objects and fields your sources use.",
    why: "Every query runs as the person looking. A source they can't read is left off their timeline and named, and the rest still loads."
  },
  {
    key: "page",
    manual: true,
    title: "Put the timeline on your record pages",
    text: "Add the Time Drive component to each record page that has sources, in Lightning App Builder.",
    what: "Opens the object's Lightning record pages in Setup. Edit the page, drag Time Drive onto it, then save and activate. Person accounts use Account's pages.",
    why: "Sources decide what the timeline shows; the record page decides where people see it. Without the component, nothing appears."
  }
];
// An Email Message's subtitle, as the timeline writes it: the format, and a sample.
const EMAIL_SUBTITLE = "Sent to: first recipient and N others";
const EMAIL_SAMPLE_SUBTITLE = "Sent to: Ada Park and 1 other";

// The Docs live in the GitHub repo: the Docs page links to them there (a new
// tab), so nothing is fetched into the org. Change the repo here.
const DOCS_SOURCE = { owner: "deejay-hub", repo: "time-drive-lwc", ref: "main", path: "docs" };
const DOCS_WEB = `https://github.com/${DOCS_SOURCE.owner}/${DOCS_SOURCE.repo}/blob/${DOCS_SOURCE.ref}/${DOCS_SOURCE.path}/`;
const DOCS = [
  {
    key: "guide",
    file: "config-guide.md",
    title: "Config Guide",
    icon: "utility:knowledge_base",
    summary: "Set up Time Drive from start to finish: permissions, record pages, sources, Data 360 and Apex."
  },
  {
    key: "faqs",
    file: "faqs.md",
    title: "FAQs",
    icon: "utility:question",
    summary: "Short answers to the questions admins ask most about the timeline and its sources."
  }
];

// Each step's name on the thread.
const STEP_NAMES = {
  parent: "Record page",
  kind: "Source",
  object: "Records",
  apex: "Class",
  date: "Date",
  lenses: "Lenses",
  range: "History",
  name: "Name",
  look: "Words and style",
  open: "Interactions"
};
const QUESTIONS = {
  parent: "Which records will the timeline sit on?",
  kind: "Where are the related records being sourced?",
  object: "Which object should we use?",
  apex: "Which Apex class returns the items?",
  date: "Which date should we use to determine where to plot the records on a timeline?",
  lenses: "Which lenses should it be part of?",
  range: "How far back should it look?",
  name: "How should we name the object in the filter?",
  look: "Pick an icon and a colour",
  open: "What shows when someone opens an item?"
};

// How far back a source looks; null is as far as the timeline goes.
const RANGES = [
  { months: 3, label: "3 months", slot: "the last 3 months" },
  { months: 6, label: "6 months", slot: "the last 6 months" },
  { months: 12, label: "1 year", slot: "the last year" },
  { months: 24, label: "2 years", slot: "the last 2 years" },
  { months: 60, label: "5 years", slot: "the last 5 years" },
  { months: null, label: "As far as the timeline goes", slot: "any time" }
];

// The views until Time Drive View's arrive.
const FORMATS = ["Text", "Date", "Date/Time", "Currency", "Number"].map((f) => ({ label: f, value: f }));

const OBJECT_ICONS = {
  case: "utility:case",
  opportunity: "utility:opportunity",
  task: "utility:task",
  event: "utility:event",
  order: "utility:orders",
  emailmessage: "utility:email",
  campaignmember: "utility:announcement",
  asset: "utility:package"
};
// Icons a search list shows at once; Show more adds as many again.
const ICONS_SHOWN = 120;

// The whole SLDS catalog, parsed once on first use: "utility:email" with
// what to search for it by.
let catalog;
function iconCatalog() {
  if (!catalog) {
    catalog = ICON_SETS.flatMap((set) =>
      set.packed.split(";").map((entry) => {
        const [name, synonyms = ""] = entry.split("|");
        return { set: set.key, name: `${set.key}:${name}`, words: `${name.replace(/_/g, " ")} ${synonyms}` };
      })
    );
  }
  return catalog;
}

// A colour's contrast with the timeline's white icons (WCAG relative
// luminance); under 3 the icon is hard to see.
function contrastWithWhite(hex) {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex ?? "");
  if (!m) return 21;
  const channel = (i) => {
    const c = parseInt(m[1].slice(i, i + 2), 16) / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  };
  const luminance = 0.2126 * channel(0) + 0.7152 * channel(2) + 0.0722 * channel(4);
  return 1.05 / (luminance + 0.05);
}

// The colours the Look step offered before the SLDS palette, by name, so
// sources that use them still read as words.
const EARLIER_COLOURS = {
  "#2F7D4F": "Green",
  "#1F7A8C": "Teal",
  "#2F6FB0": "Blue",
  "#5B5FC7": "Indigo",
  "#E5532F": "Flame",
  "#C62F2F": "Red",
  "#B07A0C": "Amber",
  "#5C5C5C": "Grey"
};

// "Blue 40" for a palette colour, an earlier colour's name, else its hex.
function colourName(hex) {
  const value = (hex ?? "").toUpperCase();
  if (EARLIER_COLOURS[value]) return EARLIER_COLOURS[value];
  for (const row of PALETTE) {
    const found = row.shades.find((sh) => sh.value === value);
    if (found) return `${row.hue} ${found.shade}`;
  }
  return value || null;
}

// The object whose icon and colour a source's items wear. A junction stands for
// the record it joins (a TaskRelation is a Task), so it takes that record's.
const THEME_OBJECTS = {
  taskrelation: "Task",
  taskwhorelation: "Task",
  eventrelation: "Event",
  eventwhorelation: "Event",
  campaignmember: "Campaign",
  opportunitycontactrole: "Opportunity",
  caserelatedissue: "Case",
  changerequestrelatedissue: "ChangeRequest",
  maintenanceasset: "MaintenancePlan"
};
// Where Salesforce has no theme to give the link itself: a file wears its document's
// (standard:file, 939393, as ContentDocument's object info reports).
const THEME_FALLBACKS = { contentdocumentlink: { icon: "standard:file", colour: "#939393" } };

// "standard:case" from the icon address Salesforce gives an object
// (.../img/icon/t4v35/standard/case_120.png).
function themeIconName(iconUrl) {
  const m = /\/img\/icon\/[^/]+\/(standard|custom|action|doctype|utility)\/([a-z0-9_]+?)(?:_\d+)?\.(?:png|svg)/i.exec(
    iconUrl ?? ""
  );
  return m ? `${m[1]}:${m[2]}`.toLowerCase() : null;
}

let catalogNames;
function inCatalog(name) {
  if (!catalogNames) catalogNames = new Set(iconCatalog().map((i) => i.name));
  return catalogNames.has(name);
}

// A colour, darkened a step at a time until the timeline's white icon can be
// seen on it (WCAG 3:1), as Setup requires; one that already can is left as it is.
function accessibleColour(hex) {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex ?? "");
  if (!m) return null;
  let value = `#${m[1].toUpperCase()}`;
  if (contrastWithWhite(value) >= MIN_CONTRAST) return value;
  const r = parseInt(m[1].slice(0, 2), 16) / 255;
  const g = parseInt(m[1].slice(2, 4), 16) / 255;
  const b = parseInt(m[1].slice(4, 6), 16) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  let l = (max + min) / 2;
  const d = max - min;
  const sat = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1));
  let hue = 0;
  if (d !== 0) {
    if (max === r) hue = ((g - b) / d + (g < b ? 6 : 0)) * 60;
    else if (max === g) hue = ((b - r) / d + 2) * 60;
    else hue = ((r - g) / d + 4) * 60;
  }
  for (let i = 0; i < 40 && contrastWithWhite(value) < MIN_CONTRAST; i++) {
    l = Math.max(0, l - 0.02);
    const c = (1 - Math.abs(2 * l - 1)) * sat;
    const x = c * (1 - Math.abs(((hue / 60) % 2) - 1));
    const base = l - c / 2;
    const [rr, gg, bb] =
      hue < 60
        ? [c, x, 0]
        : hue < 120
          ? [x, c, 0]
          : hue < 180
            ? [0, c, x]
            : hue < 240
              ? [0, x, c]
              : hue < 300
                ? [x, 0, c]
                : [c, 0, x];
    const hex2 = (n) =>
      Math.round((n + base) * 255)
        .toString(16)
        .padStart(2, "0");
    value = `#${hex2(rr)}${hex2(gg)}${hex2(bb)}`.toUpperCase();
  }
  return value;
}

const NUMBER_TYPES = new Set(["double", "currency", "integer", "long", "percent"]);
// More ways to link than this are listed with a search, in groups.
const MANY_LINKS = 6;

const OPERATORS = {
  boolean: [{ label: "is", value: "equals" }],
  picklist: [
    { label: "is", value: "equals" },
    { label: "isn't", value: "notEquals" },
    { label: "is one of", value: "oneOf" },
    { label: "isn't one of", value: "notOneOf" },
    { label: "is blank", value: "blank" },
    { label: "isn't blank", value: "notBlank" }
  ],
  number: [
    { label: "is", value: "equals" },
    { label: "isn't", value: "notEquals" },
    { label: "is more than", value: "greater" },
    { label: "is less than", value: "less" },
    { label: "is blank", value: "blank" },
    { label: "isn't blank", value: "notBlank" }
  ],
  date: [
    { label: "is on", value: "equals" },
    { label: "is after", value: "greater" },
    { label: "is before", value: "less" },
    { label: "is blank", value: "blank" },
    { label: "isn't blank", value: "notBlank" }
  ],
  datetime: [
    { label: "is after", value: "greater" },
    { label: "is before", value: "less" },
    { label: "is blank", value: "blank" },
    { label: "isn't blank", value: "notBlank" }
  ],
  text: [
    { label: "is", value: "equals" },
    { label: "isn't", value: "notEquals" },
    { label: "contains", value: "contains" },
    { label: "is blank", value: "blank" },
    { label: "isn't blank", value: "notBlank" }
  ]
};
const BOOLEAN_VALUES = [
  { label: "ticked", value: "true" },
  { label: "not ticked", value: "false" }
];

function blankDraft() {
  return {
    developerName: null,
    label: "",
    kind: null,
    active: true,
    parentObject: "Contact",
    objectName: null,
    parentField: null,
    junctionObject: null,
    junctionParentField: null,
    junctionRecordField: null,
    individualField: null,
    dataSpace: null,
    dateField: null,
    conditions: [],
    match: "all",
    filter: null,
    maxRecords: 1000,
    eventType: null,
    eventLabel: "",
    category: null,
    lenses: [],
    title: "",
    subtitle: "",
    icon: null,
    // A colour to start from; every source has its own.
    iconColour: DEFAULT_COLOUR,
    // Where a click goes, and whose layout opens (blank: the item's own).
    recordIdField: null,
    providerClass: null,
    sequence: null,
    details: [],
    highlights: []
  };
}

// Which wizard flow a saved source belongs to.
function uiKindOf(draft) {
  if (draft.kind === "Apex") return "apex";
  if (draft.kind === "Data 360") return "dmo";
  return /__c$/i.test(draft.objectName ?? "") ? "custom" : "standard";
}

function valueTypeOf(type) {
  if (type === "boolean") return "boolean";
  if (NUMBER_TYPES.has(type)) return "number";
  if (type === "date") return "date";
  if (type === "datetime") return "datetime";
  return "text";
}

function formatOf(type) {
  if (type === "date") return "Date";
  if (type === "datetime") return "Date/Time";
  if (type === "currency") return "Currency";
  if (NUMBER_TYPES.has(type)) return "Number";
  return "Text";
}

let nextKey = 0;
// Tasks, calls, emails and events start with the usual four fields to show
// when opened; the admin changes them.
const ACTIVITY_OBJECTS = new Set(["task", "event"]);
const ACTIVITY_DETAILS = [
  { field: "Description", label: "", format: "Text" },
  { field: "Who.Name", label: "", format: "Text" },
  { field: "What.Name", label: "", format: "Text" },
  { field: "Owner.Name", label: "", format: "Text" }
];

// Files (ContentDocumentLink) open with fields chosen here, and a click opens
// Salesforce's file preview, as it does everywhere else: nothing to choose
// between. They start with the file's own title, type and size, dated by when
// the document was created.
const FILE_OBJECT = "contentdocumentlink";
const FILE_DETAILS = [
  { field: "ContentDocument.Title", label: "", format: "Text" },
  { field: "ContentDocument.FileType", label: "", format: "Text" },
  { field: "ContentDocument.ContentSize", label: "", format: "Number" }
];
const FILE_DATE = "ContentDocument.CreatedDate";
const FILE_DATE_LABEL = "Content Document › Created Date";

// Highlights: the icons and colours to choose from. Utility icons, which
// take a colour well and read at a small size, and a plain dot.
const MAX_HIGHLIGHTS = 1;
const HIGHLIGHT_ICONS = [
  "dot",
  "utility:priority",
  "utility:warning",
  "utility:error",
  "utility:flag",
  "utility:favorite",
  "utility:alert",
  "utility:bolt",
  "utility:clock",
  "utility:lock",
  "utility:ban",
  "utility:check",
  "utility:info",
  "utility:like",
  "utility:dislike",
  "utility:notification"
];
const HIGHLIGHT_COLOURS = [
  { value: "#C23934", label: "Red" },
  { value: "#DD7A01", label: "Orange" },
  { value: "#FE9339", label: "Amber" },
  { value: "#2E844A", label: "Green" },
  { value: "#0176D3", label: "Blue" },
  { value: "#8E6CC8", label: "Purple" },
  { value: "#747474", label: "Grey" }
];

// A subtitle's fields: up to two, with the timeline's dot between them
// (TimeDrivePlotter.SEPARATOR, which drops out around an empty one).
const MAX_SUBTITLE_FIELDS = 2;
const SUBTITLE_SEPARATOR = " · ";

// Fields an item can show when opened, besides its title and subtitle.
const MAX_DETAILS = 4;

const keyed = (item) => ({ ...item, key: `k${++nextKey}` });

// A search result's label split around what was typed, for highlighting.
function highlight(label, term) {
  const at = term ? label.toLowerCase().indexOf(term) : -1;
  if (at < 0) return { before: label, match: "", after: "" };
  return { before: label.slice(0, at), match: label.slice(at, at + term.length), after: label.slice(at + term.length) };
}

// What to tell the user about a failed call. The controller's own messages
// (AuraHandledException) are written for people; anything else is described
// in general terms, never shown raw.
function plainError(error) {
  const body = error?.body;
  if (body?.message && (body.isUserDefinedException || !body.stackTrace)) {
    return { message: body.message, cause: "" };
  }
  return describeError(error);
}

export default class TimeDriveSetup extends LightningElement {
  // Drawn by lightning-illustration, in the page's SLDS.
  get errorImageName() {
    return illustrationName("error");
  }
  formatOptions = FORMATS;
  booleanOptions = BOOLEAN_VALUES;

  // The tab, edge to edge (see fit()).
  fitStyle = "";
  fitQueued = false;
  headerFixed;

  // Pages: home (the site's front page), pages (the record pages), parent
  // (one record page's sources), source (one source) and wizard (adding or
  // editing one).
  selectedParent;
  viewing;
  // Welcome until the org has been checked (the only page), then Setup.
  view = "welcome";
  progressReady = false;
  sources = [];
  loadingSources = true;
  loadError;
  pending = {};
  justSaved;

  // Wizard
  draft = blankDraft();
  uiKind;
  stepIndex = 0;
  reached = 0;
  sceneSeq = 0;
  direction = "forward";
  editing = false;
  dirty = false;
  objectsByKind = {};
  // Data 360's active data spaces (none without Data 360); a Data 360
  // source asks for one only when there's more than one.
  dataSpaces = [];
  dataSpacesReady;
  // Whether Data 360 sources can be set up here ({ ready, reason }): the
  // add-on package must be installed. Until it's known, or if it can't be
  // asked, nothing is blocked.
  data360Status;
  loadingList = false;
  apexProviders;
  links;
  fields;
  loadingSchema = false;
  stepError;
  filterMode = "all";
  parentChosen = false;
  rangeChosen = false;
  volumes;
  loadingVolumes = false;
  // A question the wizard answered itself, said on the next screen.

  // The search list on pick screens, and the field picker for the words.
  // The list works like a picklist: it opens to choose, and closes on a pick.
  pickerOpen = false;
  query = "";
  activeIndex = 0;
  tokenTarget;

  // Saving
  saving;
  saved = false;
  saveError;

  connectedCallback() {
    this.dataSpacesReady = this.loadDataSpaces();
    this.loadData360Status();
    // Bitcount Prop Double for titles, Figtree for text; system faces until they load.
    loadStyle(this, `${FONTS}/fonts.css`).catch(() => {});
    this.followDensity();
    this._onResize = () => {
      this.headerFixed = undefined;
      this.fitSoon();
    };
    this._onScroll = () => this.fitSoon();
    window.addEventListener("resize", this._onResize);
    window.addEventListener("scroll", this._onScroll, { passive: true });
    this.progressLoaded = this.loadProgress();
    this.loadSources();
  }

  renderedCallback() {
    fitIllustrations(this.template);
    if (!this.fitStyle) this.fit();
  }

  // Lightning pads a tab's content; Setup bleeds into that padding (it
  // varies, so it's measured) and stands at least the rest of the window
  // tall, so every page fills the tab.
  fit() {
    const host = this.template.host;
    if (!host?.getBoundingClientRect) return;
    const rect = host.getBoundingClientRect();
    const width = document.documentElement.clientWidth || window.innerWidth;
    const start = Math.max(0, Math.round(rect.left));
    const end = Math.max(0, Math.round(width - rect.right));
    // Lightning's band pads the top as much as the sides.
    // (Measured on the page, not the window, so it holds while scrolled.)
    const scrolled = window.scrollY || 0;
    const above = Math.min(start, Math.max(0, Math.round(rect.top + scrolled)));
    const top = rect.top + scrolled - above;
    const fill = Math.max(480, Math.round(window.innerHeight - top));
    // The menu pins just under Salesforce's header where that stays put, and
    // to the top of the window where it scrolls away (narrow windows).
    const mark = this.template.querySelector(".site-bar-mark")?.getBoundingClientRect();
    const under = mark ? mark.top + scrolled : top;
    const pin = this.isHeaderFixed(rect, under, scrolled) ? Math.max(0, Math.round(under)) : 0;
    const style = `--bleed-start: ${start}px; --bleed-end: ${end}px; --bleed-top: ${above}px; --fill: ${fill}px; --pin-top: ${pin}px`;
    if (style !== this.fitStyle) this.fitStyle = style;
  }

  // Once a frame at most, as the window scrolls or resizes.
  fitSoon() {
    if (this.fitQueued) return;
    this.fitQueued = true;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    requestAnimationFrame(() => {
      this.fitQueued = false;
      this.fit();
    });
  }

  // Whether Salesforce's header stays on screen as the page scrolls. Once
  // scrolled, the point just above Setup's band is either the header (it
  // stays) or Setup's own page (it scrolled away). Known again per width.
  isHeaderFixed(rect, top, scrolled) {
    if (this.headerFixed !== undefined || scrolled < 8) return this.headerFixed ?? true;
    try {
      const at = document.elementFromPoint?.(Math.round(rect.left + 8), Math.round(top - 2));
      if (at) this.headerFixed = !this.template.host.contains(at);
    } catch {
      // Can't look; assume the desktop header, which stays.
    }
    return this.headerFixed ?? true;
  }

  // The user's display density (Comfy or Compact): Lightning sets its
  // density-aware spacing for it, half as much when Compact. The spacing
  // here follows (see --d in the CSS).
  followDensity() {
    const medium = getComputedStyle(this.template.host).getPropertyValue("--lwc-varSpacingMedium").trim();
    const rem = medium.endsWith("rem") ? parseFloat(medium) : NaN;
    this.template.host.classList.toggle("density_compact", rem > 0 && rem < 0.75);
  }

  disconnectedCallback() {
    window.removeEventListener("resize", this._onResize);
    window.removeEventListener("scroll", this._onScroll);
  }

  // ---- saving results ------------------------------------------------------

  // A source's row while its change is saved: "Making active…", "Removing…".
  pend(name, change) {
    this.pending = { ...this.pending, [name]: change };
  }

  unpend(name) {
    const pending = { ...this.pending };
    delete pending[name];
    this.pending = pending;
  }

  // A source switched on or off, or removed: shown at once, then the list is
  // read again.
  sourceChanged(name, label, { active, removing }) {
    if (removing) {
      this.sources = this.sources.filter((s) => s.developerName !== name);
      this.toast("success", `${label} removed`, "It's off the timeline.");
    } else {
      this.sources = this.sources.map((s) => (s.developerName === name ? { ...s, active } : s));
      this.toast("success", active ? `${label} is active` : `${label} is inactive`, "");
    }
    this.loadSources();
  }

  // Saved: the button turns to a tick for a moment, then the list returns
  // with the source picked out.
  finishSave() {
    const { label, active, developerName } = this.draft;
    this.saved = true;
    this.dirty = false;
    this.toast(
      "success",
      `${label} saved`,
      active ? "It's active: on the timeline now." : "It's inactive, so it isn't on the timeline."
    );
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      this.saved = false;
      this.justSaved = developerName;
      this.selectedParent = this.draft.parentObject || this.selectedParent;
      this.show("parent");
      this.loadSources();
    }, 900);
  }

  toast(variant, title, message) {
    this.dispatchEvent(new ShowToastEvent({ variant, title, message }));
  }

  // ---- home ----------------------------------------------------------------

  async loadSources() {
    this.loadingSources = !this.sources.length;
    this.loadViews();
    try {
      this.sources = await getSources();
      this.loadError = undefined;
      this.loadTemplates();
    } catch (e) {
      this.loadError = plainError(e);
    } finally {
      this.loadingSources = false;
    }
  }

  // Ready-made sources (the shipped templates) this org can use, for the
  // record page being looked at; adding one copies it as a source of your own.
  templates = [];
  templatesBusy = false;

  async loadTemplates(parentObject = this.selectedParent || null) {
    try {
      this.templates = await getTemplates({ parentObject });
    } catch {
      this.templates = [];
    }
  }

  get templateRows() {
    return this.templates
      .filter((t) => !t.added && (!this.selectedParent || t.parentObject === this.selectedParent))
      .map((t) => ({
        ...t,
        icon: t.icon || "utility:record",
        chipStyle: `--chip: ${t.iconColour || "var(--setup-chip)"}`
      }));
  }

  get hasTemplates() {
    return this.templateRows.length > 0;
  }

  async handleUseTemplate(event) {
    const key = event.currentTarget.dataset.key;
    const template = this.templates.find((t) => t.key === key);
    if (!template || this.templatesBusy) return;
    this.templatesBusy = true;
    try {
      await applyTemplate({ templateKey: key });
      this.toast("success", `${template.label} added`, "It's on the timeline now. Change it any time.");
      await this.loadSources();
    } catch (e) {
      this.toast("error", `${template.label} couldn't be added`, plainError(e).message);
    } finally {
      this.templatesBusy = false;
    }
  }

  // The timeline's views: [{ developerName, name, labelName, shown, active }],
  // with the views made active or inactive here before they're saved.
  viewDrafts;
  viewEdits = {};
  viewSaving;

  async loadViews() {
    try {
      this.viewDrafts = await getViewDrafts();
    } catch {
      this.viewDrafts = undefined;
    }
  }

  // A view's name in the viewer's language, by the key sources keep in
  // their Timeline View.
  viewNameOf(key) {
    if (!key) return "";
    const v = this.viewDrafts?.find((d) => d.developerName === key);
    return v?.shown || v?.name || key;
  }

  get viewRows() {
    return (this.viewDrafts ?? []).map((v) => {
      const active = v.developerName in this.viewEdits ? this.viewEdits[v.developerName] : v.active;
      return { key: v.developerName, active };
    });
  }

  // What the filter calls a source, when it isn't just the object's name again.
  filterNameOf(src) {
    const legend = (src.legendName || src.eventLabel || "").trim();
    return legend && legend.toLowerCase() !== this.sourceName(src).toLowerCase() ? legend : "";
  }

  // "Task Relation (Tasks)".
  sourceWithFilterName(src) {
    const legend = this.filterNameOf(src);
    return legend ? `${this.sourceName(src)} (${legend})` : this.sourceName(src);
  }

  // The keys of the lenses a source is in, and their names.
  lensKeys(src) {
    return src.lenses?.length ? src.lenses : src.category ? [src.category] : [];
  }

  // The lenses it shows under: one in no lens at all is in All.
  shownLenses(keys) {
    return keys.length ? keys : ["All"];
  }

  lensNames(src) {
    return this.lensKeys(src).map((key) => this.viewNameOf(key));
  }

  // ---- the Lenses page: a grid, sources down the side and lenses across ----
  // Ticking a cell puts that source in that lens (a source can be in several),
  // and saves at once. The switch above a lens column offers it in the picker.

  lensPage = "";

  // The record pages that have sources, to pick which sources the grid lists.
  get lensTabs() {
    const pages = PARENTS.filter((p) => this.sources.some((src) => (src.parentObject || "Contact") === p.value));
    const current = pages.some((p) => p.value === this.lensPage) ? this.lensPage : (pages[0]?.value ?? "");
    return pages.map((p) => ({
      value: p.value,
      label: p.label,
      selected: p.value === current,
      pressed: String(p.value === current),
      className: `lens-tab${p.value === current ? " lens-tab_on" : ""}`
    }));
  }

  get lensCurrentPage() {
    return this.lensTabs.find((t) => t.selected)?.value ?? "";
  }

  handleLensTab(event) {
    this.lensPage = event.currentTarget.dataset.value;
  }

  // A column for each lens, All first. All is always offered, so it has no switch.
  get lensColumns() {
    const drafts = this.viewDrafts ?? [];
    const all = drafts.find((v) => v.developerName === "All");
    const columns = drafts
      .filter((v) => v.developerName !== "All")
      .map((v) => {
        const active = v.developerName in this.viewEdits ? this.viewEdits[v.developerName] : v.active;
        const name = v.shown || v.name;
        return {
          key: v.developerName,
          name,
          active,
          switchable: true,
          toggleLabel: `${name}: offered in the picker`,
          className: `lens-col${active ? "" : " lens-col_off"}`
        };
      });
    const allName = all?.shown || all?.name || "All";
    return [{ key: "All", name: allName, active: true, switchable: false, className: "lens-col" }, ...columns];
  }

  // The picker as people will see it.
  get lensStrip() {
    return this.lensColumns
      .filter((c) => c.active)
      .map((c) => c.name)
      .map((name, i) => ({
        key: `${i}-${name}`,
        name
      }));
  }

  get lensRows() {
    const page = this.lensCurrentPage;
    const columns = this.lensColumns;
    return this.sources
      .filter((src) => (src.parentObject || "Contact") === page)
      .sort((a, b) => this.sourceName(a).localeCompare(this.sourceName(b)))
      .map((src) => {
        const name = this.sourceWithFilterName(src);
        const inLenses = new Set(this.shownLenses(this.lensKeys(src)));
        return {
          key: src.developerName,
          name,
          // Tells apart sources on the same object with different filters.
          filterText: src.filter ? `Filter: ${src.filter}` : "No filter: every record",
          off: !src.active,
          iconName: src.icon || "utility:record",
          chipStyle: `--chip: ${src.iconColour || "var(--setup-chip)"}`,
          cells: columns.map((c) => ({
            key: `${src.developerName}-${c.key}`,
            lens: c.key,
            source: src.developerName,
            checked: inLenses.has(c.key),
            // Its only lens stays: switch the source off to hide it.
            only: inLenses.has(c.key) && inLenses.size === 1,
            label: `${name} in ${c.name}`
          }))
        };
      });
  }

  get hasLensRows() {
    return this.lensRows.length > 0;
  }

  // Offered in the picker or not: saved as it is switched.
  handleLensActive(event) {
    this.viewEdits = { ...this.viewEdits, [event.target.dataset.key]: event.target.checked };
    if (!this.viewSaving) this.saveViewChoices();
  }

  // A cell ticked or cleared: shown at once, saved behind it, put back if it fails.
  async handleLensCell(event) {
    const name = event.target.dataset.source;
    const lens = event.target.dataset.lens;
    const source = this.sources.find((src) => src.developerName === name);
    if (!source) return;
    const before = this.shownLenses(this.lensKeys(source));
    const after = event.target.checked ? [...before.filter((k) => k !== lens), lens] : before.filter((k) => k !== lens);
    if (!after.length) return;
    const order = this.lensColumns.map((c) => c.key);
    after.sort((a, b) => order.indexOf(a) - order.indexOf(b));
    this.setSourceLenses(name, after);
    try {
      await setSourceLenses({ developerName: name, lenses: after });
    } catch (e) {
      this.setSourceLenses(name, before);
      this.toast("error", `${this.sourceName(source)} couldn't be changed`, plainError(e).message);
    }
  }

  setSourceLenses(name, lenses) {
    this.sources = this.sources.map((src) => {
      if (src.developerName !== name) return src;
      return { ...src, lenses, category: lenses[0] ?? null };
    });
  }

  // One save at a time: a switch flipped while one saves goes in the next.
  async saveViewChoices() {
    const sent = { ...this.viewEdits };
    const views = this.viewRows.map((r) => ({ developerName: r.key, active: r.active }));
    this.viewSaving = true;
    try {
      await saveViews({ viewsJson: JSON.stringify(views) });
      this.viewDrafts = this.viewDrafts.map((d) => {
        return d.developerName in sent ? { ...d, active: sent[d.developerName] } : d;
      });
      this.viewEdits = Object.fromEntries(Object.entries(this.viewEdits).filter(([key, on]) => sent[key] !== on));
      this.guidedMark("views");
      this.toast("success", "Views saved", "The timeline's picker offers the views you chose.");
    } catch (e) {
      this.viewEdits = {};
      this.toast("error", "The views couldn't be saved", plainError(e).message);
    } finally {
      this.viewSaving = false;
    }
    if (Object.keys(this.viewEdits).length) this.saveViewChoices();
  }

  guidedMark(key) {
    return this.keepProgress((done) => done.add(key));
  }

  // The steps done, and the org check's report, are the org's (shared by its
  // admins): a step counts as done only once the org has it. Shown at once,
  // taken back if it can't be kept.
  async keepProgress(change, report) {
    // What the org already has comes first, or this would write over it.
    await this.progressLoaded;
    const before = this.guidedDone;
    const done = new Set(before);
    change(done);
    this.guidedDone = done;
    try {
      await saveProgress({ steps: [...done], report: report ? JSON.stringify(report) : null });
      return true;
    } catch (e) {
      this.guidedDone = before;
      this.toast("error", "That couldn't be saved", plainError(e).message);
      return false;
    }
  }

  async loadProgress() {
    try {
      const progress = await getProgress();
      this.guidedDone = new Set(progress?.steps ?? []);
      this.checkReport = progress?.report ? JSON.parse(progress.report) : undefined;
      // Already checked: Setup is the first page.
      if (this.orgChecked && this.view === "welcome") this.show("setup");
    } catch (e) {
      this.loadError = plainError(e);
    } finally {
      this.progressReady = true;
    }
  }

  get isWelcome() {
    return this.view === "welcome";
  }

  get logoUrl() {
    return `${ASSETS}/logo/time-drive.svg`;
  }

  get isDashboard() {
    return this.view === "dashboard";
  }

  get isSetupPage() {
    return this.view === "setup";
  }

  get isLensesPage() {
    return this.view === "lenses";
  }

  get isDocsPage() {
    return this.view === "docs";
  }

  // ---- the site's menu ------------------------------------------------------

  // Setup (the guided steps), Customize (the record pages, their sources, and
  // the wizard that adds them), Lenses and Docs (links to the Config Guide and
  // FAQs on GitHub). None shows until the org has been checked.
  get hasNav() {
    return this.orgChecked;
  }

  get navItems() {
    const section = ["pages", "parent", "source", "wizard"].includes(this.view) ? "pages" : this.view;
    if (!this.orgChecked) return [];
    return [
      { key: "setup", label: "Setup" },
      { key: "pages", label: "Customize" },
      { key: "lenses", label: "Lenses" },
      { key: "docs", label: "Docs" }
    ].map((item) => ({
      ...item,
      current: item.key === section ? "page" : null,
      className: `site-link${item.key === section ? " site-link_on" : ""}`
    }));
  }

  async handleNav(event) {
    const to = event.currentTarget.dataset.to;
    if (this.view === "wizard" && !(await this.okToLeave())) return;
    this.viewing = undefined;
    this.show(to);
    this.loadSources();
  }

  get isPagesPage() {
    return this.view === "pages";
  }

  get isParentPage() {
    return this.view === "parent";
  }

  get isSourcePage() {
    return this.view === "source" && Boolean(this.viewing);
  }

  get isWizard() {
    return this.view === "wizard";
  }

  get pageClass() {
    return `setup-page${this.isWelcome ? " setup-page_welcome" : ""}`;
  }

  // The menu's own pages need no breadcrumb.
  get showCrumbs() {
    return !["welcome", "dashboard", "setup", "pages", "lenses", "docs"].includes(this.view);
  }

  // A new page starts at the top, with focus on its heading.
  show(view) {
    this.view = view;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    requestAnimationFrame(() => {
      const page = this.template.querySelector(".setup-page");
      page?.scrollIntoView?.({ block: "start" });
      this.template.querySelector(".page-title")?.focus({ preventScroll: true });
    });
  }

  // ---- the breadcrumb ------------------------------------------------------

  // Where you are, from Setup down; every crumb but the last goes there.
  get crumbs() {
    const trail = this.customizeTrail;
    return trail.map((c, i) => {
      const current = i === trail.length - 1;
      return { ...c, key: c.to, current, ariaCurrent: current ? "page" : null };
    });
  }

  get customizeTrail() {
    const trail = [{ to: "pages", label: "Customize" }];
    if (this.view !== "pages" && this.selectedParent) {
      trail.push({ to: "parent", label: this.selectedLabel });
    }
    if (this.view === "source" && this.viewing) {
      trail.push({ to: "source", label: this.viewing.label });
    }
    if (this.view === "wizard") {
      trail.push({ to: "wizard", label: this.editing ? `Edit ${this.draft.label || "source"}` : "New source" });
    }
    return trail;
  }

  async handleCrumb(event) {
    const to = event.currentTarget.dataset.to;
    if (this.view === "wizard" && !(await this.okToLeave())) return;
    if (to === "pages") {
      this.viewing = undefined;
      this.show(to);
    } else if (to === "parent") {
      this.viewing = undefined;
      this.show("parent");
    }
    if (this.view !== "wizard") this.loadSources();
  }

  // ---- home: the record pages ---------------------------------------------

  // Every record page the timeline can sit on, and any a source already
  // names, with its sources' colours as dots on a little rail.
  // The record pages to offer: Person Account only where the org has Person
  // Accounts (the org check found them) or a source already sits on its page.
  get pages() {
    const persons =
      this.checkReport?.checks?.some((c) => c.key === "PersonAccounts" && c.present) ||
      this.sources.some((src) => src.parentObject === "PersonAccount");
    return PARENTS.filter((p) => p.value !== "PersonAccount" || persons);
  }

  get parentCards() {
    const known = PARENTS.map((p) => p.value);
    const extra = [...new Set(this.sources.map((s) => s.parentObject))].filter((p) => p && !known.includes(p));
    const parents = [...this.pages, ...extra.map((value) => ({ value, label: value, icon: "utility:record" }))];
    return parents.map((p) => {
      const mine = this.sources.filter((s) => (s.parentObject || "Contact") === p.value);
      const on = mine.filter((s) => s.active).length;
      return {
        ...p,
        countText: mine.length
          ? `${mine.length} ${mine.length === 1 ? "source" : "sources"} · ${on} active`
          : "No sources yet",
        openLabel: `${p.label} timeline`,
        dots: mine.slice(0, 18).map((s, i) => ({
          key: s.developerName,
          style: `--chip: ${s.iconColour || "var(--setup-chip)"}; --i: ${i}; opacity: ${s.active ? 1 : 0.3}`
        }))
      };
    });
  }

  // ---- the welcome page ------------------------------------------------------

  // Get started is the org check, in its popup; when it has run, Setup.
  handleGetStarted() {
    return this.handleCheckOrg();
  }

  // ---- checking the org: a popup, then a brief report on the Setup step -------

  // The last check's report, kept for the step: what each check found and
  // what was added.
  checkReport;

  async handleCheckOrg() {
    const report = await TimeDriveOrgCheck.open({ size: "small", label: "Check your org" });
    // Closed before it ran: nothing was checked.
    if (!report) return;
    // Done only once the org has it.
    if (!(await this.keepProgress((done) => done.add("orgcheck"), report))) return;
    this.checkReport = report;
    this.selectedParent = undefined;
    this.viewing = undefined;
    this.show("setup");
    await this.loadSources();
  }

  // The brief report under the step: what each check found.
  get checkReportLines() {
    const report = this.checkReport;
    if (!report) return [];
    const lines = (report.checks ?? []).map((c) => ({ key: c.key, text: `${c.label}: ${c.found}` }));
    if (report.error) lines.push({ key: "error", text: `The recommended sources couldn't be added: ${report.error}` });
    return lines;
  }

  // In a sentence, what the settings found mean for the timeline.
  get checkMeaning() {
    const report = this.checkReport;
    if (!report?.checks?.length) return "";
    const on = new Set(report.checks.filter((c) => c.present).map((c) => c.key));
    const clauses = [];
    if (on.has("SharedActivities")) clauses.push("tasks and events include every contact on them");
    if (on.has("ContactsToMultipleAccounts")) clauses.push("account pages include their related contacts");
    if (on.has("PersonAccounts")) clauses.push("Person Accounts get a timeline page of their own");
    clauses.push(on.has("EnhancedEmail") ? "emails come from Email Messages" : "emails come from email tasks");
    return `Because of what is on in your org, ${clauses.join(", and ")}.`;
  }

  // The org has been checked (the Setup step is ticked).
  get orgChecked() {
    return this.guidedDone.has("orgcheck");
  }

  // ---- the home page's dashboard ------------------------------------------

  get sourceTotal() {
    return String(this.sources.length);
  }

  get onCount() {
    return String(this.sources.filter((s) => s.active).length);
  }

  get meterStyle() {
    const total = this.sources.length;
    const on = this.sources.filter((s) => s.active).length;
    return `width: ${total ? Math.round((on / total) * 100) : 0}%`;
  }

  get offNote() {
    const off = this.sources.length - this.sources.filter((s) => s.active).length;
    if (!this.sources.length) return "No sources yet: Add a source to start a timeline.";
    return off ? `${off} inactive. They stay set up; make them active any time.` : "Every source is active.";
  }

  // Each kind of source, as a share of them all.
  get kindBars() {
    const total = Math.max(1, this.sources.length);
    return TYPES.map((t) => {
      const n = this.sources.filter((src) => (src.type || "standard") === t.value).length;
      return { key: t.value, label: t.label, count: String(n), style: `width: ${Math.round((n / total) * 100)}%` };
    });
  }

  // Each record page and how many of its sources are on.
  get glanceRows() {
    return this.parentCards.map((p) => {
      const mine = this.sources.filter((s) => (s.parentObject || "Contact") === p.value);
      const on = mine.filter((s) => s.active).length;
      return {
        key: p.value,
        value: p.value,
        label: p.label,
        openLabel: p.openLabel,
        detail: mine.length ? `${mine.length} ${mine.length === 1 ? "source" : "sources"}` : "No sources yet",
        pill: mine.length ? `${on} active` : "Empty",
        pillClass: `pill${on ? " pill_ok" : ""}`
      };
    });
  }

  // The dashboard's table: a column per record page, its active sources
  // down it in legend order. Rows run as deep as the longest column.
  get activeColumns() {
    return this.parentCards.map((p) => ({
      key: p.value,
      value: p.value,
      label: p.label,
      openLabel: `${p.label}: customize`,
      sources: this.sources
        .filter((s) => s.active && (s.parentObject || "Contact") === p.value)
        .sort((a, b) => (a.sequence ?? 0) - (b.sequence ?? 0) || a.label.localeCompare(b.label))
    }));
  }

  get activeTableRows() {
    const columns = this.activeColumns;
    const depth = Math.max(1, ...columns.map((c) => c.sources.length));
    return Array.from({ length: depth }, (_, i) => ({
      key: `row-${i}`,
      cells: columns.map((c) => {
        const s = c.sources[i];
        return {
          key: `${c.key}-${i}`,
          has: Boolean(s),
          label: s?.label ?? (i === 0 ? "None active" : ""),
          iconName: s?.icon || "utility:record",
          chipStyle: `--chip: ${s?.iconColour || "var(--setup-chip)"}`,
          className: `kd-cell${s ? "" : " kd-cell_empty"}`
        };
      })
    }));
  }

  get offSources() {
    return this.sources
      .filter((s) => !s.active)
      .map((s) => ({
        developerName: s.developerName,
        label: s.label,
        where: `${PARENTS.find((p) => p.value === (s.parentObject || "Contact"))?.label ?? s.parentObject} · ${
          this.lensNames(s).join(", ") || "No view"
        }`,
        openLabel: `${s.label}: open`,
        iconName: s.icon || "utility:record",
        chipStyle: `--chip: ${s.iconColour || "var(--setup-chip)"}`
      }));
  }

  get hasOffSources() {
    return this.offSources.length > 0;
  }

  // An off source, opened on its own page (under its record page).
  handleOpenSource(event) {
    const source = this.sources.find((s) => s.developerName === event.currentTarget.dataset.name);
    this.selectedParent = source?.parentObject || PARENTS[0].value;
    this.handleViewSource(event);
  }

  handleWatchVideo() {
    if (HOW_TO_VIDEO_URL) {
      window.open(HOW_TO_VIDEO_URL, "_blank", "noopener");
    } else {
      this.toast("info", "The how-to video is on its way", "It will open here on YouTube once it's published.");
    }
  }

  // ---- Docs ------------------------------------------------------------------

  // The Config Guide and FAQs, each a link to its page on GitHub.
  get docs() {
    return DOCS.map((doc) => ({ ...doc, href: DOCS_WEB + doc.file }));
  }

  // ---- the Setup page: guided steps ---------------------------------------

  guidedDone = new Set();
  guidedSelected;

  // What Setup can see for itself about each step.
  guidedState(step) {
    const ticked = this.guidedDone.has(step.key);
    switch (step.kind ?? step.key) {
      case "orgcheck":
        return {
          done: this.orgChecked,
          report: this.orgChecked ? this.checkReportLines : [],
          meaning: this.orgChecked ? this.checkMeaning : ""
        };
      case "review":
        if (!this.sources.length) return { done: ticked, status: "" };
        return {
          done: ticked,
          status: `${this.sources.length} ${this.sources.length === 1 ? "source" : "sources"} set up, ${this.sources.filter((src) => src.active).length} active`
        };
      case "users": {
        const objects = [
          ...new Set(this.sources.filter((src) => src.active).map((src) => src.objectLabel || src.objectName))
        ]
          .filter(Boolean)
          .sort();
        return { done: ticked, status: objects.length ? `Your active sources read: ${objects.join(", ")}` : "" };
      }
      case "page": {
        const pages = this.recordPagesInUse.map((p) => p.label);
        return { done: ticked, status: pages.length ? `Sources on: ${pages.join(", ")}` : "" };
      }
      default:
        return { done: ticked, status: "" };
    }
  }

  // Record pages with an active source, as App Builder knows them (a
  // person account's page is an Account page).
  get recordPagesInUse() {
    const objects = new Set(
      this.sources
        .filter((src) => src.active)
        .map((src) => (src.parentObject === "PersonAccount" ? "Account" : src.parentObject || "Contact"))
    );
    return [...objects].sort().map((object) => ({
      object,
      label: PARENTS.find((p) => p.value === object)?.label ?? object
    }));
  }

  // Each step's actions: buttons that do it here, or links to the
  // Salesforce page where it's done (in a new tab).
  guidedActions(step, done) {
    switch (step.kind ?? step.key) {
      case "video":
        return [{ label: "Watch video", handler: "video", primary: !done }];
      case "perms":
        return [{ label: "Open permission sets", href: "/lightning/setup/PermSets/home" }];
      case "views":
        return [{ label: "Open Lenses", handler: "lenses", primary: !done }];
      case "orgcheck":
        return [{ label: done ? "Check again" : "Check my org", handler: "check", primary: !done }];
      case "review":
        return [{ label: "Open Customize", handler: "customize", primary: !done }];
      case "users":
        return [{ label: "Open permission sets", href: "/lightning/setup/PermSets/home" }];
      case "page": {
        const pages = this.recordPagesInUse.length ? this.recordPagesInUse : [{ object: "Contact", label: "Contact" }];
        return pages.map((p) => ({
          label: `${p.label} pages`,
          href: `/lightning/setup/ObjectManager/${p.object}/LightningPages/view`
        }));
      }
      default:
        return [];
    }
  }

  get guidedStepList() {
    return GUIDED_STEPS;
  }

  get guidedSteps() {
    const steps = this.guidedStepList.map((step, i) => {
      const state = this.guidedState(step);
      const actions = this.guidedActions(step, state.done).map((a, j) => ({
        ...a,
        key: `${step.key}-${j}`,
        isLink: Boolean(a.href),
        className: a.primary ? "primary guided-button" : "ghost guided-button"
      }));
      return {
        ...step,
        ...state,
        actions,
        number: String(i + 1),
        report: state.report ?? []
      };
    });
    const selected = this.guidedSelected ?? steps.find((st) => !st.done)?.key ?? steps[0].key;
    return steps.map((st) => ({
      ...st,
      selected: st.key === selected,
      pressed: String(st.key === selected),
      showCheck: Boolean(st.manual && !st.auto),
      checkLabel: st.checkLabel ?? "I am done with this step",
      doneLabel: st.skipped ? "Skipped" : "Done",
      className: `guided-step${st.done ? " guided-step_done" : ""}${st.key === selected ? " guided-step_on" : ""}`
    }));
  }

  // The progress bar: a segment per step, filled when done. When every
  // step is done the segments join into one full bar.
  get guidedSegments() {
    return this.guidedSteps.map((st) => ({
      key: st.key,
      label: `${st.title}: ${st.done ? st.doneLabel.toLowerCase() : "to do"}`,
      className: `guided-segment${st.done ? " guided-segment_done" : ""}`
    }));
  }

  get guidedProgressText() {
    const steps = this.guidedSteps;
    return `${steps.filter((st) => st.done).length} of ${steps.length}`;
  }

  get guidedAllDone() {
    return this.guidedSteps.every((st) => st.done);
  }

  get guidedProgressClass() {
    return this.guidedAllDone ? "guided-progress guided-progress_done" : "guided-progress";
  }

  get guidedSelectedStep() {
    return this.guidedSteps.find((st) => st.selected);
  }

  get guidedAsideStep() {
    const st = this.guidedSelectedStep;
    return st.done ? `Step ${st.number} · ${st.doneLabel}` : `Step ${st.number}`;
  }

  get guidedAsideWhat() {
    const st = this.guidedSelectedStep;
    return st.done && !st.skipped ? "What it did" : "What it does";
  }

  handleGuidedSelect(event) {
    this.guidedSelected = event.currentTarget.dataset.key;
  }

  // Anywhere on a step shows its help, done or not; its action and its
  // checkbox keep their own clicks.
  handleGuidedRow(event) {
    if (event.target.closest(".guided-act, .guided-check, .guided-choices")) return;
    this.guidedSelected = event.currentTarget.dataset.key;
  }

  handleGuidedDone(event) {
    const { key } = event.target.dataset;
    const checked = event.target.checked;
    this.keepProgress((done) => (checked ? done.add(key) : done.delete(key)));
  }

  handleGuidedAction(event) {
    const handler = event.currentTarget.dataset.handler;
    if (handler === "add") this.handleAddFromHome();
    else if (handler === "customize") this.show("pages");
    else if (handler === "check") this.handleCheckOrg();
    else if (handler === "lenses") this.show("lenses");
    else if (handler === "video") this.handleWatchVideo();
    else if (handler === "retry") this.handleRetryLoad();
  }

  handleOpenDashboard() {
    this.show("dashboard");
  }

  // From home: straight into adding a source to Contact.
  handleAddFromHome() {
    this.selectedParent = PARENTS[0].value;
    this.handleAdd();
  }

  handleParentCard(event) {
    this.selectedParent = event.currentTarget.dataset.value;
    this.loadTemplates();
    this.handleClearSourceFilter();
    this.show("parent");
  }

  // ---- home: the chosen page's sources, by type -----------------------------

  get selectedLabel() {
    return PARENTS.find((p) => p.value === this.selectedParent)?.label ?? this.selectedParent;
  }

  get selectedSources() {
    return this.sources.filter((s) => (s.parentObject || "Contact") === this.selectedParent);
  }

  get hasSelectedSources() {
    return this.selectedSources.length > 0;
  }

  // A search and quick filters by type and by status over the page's
  // sources, as one list. They combine: Standard + Inactive is every
  // standard source that's off. Each pill counts what choosing it would show.
  sourceQuery = "";
  sourceType = "all";
  sourceStatus = "all";

  sourceMatches(src, { type = this.sourceType, status = this.sourceStatus } = {}) {
    if (type !== "all" && (src.type || "standard") !== type) return false;
    if (status === "active" && !src.active) return false;
    if (status === "inactive" && src.active) return false;
    const words = this.sourceQuery.trim().toLowerCase().split(/\s+/).filter(Boolean);
    if (!words.length) return true;
    const text = [
      src.label,
      src.objectLabel,
      src.legendName,
      src.objectName,
      this.lensKeys(src).join(" "),
      src.kind,
      src.summary,
      src.developerName
    ]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();
    return words.every((w) => text.includes(w));
  }

  pill(key, label, count, on) {
    return {
      key,
      text: `${label} ${count}`,
      pressed: String(on),
      className: `chip-choice chip-choice_small${on ? " chip-choice_on" : ""}`
    };
  }

  get sourceTypes() {
    const count = (type) => this.selectedSources.filter((src) => this.sourceMatches(src, { type })).length;
    return [
      this.pill("all", "All", count("all"), this.sourceType === "all"),
      ...TYPES.map((t) => this.pill(t.value, t.short, count(t.value), this.sourceType === t.value))
    ];
  }

  get sourceStatuses() {
    const count = (status) => this.selectedSources.filter((src) => this.sourceMatches(src, { status })).length;
    return [
      this.pill("all", "Any", count("all"), this.sourceStatus === "all"),
      this.pill("active", "Active", count("active"), this.sourceStatus === "active"),
      this.pill("inactive", "Inactive", count("inactive"), this.sourceStatus === "inactive")
    ];
  }

  get filteredSources() {
    return this.selectedSources.filter((src) => this.sourceMatches(src));
  }

  get sourceRows() {
    return this.filteredSources.map((src, i) => this.sourceCard(src, i));
  }

  get hasFilteredSources() {
    return this.filteredSources.length > 0;
  }

  get sourceFiltered() {
    return this.sourceType !== "all" || this.sourceStatus !== "all" || Boolean(this.sourceQuery.trim());
  }

  get sourceCountText() {
    const shown = this.filteredSources.length;
    const total = this.selectedSources.length;
    return this.sourceFiltered
      ? `Showing ${shown} of ${total} ${total === 1 ? "source" : "sources"}`
      : `${total} ${total === 1 ? "source" : "sources"}`;
  }

  handleSourceQuery(event) {
    this.sourceQuery = event.target.value;
  }

  handleSourceType(event) {
    this.sourceType = event.currentTarget.dataset.value;
  }

  handleSourceStatus(event) {
    this.sourceStatus = event.currentTarget.dataset.value;
  }

  handleClearSourceFilter() {
    this.sourceQuery = "";
    this.sourceType = "all";
    this.sourceStatus = "all";
  }

  // A source is listed by the records it reads (Task Relation), not by what the
  // legend or filter calls it (Tasks): that name is on its page. An Apex source
  // reads no object, so it keeps its own.
  sourceName(s) {
    return s.type === "apex" ? s.label : s.objectLabel || s.label;
  }

  sourceCard(s, index) {
    const pending = this.pending[s.developerName];
    const active = pending && !pending.removing ? pending.active : s.active;
    // The records it reads, with what the filter calls it after it in brackets
    // (Task (Calls)), so several sources on one object can be told apart.
    const name = this.sourceWithFilterName(s);
    return {
      ...s,
      name,
      active,
      pending: Boolean(pending),
      pendingText: pending
        ? pending.removing
          ? "Removing…"
          : pending.active
            ? "Making active…"
            : "Making inactive…"
        : "",
      className: `row${active ? "" : " row_off"}${pending?.removing ? " row_leaving" : ""}${
        s.developerName === this.justSaved ? " row_saved" : ""
      }`,
      style: `--i: ${index}`,
      chipStyle: `--chip: ${s.iconColour || "var(--setup-chip)"}`,
      iconName: s.icon || "utility:record",
      offText: active ? "" : "Inactive",
      categoryLabel: this.lensNames(s).join(", "),
      toggleLabel: `${name}: active`,
      viewLabel: `${name}: open`,
      editLabel: `Edit ${name}`,
      removeLabel: `Remove ${name}`
    };
  }

  async handleRemove(event) {
    const name = event.currentTarget.dataset.name;
    const source = this.sources.find((s) => s.developerName === name);
    const ok = await TimeDriveConfirm.open({
      size: "small",
      title: `Remove ${source.label}?`,
      message: "It comes off the timeline and out of this list, for good.",
      confirmLabel: "Remove"
    });
    if (!ok) return;
    if (this.view === "source") {
      this.viewing = undefined;
      this.show("parent");
    }
    this.pend(name, { active: false, removing: true });
    try {
      await removeSource({ developerName: name });
      this.unpend(name);
      this.sourceChanged(name, source.label, { removing: true });
    } catch (e) {
      this.unpend(name);
      this.toast("error", `${source.label} couldn't be removed`, plainError(e).message);
    }
  }

  // ---- home: view one source -------------------------------------------------

  async handleViewSource(event) {
    const name = event.currentTarget.dataset.name;
    const s = this.sources.find((x) => x.developerName === name);
    this.viewing = {
      ...s,
      name: this.sourceName(s),
      chipStyle: `--chip: ${s.iconColour || "var(--setup-chip)"}`,
      iconName: s.icon || "utility:record",
      kindLabel: TYPES.find((t) => t.value === s.type)?.label.replace(/s$/, "") ?? s.kind
    };
    this.show("source");
    try {
      const draft = await getSource({ developerName: name });
      if (this.viewing?.developerName !== name) return;
      this.viewing = { ...this.viewing, draft };
      // Its look at a glance: the wizard's previews, from what's saved.
      this.draft = {
        ...blankDraft(),
        ...draft,
        conditions: (draft.conditions ?? []).map(keyed),
        details: (draft.details ?? []).map(keyed)
      };
      this.uiKind = uiKindOf(this.draft);
      this.filterMode = this.draft.conditions.length ? "some" : this.draft.filter ? "fixed" : "all";
      this.fields = undefined;
      await this.loadSchema();
      this.syncPreviewObject();
    } catch (e) {
      this.toast("error", `${s.label} couldn't be read`, plainError(e).message);
    }
  }

  // The source page's "How it looks": where it sits in the filters and
  // legend (with its neighbours in the same view), and an opened item.
  // Every source on the record page, in legend order, the one being
  // viewed marked.
  get sourceFilterRows() {
    const v = this.viewing;
    if (!v) return [];
    const counts = [12, 7, 4, 9, 3, 15];
    return this.sources
      .filter((src) => (src.parentObject || "Contact") === this.viewParent)
      .sort((a, b) => (a.sequence ?? 0) - (b.sequence ?? 0) || a.label.localeCompare(b.label))
      .map((src, i) => {
        const mine = src.developerName === v.developerName;
        return {
          key: src.developerName,
          place: String(i + 1),
          name: src.legendName || src.eventLabel || src.label,
          view: this.lensNames(src).join(", "),
          icon: src.icon || "utility:record",
          chipStyle: `--chip: ${src.iconColour || "var(--setup-chip)"}`,
          count: String(counts[i % counts.length]),
          mine,
          className: `mock-filter-row${mine ? " mock-filter-row_mine" : ""}${src.active ? "" : " mock-filter-row_off"}`
        };
      });
  }

  get sourceFilterHead() {
    const n = this.sourceFilterRows.length;
    return `${n} ${n === 1 ? "source" : "sources"} on the ${PARENTS.find((p) => p.value === this.viewParent)?.label ?? this.viewParent} timeline`;
  }

  get viewParent() {
    return this.viewing?.parentObject || "Contact";
  }

  get viewFacts() {
    const d = this.viewing?.draft;
    const v = this.viewing;
    if (!v) return [];
    const facts = [
      { key: "type", label: "Comes from", value: v.kindLabel },
      { key: "records", label: "Records", value: v.objectLabel || d?.providerClass || "" },
      { key: "link", label: `Linked to the ${this.parentLabelOf(v.parentObject)} by`, value: this.viewLinkText },
      { key: "date", label: "Plotted by date", value: d?.dateField ? this.fieldLabel(d.dateField) : "" },
      { key: "filter", label: "Only the records where", value: this.viewFilterText },
      { key: "named", label: "Name in the filter", value: this.namedText },
      { key: "view", label: "Lens", value: this.lensNames(v).join(", ") || "None" },
      { key: "title", label: "Title", value: d?.title || "" },
      { key: "subtitle", label: "Subtitle", value: d?.subtitle || "" },
      { key: "opens", label: "When it is opened", value: d ? this.openAnswer : "" },
      { key: "clicks", label: "When its title is clicked", value: d && this.isSalesforce ? this.clickAnswer : "" }
    ];
    return facts.filter((f) => f.value);
  }

  // What the legend and filter call the source, as the viewer reads it
  // (translated where it is a label), and where it comes from when it is one.
  get namedText() {
    const v = this.viewing;
    if (!v || v.kind === "Apex") return "";
    const name = v.legendName || v.eventLabel || "";
    const raw = v.eventLabel?.trim() ?? "";
    if (name && raw.startsWith(LABEL_PREFIX)) return `${name} · custom label ${raw.slice(LABEL_PREFIX.length)}`;
    return name;
  }

  parentLabelOf(value) {
    return PARENTS.find((p) => p.value === (value || "Contact"))?.label ?? value ?? "record";
  }

  // How its records link to the record page's: the way chosen, in words.
  get viewLinkText() {
    if (!this.viewing?.draft) return "";
    return this.isSalesforce ? (this.chosenLink?.label ?? this.linkSlot ?? "") : (this.linkSlot ?? "");
  }

  // The filter they chose, if any: the conditions in words, or the filter
  // text a source ships with.
  get viewFilterText() {
    const d = this.viewing?.draft;
    if (!d || (!d.conditions?.length && !d.filter)) return "";
    return this.filterSummary;
  }

  // The open source, as its row shows it (active or not, pending).
  get viewingRow() {
    const s = this.sources.find((x) => x.developerName === this.viewing?.developerName);
    return s ? this.sourceCard(s, 0) : undefined;
  }

  async handleToggle(event) {
    const name = event.target.dataset.name;
    const active = event.target.checked;
    const source = this.sources.find((s) => s.developerName === name);
    const toggle = event.target;
    this.pend(name, { active });
    try {
      await setSourceActive({ developerName: name, active });
      this.unpend(name);
      this.sourceChanged(name, source.label, { active });
    } catch (e) {
      this.unpend(name);
      toggle.checked = !active;
      const error = plainError(e);
      this.toast("error", `${source.label} couldn't be made ${active ? "active" : "inactive"}`, error.message);
    }
  }

  handleRetryLoad() {
    this.loadError = undefined;
    this.progressLoaded = this.loadProgress();
    this.loadSources();
  }

  // ---- the wizard: starting and leaving ------------------------------------

  handleAdd() {
    this.resetWizard();
    this.draft = { ...blankDraft(), parentObject: this.selectedParent || "Contact" };
    this.editing = false;
    if (this.selectedParent) {
      this.parentChosen = true;
      this.stepIndex = 1;
      this.reached = 1;
    }
    this.show("wizard");
    this.focusScene();
  }

  async handleEdit(event) {
    const name = event.currentTarget.dataset.name;
    this.viewing = undefined;
    this.resetWizard();
    this.editing = true;
    this.show("wizard");
    this.loadingSchema = true;
    try {
      const draft = await getSource({ developerName: name });
      this.draft = {
        ...blankDraft(),
        ...draft,
        conditions: (draft.conditions ?? []).map(keyed),
        details: (draft.details ?? []).map(keyed)
      };
      this.uiKind = uiKindOf(this.draft);
      // Conditions the builder made open as rows; any other filter (one that
      // ships with a source) stays as the text it is.
      this.filterMode = this.draft.conditions.length ? "some" : this.draft.filter ? "fixed" : "all";
      // The data spaces decide the steps, so the last one is known after.
      await this.dataSpacesReady;
      this.fillOnlyDataSpace();
      // Editing opens on the last step: everything at a glance, each
      // answer one click away on the thread.
      this.stepIndex = this.flow.length - 1;
      this.reached = this.stepIndex;
      this.sceneSeq++;
      if (this.uiKind === "apex") this.loadApexProviders();
      else this.loadObjects();
      await this.loadSchema();
    } catch (e) {
      this.stepError = plainError(e);
    } finally {
      this.loadingSchema = false;
    }
    this.focusScene();
  }

  resetWizard() {
    this.lookTouched = false;
    this.legendModeChoice = undefined;
    this.legendDefaulted = false;
    this.legendPicked = false;
    this.legendCleared = false;
    this.clickPicked = false;
    this.clickCleared = false;
    this.labelText = undefined;
    this.legendKeys = undefined;
    this.legendTouched = false;
    this.uiKind = undefined;
    this.stepIndex = 0;
    this.reached = 0;
    this.direction = "forward";
    this.sceneSeq++;
    this.dirty = false;
    this.query = "";
    this.activeIndex = 0;
    this.tokenTarget = undefined;
    this.links = undefined;
    this.fields = undefined;
    this.stepError = undefined;
    this.saveError = undefined;
    this.saved = false;
    this.filterMode = "all";
    this.justSaved = undefined;
    this.parentChosen = false;
    this.rangeChosen = false;
    this.volumes = undefined;
    this.linkBrowsing = false;
  }

  // Unsaved answers are lost on leaving: ask first.
  async okToLeave() {
    if (this.saving) return false;
    if (!this.dirty) return true;
    return TimeDriveConfirm.open({
      size: "small",
      title: "Leave without saving?",
      message: "Your answers for this source will be lost.",
      confirmLabel: "Leave"
    });
  }

  get wizardTitle() {
    return this.editing ? `Editing ${this.draft.label || "a source"}` : "New source";
  }

  // ---- the wizard: steps ---------------------------------------------------

  get flow() {
    return FLOWS[this.uiKind] ?? FLOWS.standard;
  }

  async loadDataSpaces() {
    try {
      this.dataSpaces = (await getDataSpaces()) ?? [];
    } catch {
      this.dataSpaces = [];
    }
  }

  async loadData360Status() {
    try {
      this.data360Status = await getData360Status();
    } catch {
      this.data360Status = undefined;
    }
  }

  // The Data 360 kind is out of reach (shown, but disabled) without the add-on.
  isKindDisabled(value) {
    return value === "dmo" && this.data360Status?.ready === false;
  }

  // With one data space there's nothing to ask: a Data 360 source is in it.
  fillOnlyDataSpace() {
    if (this.uiKind === "dmo" && this.dataSpaces.length === 1 && !this.draft.dataSpace) {
      this.draft = { ...this.draft, dataSpace: this.dataSpaces[0].value };
    }
  }

  // Several data spaces: which one holds the engagement is asked on the
  // Records step, above the objects (the DMOs, their fields and identity
  // resolution all belong to one).
  get showSpaceChooser() {
    return this.stepKey === "object" && this.isDmo && this.dataSpaces.length > 1;
  }

  get spaceLabel() {
    return this.dataSpaces.find((s) => s.value === this.draft.dataSpace)?.label ?? this.draft.dataSpace ?? "";
  }

  get needsSpace() {
    return this.showSpaceChooser && !this.draft.dataSpace;
  }

  // The object list waits for its data space.
  get showPicker() {
    return this.isPickStep && !(this.stepKey === "object" && this.needsSpace);
  }

  get spaceOptions() {
    return this.dataSpaces.map((s) => ({ label: s.label, value: s.value }));
  }

  handleDataSpace(event) {
    this.chooseDataSpace(event.detail.value);
  }

  chooseDataSpace(value) {
    if (value === this.draft.dataSpace) return;
    // The DMO, its fields and its link belong to the old data space.
    this.fields = undefined;
    this.reached = this.stepIndex;
    this.update({ dataSpace: value, objectName: null, individualField: null, dateField: null });
    this.pickerOpen = true;
    this.query = "";
    this.loadObjects();
  }

  get stepKey() {
    return this.flow[this.stepIndex];
  }

  get question() {
    if (this.stepKey === "object" && this.isDmo) return "Which engagement should the timeline show?";
    if (this.stepKey === "look" && this.showWords) return "What should each item say, and look like?";
    if (this.stepKey === "open" && this.isSalesforce) return "What happens when someone opens or clicks an item?";
    return QUESTIONS[this.stepKey];
  }

  get hint() {
    switch (this.stepKey) {
      case "parent":
        return "Its timeline shows the records that belong to the one on the page.";
      case "object":
        return this.isDmo
          ? "Data model objects in Data 360 that you can read."
          : `Only ${this.uiKind === "custom" ? "custom" : "standard"} objects that link to a ${this.parentLabel} are listed.`;
      case "apex":
        return "Classes that extend TimeDriveApexSource.";
      case "date":
        return "The date places each item on the timeline.";
      case "lenses":
        return "A lens lets people narrow the timeline to one area, like Service. All is where the timeline opens: leave it out to show these items only in the lenses you choose.";
      case "range":
        return "Less history reads fewer records, so the timeline loads faster.";
      case "name":
        return "What the legend and filters call these items, where they sit in the legend, and the view they belong to.";
      case "look":
        return !this.showWords
          ? ""
          : "Choose the field each item's title shows, and up to two for its subtitle (read with a dot between them). A lookup (›) leads to a related record's fields: a member's Campaign › Name, say.";
      case "open":
        return this.isSalesforce
          ? "Opening an item shows more about it, right on the timeline. Clicking its title opens a record page: for a junction like Campaign Member, often the record it joins to. The previews use sample values."
          : "Opening an item shows more about it, right on the timeline. The preview uses sample values.";
      default:
        return "";
    }
  }

  // The scene re-renders as a new element on every step, so its entrance
  // plays each time: a one-item list keyed by the step.
  get scenes() {
    return [
      {
        key: `${this.stepKey}-${this.sceneSeq}`,
        className: `scene scene_${this.direction}`
      }
    ];
  }

  get isParentStep() {
    return this.stepKey === "parent";
  }

  get parentTiles() {
    const current = this.isAnswered("parent") ? this.draft.parentObject : null;
    return this.pages.map((p) => ({
      ...p,
      checked: String(p.value === current),
      className: `option option_kind${p.value === current ? " option_on" : ""}`
    }));
  }

  get parentLabel() {
    return PARENTS.find((p) => p.value === this.draft.parentObject)?.label ?? this.draft.parentObject ?? "record";
  }

  handleParent(event) {
    const value = event.currentTarget.dataset.value;
    if (value !== this.draft.parentObject) {
      // Everything after depends on the parent.
      this.uiKind = undefined;
      this.reached = 0;
      this.update({
        ...blankDraft(),
        label: this.draft.label,
        developerName: this.draft.developerName,
        parentObject: value
      });
    }
    this.parentChosen = true;
    this.afterPick();
  }

  get isKindStep() {
    return this.stepKey === "kind";
  }
  // Under the object picker, once an object is chosen and the list is closed.
  get isLinkStep() {
    return this.stepKey === "object" && this.isSalesforce && Boolean(this.draft.objectName) && !this.showPickerResults;
  }

  // Data 360: under the object, the field that holds the individual (or the
  // account), chosen for you when there's the usual one.
  get isIndividualStep() {
    return this.stepKey === "object" && this.isDmo && Boolean(this.draft.objectName) && !this.showPickerResults;
  }

  get individualQuestion() {
    return this.draft.parentObject === "Account"
      ? "Which field holds the account?"
      : "Which field holds the individual?";
  }

  get individualHint() {
    return this.draft.parentObject === "Account"
      ? "Data 360 matches the field's values to the Account's Id."
      : `Data 360 finds the ${this.parentLabel}'s unified profile, then reads the engagement of each individual in it.`;
  }

  get individualCombo() {
    return this.individualOptions.map((o) => ({ label: `${o.label} (${o.value})`, value: o.value }));
  }

  handleIndividualField(event) {
    this.update({ individualField: event.detail.value });
  }

  get linkQuestion() {
    // An account's records are tied to it by a field that holds the account.
    return this.draft.parentObject === "Account"
      ? "Which field holds the account?"
      : `How do they link to the ${this.parentLabel}?`;
  }
  // A date on a related record (a Task's due date, for a TaskRelation) is
  // chosen from the same box as the object's own: a lookup in its list leads
  // on, in the field picker, to that record's dates.
  relatedDateOpen = false;
  relatedStart;

  get dateTypes() {
    return DATE_TYPES;
  }

  get showRelatedDate() {
    return this.stepKey === "date" && this.isSalesforce && this.relatedDateOpen;
  }

  get relatedStartField() {
    return (this.fields ?? []).find((f) => f.name === this.relatedStart);
  }

  handleRelatedDatePick(event) {
    const { path, label } = event.detail;
    this.relatedDateOpen = false;
    this.pathLabels = { ...this.pathLabels, [path]: label };
    this.update({ dateField: path });
    this.afterPick();
  }

  handleRelatedDateClose() {
    this.relatedDateOpen = false;
  }

  // Icon and colour down the left, the title and subtitle down the right.
  get styleGridClass() {
    return `style-grid${this.showWords ? "" : " style-grid_solo"}`;
  }

  get isFilterStep() {
    // Under the way they link, once one is chosen.
    if (this.isSalesforce) return this.isLinkStep && this.isAnswered("link") && !this.linkBrowsing;
    return this.isIndividualStep && this.isAnswered("link");
  }
  get isNameStep() {
    return this.stepKey === "name";
  }
  // Apex classes say what their items read themselves: only style to pick.
  get showWords() {
    return this.uiKind !== "apex";
  }
  get isOpenStep() {
    return this.stepKey === "open";
  }

  get isLookStep() {
    return this.stepKey === "look";
  }
  // The last question: Save takes the place of Next.
  get isLastStep() {
    return this.stepIndex === this.flow.length - 1;
  }
  get isDmo() {
    return this.uiKind === "dmo";
  }
  get isApex() {
    return this.uiKind === "apex";
  }
  get isSalesforce() {
    return this.uiKind === "standard" || this.uiKind === "custom";
  }

  isAnswered(key) {
    const d = this.draft;
    switch (key) {
      case "parent":
        return Boolean(d.parentObject) && (this.parentChosen || this.editing);
      case "range":
        return this.rangeChosen || this.editing;
      case "kind":
        return Boolean(this.uiKind);
      case "object":
        return Boolean(d.objectName) && this.isAnswered("link");
      case "apex":
        return Boolean(d.providerClass);
      case "link":
        return this.isDmo ? Boolean(d.individualField) : Boolean(d.parentField || d.junctionObject);
      case "date":
        return Boolean(d.dateField);
      case "name":
        return Boolean(d.label?.trim()) && this.legendDecided;
      default:
        return true;
    }
  }

  // Why Continue is off, when it is.
  get blockedReason() {
    if (this.loadingSchema) return "Reading the object…";
    switch (this.stepKey) {
      case "parent":
        return this.isAnswered("parent") ? "" : "Choose one to continue.";
      case "range":
        return this.isAnswered("range") ? "" : "Choose how far back to continue.";
      case "kind":
        return this.uiKind ? "" : "Choose one to continue.";
      case "object":
        if (this.needsSpace) return "Choose a data space to continue.";
        if (!this.draft.objectName) return "Choose an object to continue.";
        return !this.isAnswered("link") ? "Choose a link to continue." : "";
      case "apex":
        return this.draft.providerClass ? "" : "Choose a class to continue.";
      case "link":
        return this.isAnswered("link") ? "" : "Choose a link to continue.";
      case "date":
        return this.draft.dateField ? "" : "Choose a date to continue.";
      case "name":
        if (!this.legendDecided) return "Choose how to name it to continue.";
        if (this.legendMode === "label" && !this.labelText) return "Choose a custom label that exists to continue.";
        return this.draft.label?.trim() ? "" : "Give it a name to continue.";
      case "open":
        if (this.isSalesforce && !this.clickDecided) return "Choose what a click on its title opens to continue.";
        if (!this.draft.details?.some((x) => x.field)) return "Add a field to continue.";
        if (this.isSalesforce && this.clickChoice === "related" && !this.draft.recordIdField)
          return "Choose the record a click opens to continue.";
        return "";
      default:
        return "";
    }
  }

  get continueDisabled() {
    return Boolean(this.blockedReason);
  }

  get backDisabled() {
    return this.stepIndex === 0 || Boolean(this.saving);
  }

  handleBack() {
    if (this.stepIndex > 0) this.goTo(this.stepIndex - 1);
  }

  handleContinue() {
    if (!this.continueDisabled) this.goTo(this.stepIndex + 1);
  }

  goTo(index) {
    const next = Math.max(0, Math.min(index, this.flow.length - 1));
    // Past Look only with a look people can see (WCAG contrast).
    if (next > this.flow.indexOf("look") && this.flow.includes("look") && this.stopForContrast()) return;
    this.direction = next < this.stepIndex ? "back" : "forward";
    this.stepIndex = next;
    this.syncPreviewObject();
    if (this.stepKey === "name") {
      if (this.legendMode === "label" && this.labelText === undefined) this.lookUpLabel();
      else this.syncLabel();
    }
    this.reached = Math.max(this.reached, next);
    this.sceneSeq++;
    this.stepError = undefined;
    this.query = "";
    // A pick step with nothing chosen yet opens its list; once chosen, it
    // shows the choice, closed, like a picklist.
    this.pickerOpen = this.isPickStep && !this.pickerValue;
    this.activeIndex = Math.max(
      0,
      this.pickerResults.findIndex((r) => r.selected)
    );
    this.tokenTarget = undefined;
    if (this.stepKey === "object") this.loadObjects();
    if (this.stepKey === "apex") this.loadApexProviders();
    if (this.stepKey === "range") this.loadVolumes();
    this.focusScene();
  }

  // After render: focus the search box on a pick screen, otherwise the
  // question, so keyboard and screen reader users start in the right place.
  focusScene() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    requestAnimationFrame(() => {
      const target =
        this.template.querySelector(".picker-input, .name-input") ?? this.template.querySelector(".question");
      target?.focus({ preventScroll: true });
      // Only the steps bar scrolls to the current step, never the page.
      const thread = this.template.querySelector(".thread");
      const current = thread?.querySelector(".knot_current");
      if (thread && current) {
        thread.scrollLeft = Math.max(0, current.offsetLeft - (thread.clientWidth - current.offsetWidth) / 2);
      }
    });
  }

  // Enter continues, wherever it isn't already doing something.
  handleKeydown(event) {
    const tag = event.target?.tagName;
    const inPicker = event.target?.closest?.(".picker, .token-picker");
    if (event.key === "Enter" && !event.shiftKey && tag !== "TEXTAREA" && tag !== "BUTTON" && !inPicker) {
      if (this.isLastStep) return;
      event.preventDefault();
      this.handleContinue();
    } else if (this.isKindStep && /^[1-9]$/.test(event.key) && tag !== "INPUT") {
      const kind = this.kindTiles[Number(event.key) - 1];
      if (kind) this.chooseKind(kind.value);
    }
  }

  // Every answer goes through here: the draft is replaced, so the page
  // re-renders.
  update(patch) {
    this.draft = { ...this.draft, ...patch };
    this.dirty = true;
  }

  // ---- the thread ----------------------------------------------------------

  // Each step's answer so far, in words (null when not answered).
  get answers() {
    const d = this.draft;
    const kind = KINDS.find((k) => k.value === this.uiKind);
    const colour = colourName(d.iconColour);
    return {
      parent: this.isAnswered("parent") ? this.parentLabel : null,
      kind: kind?.label ?? null,
      object: d.objectName
        ? (this.dataSpaces.length > 1 && d.dataSpace ? `${this.spaceLabel} · ` : "") +
          (this.linkSlot
            ? `${this.objectPlural} · ${this.linkSlot}${this.isFiltered ? ` · ${this.filterSlot}` : ""}`
            : this.objectPlural)
        : null,
      apex: d.providerClass || null,
      link: this.linkSlot,
      date: d.dateField ? this.fieldLabel(d.dateField) : null,

      lenses: this.reached > this.flow.indexOf("lenses") ? this.lensesAnswer : null,
      range: this.isAnswered("range")
        ? (RANGES.find((r) => r.months === (d.historyMonths ?? null))?.label ?? null)
        : null,
      name: d.label?.trim() || null,
      look:
        this.reached > this.flow.indexOf("look")
          ? this.showWords
            ? `${this.titleField ? this.fieldLabel(this.titleField) : "Its name"} · ${colour ?? "No colour chosen"}`
            : (colour ?? "No colour chosen")
          : null,
      open: this.reached > this.flow.indexOf("open") ? this.openingAnswer : null
    };
  }

  // The steps as knots on a rail, after the record page (the breadcrumb
  // says it). Answered knots show their answer; any step reached so far is
  // one click away, back or forward.
  stepName(step) {
    return step === "look" && !this.showWords ? "Style" : STEP_NAMES[step];
  }

  get thread() {
    const answers = this.answers;
    return this.flow
      .map((step, index) => ({ step, index }))
      .filter(({ step }) => step !== "parent" || !(this.parentChosen || this.editing))
      .map(({ step, index }, at) => {
        const current = index === this.stepIndex;
        const answer = answers[step];
        const done = !current && index <= this.reached && Boolean(answer);
        const reachable = index <= this.reached && !this.saving;
        return {
          key: step,
          step,
          number: `Step ${at + 1}`,
          name: this.stepName(step),
          answer: answer ?? "",
          ariaCurrent: current ? "step" : null,
          disabled: !reachable || current,
          ariaLabel: `${this.stepName(step)}${answer ? `: ${answer}` : ""}${current ? ", this step" : ""}`,
          className: `knot${current ? " knot_current" : ""}${done ? " knot_done" : ""}${reachable ? "" : " knot_todo"}`
        };
      });
  }

  // The answers so far, for the panel beside the question.
  get soFar() {
    return this.thread
      .filter((k) => k.answer && k.step !== this.stepKey)
      .map((k) => ({ key: k.key, step: k.step, name: k.name, answer: k.answer }));
  }

  get hasSoFar() {
    return this.soFar.length > 0;
  }

  // "Step 3 of 10", for the footer.
  get stepCountText() {
    const steps = this.thread;
    const at = steps.findIndex((k) => k.step === this.stepKey);
    return `Step ${at + 1} of ${steps.length}`;
  }

  get linkSlot() {
    const d = this.draft;
    if (this.isDmo) return d.individualField ? this.fieldLabel(d.individualField) : null;
    if (d.junctionObject) return this.objectLabelOf(d.junctionObject);
    return d.parentField ? this.fieldLabel(d.parentField) : null;
  }

  get isFiltered() {
    return Boolean(this.draft.conditions?.some((c) => c.field) || this.draft.filter);
  }

  get filterSlot() {
    const summary = this.filterSummary;
    return summary ? `Only where ${summary}` : "Every record";
  }

  handleKnot(event) {
    const index = this.flow.indexOf(event.currentTarget.dataset.step);
    if (index >= 0) this.goTo(index);
  }

  // ---- step: kind ----------------------------------------------------------

  get kindTiles() {
    return KINDS.map((k, i) => {
      const disabled = this.isKindDisabled(k.value);
      return {
        ...k,
        // Why it can't be chosen, in place of what it does.
        detail: disabled ? this.data360Status.reason : k.detail,
        disabled,
        shortcut: String(i + 1),
        checked: String(k.value === this.uiKind),
        className: `option option_kind${k.value === this.uiKind ? " option_on" : ""}`
      };
    });
  }

  handleKind(event) {
    this.chooseKind(event.currentTarget.dataset.value);
  }

  chooseKind(value) {
    if (this.isKindDisabled(value)) return;
    if (value !== this.uiKind) {
      const kind = value === "apex" ? "Apex" : value === "dmo" ? "Data 360" : "Salesforce";
      this.uiKind = value;
      this.reached = 1;
      this.links = undefined;
      this.fields = undefined;
      this.update({
        ...blankDraft(),
        label: this.draft.label,
        developerName: this.draft.developerName,
        sequence: this.draft.sequence,
        parentObject: this.draft.parentObject,
        kind,
        maxRecords: value === "dmo" ? 500 : 1000
      });
      this.fillOnlyDataSpace();
    }
    this.afterPick();
  }

  // Picks move straight on, after a beat that lets the choice show.
  // A pick never moves on by itself: the answer is selected and Next takes
  // focus, so Enter (or a click) goes on when the user is ready.
  afterPick() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    requestAnimationFrame(() => this.template.querySelector(".wz-foot .primary:not([disabled])")?.focus());
  }

  // ---- the search list (objects, classes, dates, individual fields) --------

  get isPickStep() {
    return ["object", "apex", "date"].includes(this.stepKey);
  }

  // Everything to choose from on this screen.
  get pickerItems() {
    switch (this.stepKey) {
      case "object":
        return this.objects.map((o) => ({ value: o.value, label: o.label, detail: o.detail }));
      case "apex":
        return (this.apexProviders ?? []).map((o) => ({ value: o.value, label: o.label, detail: o.detail }));
      case "date":
        return this.dateOptions;
      default:
        return [];
    }
  }

  get pickerValue() {
    const d = this.draft;
    return {
      object: d.objectName,
      apex: d.providerClass,
      date: d.dateField
    }[this.stepKey];
  }

  get pickerLabel() {
    return {
      object: "Search objects",
      apex: "Search classes",
      date: "Search date fields"
    }[this.stepKey];
  }

  get pickerPlaceholder() {
    const count = this.pickerItems.length;
    const noun = { object: "objects", apex: "classes", date: "date fields", link: "fields" }[this.stepKey];
    return count > 8 ? `Search ${count.toLocaleString()} ${noun}` : `Search ${noun}`;
  }

  get matchingItems() {
    const term = this.query.trim().toLowerCase();
    const items = this.pickerItems;
    if (!term) return items;
    const starts = [];
    const contains = [];
    for (const item of items) {
      const label = item.label.toLowerCase();
      if (label.startsWith(term)) starts.push(item);
      else if (label.includes(term) || item.value.toLowerCase().includes(term)) contains.push(item);
    }
    return [...starts, ...contains];
  }

  get pickerResults() {
    const term = this.query.trim().toLowerCase();
    const selected = this.pickerValue;
    return this.matchingItems.slice(0, RESULTS_SHOWN).map((item, i) => ({
      ...item,
      ...highlight(item.label, term),
      id: `result-${i}`,
      index: i,
      selected: item.value === selected,
      ariaSelected: String(i === this.activeIndex),
      className: `result${i === this.activeIndex ? " result_active" : ""}${item.value === selected ? " result_on" : ""}`
    }));
  }

  get pickerSelectedLabel() {
    const value = this.pickerValue;
    if (!value) return "";
    const listed = this.pickerItems.find((i) => i.value === value)?.label;
    // A date on a related record (Task.ActivityDate) isn't in the list: it reads Task › Due Date.
    return listed ?? (this.stepKey === "date" ? this.fieldLabel(value) : value);
  }

  // The box shows the choice when closed, and what's typed when open.
  get pickerInputValue() {
    return this.pickerOpen ? this.query : this.pickerSelectedLabel || this.query;
  }

  get pickerExpanded() {
    return String(this.pickerOpen);
  }

  get showPickerResults() {
    return this.pickerOpen;
  }

  openPicker() {
    if (this.pickerOpen) return;
    this.pickerOpen = true;
    this.query = "";
    this.activeIndex = Math.max(
      0,
      this.pickerResults.findIndex((r) => r.selected)
    );
  }

  handlePickerClick() {
    this.openPicker();
  }

  // Focus leaving the box and its list closes it.
  handlePickerFocusout(event) {
    if (!event.currentTarget.contains(event.relatedTarget)) {
      this.pickerOpen = false;
      this.query = "";
    }
  }

  // A click in the list mustn't take focus from the box first.
  handleResultsMousedown(event) {
    event.preventDefault();
  }

  get activeDescendant() {
    return this.pickerResults.length ? `result-${this.activeIndex}` : null;
  }

  get pickerMore() {
    const more = this.matchingItems.length - RESULTS_SHOWN;
    return more > 0 ? `${more.toLocaleString()} more. Keep typing to narrow them down.` : "";
  }

  get pickerEmpty() {
    if (this.pickerBusy) return "";
    if (!this.pickerItems.length) {
      switch (this.stepKey) {
        case "object":
          return this.isDmo
            ? "There are no Data 360 data model objects you can read here. Is Data 360 set up, with access to its data space?"
            : `No ${this.uiKind === "custom" ? "custom" : "standard"} objects you can read link to a ${this.parentLabel}.`;
        case "apex":
          return "No class here extends TimeDriveApexSource yet. Ask a developer to write one, then come back.";
        case "date":
          // Nothing at all to read is a matter of access, not of dates.
          return this.fields?.length
            ? `${this.objectLabel} has no date fields you can read, so its records can't go on the timeline.`
            : `You can't read any of ${this.objectLabel}'s fields, so its records can't go on the timeline. Ask an admin for read access to ${this.objectLabel}, then come back.`;
        default:
          return "There are no fields to choose from.";
      }
    }
    return this.matchingItems.length ? "" : `Nothing matches “${this.query.trim()}”.`;
  }

  get pickerBusy() {
    return this.loadingList || (this.loadingSchema && this.stepKey !== "object");
  }

  handleQuery(event) {
    this.pickerOpen = true;
    this.query = event.target.value ?? "";
    this.activeIndex = 0;
  }

  handlePickerKeydown(event) {
    const count = this.pickerResults.length;
    if (!this.pickerOpen && (event.key === "ArrowDown" || event.key === "ArrowUp")) {
      event.preventDefault();
      this.openPicker();
      return;
    }
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      if (!count) return;
      const step = event.key === "ArrowDown" ? 1 : -1;
      this.activeIndex = (this.activeIndex + step + count) % count;
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      requestAnimationFrame(() => this.template.querySelector(".result_active")?.scrollIntoView({ block: "nearest" }));
    } else if (event.key === "Enter") {
      event.preventDefault();
      const active = this.pickerOpen ? this.pickerResults[this.activeIndex] : null;
      if (active) this.pick(active.value);
      else if (!this.continueDisabled) this.handleContinue();
    } else if (event.key === "Escape" && this.pickerOpen) {
      event.preventDefault();
      event.stopPropagation();
      this.pickerOpen = false;
      this.query = "";
      this.activeIndex = 0;
    }
  }

  handleResultClick(event) {
    this.pick(event.currentTarget.dataset.value);
  }

  handleResultHover(event) {
    this.activeIndex = Number(event.currentTarget.dataset.index);
  }

  async pick(value) {
    // Chosen: the list closes and the box shows the choice.
    this.pickerOpen = false;
    this.query = "";
    switch (this.stepKey) {
      case "object":
        await this.chooseObject(value);
        break;
      case "apex":
        this.chooseApex(value);
        break;
      case "date":
        // A lookup in the list leads to the related record's dates.
        if (value.startsWith(LOOKUP_ROW)) {
          this.relatedStart = value.slice(LOOKUP_ROW.length);
          this.relatedDateOpen = true;
          this.pickerOpen = false;
          return;
        }
        this.relatedDateOpen = false;
        this.update({ dateField: value });
        break;
      default:
        return;
    }
    this.afterPick();
  }

  // ---- step: object --------------------------------------------------------

  async loadObjects() {
    const kind = this.uiKind;
    const parentObject = this.draft.parentObject;
    const dataSpace = kind === "dmo" ? (this.draft.dataSpace ?? null) : null;
    const key = this.objectsKey;
    if (!kind || kind === "apex" || this.objectsByKind[key] || this.needsSpace) return;
    this.loadingList = true;
    try {
      const objects = await getObjects({ kind, parentObject, dataSpace });
      this.objectsByKind = { ...this.objectsByKind, [key]: objects };
    } catch (e) {
      this.stepError = plainError(e);
    } finally {
      this.loadingList = false;
    }
  }

  // DMOs are listed per data space.
  get objectsKey() {
    const space = this.uiKind === "dmo" ? `:${this.draft.dataSpace ?? ""}` : "";
    return `${this.uiKind}:${this.draft.parentObject}${space}`;
  }

  get objects() {
    return this.objectsByKind[this.objectsKey] ?? [];
  }

  async chooseObject(value) {
    if (value === this.draft.objectName) return;
    const object = this.objects.find((o) => o.value === value);
    const previous = this.objectLabel;
    const d = this.draft;
    // Answers that came from the previous object no longer apply; names the
    // wizard suggested follow the new one.
    const suggested = (text) => !text || text === previous;
    const defaultLegend = this.isSalesforce ? DEFAULT_LEGEND_LABELS[value.toLowerCase()] : undefined;
    const file = this.isSalesforce && value.toLowerCase() === FILE_OBJECT;
    if (file) this.pathLabels = { ...this.pathLabels, [FILE_DATE]: FILE_DATE_LABEL };
    this.update({
      objectName: value,
      parentField: null,
      junctionObject: null,
      junctionParentField: null,
      junctionRecordField: null,
      individualField: null,
      dateField: file ? FILE_DATE : null,
      conditions: [],
      filter: null,
      details: file
        ? FILE_DETAILS.map(keyed)
        : this.isSalesforce && ACTIVITY_OBJECTS.has(value.toLowerCase())
          ? ACTIVITY_DETAILS.map(keyed)
          : [],
      highlights: [],
      // A file's click opens its document, whatever the link says.
      recordIdField: file ? "ContentDocumentId" : null,
      label: suggested(d.label) ? object.label : d.label,
      // Salesforce objects: blank is the object's own (translated) name; a few
      // start on a custom label of ours, which is translated too.
      eventLabel: this.isDmo
        ? suggested(d.eventLabel)
          ? object.label
          : d.eventLabel
        : defaultLegend
          ? `${LABEL_PREFIX}${defaultLegend}`
          : "",
      title: file ? "{ContentDocument.Title}" : suggested(d.title) ? object.label : d.title,
      subtitle: file
        ? "{ContentDocument.FileType}"
        : this.isDmo
          ? d.subtitle
          : suggested(d.subtitle)
            ? "{Name}"
            : d.subtitle,
      icon: this.lookTouched
        ? (d.icon ?? OBJECT_ICONS[value.toLowerCase()] ?? (this.isDmo ? "utility:world" : "utility:record"))
        : (OBJECT_ICONS[value.toLowerCase()] ?? (this.isDmo ? "utility:world" : "utility:record")),
      iconColour: this.lookTouched ? d.iconColour : null
    });
    // Salesforce's own icon and colour for it, where known at once.
    this.applyObjectLook();
    this.reached = this.stepIndex;
    this.filterMode = "all";
    this.volumes = undefined;
    // Its name starts on the custom label, chosen, with what it reads as; going
    // on to another object takes that choice back.
    if (defaultLegend) {
      this.legendPicked = true;
      this.legendCleared = false;
      this.legendDefaulted = true;
      this.lookUpLabel();
    } else if (this.legendDefaulted) {
      this.legendPicked = false;
      this.legendDefaulted = false;
    }
    await this.loadSchema();
    this.suggestAnswers();
  }
  legendDefaulted = false;

  // A Task whose filter is one kind of activity (TaskSubtype is Call, or Email)
  // starts on that kind's custom label; changing the filter follows it, until
  // the name has been chosen by hand.
  syncDefaultLegend() {
    if (!this.isSalesforce || String(this.draft.objectName).toLowerCase() !== "task") return;
    const condition = (this.draft.conditions ?? []).find((c) => c.field === "TaskSubtype" && c.operator === "equals");
    const name = TASK_SUBTYPE_LEGENDS[String(condition?.value ?? "").toLowerCase()];
    if (name && (!this.legendPicked || this.legendDefaulted)) {
      this.update({ eventLabel: `${LABEL_PREFIX}${name}` });
      this.legendPicked = true;
      this.legendCleared = false;
      this.legendDefaulted = true;
      this.lookUpLabel();
    } else if (!name && this.legendDefaulted) {
      this.update({ eventLabel: "" });
      this.legendPicked = false;
      this.legendDefaulted = false;
    }
  }

  // Fields and links for the chosen object. Each read is timed to the console
  // (Time Drive setup: …), and one that is still not back after SCHEMA_PATIENCE
  // says which, with a way to try again, instead of leaving the step spinning.
  async loadSchema() {
    const objectName = this.draft.objectName;
    if (!objectName) return;
    this.loadingSchema = true;
    const waiting = new Set(["fields", ...(this.isSalesforce ? ["links"] : [])]);
    const timed = (name, promise) =>
      promise.finally(() => {
        waiting.delete(name);
      });
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    const timer = setTimeout(() => {
      if (!waiting.size || objectName !== this.draft.objectName) return;
      this.stepError = {
        message: "Reading this object is taking longer than expected.",
        cause: `Still waiting for its ${[...waiting].join(" and ")}. Choose it again to try once more.`
      };
      this.loadingSchema = false;
    }, SCHEMA_PATIENCE);
    try {
      const [fields, links] = await Promise.all([
        timed("fields", getFields({ objectName })),
        this.isSalesforce
          ? timed("links", getLinks({ parentObject: this.draft.parentObject, objectName }))
          : Promise.resolve([])
      ]);
      if (objectName !== this.draft.objectName) return;
      this.stepError = undefined;
      this.fields = fields;
      this.links = links;
      // The related records a saved source reads fields from, for their labels.
      for (const path of [this.draft.dateField, ...(this.draft.conditions ?? []).map((c) => c.field)]) {
        if (path?.includes(".")) this.loadPathFields(path);
      }
    } catch (e) {
      this.stepError = plainError(e);
    } finally {
      clearTimeout(timer);
      this.loadingSchema = false;
    }
  }

  // Answers worth guessing: the only link, the Data 360 defaults, and a
  // Name field for the subtitle.
  suggestAnswers() {
    const patch = {};
    const has = (name) => this.fields?.some((f) => f.name === name);
    if (this.isSalesforce && this.links?.length === 1) Object.assign(patch, this.linkPatch(this.links[0]));
    if (this.isDmo) {
      if (has("ssot__IndividualId__c")) patch.individualField = "ssot__IndividualId__c";
      if (has("ssot__EngagementDateTm__c")) patch.dateField = "ssot__EngagementDateTm__c";
    }
    if (this.isSalesforce && !has("Name") && this.draft.subtitle === "{Name}") patch.subtitle = "";
    if (Object.keys(patch).length) this.update(patch);
  }

  // ---- step: Apex class ----------------------------------------------------

  async loadApexProviders() {
    if (this.apexProviders) return;
    this.loadingList = true;
    try {
      this.apexProviders = await getApexProviders();
    } catch (e) {
      this.stepError = plainError(e);
    } finally {
      this.loadingList = false;
    }
  }

  chooseApex(value) {
    if (value === this.draft.providerClass) return;
    const d = this.draft;
    const suggested = (text) => !text || text === d.providerClass;
    this.update({
      providerClass: value,
      label: suggested(d.label) ? value : d.label,
      eventLabel: suggested(d.eventLabel) ? value : d.eventLabel,
      icon: d.icon ?? "utility:apex"
    });
  }

  // ---- step: link ----------------------------------------------------------

  // Every way they link, in order: with many, master-detail first, then
  // lookups, then links through a related object, each by name.
  get allLinkChoices() {
    const d = this.draft;
    const choices = (this.links ?? []).map((l) => {
      const on = l.junctionObject
        ? l.junctionObject === d.junctionObject && l.junctionRecordField === d.junctionRecordField
        : !d.junctionObject && l.parentField === d.parentField;
      return {
        ...l,
        icon: l.junctionObject ? "utility:merge" : "utility:link",
        kindText: l.kindText || (l.junctionObject ? "Through a related object" : `A lookup to the ${this.parentLabel}`),
        checked: String(on),
        className: `option${this.manyLinks ? " option_compact" : ""}${on ? " option_on" : ""}`,
        group: l.junctionObject ? 2 : l.masterDetail ? 0 : 1
      };
    });
    if (!this.manyLinks) return choices;
    const name = (l) => (l.fieldLabel || l.how || l.label || "").toLowerCase();
    return choices.sort((a, b) => a.group - b.group || name(a).localeCompare(name(b)));
  }

  // Many options (a busy org: 20 lookups and a few master-detail) become a
  // searchable, grouped list instead of a wall of cards.
  get manyLinks() {
    return (this.links?.length ?? 0) > MANY_LINKS;
  }

  linkQuery = "";

  handleLinkQuery(event) {
    this.linkQuery = event.detail?.value ?? event.target.value ?? "";
  }

  // What the search leaves, with each group's heading on its first.
  get linkChoices() {
    const term = this.linkQuery.trim().toLowerCase();
    const all = this.allLinkChoices;
    const shown =
      !this.manyLinks || !term
        ? all
        : all.filter((l) =>
            [l.label, l.how, l.kindText, l.fieldLabel].some((t) => (t ?? "").toLowerCase().includes(term))
          );
    const heads = ["Master-detail", "Lookups", "Through a related object"];
    return shown.map((l, i) => ({
      ...l,
      groupHeading: this.manyLinks && (i === 0 || shown[i - 1].group !== l.group) ? heads[l.group] : "",
      groupKey: `group-${l.key}`
    }));
  }

  // The search shows only while the list does.
  get showLinkSearch() {
    return this.manyLinks && !this.linkFocused;
  }

  get noLinkMatches() {
    return this.manyLinks && this.linkChoices.length === 0;
  }

  get linkCountText() {
    const shown = this.linkChoices.length;
    const all = this.links?.length ?? 0;
    return shown === all ? `${all} ways they link` : `${shown} of ${all} ways they link`;
  }

  // Once a link is chosen, the list gives way to the choice (with a close
  // button back to every option) and, beside it, what it means: a few plain
  // words over a small diagram of the objects and the lookups between them.
  linkBrowsing = false;

  get chosenLink() {
    return this.allLinkChoices.find((l) => l.checked === "true");
  }

  get linkFocused() {
    return Boolean(this.chosenLink) && !this.linkBrowsing;
  }

  get linkOptionsClass() {
    return `options${this.manyLinks ? " options_many" : ""}${this.linkFocused ? " options_hidden" : ""}`;
  }

  handleLinkChange() {
    this.linkBrowsing = true;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    requestAnimationFrame(() => this.template.querySelector(".options .option_on")?.focus());
  }

  // "Each Task has a Name field pointing to one Contact…"
  get linkStory() {
    const l = this.chosenLink;
    if (!l) return "";
    const parent = l.parentLabel || this.parentLabel;
    const object = l.objectLabel || this.objectLabel;
    const plural = this.objectPlural || object;
    // "Contact ID" reads "Contact" in a sentence, with its API name for clarity.
    const field = (label, api) => `${(label ?? "").replace(/\s+ID$/i, "")} (${api})`;
    if (l.junctionObject) {
      const junction = l.junctionLabel || l.junctionObject;
      return `${junction} records join ${parent}s to ${plural}. Each one points to one ${parent} (its ${field(l.fieldLabel, l.junctionParentField)} field) and one ${object} (its ${field(l.recordFieldLabel, l.junctionRecordField)} field). The timeline shows every ${object} joined to the ${parent} on the page.`;
    }
    return `Each ${object} has a ${field(l.fieldLabel, l.parentField)} field that points to one ${parent}. The timeline shows the ${plural} that point to the ${parent} on the page.`;
  }

  get linkKindText() {
    const l = this.chosenLink;
    if (!l) return "";
    if (l.junctionObject) return "A junction object between the two";
    return l.masterDetail ? "A master-detail relationship" : "A lookup relationship";
  }

  get linkKindNote() {
    const l = this.chosenLink;
    if (!l) return "";
    if (l.note) return l.note;
    if (l.junctionObject) return "";
    return l.masterDetail
      ? `Master-detail: an ${l.objectLabel} can't exist without its ${l.parentLabel}.`
      : `Lookup: the field can be blank, so some ${this.objectPlural} may belong to no ${l.parentLabel}.`;
  }

  get noLinksTitle() {
    return `Nothing links ${this.objectPlural} to a ${this.parentLabel}.`;
  }

  get noLinksText() {
    return `The timeline needs a lookup to ${this.parentLabel}, on the object or on a related object. Add one, or choose other records.`;
  }

  get noLinks() {
    return this.isSalesforce && this.links && !this.links.length;
  }

  linkPatch(link) {
    return {
      parentField: link.junctionObject ? null : link.parentField,
      junctionObject: link.junctionObject ?? null,
      junctionParentField: link.junctionParentField ?? null,
      junctionRecordField: link.junctionRecordField ?? null
    };
  }

  handleLink(event) {
    const link = this.links.find((l) => l.key === event.currentTarget.dataset.key);
    this.update(this.linkPatch(link));
    this.linkBrowsing = false;
    this.linkQuery = "";
    this.afterPick();
  }

  get individualOptions() {
    const fields = (this.fields ?? []).filter((f) => f.type === "string" || f.type === "reference" || f.type === "id");
    // Individual fields first: they're nearly always the answer.
    const rank = (f) => (/individual/i.test(f.name) ? 0 : 1);
    return [...fields]
      .sort((a, b) => rank(a) - rank(b))
      .map((f) => ({ value: f.name, label: f.label, detail: f.name, tag: rank(f) === 0 ? "Usual" : "" }));
  }

  // ---- step: date ----------------------------------------------------------

  get dateOptions() {
    const dates = (this.fields ?? []).filter((f) => f.type === "date" || f.type === "datetime");
    // The object's own dates before the system's (Created, Last Modified…).
    const system =
      /^(\w+\.)?(CreatedDate|LastModifiedDate|SystemModstamp|LastActivityDate|LastViewedDate|LastReferencedDate)$/;
    const rank = (f) => (system.test(f.name) ? 1 : 0);
    const own = [...dates]
      .sort((a, b) => rank(a) - rank(b))
      .map((f, i) => ({
        value: f.name,
        label: f.label,
        detail: f.type === "date" ? "Date" : "Date and time",
        tag:
          f.name === "ssot__EngagementDateTm__c" ? "Usual" : !this.isDmo && i === 0 && rank(f) === 0 ? "Suggested" : ""
      }));
    // Then the lookups, each leading on to its record's dates.
    const related = this.isSalesforce
      ? this.relatedLookups.map((f) => ({
          value: `${LOOKUP_ROW}${f.name}`,
          label: `${f.label} ›`,
          detail: `A date on the related ${this.objectLabelOf(f.referenceTo) || f.referenceTo}`,
          tag: ""
        }))
      : [];
    return [...own, ...related];
  }

  // ---- step: filter --------------------------------------------------------

  get filterChoices() {
    const some = this.filterMode !== "all";
    return [
      {
        value: "all",
        label: "Every one",
        detail: `Every record that links to the ${this.parentLabel}.`,
        icon: "utility:list",
        on: !some
      },
      {
        value: "some",
        label: "Only some",
        detail: "Only records that meet conditions you set.",
        icon: "utility:filterList",
        on: some
      }
    ].map((c) => ({ ...c, checked: String(c.on), className: `option${c.on ? " option_on" : ""}` }));
  }

  get showConditions() {
    return this.filterMode === "some";
  }

  // A filter the builder can't show (an OR, a NOT IN ...): kept as it is
  // until it's replaced with conditions.
  get filterFixed() {
    return this.filterMode === "fixed";
  }

  handleFilterMode(event) {
    const mode = event.currentTarget.dataset.value;
    if (mode === "all") {
      this.filterMode = "all";
      this.update({ conditions: [], filter: null });
      this.syncDefaultLegend();
      this.afterPick();
    } else if (this.filterMode === "all") {
      this.filterMode = "some";
      if (!this.draft.conditions.length) this.handleAddCondition();
    }
  }

  get conditionFieldOptions() {
    const own = (this.fields ?? [])
      .filter((f) => f.filterable && f.type !== "textarea" && f.type !== "multipicklist" && f.type !== "address")
      .map((f) => ({ label: f.label, value: f.name }));
    // The related fields already chosen show as chosen; a new one is picked
    // object first, then field, so this list stays the object's own.
    const chosen = [...new Set((this.draft.conditions ?? []).map((c) => c.field).filter((f) => f?.includes(".")))].map(
      (path) => ({ label: this.fieldLabel(path), value: path })
    );
    const related = this.hasLookups ? [{ label: "A field on a related record…", value: RELATED_FIELD }] : [];
    return [...own, ...chosen, ...related];
  }

  get hasLookups() {
    return (this.fields ?? []).some((f) => f.referenceTo && f.relationshipName);
  }

  // The condition whose related field is being picked (the picker shows under the list).
  relatedFilterIndex;

  get relatedFilterOpen() {
    return this.relatedFilterIndex !== undefined;
  }

  handleRelatedFilterPick(event) {
    const { path, label, field } = event.detail;
    const index = this.relatedFilterIndex;
    this.relatedFilterIndex = undefined;
    this.pathLabels = { ...this.pathLabels, [path]: label };
    this.pathInfo = { ...this.pathInfo, [path]: { ...field, name: path } };
    const valueType = valueTypeOf(field.type);
    const conditions = this.draft.conditions.map((c, i) => {
      if (i !== index) return c;
      return {
        ...c,
        field: path,
        valueType,
        operator: valueType === "datetime" ? "greater" : "equals",
        value: valueType === "boolean" ? "true" : ""
      };
    });
    this.update({ conditions });
  }

  handleRelatedFilterClose() {
    this.relatedFilterIndex = undefined;
  }

  get conditionRows() {
    return (this.draft.conditions ?? []).map((c, index) => {
      const field = this.fieldInfo(c.field);
      const type = field?.type;
      const group = type === "boolean" ? "boolean" : type === "picklist" ? "picklist" : valueTypeOf(type);
      const valueless = c.operator === "blank" || c.operator === "notBlank";
      const several = c.operator === "oneOf" || c.operator === "notOneOf";
      return {
        ...c,
        index,
        operators: OPERATORS[group] ?? OPERATORS.text,
        picklistValues: field?.values?.map((v) => ({ label: v.label, value: v.value })) ?? [],
        isPicklistList: several && group === "picklist",
        isPicklist: !valueless && !several && group === "picklist",
        isBoolean: !valueless && group === "boolean",
        isDate: !valueless && (group === "date" || group === "datetime"),
        isNumber: !valueless && group === "number",
        isText: !valueless && group === "text",
        noField: !c.field,
        joinText: index === 0 ? "Where" : this.draft.match === "any" ? "or" : "and",
        removeLabel: `Remove condition ${index + 1}`
      };
    });
  }

  handleAddCondition() {
    this.update({
      conditions: [...this.draft.conditions, keyed({ field: null, operator: "equals", value: "", valueType: "text" })]
    });
  }

  handleConditionChange(event) {
    const index = Number(event.target.dataset.index);
    const part = event.target.dataset.part;
    const value = event.detail.value ?? event.target.value;
    if (part === "field" && value === RELATED_FIELD) {
      this.relatedFilterIndex = index;
      // Back to what was chosen, so the box doesn't read as the new choice.
      this.update({ conditions: [...this.draft.conditions] });
      return;
    }
    const conditions = this.draft.conditions.map((c, i) => {
      if (i !== index) return c;
      if (part === "field") {
        if (value === RELATED_FIELD) return c;
        const valueType = valueTypeOf(this.fieldInfo(value)?.type);
        const operator = valueType === "datetime" ? "greater" : "equals";
        return { ...c, field: value, valueType, operator, value: valueType === "boolean" ? "true" : "" };
      }
      if (part === "operator") {
        // One value or several: what was chosen carries over.
        const several = value === "oneOf" || value === "notOneOf";
        return several
          ? { ...c, operator: value, values: c.values?.length ? c.values : c.value ? [c.value] : [], value: "" }
          : { ...c, operator: value, value: c.value || c.values?.[0] || "", values: undefined };
      }
      return { ...c, [part]: value };
    });
    this.update({ conditions });
    this.syncDefaultLegend();
  }

  // All of the conditions, or any of them.
  get matchOptions() {
    return [
      { label: "All of these", value: "all" },
      { label: "Any of these", value: "any" }
    ];
  }

  get showMatch() {
    return (this.draft.conditions?.length ?? 0) > 1;
  }

  handleMatch(event) {
    this.update({ match: event.detail.value });
    this.syncDefaultLegend();
  }

  handleRemoveCondition(event) {
    const index = Number(event.currentTarget.dataset.index);
    const conditions = this.draft.conditions.filter((_, i) => i !== index);
    if (!conditions.length) this.filterMode = "all";
    this.update({ conditions });
    this.syncDefaultLegend();
  }

  handleReplaceFilter() {
    this.filterMode = "some";
    this.update({ filter: null, conditions: [] });
    this.handleAddCondition();
  }

  // ---- step: lenses --------------------------------------------------------
  // One or more of the timeline's lenses (its picker's views), or none.

  get isLensesStep() {
    return this.stepKey === "lenses";
  }

  get lensesAnswer() {
    return this.shownLenses(this.draftLenses)
      .map((key) => this.viewNameOf(key))
      .join(", ");
  }

  get draftLenses() {
    return this.draft.lenses ?? (this.draft.category ? [this.draft.category] : []);
  }

  get lensChoices() {
    const chosen = new Set(this.shownLenses(this.draftLenses));
    return this.lensColumns.map((c) => ({
      key: c.key,
      label: c.name,
      pressed: String(chosen.has(c.key)),
      className: `chip-choice${chosen.has(c.key) ? " chip-choice_on" : ""}`
    }));
  }

  get hasLensChoices() {
    return this.lensChoices.length > 0;
  }

  // Where its items will show, in words.
  get lensesShownUnder() {
    return this.shownLenses(this.draftLenses)
      .map((key) => this.viewNameOf(key))
      .join(" · ");
  }

  // At least one lens stays chosen: a source in none would be in All anyway.
  handleLensChoice(event) {
    const key = event.currentTarget.dataset.value;
    const now = this.shownLenses(this.draftLenses);
    const next = now.includes(key) ? now.filter((k) => k !== key) : [...now, key];
    if (!next.length) return;
    const order = this.lensColumns.map((c) => c.key);
    next.sort((a, b) => order.indexOf(a) - order.indexOf(b));
    this.update({ lenses: next, category: next[0] ?? null });
  }

  // ---- step: range ---------------------------------------------------------

  get isRangeStep() {
    return this.stepKey === "range";
  }

  // Counts what each range would read, so the choice is an informed one.
  async loadVolumes() {
    if (this.isApex || !this.draft.objectName || !this.draft.dateField) {
      this.volumes = undefined;
      return;
    }
    const seq = ++this.volumeSeq;
    this.loadingVolumes = true;
    try {
      const volumes = await getVolumes({ draftJson: this.draftJson() });
      if (seq === this.volumeSeq) this.volumes = volumes;
    } catch {
      // Not counted: the step goes on without volumes.
      if (seq === this.volumeSeq) this.volumes = undefined;
    } finally {
      if (seq === this.volumeSeq) this.loadingVolumes = false;
    }
  }

  volumeSeq = 0;

  get hasVolumes() {
    return this.volumes?.total != null;
  }

  // "1,240 Customer Orders, on 310 Contacts."
  get volumeHeadline() {
    const v = this.volumes;
    if (!v || v.total == null) return "";
    const total = `${v.total.toLocaleString()}${v.more ? "+" : ""}`;
    const parents = v.parents ? `, on ${v.parents.toLocaleString()} ${this.parentLabel}s` : "";
    return `${total} ${v.total === 1 ? this.objectLabel : this.objectPlural} in all${parents}.`;
  }

  get volumeUnavailable() {
    return !this.isApex && !this.loadingVolumes && this.volumes && this.volumes.total == null;
  }

  get rangeChoices() {
    const v = this.volumes;
    const cap = this.draft.maxRecords || 1000;
    const countFor = (months) => (months == null ? v?.total : v?.ranges?.find((r) => r.months === months)?.count);
    const moreFor = (months) => (months == null ? v?.more : v?.ranges?.find((r) => r.months === months)?.more);
    const each = (count) => (v?.parents && count != null ? count / v.parents : null);
    // The suggestion: the most history that keeps each record's items
    // under the cap.
    let suggested;
    if (v?.total != null) {
      for (const r of [...RANGES].reverse()) {
        const count = countFor(r.months);
        const per = each(count);
        if (count != null && !moreFor(r.months) && (per == null ? count <= cap : per <= cap)) {
          suggested = r.months;
          break;
        }
      }
    }
    const current = this.isAnswered("range") ? (this.draft.historyMonths ?? null) : undefined;
    return RANGES.map((r) => {
      const count = countFor(r.months);
      const per = each(count);
      let detail = "";
      if (count != null) {
        detail = `${count.toLocaleString()}${moreFor(r.months) ? "+" : ""} ${count === 1 ? "record" : "records"}`;
        if (per != null)
          detail += `, about ${per < 1 ? "1" : Math.round(per).toLocaleString()} per ${this.parentLabel}`;
      }
      const busy = per != null && per > cap;
      return {
        key: String(r.months),
        value: r.months == null ? "" : String(r.months),
        label: r.label,
        detail: detail || (this.loadingVolumes ? "Counting…" : ""),
        tag: busy ? `Over the ${cap.toLocaleString()} cap` : r.months === suggested ? "Suggested" : "",
        tagClass: `option-tag${busy ? " option-tag_warn" : ""}`,
        checked: String(r.months === current),
        className: `option option_range${r.months === current ? " option_on" : ""}`
      };
    });
  }

  handleRange(event) {
    const value = event.currentTarget.dataset.value;
    this.rangeChosen = true;
    this.update({ historyMonths: value === "" ? null : Number(value) });
    this.afterPick();
  }

  // ---- step: name ----------------------------------------------------------

  // ---- step: words ---------------------------------------------------------

  get hasFields() {
    return this.fields?.length > 0;
  }

  get tokenFields() {
    return (this.fields ?? []).filter((f) => f.type !== "address" && f.type !== "location");
  }

  // The title or subtitle as the timeline would show it: words, and chips
  // for the fields that fill in per item.
  partsOf(text) {
    const out = [];
    const source = text ?? "";
    const pattern = /\{([^}]+)\}/g;
    let last = 0;
    let i = 0;
    let match;
    while ((match = pattern.exec(source)) !== null) {
      if (match.index > last) out.push({ key: `w${i++}`, className: "plain", text: source.slice(last, match.index) });
      out.push({ key: `f${i++}`, className: "token", text: this.fieldLabel(match[1]) });
      last = pattern.lastIndex;
    }
    if (last < source.length) out.push({ key: `w${i++}`, className: "plain", text: source.slice(last) });
    return out;
  }

  // The title is one field: the first {Field} in what's kept, or none (the
  // title then shows the source's name). The subtitle is up to two, read
  // with a dot between them ("{Owner.Name} · {What.Name}").
  firstField(text) {
    return /\{([^}]+)\}/.exec(text ?? "")?.[1] ?? "";
  }

  fieldsIn(text) {
    return [...(text ?? "").matchAll(/\{([^}]+)\}/g)].map((m) => m[1]).slice(0, MAX_SUBTITLE_FIELDS);
  }

  get subtitleFields() {
    return this.isEmailMessage ? [] : this.fieldsIn(this.draft.subtitle);
  }

  // The subtitle from its fields, in order, a dot between them.
  subtitleOf(fields) {
    return fields
      .filter(Boolean)
      .map((f) => `{${f}}`)
      .join(SUBTITLE_SEPARATOR);
  }

  get titleField() {
    return this.firstField(this.draft.title);
  }

  get subtitleField() {
    return this.subtitleFields[0] ?? "";
  }

  get subtitleSecondField() {
    return this.subtitleFields[1] ?? "";
  }

  get titleChoice() {
    return this.titleField ? this.fieldLabel(this.titleField) : "None: its name";
  }

  get subtitleChoice() {
    if (this.isEmailMessage) return EMAIL_SUBTITLE;
    return this.subtitleField ? this.fieldLabel(this.subtitleField) : "None";
  }

  get titleChoiceClass() {
    return `field-choice-name${this.titleField ? "" : " field-choice-name_none"}`;
  }

  get subtitleChoiceClass() {
    return `field-choice-name${this.subtitleField ? "" : " field-choice-name_none"}`;
  }

  // The second field: offered once there's a first.
  get showSubtitleSecond() {
    return Boolean(this.subtitleField) && !this.isEmailMessage;
  }

  get subtitleSecondChoice() {
    return this.subtitleSecondField ? this.fieldLabel(this.subtitleSecondField) : "Add a second field";
  }

  get subtitleSecondChoiceClass() {
    return `field-choice-name${this.subtitleSecondField ? "" : " field-choice-name_none"}`;
  }

  get subtitleSecondLabel() {
    return `Subtitle, second field: ${this.subtitleSecondField ? this.fieldLabel(this.subtitleSecondField) : "none"}`;
  }

  get canClearSubtitleSecond() {
    return Boolean(this.subtitleSecondField);
  }

  get subtitleSecondTokensOpen() {
    return this.tokenTarget === "subtitle2";
  }

  get cannotChooseTitleField() {
    return !this.hasFields;
  }

  get canClearTitle() {
    return Boolean(this.titleField);
  }

  get canClearSubtitle() {
    return Boolean(this.subtitleField);
  }

  // Email Messages' subtitle is the timeline's own (sender, then who it was
  // sent to; see TimeDriveEmails), so it isn't edited here.
  get isEmailMessage() {
    return this.draft?.objectName === "EmailMessage";
  }

  get cannotChooseSubtitleField() {
    return !this.hasFields || this.isEmailMessage;
  }

  get canAddSubtitleChoice() {
    return !this.cannotChooseSubtitleField;
  }

  // Taken off: the title shows the source's name again; a subtitle field
  // goes, and a second one moves up to first.
  handleFieldClear(event) {
    const field = event.currentTarget.dataset.field;
    if (field === "subtitle" || field === "subtitle2") {
      const fields = [...this.subtitleFields];
      fields.splice(field === "subtitle" ? 0 : 1, 1);
      this.update({ subtitle: this.subtitleOf(fields) });
    } else {
      this.update({ [field]: "" });
    }
    this.tokenTarget = undefined;
  }

  get titleParts() {
    return this.partsOf(this.titleField ? `{${this.titleField}}` : this.draft.label || "Title");
  }

  get subtitleParts() {
    if (this.isEmailMessage) return [{ key: "email", text: EMAIL_SAMPLE_SUBTITLE, className: "plain" }];
    return this.partsOf(this.subtitleOf(this.subtitleFields));
  }

  get titleTokensOpen() {
    return this.tokenTarget === "title";
  }

  get subtitleTokensOpen() {
    return this.tokenTarget === "subtitle";
  }

  handleTokenOpen(event) {
    const target = event.currentTarget.dataset.field;
    // The picker focuses its own search when it opens.
    this.tokenTarget = this.tokenTarget === target ? undefined : target;
  }

  // The field chosen takes the place of the one there.
  insertToken(name) {
    if (this.tokenTarget === "subtitle" || this.tokenTarget === "subtitle2") {
      const fields = [...this.subtitleFields];
      fields[this.tokenTarget === "subtitle" ? 0 : 1] = name;
      this.update({ subtitle: this.subtitleOf(fields) });
    } else {
      this.update({ [this.tokenTarget]: `{${name}}` });
    }
    this.tokenTarget = undefined;
  }

  // ---- step: look ----------------------------------------------------------

  // ---- step: look (the SLDS icon catalog, and colours) ----------------

  iconQuery = "";
  iconSet = "all";
  iconLimit = ICONS_SHOWN;

  get iconSets() {
    const all = iconCatalog();
    return [
      { key: "all", label: "All", count: all.length },
      ...ICON_SETS.map((set) => ({
        key: set.key,
        label: set.label,
        count: all.filter((i) => i.set === set.key).length
      }))
    ].map((set) => ({
      ...set,
      text: `${set.label} ${set.count.toLocaleString()}`,
      pressed: String(set.key === this.iconSet),
      className: `chip-choice chip-choice_small${set.key === this.iconSet ? " chip-choice_on" : ""}`
    }));
  }

  get iconMatches() {
    const terms = this.iconQuery.trim().toLowerCase().split(/\s+/).filter(Boolean);
    return iconCatalog().filter(
      (i) => (this.iconSet === "all" || i.set === this.iconSet) && terms.every((t) => i.words.includes(t))
    );
  }

  get iconChoices() {
    const current = this.draft.icon;
    return this.iconMatches.slice(0, this.iconLimit).map((i) => ({
      name: i.name,
      label: i.name.replace(":", ": ").replace(/_/g, " "),
      pressed: String(i.name === current),
      className: `icon-choice${i.name === current ? " icon-choice_on" : ""}`
    }));
  }

  get iconCountText() {
    const total = this.iconMatches.length;
    if (!total) return "No icons match. Try another word, like \u201cmoney\u201d or \u201cchat\u201d.";
    const shown = Math.min(total, this.iconLimit);
    return shown < total
      ? `Showing ${shown.toLocaleString()} of ${total.toLocaleString()} icons`
      : `${total.toLocaleString()} ${total === 1 ? "icon" : "icons"}`;
  }

  get iconHasMore() {
    return this.iconMatches.length > this.iconLimit;
  }

  get iconCurrentText() {
    return this.draft.icon ? `Chosen: ${this.draft.icon}` : "Chosen: the source's default";
  }

  handleIconQuery(event) {
    this.iconQuery = event.target.value ?? "";
    this.iconLimit = ICONS_SHOWN;
  }

  handleIconSet(event) {
    this.iconSet = event.currentTarget.dataset.value;
    this.iconLimit = ICONS_SHOWN;
  }

  // More icons as the list scrolls near its end: no button to press.
  handleIconScroll(event) {
    const list = event.currentTarget;
    if (this.iconHasMore && list.scrollTop + list.clientHeight >= list.scrollHeight - 120) {
      this.iconLimit += ICONS_SHOWN;
    }
  }

  handleIcon(event) {
    this.lookTouched = true;
    this.update({ icon: event.currentTarget.dataset.value });
  }

  get paletteRows() {
    const current = (this.draft.iconColour ?? "").toUpperCase();
    return PALETTE.map((row) => ({
      key: row.hue,
      hue: row.hue,
      swatches: row.shades.map((sh) => ({
        key: sh.value,
        value: sh.value,
        label: `${row.hue} ${sh.shade}`,
        pressed: String(sh.value === current),
        style: `--swatch: ${sh.value}`,
        className: `swatch${sh.value === current ? " swatch_on" : ""}`
      }))
    }));
  }

  get colourText() {
    return colourName(this.draft.iconColour) ?? "No colour chosen";
  }

  get customColour() {
    return this.draft.iconColour || "#0B827C";
  }

  // WCAG 2.2, 1.4.11 Non-text Contrast: the white icon on its colour, and
  // the coloured node on the page, need 3:1 or more.
  get contrastProblem() {
    const colour = this.draft.iconColour;
    if (!colour) return null;
    const ratio = contrastWithWhite(colour);
    return ratio < MIN_CONTRAST ? { colour, ratio: Math.floor(ratio * 10) / 10 } : null;
  }

  // Says why with an error toast, takes the user to Look, and stops.
  stopForContrast() {
    const problem = this.contrastProblem;
    if (!problem) return false;
    this.toast(
      "error",
      "Choose a darker colour",
      `The white icon on ${problem.colour} has a contrast of ${problem.ratio}:1. WCAG needs at least ${MIN_CONTRAST}:1 so everyone can see it.`
    );
    const look = this.flow.indexOf("look");
    if (look >= 0 && this.stepIndex !== look) this.goTo(look);
    return true;
  }

  handleColour(event) {
    this.lookTouched = true;
    this.update({ iconColour: event.currentTarget.dataset.value });
  }

  handleCustomColour(event) {
    const value = (event.detail?.value ?? event.target.value ?? "").toUpperCase();
    if (/^#[0-9A-F]{6}$/.test(value)) {
      this.lookTouched = true;
      this.update({ iconColour: value });
    }
  }

  // ---- the object's own icon and colour -----------------------------------

  // A source starts with the icon and colour Salesforce gives its object (a
  // junction takes its record's); choosing either yourself keeps your choice,
  // and a button puts the object's back.
  lookTouched = false;
  theme;

  get themeObject() {
    const name = this.draft.objectName;
    if (!this.isSalesforce || !name || THEME_FALLBACKS[name.toLowerCase()]) return undefined;
    return THEME_OBJECTS[name.toLowerCase()] ?? name;
  }

  @wire(getObjectInfo, { objectApiName: "$themeObject" })
  wiredTheme({ data }) {
    if (!data?.themeInfo) return;
    this.theme = {
      object: data.apiName,
      label: data.label,
      icon: themeIconName(data.themeInfo.iconUrl),
      colour: data.themeInfo.color ? `#${data.themeInfo.color}` : null
    };
    this.applyObjectLook();
  }

  // The icon and colour the object comes with, or null where they're not known.
  get objectLook() {
    const fallback = THEME_FALLBACKS[String(this.draft.objectName ?? "").toLowerCase()];
    if (this.isSalesforce && fallback) {
      return { icon: fallback.icon, colour: accessibleColour(fallback.colour), label: this.objectLabel };
    }
    const t = this.theme;
    if (!this.isSalesforce || !t || t.object !== this.themeObject) return null;
    const icon = t.icon && inCatalog(t.icon) ? t.icon : null;
    const colour = accessibleColour(t.colour);
    return icon || colour ? { icon, colour, label: t.label } : null;
  }

  // A new source takes them; a saved one, or one the person has set, doesn't.
  applyObjectLook() {
    const look = this.objectLook;
    if (!look || this.lookTouched || this.editing) return;
    const icon = look.icon ?? this.draft.icon;
    const iconColour = look.colour ?? this.draft.iconColour;
    // Changing the draft re-reads the theme wire, which calls this again: stop
    // once there is nothing to change, or it never ends.
    if (icon === this.draft.icon && iconColour === this.draft.iconColour) return;
    this.update({ icon, iconColour });
  }

  get canRestoreLook() {
    const look = this.objectLook;
    if (!look) return false;
    return (
      (Boolean(look.icon) && this.draft.icon !== look.icon) ||
      (Boolean(look.colour) && (this.draft.iconColour ?? "").toUpperCase() !== look.colour)
    );
  }

  get restoreLookLabel() {
    return `Use ${this.objectLook?.label ?? "the object"}'s icon and colour`;
  }

  handleRestoreLook() {
    const look = this.objectLook;
    if (!look) return;
    this.lookTouched = false;
    this.update({ icon: look.icon ?? this.draft.icon, iconColour: look.colour ?? this.draft.iconColour });
  }

  get nodeStyle() {
    return `--chip: ${this.draft.iconColour || "var(--setup-chip)"}`;
  }

  get iconName() {
    return this.draft.icon || "utility:record";
  }

  get sampleDate() {
    return new Date().toISOString();
  }

  // ---- steps: opened and click ----------------------------------------------

  clickPicked = false;
  clickCleared = false;

  // Files: fields only, and a click opens the file preview (see FILE_OBJECT).
  get isFile() {
    return this.isSalesforce && String(this.draft.objectName ?? "").toLowerCase() === FILE_OBJECT;
  }

  get clickDecided() {
    return this.isFile || ((this.clickPicked || this.editing) && !this.clickCleared);
  }

  // A file's click has one answer: nothing to take back.
  get clickChangeable() {
    return !this.isFile;
  }

  get clickFocused() {
    return this.clickDecided;
  }

  get chosenClick() {
    return this.clickOptions.find((o) => o.checked === "true");
  }

  get clickOptionsClass() {
    return `options options_stack${this.clickFocused ? " options_hidden" : ""}`;
  }

  handleClickChange() {
    this.clickPicked = false;
    this.clickCleared = true;
  }

  // Lookups worth opening or showing: one object each, not the system ones,
  // the record page's own link last (it's the page the timeline is on).
  get relatedLookups() {
    const skip = /^(CreatedById|LastModifiedById|OwnerId|RecordTypeId|MasterRecordId|ParentId)$/;
    const page = this.draft.parentField;
    return (this.fields ?? [])
      .filter((f) => f.referenceTo && f.relationshipName && !skip.test(f.name))
      .filter((f) => !["User", "Group", "RecordType"].includes(f.referenceTo))
      .sort((a, b) => (a.name === page) - (b.name === page) || a.label.localeCompare(b.label))
      .map((f) => ({ ...f, label: lookupLabel(f) }));
  }

  lookupChips(selected) {
    return this.relatedLookups.map((l) => ({
      key: l.name,
      value: l.name,
      text: l.name === this.draft.parentField ? `${l.label} (this page's record)` : l.label,
      pressed: String(l.name === selected),
      className: `chip-choice chip-choice_small${l.name === selected ? " chip-choice_on" : ""}`
    }));
  }

  // The fields an opened item shows, by name and in order (a label of their
  // own, else the field's): "Status, Owner, Related To".
  get openAnswer() {
    const names = (this.draft.details ?? [])
      .filter((x) => x.field)
      .map((x) => (x.label?.trim() ? x.label.trim() : this.fieldLabel(x.field)));
    return names.length ? names.join(", ") : "No fields";
  }

  // What a click opens: the item's own record, or a related one.
  get clickChoice() {
    if (this.isFile) return "file";
    return this.draft.recordIdField ? "related" : "own";
  }

  get clickOptions() {
    const own = this.objectLabelOf(this.draft.objectName) || "record";
    if (this.isFile) {
      return [
        {
          value: "file",
          title: "The file preview",
          text: "Opens the file in Salesforce's file preview, as it does anywhere else.",
          icon: "doctype:attachment",
          checked: "true",
          className: "option option_choice option_on"
        }
      ];
    }
    return [
      {
        value: "own",
        title: "Its own record",
        text: `The ${own} the item stands for.`,
        icon: "utility:record_lookup"
      },
      {
        value: "related",
        title: "A related record",
        text: "The record it points to, such as a member's Campaign.",
        icon: "utility:hierarchy",
        disabled: !this.relatedLookups.length
      }
    ].map((o) => ({
      ...o,
      checked: String(this.clickDecided && o.value === this.clickChoice),
      className: `option option_choice${this.clickDecided && o.value === this.clickChoice ? " option_on" : ""}${o.disabled ? " option_disabled" : ""}`
    }));
  }

  get isClickRelated() {
    return this.clickDecided && this.clickChoice === "related";
  }

  handleClickChoice(event) {
    if (this.isFile) return;
    this.clickPicked = true;
    this.clickCleared = false;
    const value = event.currentTarget.dataset.value;
    if (value === "own") this.update({ recordIdField: null });
    else {
      const pick = this.relatedLookups[0];
      if (pick) this.update({ recordIdField: pick.name });
    }
    this.syncPreviewObject();
  }

  get clickLookupChips() {
    return this.lookupChips(this.draft.recordIdField);
  }

  handleClickLookup(event) {
    this.update({ recordIdField: event.currentTarget.dataset.value });
    this.syncPreviewObject();
  }

  get clickTarget() {
    // A file lands on the preview, which has no layout to read.
    if (this.isFile) return { field: "ContentDocumentId", objectName: undefined, label: "file preview" };
    const path = this.draft.recordIdField;
    if (!path)
      return { field: null, objectName: this.draft.objectName, label: this.objectLabelOf(this.draft.objectName) };
    const l = this.relatedLookups.find((x) => x.name === path);
    return { field: path, objectName: l?.referenceTo, label: l?.label ?? this.fieldLabel(path) };
  }

  // Both halves of the Opening step, for the thread and the review.
  get openingAnswer() {
    return this.isSalesforce ? `${this.openAnswer} · Click: ${this.clickAnswer}` : this.openAnswer;
  }

  get mockTitleClass() {
    return this.isSalesforce ? "mock-title mock-title_link" : "mock-title";
  }

  get clickAnswer() {
    if (this.isFile) return "The file preview";
    return this.clickChoice === "own" ? "Its own record" : `Its ${this.clickTarget.label}`;
  }

  // ---- the previews: an item as the timeline draws it, with sample values

  // The page a click lands on: its object's fields, for a sample name.
  syncPreviewObject() {
    const onSourcePage = this.view === "source";
    const click =
      (onSourcePage || this.stepKey === "open") && this.isSalesforce ? this.clickTarget.objectName : undefined;
    if (click !== this.clickObject) {
      this.clickObject = click;
      if (click) this.loadPreviewFields(click);
    }
  }

  previewFields = {};
  clickObject;

  async loadPreviewFields(objectName) {
    if (this.previewFields[objectName] || objectName === this.draft.objectName) return;
    try {
      const fields = await getFields({ objectName });
      this.previewFields = { ...this.previewFields, [objectName]: fields };
    } catch {
      // The preview falls back to the layout's labels with plain samples.
    }
  }

  // An object's fields for the preview: [{ name, label }].
  fieldsOf(objectName) {
    return objectName === this.draft.objectName ? (this.fields ?? []) : (this.previewFields[objectName] ?? []);
  }

  // A sample value for a field, by its type and name: what the preview shows.
  sample(field, objectName) {
    const name = field?.name ?? "";
    const label = (field?.label ?? name).toLowerCase();
    const type = field?.type;
    if (name === "Name" || name === "Subject" || name === "Title") return this.sampleName(objectName);
    if (/email/i.test(name)) return "sam.lee@example.com";
    if (/phone|mobile/i.test(name)) return "+1 415 555 0142";
    switch (type) {
      case "picklist":
      case "multipicklist":
        return field.values?.[0]?.label ?? "Active";
      case "currency":
        return (1250).toLocaleString(undefined, { style: "currency", currency: "USD" });
      case "percent":
        return "35%";
      case "double":
      case "integer":
      case "long":
        return "42";
      case "boolean":
        return "Yes";
      case "date":
        return new Date().toLocaleDateString();
      case "datetime":
        return new Date().toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
      case "reference":
        return SAMPLE_NAMES[field.referenceTo] ?? "Acme Ltd";
      case "url":
        return "example.com";
      case "textarea":
        return "A short note about this one.";
      default:
        return `Sample ${label}`;
    }
  }

  // A sample record name: a known one, else "Sample <object label>".
  sampleName(objectName) {
    if (SAMPLE_NAMES[objectName]) return SAMPLE_NAMES[objectName];
    const label = this.objectLabelOf(objectName) || (objectName ?? "").replace(/__c$/, "").replace(/_/g, " ");
    return label ? `Sample ${label}` : SAMPLE_NAMES.default;
  }

  // A {path} token's sample: follows lookups by relationship name.
  sampleOf(path) {
    const steps = String(path).split(".");
    let objectName = this.draft.objectName;
    let fields = this.fields ?? [];
    for (const rel of steps.slice(0, -1)) {
      const lookup = fields.find((f) => f.relationshipName === rel);
      objectName = lookupTarget(lookup);
      fields = this.fieldsOf(objectName);
    }
    const last = steps[steps.length - 1];
    return this.sample(fields.find((f) => f.name === last) ?? { name: last, label: last }, objectName);
  }

  fillSample(template) {
    return (template ?? "").replace(/\{([^}]+)\}/g, (all, path) => this.sampleOf(path));
  }

  get previewTitle() {
    return this.fillSample(this.draft.title) || this.draft.label || "Order placed";
  }

  get previewSubtitle() {
    return this.isEmailMessage ? EMAIL_SAMPLE_SUBTITLE : this.fillSample(this.draft.subtitle);
  }

  get previewTime() {
    return new Date().toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
  }

  // The opened item's facts: the chosen fields, with sample values.
  get previewFacts() {
    return (this.draft.details ?? [])
      .filter((x) => x.field)
      .map((x, i) => ({
        key: `d${i}`,
        label: x.label || this.detailFieldLabel(x.field),
        value: this.sampleOf(x.field)
      }));
  }

  get previewLoading() {
    return false;
  }

  get previewSourceNote() {
    return "The fields you choose, in order.";
  }

  get previewEmpty() {
    return this.previewFacts.length === 0;
  }

  get previewEmptyText() {
    return "Choose a field and it shows here.";
  }

  get clickPageHeadClass() {
    return "mock-page-head mock-page-head_alone";
  }

  // The click preview: the record page a click lands on.
  get clickPageLabel() {
    return this.objectLabelOf(this.clickTarget.objectName) || this.clickTarget.label || "Record";
  }

  get clickPageName() {
    return this.sampleName(this.clickTarget.objectName);
  }

  // ---- fields through lookups (Words, and Details' chosen fields) ---------

  // Labels for paths through lookups, as the picker named them.
  pathLabels = {};

  handleFieldPick(event) {
    const { path, label } = event.detail;
    this.pathLabels = { ...this.pathLabels, [path]: label };
    this.loadPathFields(path);
    if (this.tokenTarget?.startsWith("detail-")) {
      const index = Number(this.tokenTarget.slice(7));
      const details = this.draft.details.map((d, i) => {
        if (i !== index) return d;
        return { ...d, field: path, label: "", format: formatOf(event.detail.type) };
      });
      this.update({ details });
      this.tokenTarget = undefined;
    } else {
      this.insertToken(path);
    }
  }

  handleFieldPickClose() {
    this.tokenTarget = undefined;
  }

  // A path's related object's fields, so its sample reads true to type.
  loadPathFields(path) {
    const rel = String(path).split(".");
    if (rel.length < 2) return;
    const lookup = (this.fields ?? []).find((f) => f.relationshipName === rel[0]);
    const target = lookupTarget(lookup);
    if (target) this.loadPreviewFields(target);
  }

  handleDetailPickOpen(event) {
    const target = `detail-${event.currentTarget.dataset.index}`;
    this.tokenTarget = this.tokenTarget === target ? undefined : target;
  }

  // ---- step: name — the legend name, its place in the legend, its view ----

  // The record page's sources in legend order, this one as THIS_SOURCE:
  // built when the Name step first opens (a new source at the top, an edited one
  // where it is), then dragged or moved from there.
  legendKeys;
  legendTouched = false;
  dragKey;

  get legendOthers() {
    const parent = this.draft.parentObject || "Contact";
    return this.sources
      .filter((src) => (src.parentObject || "Contact") === parent && src.developerName !== this.draft.developerName)
      .sort((a, b) => (a.sequence ?? 0) - (b.sequence ?? 0) || a.label.localeCompare(b.label));
  }

  get legendOrder() {
    if (this.legendKeys) return this.legendKeys;
    const others = this.legendOthers;
    const keys = others.map((src) => src.developerName);
    if (!this.editing) return [THIS_SOURCE, ...keys];
    const mine = this.draft.sequence ?? 0;
    const at = others.findIndex((src) => (src.sequence ?? 0) > mine);
    keys.splice(at < 0 ? keys.length : at, 0, THIS_SOURCE);
    return keys;
  }

  get legendName() {
    switch (this.legendMode) {
      case "auto":
        return this.objectPlural || this.objectLabel || this.draft.label || "New source";
      case "related":
        return this.relatedPlural || this.objectPlural || this.draft.label || "New source";
      case "label":
        return this.labelText || (this.customLabelName ? `$Label.${this.customLabelName}` : "Custom label");
      default:
        return this.draft.eventLabel?.trim() || "";
    }
  }

  get legendRows() {
    const byName = new Map(this.legendOthers.map((src) => [src.developerName, src]));
    const order = this.legendOrder.filter((key) => key === THIS_SOURCE || byName.has(key));
    return order.map((key, i) => {
      const mine = key === THIS_SOURCE;
      const src = byName.get(key);
      return {
        key,
        mine,
        name: mine ? this.legendName || "New source" : src.legendName || src.eventLabel || src.label,
        icon: mine ? this.iconName : src.icon || "utility:record",
        chipStyle: `--chip: ${(mine ? this.draft.iconColour : src.iconColour) || "var(--setup-chip)"}`,
        off: !mine && !src.active,
        place: String(i + 1),
        first: i === 0,
        last: i === order.length - 1,
        upLabel: `Move ${mine ? this.legendName : src.label} up`,
        downLabel: `Move ${mine ? this.legendName : src.label} down`,
        className: `legend-row${mine ? " legend-row_mine" : ""}${key === this.dragKey ? " legend-row_dragging" : ""}`
      };
    });
  }

  get legendCountText() {
    const n = this.legendRows.length;
    return n === 1 ? "The only source on this page." : `${n} sources on the ${this.parentLabel} timeline.`;
  }

  moveLegend(key, to) {
    const keys = [...this.legendOrder];
    const from = keys.indexOf(key);
    if (from < 0 || to < 0 || to >= keys.length || from === to) return;
    keys.splice(to, 0, keys.splice(from, 1)[0]);
    this.legendKeys = keys;
    this.legendTouched = true;
    this.dirty = true;
  }

  handleLegendMove(event) {
    const { key, dir } = event.currentTarget.dataset;
    const keys = this.legendOrder;
    this.moveLegend(key, keys.indexOf(key) + Number(dir));
  }

  handleLegendDragStart(event) {
    this.dragKey = event.currentTarget.dataset.key;
    event.dataTransfer?.setData("text/plain", this.dragKey);
    if (event.dataTransfer) event.dataTransfer.effectAllowed = "move";
  }

  // Over another row: the dragged one takes its place, so the list shows
  // where it'll land as it moves.
  handleLegendDragOver(event) {
    if (!this.dragKey) return;
    event.preventDefault();
    const over = event.currentTarget.dataset.key;
    if (over !== this.dragKey) this.moveLegend(this.dragKey, this.legendOrder.indexOf(over));
  }

  handleLegendDrop(event) {
    event.preventDefault();
    this.dragKey = undefined;
  }

  handleLegendDragEnd() {
    this.dragKey = undefined;
  }

  // A lightning-input reports typing as change (on each keystroke), not input.
  handleLegendName(event) {
    const value = event.detail?.value ?? event.target.value ?? "";
    this.legendModeChoice = "text";
    this.update({ eventLabel: value, label: value.trim() });
  }

  // The source's own name follows what the legend calls it.
  syncLabel() {
    const name = this.legendName;
    if (name && name !== this.draft.label && !(this.legendMode === "label" && !this.labelText)) {
      this.update({ label: name.slice(0, 40) });
    }
  }

  // ---- the legend name: the object's own, a custom label, or typed ---------

  // Salesforce objects default to their own plural name, which Salesforce
  // translates; a custom label ($Label.Name) translates too; typed words are
  // one language.
  legendModeChoice;
  labelText;
  labelLookupSeq = 0;

  get legendMode() {
    const value = this.draft.eventLabel?.trim() ?? "";
    if (value.startsWith(LABEL_PREFIX)) return "label";
    if (value.startsWith(OBJECT_PREFIX)) return "related";
    if (this.legendModeChoice === "related") return "related";
    if (this.legendModeChoice) return this.legendModeChoice;
    if (value) return "text";
    return this.isSalesforce ? "auto" : "text";
  }

  get legendModes() {
    const plural = this.objectPlural || "its object's name";
    return [
      {
        value: "auto",
        title: "The object's name",
        text: `Shown as “${plural}”, in each person's language. Salesforce translates object names.`,
        icon: "utility:world",
        salesforce: true
      },
      {
        value: "related",
        title: "A related object's name",
        text: `Shown as “${this.relatedPlural || "its name"}”, in each person's language. For a junction like ${this.objectLabel || "this object"}, pick the object it joins.`,
        icon: "utility:link",
        salesforce: true,
        needsRelated: true
      },
      {
        value: "label",
        title: "A custom label, for several languages",
        text: "Your own words, translated for each person.",
        icon: "utility:translate"
      },
      {
        value: "text",
        title: "Type a name, in one language",
        text: "The legend shows exactly what you type, to everyone.",
        icon: "utility:edit"
      }
    ]
      .filter((m) => (this.isSalesforce || !m.salesforce) && (!m.needsRelated || this.relatedObjects.length > 0))
      .map((m) => ({
        ...m,
        checked: String(this.legendDecided && m.value === this.legendMode),
        className: `option option_small${this.legendDecided && m.value === this.legendMode ? " option_on" : ""}`
      }));
  }

  // The objects this one points to, whose names it could take: a junction's
  // record (Task for a TaskRelation), its date's first. Not who made it or
  // owns it.
  get relatedObjects() {
    const skip = new Set(["CreatedById", "LastModifiedById", "OwnerId", "RecordTypeId"]);
    const seen = new Set();
    const found = [];
    for (const f of this.fields ?? []) {
      if (!f.referenceTo || !f.relationshipName || skip.has(f.name) || seen.has(f.referenceTo)) continue;
      if (f.referenceTo === "User" || f.referenceTo === "Group") continue;
      seen.add(f.referenceTo);
      found.push({
        value: f.referenceTo,
        plural: f.referencePlural || f.referenceLabel || f.referenceTo,
        via: f.label,
        first: this.draft.dateField?.startsWith(`${f.relationshipName}.`) ? 0 : 1
      });
    }
    return found.sort((a, b) => a.first - b.first);
  }

  get relatedName() {
    const value = this.draft.eventLabel?.trim() ?? "";
    return value.startsWith(OBJECT_PREFIX) ? value.slice(OBJECT_PREFIX.length) : "";
  }

  get relatedPlural() {
    const objects = this.relatedObjects;
    const chosen = objects.find((o) => o.value === this.relatedName) ?? (this.relatedName ? null : objects[0]);
    return chosen?.plural ?? "";
  }

  get relatedChoices() {
    const current = this.relatedName;
    return this.relatedObjects.map((o) => ({
      value: o.value,
      label: o.plural,
      title: `Through ${o.via}`,
      pressed: String(o.value === current),
      className: `chip-choice${o.value === current ? " chip-choice_on" : ""}`
    }));
  }

  get isLegendRelated() {
    return this.legendDecided && this.legendMode === "related";
  }

  handleRelatedObject(event) {
    this.update({ eventLabel: `${OBJECT_PREFIX}${event.currentTarget.dataset.value}` });
    this.syncLabel();
  }

  get isLegendLabel() {
    return this.legendDecided && this.legendMode === "label";
  }

  get isLegendText() {
    return this.legendDecided && this.legendMode === "text";
  }

  get customLabelName() {
    const value = this.draft.eventLabel?.trim() ?? "";
    return value.startsWith(LABEL_PREFIX) ? value.slice(LABEL_PREFIX.length) : "";
  }

  get labelStatus() {
    if (!this.customLabelName) return { text: "Enter the custom label's API name.", className: "label-status" };
    if (this.labelText === undefined) return { text: "Looking it up…", className: "label-status" };
    return this.labelText
      ? { text: `Reads “${this.labelText}” in your language.`, className: "label-status label-status_ok" }
      : {
          text: `There's no custom label called ${this.customLabelName} yet. Create it in Setup, then come back.`,
          className: "label-status label-status_missing"
        };
  }

  // Nothing is chosen until it's clicked (an existing source has its saved
  // way). The chosen way moves to the top; the X clears it, so the choice is
  // made again.
  legendPicked = false;
  legendCleared = false;

  get legendDecided() {
    return (this.legendPicked || this.editing) && !this.legendCleared;
  }

  get legendFocused() {
    return this.legendDecided;
  }

  get chosenLegend() {
    return this.legendModes.find((m) => m.checked === "true");
  }

  get legendOptionsClass() {
    return `options options_stack${this.legendFocused ? " options_hidden" : ""}`;
  }

  handleLegendChange() {
    this.legendPicked = false;
    this.legendCleared = true;
  }

  handleLegendMode(event) {
    this.legendPicked = true;
    this.legendCleared = false;
    const mode = event.currentTarget.dataset.value;
    this.legendModeChoice = mode === "auto" ? undefined : mode;
    if (mode === "auto") this.update({ eventLabel: "" });
    else if (mode === "related") {
      // The object it joins, to start with (the one its date is read from).
      const first = this.relatedObjects[0]?.value;
      this.update({ eventLabel: first ? `${OBJECT_PREFIX}${first}` : "" });
    } else if (mode === "label") this.update({ eventLabel: `${LABEL_PREFIX}${this.customLabelName}` });
    else if (
      this.draft.eventLabel?.trim().startsWith(LABEL_PREFIX) ||
      this.draft.eventLabel?.trim().startsWith(OBJECT_PREFIX) ||
      !this.draft.eventLabel
    ) {
      // Off a custom label (even one with no name yet, which is still the
      // "$Label." prefix and reads as a label), back to typed words.
      this.update({ eventLabel: this.draft.label || "" });
    }
    if (mode === "label") this.lookUpLabel();
    else this.syncLabel();
  }

  handleCustomLabel(event) {
    const name = (event.target.value ?? "").trim().replace(/^\$Label\./, "");
    this.update({ eventLabel: `${LABEL_PREFIX}${name}` });
    this.lookUpLabel();
  }

  // What the label reads as, for the preview; null when there's none.
  async lookUpLabel() {
    const name = this.customLabelName;
    const seq = ++this.labelLookupSeq;
    this.labelText = undefined;
    if (!name) return;
    try {
      const text = await getLabelText({ name });
      if (seq === this.labelLookupSeq) {
        this.labelText = text ?? null;
        this.syncLabel();
      }
    } catch {
      if (seq === this.labelLookupSeq) this.labelText = null;
    }
  }

  // ---- the chosen fields ----------------------------------------------------

  get detailRows() {
    return (this.draft.details ?? []).map((d, index) => ({
      ...d,
      index,
      pickerOpen: this.tokenTarget === `detail-${index}`,
      fieldText: d.field ? this.fieldLabel(d.field) : "Choose a field",
      fieldClass: d.field ? "detail-field-text" : "detail-field-text detail-field-text_empty",
      removeLabel: `Remove ${this.fieldLabel(d.field) || "detail"}`,
      first: index === 0,
      last: index === this.draft.details.length - 1,
      upLabel: `Move ${this.fieldLabel(d.field) || "this field"} up`,
      downLabel: `Move ${this.fieldLabel(d.field) || "this field"} down`
    }));
  }

  // Fields you choose show in this order; with more than one, they move.
  get canReorderDetails() {
    return (this.draft.details?.length ?? 0) > 1;
  }

  handleMoveDetail(event) {
    const index = Number(event.currentTarget.dataset.index);
    const to = index + Number(event.currentTarget.dataset.dir);
    const details = [...this.draft.details];
    if (to < 0 || to >= details.length) return;
    [details[index], details[to]] = [details[to], details[index]];
    this.update({ details });
  }

  // ---- highlights: an icon when a field has a value ---------------------------

  get canHighlight() {
    return this.isSalesforce || this.isApex;
  }

  get highlightHelp() {
    return this.isApex
      ? "Mark an item with a small icon where a row's value is true: a checkbox field the class reads (Flagged__c), or a key of its rows. One per source."
      : "Mark an item with a small icon when a checkbox is checked, such as High priority or Overdue. One per source.";
  }

  get canAddHighlight() {
    return (this.draft.highlights?.length ?? 0) < MAX_HIGHLIGHTS;
  }

  // Checkboxes: on or off, nothing to choose between. Overdue tasks have one
  // of Time Drive's own (Overdue__c); other logic is a formula checkbox of
  // the admin's.
  get highlightFieldOptions() {
    return (this.fields ?? []).filter((f) => f.type === "boolean").map((f) => ({ label: f.label, value: f.name }));
  }

  get highlightRows() {
    return (this.draft.highlights ?? []).map((h, index) => {
      const field = this.fieldInfo(h.field);
      const colour = h.colour ?? HIGHLIGHT_COLOURS[0].value;
      return {
        ...h,
        index,
        key: `h${index}`,
        colourStyle: `--flag: ${colour}`,
        removeLabel: `Remove ${field?.label ?? "this highlight"}`,
        iconChoices: HIGHLIGHT_ICONS.map((value) => ({
          key: `i-${value}`,
          value,
          isDot: value === "dot",
          label: value === "dot" ? "Dot" : value.replace("utility:", "").replace(/_/g, " "),
          pressed: String((h.icon ?? "utility:priority") === value),
          className: `icon-choice highlight-icon${(h.icon ?? "utility:priority") === value ? " icon-choice_on" : ""}`
        })),
        colourChoices: HIGHLIGHT_COLOURS.map((c) => ({
          key: `c-${c.value}`,
          ...c,
          style: `--swatch: ${c.value}`,
          pressed: String(colour.toUpperCase() === c.value),
          className: `swatch swatch_small${colour.toUpperCase() === c.value ? " swatch_on" : ""}`
        }))
      };
    });
  }

  // The preview row's marks: what the rules would add to an item.
  get previewFlags() {
    return (this.draft.highlights ?? [])
      .filter((h) => h.field)
      .map((h, i) => ({
        key: `pf${i}`,
        isDot: !h.icon || h.icon === "dot",
        icon: h.icon,
        text: this.fieldLabel(h.field),
        style: `--flag: ${h.colour ?? HIGHLIGHT_COLOURS[0].value}`
      }));
  }

  setHighlights(highlights) {
    this.update({ highlights });
  }

  handleAddHighlight() {
    if (!this.canAddHighlight) return;
    this.setHighlights([
      ...(this.draft.highlights ?? []),
      { field: null, icon: "utility:priority", colour: HIGHLIGHT_COLOURS[0].value }
    ]);
  }

  handleRemoveHighlight(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.setHighlights(this.draft.highlights.filter((_, i) => i !== index));
  }

  changeHighlight(event, change) {
    const index = Number(event.currentTarget.dataset.index);
    this.setHighlights(this.draft.highlights.map((h, i) => (i === index ? { ...h, ...change } : h)));
  }

  handleHighlightField(event) {
    this.changeHighlight(event, { field: event.detail.value });
  }

  handleHighlightIcon(event) {
    this.changeHighlight(event, { icon: event.currentTarget.dataset.value });
  }

  handleHighlightColour(event) {
    this.changeHighlight(event, { colour: event.currentTarget.dataset.value });
  }

  get maxDetails() {
    return MAX_DETAILS;
  }

  get canAddDetail() {
    return (this.draft.details?.length ?? 0) < MAX_DETAILS;
  }

  handleAddDetail() {
    if (!this.canAddDetail) return;
    this.update({ details: [...this.draft.details, keyed({ field: null, label: "", format: "Text" })] });
  }

  handleDetailChange(event) {
    const index = Number(event.target.dataset.index);
    const part = event.target.dataset.part;
    const value = event.detail.value;
    const details = this.draft.details.map((d, i) => {
      if (i !== index) return d;
      if (part === "field") {
        const field = this.fieldInfo(value);
        return { ...d, field: value, label: "", format: formatOf(field?.type) };
      }
      return { ...d, [part]: value };
    });
    this.update({ details });
  }

  handleRemoveDetail(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.update({ details: this.draft.details.filter((_, i) => i !== index) });
  }

  handleActive(event) {
    this.update({ active: event.target.checked });
  }

  get filterSummary() {
    const d = this.draft;
    if (this.filterFixed || !d.conditions?.length) return d.filter ?? "";
    return d.conditions
      .filter((c) => c.field)
      .map((c) => {
        const row = this.conditionRows.find((r) => r.key === c.key);
        const op = row?.operators.find((o) => o.value === c.operator)?.label ?? c.operator;
        const blank = c.operator === "blank" || c.operator === "notBlank";
        const label = (v) => row?.picklistValues.find((p) => p.value === v)?.label ?? v;
        let value = c.value;
        if (row?.isBoolean) value = c.value === "true" ? "ticked" : "not ticked";
        else if (row?.isPicklistList) value = (c.values ?? []).map(label).join(", ");
        else if (row?.isPicklist) value = label(c.value);
        return `${this.fieldLabel(c.field)} ${op}${blank ? "" : ` ${value}`}`;
      })
      .join(d.match === "any" ? " or " : " and ");
  }

  // ---- saving --------------------------------------------------------------

  get saveLabel() {
    if (this.saved) return "Saved";
    if (this.saving) return "Saving…";
    return this.editing ? "Save changes" : "Save source";
  }

  get saveClass() {
    return `save${this.saving ? " save_busy" : ""}${this.saved ? " save_done" : ""}`;
  }

  get saveIcon() {
    return this.saved ? "utility:check" : "utility:upload";
  }

  get saveDisabled() {
    return (
      Boolean(this.saving) ||
      this.saved ||
      Boolean(this.blockedReason) ||
      this.flow.some((key) => !this.isAnswered(key))
    );
  }

  get missingAnswers() {
    return this.flow.some((key) => !this.isAnswered(key))
      ? "Answer the steps still open on the thread above to save."
      : "";
  }

  async handleSave() {
    if (this.saveDisabled || this.stopForContrast()) return;
    if (this.isApex && !(await this.confirmApexScale())) return;
    this.saveError = undefined;
    this.saving = true;
    try {
      const ticket = await saveDraft({ draftJson: this.draftJson() });
      this.draft = { ...this.draft, developerName: ticket.developerName };
      this.saving = false;
      this.finishSave();
    } catch (e) {
      this.saving = false;
      this.saveError = plainError(e);
    }
  }

  // An Apex class runs on every timeline that shows its source: before it's
  // saved, the admin says they've thought about how it scales.
  confirmApexScale() {
    return TimeDriveConfirm.open({
      size: "small",
      label: "Before you save an Apex source",
      title: "Before you save an Apex source",
      message:
        `${this.draft.providerClass || "This class"} runs every time a timeline with this source loads, for every ` +
        "person who opens one. Code that reads too many records, queries in a loop or calls out slowly can make " +
        "every timeline slow, or stop it loading, as the data grows. Check it against the largest records your org " +
        "has, and keep it within Salesforce's limits. A class that counts its items is only asked for the days on " +
        "screen; one that doesn't is read for the whole timeline, up to its Max Records.",
      acknowledgement:
        "I've thought about how this class scales and performs with our data, and I take responsibility for it.",
      confirmLabel: "Save"
    });
  }

  draftJson() {
    const d = this.draft;
    return JSON.stringify({
      ...d,
      label: d.label?.trim(),
      // Blank: the object's own name. $Label.Name: a custom label. Else typed.
      eventLabel:
        this.legendMode === "auto"
          ? null
          : this.legendMode === "label"
            ? d.eventLabel?.trim()
            : d.eventLabel?.trim() || d.label?.trim(),
      // A filter the builder can't show is kept as the text it is.
      conditions: this.filterFixed ? [] : d.conditions.filter((c) => c.field),
      filter: this.filterFixed ? d.filter : null,
      details: d.details.filter((x) => x.field),
      recordIdField: d.recordIdField || null,
      legendOrder: !this.editing || this.legendTouched ? this.legendOrder : null
    });
  }

  // ---- helpers -------------------------------------------------------------

  fieldInfo(name) {
    if (name?.includes(".")) return this.pathInfo[name];
    return name ? this.fields?.find((f) => f.name === name) : undefined;
  }

  // What the picker said of the fields chosen through lookups (Task.Subject):
  // their type and values, for the filter's operators and value box.
  pathInfo = {};

  // A field's label; a path through lookups reads "Campaign › Name".
  fieldLabel(name) {
    if (name?.includes(".")) {
      if (this.pathLabels[name]) return this.pathLabels[name];
      const steps = name.split(".");
      const lookup = (this.fields ?? []).find((f) => f.relationshipName === steps[0]);
      // One step in, the related object's field is known once its fields are read.
      const field =
        steps.length === 2 && lookup?.referenceTo
          ? this.previewFields[lookup.referenceTo]?.find((f) => f.name === steps[1])
          : undefined;
      return [lookup ? lookupLabel(lookup) : steps[0], ...(field ? [field.label] : steps.slice(1))].join(" › ");
    }
    return this.fieldInfo(name)?.label ?? name ?? "";
  }

  // What an opened item calls a chosen field: the field's own label, as the
  // timeline shows it in the user's language; through a lookup, the lookup's
  // when it ends at Name (Who.Name reads "Name"), else the last field's. No
  // object name in front.
  detailFieldLabel(name) {
    if (!name?.includes(".")) return this.fieldLabel(name);
    const steps = name.split(".");
    const lookup = (this.fields ?? []).find((f) => f.relationshipName === steps[0]);
    if (steps.length === 2 && steps[1] === "Name" && lookup) return lookup.label;
    return (this.pathLabels[name] ?? steps[steps.length - 1]).split(" › ").pop();
  }

  objectLabelOf(name) {
    for (const list of Object.values(this.objectsByKind)) {
      const found = list.find((o) => o.value === name);
      if (found) return found.label;
    }
    return name ?? "";
  }

  get objectLabel() {
    return this.objectLabelOf(this.draft.objectName);
  }

  get objectPlural() {
    const name = this.draft.objectName;
    for (const list of Object.values(this.objectsByKind)) {
      const found = list.find((o) => o.value === name);
      if (found) return found.pluralLabel || found.label;
    }
    return name ?? "";
  }
}
