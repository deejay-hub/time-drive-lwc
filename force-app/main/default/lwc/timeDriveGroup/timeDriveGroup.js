/**
 * View all for a timeline's grouped row: the items it stands for, listed as
 * Salesforce lists them (a related list's View All), 50 at a time as the
 * table scrolls. The timeline links here with the record, the type and the
 * row's span in the page's state; the count and label it showed come too,
 * so the header reads right before the first page arrives. Its columns are
 * the source's own: the title (linking to the record), the subtitle, the
 * detail fields the admin chose, then the date.
 */
import { LightningElement, wire } from "lwc";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import getGroupPage from "@salesforce/apex/TimeDriveController.getGroupPage";
import LOCALE from "@salesforce/i18n/locale";
import LANG from "@salesforce/i18n/lang";
import SHORT_TIME_FORMAT from "@salesforce/i18n/dateTime.shortTimeFormat";
import ZONE from "@salesforce/i18n/timeZone";
import { describeError, describeProblems } from "c/timeDriveErrors";
import { LABELS, format, labelNamed } from "c/timeDriveLabels";
import { detailText, ownWords } from "c/timeDriveFormat";

const PAGE_SIZE = 50;
// The page fits the window, at least this tall (px), Lightning's margin below.
const MIN_PAGE = 360;
const PAGE_FOOT = 12;
const NUMBER = new Intl.NumberFormat(LOCALE);
// Words follow the language, dates the locale; Gregorian, in the user's Salesforce
// time zone (the browser's if it doesn't know the name) and on the 12 or 24 hour
// clock their locale shows.
const LIST_FORMAT = new Intl.ListFormat(LANG, { style: "long", type: "conjunction" });
const HOUR12 = /a/.test(String(SHORT_TIME_FORMAT ?? ""));
const instant = (options) => {
  const all = { calendar: "gregory", ...options, ...(options.timeStyle ? { hour12: HOUR12 } : {}) };
  try {
    return new Intl.DateTimeFormat(LOCALE, { timeZone: ZONE, ...all });
  } catch {
    return new Intl.DateTimeFormat(LOCALE, all);
  }
};
const DATE_TIME = instant({ dateStyle: "medium", timeStyle: "short" });
const DATE_ONLY = instant({ dateStyle: "medium" });
const DAY = instant({ weekday: "short", day: "numeric", month: "short", year: "numeric" });

/** The component's namespace ("c" unpackaged), from its own tag. */
export function namespaceOf(component) {
  return (component.template?.host?.tagName ?? "c-").split("-")[0].toLowerCase();
}

// The loading table: rows of bars of varied widths, as text would be.
const SKELETON_ROWS = [62, 48, 70, 55, 66, 44, 58, 50].map((w, i) => ({
  key: `row${i}`,
  cells: [w, 40 + ((i * 7) % 30), 30 + ((i * 11) % 35), 45].map((width, j) => ({
    key: `cell${j}`,
    style: `width: ${width}%`
  }))
}));

// Where an item's link goes: its page, or for a file (a ContentDocument, key
// prefix 069) its document. The same as the timeline's.
function recordHref(id) {
  return typeof id === "string" && id.startsWith("069")
    ? `/lightning/r/ContentDocument/${id}/view`
    : `/lightning/r/${id}/view`;
}

// Each View all page's table, as last built (see table()).
const TABLES = new WeakMap();

export default class TimeDriveGroup extends NavigationMixin(LightningElement) {
  labels = LABELS;

  state = {};
  items = [];
  more = false;
  loading = false;
  error;
  problems;
  label;
  icon;
  dateOnly = false;
  recordName;
  cursor = null;
  // The first page has come back (or failed): the header (icon, title,
  // count, the way back) shows, all at once, with the table; until then
  // they're skeletons. Refresh keeps the header.
  headerReady = false;
  // Each load's ticket: a reply to an older one (before Refresh) is dropped.
  ticket = 0;

