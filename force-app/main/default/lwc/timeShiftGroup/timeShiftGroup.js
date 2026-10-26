/**
 * View all for a timeline's grouped row: the items it stands for, listed as
 * Salesforce lists them (a related list's View All), 50 at a time as the
 * table scrolls. The timeline links here with the record, the type and the
 * row's span in the page's state; the count and label it showed come too,
 * so the header reads right before the first page arrives. Its columns are
 * the items' object's compact layout, as a standard list's are its layout's:
 * the first field links to the record.
 */
import { LightningElement, wire } from "lwc";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import { getLayout } from "lightning/uiLayoutApi";
import getGroupPage from "@salesforce/apex/TimeShiftController.getGroupPage";
import LOCALE from "@salesforce/i18n/locale";
import LANG from "@salesforce/i18n/lang";
import SHORT_TIME_FORMAT from "@salesforce/i18n/dateTime.shortTimeFormat";
import ZONE from "@salesforce/i18n/timeZone";
import { describeError, describeProblems } from "c/timeShiftErrors";
import { LABELS, format } from "c/timeShiftLabels";

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

/** A compact layout's fields, in order: each item's first field. */
export function fieldsOf(layout) {
  const out = [];
  for (const section of layout?.sections ?? []) {
    for (const row of section.layoutRows ?? []) {
      for (const item of row.layoutItems ?? []) {
        const field = (item.layoutComponents ?? []).find((c) => c.componentType === "Field" && c.apiName);
        if (field && item.label && !out.some((f) => f.apiName === field.apiName)) {
          out.push({ apiName: field.apiName, label: item.label });
        }
      }
    }
  }
  return out;
}

export default class TimeShiftGroup extends NavigationMixin(LightningElement) {
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
  // The compact layout's fields ({ apiName, label }), once it's been read
  // (or couldn't be: no extra columns then); the first page waits for it.
  layoutFields = [];
  layoutReady = false;
  pending = false;
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
    // A new object (or the first state): its layout is still to come.
    if (next.object !== this.state.object || !("recordId" in this.state)) {
      this.layoutFields = [];
      this.layoutReady = !next.object;
    }
    this.state = next;
    this.headerReady = false;
    this.reload();
  }

  get layoutObject() {
    return this.state.object;
  }

  @wire(getLayout, { objectApiName: "$layoutObject", layoutType: "Compact", mode: "View" })
  wiredLayout({ data, error }) {
    if (!data && !error) return;
    this.layoutFields = data ? fieldsOf(data) : [];
    this.layoutReady = true;
    this.start();
  }

  reload() {
    this.ticket++;
    this.items = [];
    this.cursor = null;
    this.more = false;
    this.error = undefined;
    this.problems = undefined;
    this.loading = false;
    this.pending = Boolean(this.state.recordId && this.state.type);
    this.start();
  }

  // The first page, once the columns are known.
  start() {
    if (!this.pending || !this.layoutReady) return;
    this.pending = false;
    this.load();
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
        cursor: this.cursor,
        fields: this.layoutFields.map((f) => f.apiName)
      });
      if (ticket !== this.ticket) return;
      if (!this.cursor) {
        this.label = page.label;
        this.icon = page.icon;
        this.dateOnly = page.dateOnly;
        this.recordName = page.recordName;
      }
      this.items = [...this.items, ...(page.items ?? [])];
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

  // Every item's detail labels, in the order they first appear, as columns.
  get detailLabels() {
    const labels = [];
    for (const item of this.items) {
      for (const d of item.details ?? []) {
        if (d.label && !labels.includes(d.label)) labels.push(d.label);
      }
    }
    return labels;
  }

  get columns() {
    if (this.layoutFields.length) return this.layoutColumns;
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

  // The layout's fields, the first linking to the record; then the
  // source's own detail fields the layout hasn't got; then the date.
  get layoutColumns() {
    const [first, ...rest] = this.layoutFields;
    const columns = [
      {
        label: first.label,
        fieldName: "recordUrl",
        type: "url",
        typeAttributes: { label: { fieldName: "field0" }, tooltip: { fieldName: "field0" }, target: "_self" },
        hideDefaultActions: true
      },
      ...rest.map((f, i) => ({ label: f.label, fieldName: `field${i + 1}`, hideDefaultActions: true }))
    ];
    const taken = new Set(this.layoutFields.map((f) => f.label));
    this.detailLabels.forEach((label, i) => {
      if (!taken.has(label)) columns.push({ label, fieldName: `detail${i}`, hideDefaultActions: true });
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
    const labels = this.detailLabels;
    return this.items.map((item) => {
      const row = {
        id: item.id,
        title: item.title,
        recordUrl: item.recordId ? `/lightning/r/${item.recordId}/view` : null,
        subtitle: item.subtitle,
        when: this.whenText(item)
      };
      this.layoutFields.forEach((f, i) => {
        row[`field${i}`] = item.columns?.[f.apiName] ?? "";
      });
      // The link always has something to click.
      if (this.layoutFields.length && !row.field0) row.field0 = item.title;
      for (const d of item.details ?? []) {
        row[`detail${labels.indexOf(d.label)}`] = d.value;
      }
      return row;
    });
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

  // Until the first page is in (the layout read, then the rows): the
  // table's shape, so nothing moves when it arrives. The table's own
  // spinner is for the pages after.
  get showSkeleton() {
    return !this.missingState && !this.error && this.items.length === 0 && (this.pending || this.loading);
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