  @wire(CurrentPageReference)
  wiredPage(ref) {
    const ns = `${namespaceOf(this)}__`;
    const s = ref?.state ?? {};
    const next = {
      recordId: s[`${ns}recordId`],
      type: s[`${ns}type`],
      from: s[`${ns}from`],
      to: s[`${ns}to`],
      count: Number(s[`${ns}count`]) || null,
      label: s[`${ns}label`],
      icon: s[`${ns}icon`],
      object: s[`${ns}object`]
    };
    if (JSON.stringify(next) === JSON.stringify(this.state)) return;
    this.state = next;
    this.headerReady = false;
    this.reload();
  }

  reload() {
    this.ticket++;
    this.items = [];
    this.cursor = null;
    this.more = false;
    this.error = undefined;
    this.problems = undefined;
    this.loading = false;
    if (this.state.recordId && this.state.type) this.load();
  }

  async load() {
    if (this.loading) return;
    const ticket = this.ticket;
    this.loading = true;
    try {
      const page = await getGroupPage({
        recordId: this.state.recordId,
        type: this.state.type,
        fromAt: this.state.from,
        toAt: this.state.to,
        pageSize: PAGE_SIZE,
        cursor: this.cursor
      });
      if (ticket !== this.ticket) return;
      if (!this.cursor) {
        this.label = labelNamed(page.labelName, page.label);
        this.icon = page.icon;
        this.dateOnly = page.dateOnly;
        this.recordName = page.recordName;
      }
      this.items = [...this.items, ...(page.items ?? []).map(ownWords)];
      this.headerReady = true;
      this.cursor = page.cursor;
      this.more = page.more === true;
      this.problems = page.problems?.length ? page.problems : this.problems;
    } catch (error) {
      if (ticket !== this.ticket) return;
      this.headerReady = true;
      this.error = describeError(error);
      this.more = false;
    } finally {
      if (ticket === this.ticket) this.loading = false;
    }
  }

  // The table's scrolled near its end.
  handleLoadMore() {
    if (this.more && !this.loading) this.load();
  }

  handleRefresh() {
    this.reload();
  }

  // ---- fitting the window: only the rows scroll, the header stays put -------

  pageHeight = null;

  connectedCallback() {
    this.onResize = () => this.fit();
    window.addEventListener("resize", this.onResize);
  }

  disconnectedCallback() {
    window.removeEventListener("resize", this.onResize);
  }

  renderedCallback() {
    if (this.pageHeight === null) this.fit();
  }

  // From where the page starts (below Lightning's header) to the window's
  // foot, less the margin Lightning leaves there.
  fit() {
    const top = this.template.host.getBoundingClientRect().top + window.scrollY;
    const height = Math.max(MIN_PAGE, Math.floor(window.innerHeight - top - PAGE_FOOT));
    if (height !== this.pageHeight) this.pageHeight = height;
  }

  get pageStyle() {
    return this.pageHeight ? `height: ${this.pageHeight}px` : "";
  }

  // ---- the table -----------------------------------------------------------

  // The table's rows and detail columns, kept between renders: a render (the
  // loading flag, a resize) reuses them, and a new page only adds its own
  // rows. A detail label keeps its column once it has one (new ones go at
  // the end), so rows already built stay right.
  // (Kept off the component, in TABLES: a field written while rendering
  // would ask for another render.)
  table() {
    const t = TABLES.get(this) ?? { items: null, dateOnly: null, labels: [], index: new Map(), rows: [] };
    if (t.items === this.items && t.dateOnly === this.dateOnly) return t;
    const extends_ =
      t.items &&
      t.dateOnly === this.dateOnly &&
      this.items.length >= t.items.length &&
      t.items.every((item, i) => this.items[i] === item);
    const start = extends_ ? t.items.length : 0;
    const labels = extends_ ? [...t.labels] : [];
    const index = extends_ ? new Map(t.index) : new Map();
    const rows = extends_ ? [...t.rows] : [];
    for (let i = start; i < this.items.length; i++) {
      const item = this.items[i];
      const row = {
        id: item.id,
        title: item.title,
        recordUrl: item.recordId ? recordHref(item.recordId) : null,
        subtitle: item.subtitle,
        when: this.whenText(item)
      };
      for (const d of item.details ?? []) {
        if (!d.label) continue;
        if (!index.has(d.label)) {
          index.set(d.label, labels.length);
          labels.push(d.label);
        }
        row[`detail${index.get(d.label)}`] = detailText(d);
      }
      rows.push(row);
    }
    const built = { items: this.items, dateOnly: this.dateOnly, labels, index, rows };
    TABLES.set(this, built);
    return built;
  }

  // Every item's detail labels, in the order they first appear, as columns.
  get detailLabels() {
    return this.table().labels;
  }

  get columns() {
    const columns = [
      {
        label: LABELS.groupColName,
        fieldName: "recordUrl",
        type: "url",
        typeAttributes: { label: { fieldName: "title" }, tooltip: { fieldName: "title" }, target: "_self" },
        hideDefaultActions: true
      }
    ];
    if (this.items.some((item) => item.subtitle)) {
      columns.push({ label: LABELS.groupColSummary, fieldName: "subtitle", hideDefaultActions: true });
    }
    this.detailLabels.forEach((label, i) => {
      columns.push({ label, fieldName: `detail${i}`, hideDefaultActions: true });
    });
    columns.push({
      label: this.dateOnly ? LABELS.groupColDate : LABELS.groupColDateTime,
      fieldName: "when",
      initialWidth: 190,
      hideDefaultActions: true
    });
    return columns;
  }

  get rows() {
    return this.table().rows;
  }

  whenText(item) {
    const at = new Date(item.occurredAt);
    if (Number.isNaN(at.getTime())) return "";
    return this.dateOnly || item.allDay ? DATE_ONLY.format(at) : DATE_TIME.format(at);
  }

  // ---- the header ----------------------------------------------------------

  get heading() {
    return this.label || this.state.label || LABELS.groupHeading;
  }

  // "342 items", as the timeline counted them; "50+ items" while more are to
  // come and the count is unknown; what's loaded once it's all there.
  get countText() {
    const loaded = this.items.length;
    const done = !this.more && !this.loading;
    const n = done ? loaded : Math.max(this.state.count ?? 0, loaded);
    if (!(done || this.state.count >= loaded)) return format(LABELS.groupCountMore, NUMBER.format(loaded));
    return n === 1 ? LABELS.itemsOne : format(LABELS.itemsMany, NUMBER.format(n));
  }

  // The day it was on, or the days a week's or month's row spans.
  get spanText() {
    const from = new Date(this.state.from);
    const to = new Date(this.state.to);
    if (Number.isNaN(from.getTime()) || Number.isNaN(to.getTime())) return "";
    const first = DAY.format(from);
    const last = DAY.format(to);
    return first === last ? first : `${first} – ${last}`;
  }

  get metaText() {
    return [this.countText, LABELS.groupSorted, this.spanText].filter(Boolean).join(" • ");
  }

  get iconName() {
    return this.icon || this.state.icon || "standard:record";
  }

  get recordUrl() {
    return this.state.recordId ? `/lightning/r/${this.state.recordId}/view` : null;
  }

  get backText() {
    return this.recordName ? format(LABELS.groupBack, this.recordName) : LABELS.groupBackRecord;
  }

  // Back to the record the timeline is on (not its object's list).
  openParent(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId: this.state.recordId, actionName: "view" }
    });
  }

  // ---- states --------------------------------------------------------------

  get missingState() {
    return !this.state.recordId || !this.state.type;
  }

  get showTable() {
    return !this.missingState && !this.error && this.items.length > 0;
  }

  // Until the first page is in: the table's shape, so nothing moves when it
  // arrives. The table's own spinner is for the pages after.
  get showSkeleton() {
    return !this.missingState && !this.error && this.items.length === 0 && this.loading;
  }

  get isEmpty() {
    return !this.missingState && !this.error && !this.showSkeleton && this.items.length === 0;
  }

  get skeletonRows() {
    return SKELETON_ROWS;
  }

  get problemNotice() {
    return describeProblems(this.problems, LIST_FORMAT);
  }

  get progressText() {
    if (this.loading) return LABELS.groupLoadingMore;
    return format(LABELS.groupShown, NUMBER.format(this.items.length));
  }
}
