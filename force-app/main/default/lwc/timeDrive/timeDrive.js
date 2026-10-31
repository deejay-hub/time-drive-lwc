/**
 * Time Drive: a record's engagement in time order, from
 * every source set up in Time Drive Setup (Salesforce records, Data 360 DMOs
 * and Apex providers). Vertical in narrow regions; from 640px of width the
 * days lay out as columns along a horizontal axis.
 */
import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { IsConsoleNavigation, openTab } from "lightning/platformWorkspaceApi";
import { LABELS, format } from "c/timeDriveLabels";
import getTimeline from "@salesforce/apex/TimeDriveController.getTimeline";
import getTimelineDiagnosed from "@salesforce/apex/TimeDriveController.getTimelineDiagnosed";
import getDays from "@salesforce/apex/TimeDriveController.getPageDays";
import getRights from "@salesforce/apex/TimeDriveController.getRights";
import getViews from "@salesforce/apex/TimeDriveController.getViews";
import getPreference from "@salesforce/apex/TimeDriveController.getPreference";
import savePreference from "@salesforce/apex/TimeDriveController.savePreference";
import getActivityActions from "@salesforce/apex/TimeDriveController.getActivityActions";
import TimeDriveConfirm from "c/timeDriveConfirm";
import LightningConfirm from "lightning/confirm";
import { deleteRecord } from "lightning/uiRecordApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { registerRefreshHandler, unregisterRefreshHandler } from "lightning/refresh";
import FORM_FACTOR from "@salesforce/client/formFactor";
import DIR from "@salesforce/i18n/dir";
import LOCALE from "@salesforce/i18n/locale";
import LANG from "@salesforce/i18n/lang";
import { note, setServerReport } from "c/timeDriveTraceLog";
import {
  describeError,
  describeProblems,
  fitIllustrations,
  illustrationName,
  illustrationState,
  isSlds2
} from "c/timeDriveErrors";
import {
  EVENT_TYPES,
  VIEWS,
  FORMATS,
  filePreviewRef,
  isFileId,
  recordHref,
  buildMinimap,
  dayAtPercent,
  currentPeriodKey,
  periodDate,
  windowEnds,
  dayWord,
  formatCount,
  relativeDay,
  percentAtDay,
  periodLabel,
  typeInfo,
  viewFor,
  windowDates,
  windowRange
} from "./timeDriveModel";

const WIDE_FROM = 640;
// The smallest a heatmap cell may be, in px: `base` on up to 5 years of
// history, a quarter as big again past 5 years and 1.7 times as big past 10,
// so a long history merges into fewer, readable cells (quarters, then
// half-years, then years) instead of a crowded strip.
function minCellSize(days, base) {
  const times = days.map((d) => d.time).filter(Number.isFinite);
  if (times.length < 2) return base;
  const years = (Math.max(...times) - Math.min(...times)) / (365.25 * 86400000);
  if (years > 10) return Math.round(base * 1.7);
  if (years > 5) return Math.round(base * 1.25);
  return base;
}
// Takes values only to read them: reading a field or getter makes LWC
// re-render the caller when it changes, or builds what the getter caches.
function dependOn() {}
// Vertical: days of activity shown at first, and added by scrolling near
// either end. The window of drawn days stays under
// MAX_WINDOW_DAYS: days far behind the view are dropped again.
const DAY_PAGE = 7;
const MAX_WINDOW_DAYS = 28;
// Vertical: how close to an end of the list (px) scrolling loads the next days.
const NEAR_END = 160;
// Dragging the scrub tab: how far the skeleton list slides per day passed.
const PREVIEW_DAY_PX = 96;
// Drawing and fetching wait until dragging or fast scrolling (px per ms)
// pauses this long (ms).
const SETTLE_MS = 150;
const FAST_SCROLL = 1.5;
// How long the "Click to scroll the timeline" hint shows (ms).
const HINT_MS = 1800;
// Horizontal: columns either side of the view that get their events drawn;
// the rest are date-only shells until scrolled near.
const WINDOW_BUFFER = 3;
// Columns read with the first request (see openingColumns): 6 in view and the buffer either side.
const OPENING_COLUMNS = 6 + 2 * WINDOW_BUFFER;
// The spacing hooks the page sets from the user's Display Density, in order of
// trust, each with its fixed twin (the same step, which density doesn't move).
// Read on the host: in SLDS 1 the medium step is 1rem in Comfy and 0.5rem in
// Compact (measured); SLDS 2's hook is meant to move the same way. Compact is
// the step reading less than its twin, 1rem where the page has no twin.
const DENSITY_HOOKS = [
  ["--slds-g-spacing-var-4", "--slds-g-spacing-4"],
  ["--lwc-varSpacingMedium", "--lwc-spacingMedium"]
];
// What the card asks for and when, in the console ("[Time Drive]"): the
// requests and how long each took, the window it draws, scrolling.
function trace(...what) {
  // Objects as text, so what is pasted from the console reads in full.
  const text = what.map((part) => {
    if (part === null || typeof part !== "object") return part;
    try {
      return JSON.stringify(part);
    } catch {
      return String(part);
    }
  });
  const at = Math.round(performance.now());
  console.info("[Time Drive]", at, ...text);
  // For the Diagnostics page in Setup, which reads the same lines.
  note(at, text.join(" "));
}
// "Order placed, Order delivered and Order canceled", in the user's language.
const LIST_FORMAT = new Intl.ListFormat(LANG, { style: "long", type: "conjunction" });
// Fetched days kept in memory at most (the drawn window is far smaller).
const MAX_CACHED_DAYS = 120;
// Days are read ahead of the scroll, so the ones about to be drawn are already
// here. Once the window has moved, an unread day within PREFETCH_TRIGGER of its
// edge in the direction it is going starts a request; the unread days out to
// PREFETCH_FAR that way (PREFETCH_NEAR the other way) go together, nearest first
// and at most PREFETCH_MAX at a time: a request costs about 0.6 s whatever it
// holds, but one with 30 days takes twice as long to come back as one with 12.
const PREFETCH_TRIGGER = 3;
const PREFETCH_FAR = 6;
const PREFETCH_NEAR = 2;
const PREFETCH_MAX = 18;

// Fit mode: horizontally, when every active day fits at once (up to the
// five the track shows across), the columns share the whole width.
const FIT_MAX_DAYS = 5;
// The narrowest a shared column may be, in rem.
const FIT_MIN_REM = 15;

// The Salesforce mobile app on a phone: one column, lighter rows, bigger targets.
const isPhone = () => FORM_FACTOR === "Small";
// App Builder Activity Actions.
// Full actions shown before the rest go in a menu: in a narrow card, and in a wide one.
const NARROW_ACTIONS = 1;
// The actions that stay on show first (the icons' names).
const ACTION_PRIORITY = ["log_a_call", "email", "new_event", "new_task"];
const WIDE_ACTIONS = 4;
const ACTION_MODES = ["none", "one button", "inline", "full"];

// A button icon takes a utility icon: an action's own (action:new_task) as
// its utility match (utility:task).
const UTILITY_FOR_ACTION = {
  new_task: "utility:task",
  new_event: "utility:event",
  log_a_call: "utility:call",
  email: "utility:email",
  new_note: "utility:note",
  new_case: "utility:case"
};
// The four standard activity actions are named by our own labels (so they
// follow the translations here); any other action keeps Salesforce's.
const ACTION_LABEL = {
  new_task: LABELS.actionNewTask,
  new_event: LABELS.actionNewEvent,
  log_a_call: LABELS.actionLogCall,
  email: LABELS.actionEmail
};
function actionLabelFor(action) {
  return ACTION_LABEL[action.icon?.split(":")[1]] ?? action.label;
}
function utilityIconFor(icon) {
  if (!icon) return "utility:add";
  const [set, name] = icon.split(":");
  if (set === "utility") return icon;
  return UTILITY_FOR_ACTION[name] ?? (name?.startsWith("new_") ? `utility:${name.slice(4)}` : "utility:add");
}

// The icon after an Email Message's title, by what tracking says.
const EMAIL_STATES = {
  opened: { icon: "utility:preview", label: LABELS.emailOpened },
  unopened: { icon: "utility:hide", label: LABELS.emailUnopened },
  bounced: { icon: "utility:warning", label: LABELS.emailBounced }
};

// The overview (minimap, scrubber) shows only when the days overflow the
// track, and has at least this many days and two cells to show.
const MINIMAP_MIN_DAYS = 2;
// Dates in the user's Salesforce locale (and, for times, its time zone).
const TIME_FORMAT = FORMATS.time;
const DAY_SHORT_FORMAT = FORMATS.dayShort;
const DAY_SHORT_TIME_FORMAT = FORMATS.dayShortTime;
const DATE_TIME_FORMAT = FORMATS.dateTime;
const WEEKDAY_SHORT = FORMATS.weekday;
const MONTH_SHORT = FORMATS.month;
const MONTH_YEAR = FORMATS.monthYear;

// The window's ends, across: nothing to see this far out.

// "2026-10-18" (server day key) -> local midnight, for labels and the minimap.
function keyTime(key) {
  const [y, m, d] = key.split("-").map(Number);
  return new Date(y, m - 1, d).getTime();
}

export default class TimeDrive extends NavigationMixin(LightningElement) {
  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    this._recordId = value;
    this.requestTimeline();
  }
  _recordId;
  // The Diagnostics page asks the card to have its opening request report what
  // it ran (getTimelineDiagnosed); the report goes to c/timeDriveTraceLog.
  @api diagnose = false;
  // The words on the page, in the viewer's language.
  labels = LABELS;
  // App Builder properties.
  @api cardTitle = "Time Drive";
  // Where the timeline opens: Today (its slot, real or a placeholder),
  // Earliest item or Latest item.
  @api openAt = "Today";
  // The lens it opens on (an App Builder property); the picker changes it.
  @api defaultLens = "All";
  @api layout = "Auto"; // Auto | Vertical | Horizontal
  // The page is in SLDS 1 (Salesforce Lightning Design System's first look).
  slds1 = false;
  // Horizontal layout only: the height of the day columns, in pixels. Days
  // with more events scroll inside their column, so moving between days
  // never changes the card's height.
  @api horizontalHeight = 260;
  // Full detail (each item's time and date) or titles only: the user's own
  // choice (the button after Today), kept for them in the org. A phone starts
  // light unless they have chosen.
  _lite;
  get lite() {
    if (this._lite !== undefined) return this._lite;
    return isPhone();
  }
  get showWhen() {
    return !this.lite;
  }
  get liteLabel() {
    return this.lite ? LABELS.buttonLiteOff : LABELS.buttonLiteOn;
  }
  toggleLite() {
    this._lite = !this.lite;
    this.keepPreference(null, this._lite ? "lite" : "max");
  }

  // The last lens and label choice are the user's own (Time Drive Preference),
  // kept in the org: they follow the person to any browser. Nothing else is.
  keepPreference(lens, itemDetail) {
    savePreference({ lens, itemDetail }).catch(() => {
      // Not kept (no access): the choice still holds for this visit.
    });
  }

  // A lens the org offers (the list, once it is here, else the built-in ones).
  offers(lens) {
    return this.viewList.some((v) => v.value === lens);
  }

  async loadPreference() {
    try {
      const kept = await getPreference();
      if (this._gone) return;
      // Anything they chose meanwhile stands.
      if (this._lite === undefined && (kept?.itemDetail === "Lite" || kept?.itemDetail === "Max")) {
        this._lite = kept.itemDetail === "Lite";
      }
      // Their last lens, while the org still offers it.
      if (!this._picked && kept?.lens && kept.lens !== this.view && this.offers(kept.lens)) {
        this.view = kept.lens;
        this.applyQueryChange();
      }
    } catch {
      // Not read: the page's own defaults stand.
    }
  }

  // Auto follows the user's density; Comfy or Compact overrides it here.
  @api density = "Auto";
  // Vertical layout only: the list's greatest height, in pixels. A record
  // with a few days gets a list as tall as they are; past this, it scrolls
  // inside the card.
  @api verticalHeight = 560;
  // The visible height of the page and of this card's header, for the phone's
  // fit-the-screen list (see listHeight).
  viewportHeight = 0;
  headerHeight = 0;
  // How far back and ahead the timeline plots, in years (App Builder lists
  // 0.25 to 10; Future also None, for up to today). Applied on the server,
  // to every source.
  @api
  get historyYears() {
    return this._historyYears;
  }
  set historyYears(value) {
    this._historyYears = value;
    this.queryHistory = value == null || value === "" ? null : String(value);
    this.requestTimeline();
  }
  _historyYears = "0.5";
  @api
  get futureYears() {
    return this._futureYears;
  }
  set futureYears(value) {
    this._futureYears = value;
    this.queryFuture = value == null || value === "" ? null : String(value);
    this.requestTimeline();
  }
  _futureYears = "None";

  // App Builder "Activity Actions": the record's New Task, Log a Call,
  // Email, New Event ... as on the standard Activity component. None; One
  // button (a + menu); Inline (a button each, among the tools); Full (a
  // button each with its name, on a line of its own, or among the tools in
  // a wide horizontal card). Defaults to Inline.
  @api
  get activityActionsMode() {
    return this._actionsMode;
  }
  set activityActionsMode(value) {
    const mode = String(value ?? "").toLowerCase();
    this._actionsMode = ACTION_MODES.includes(mode) ? mode : "inline";
  }
  _actionsMode = "inline";

  // The actions, from the record's layout (see getActivityActions); none
  // asked for when the option is None.
  @wire(getActivityActions, { recordId: "$actionsRecordId" })
  wiredActions({ data }) {
    this.actions = data ?? [];
  }
  actions = [];
  get actionsRecordId() {
    // None on a phone, which has no activity buttons: nothing to ask for.
    return this._actionsMode === "none" || isPhone() ? undefined : this.recordId;
  }
  get activityActions() {
    return this.actions.map((a) => ({
      ...a,
      key: a.apiName,
      label: actionLabelFor(a),
      buttonIcon: utilityIconFor(a.icon),
      // The action's own colour for its circle (grey if it has none).
      style: `--action: ${a.colour || "#747474"}`
    }));
  }
  // One in a narrow card, four in a wide one; the rest go in a menu beside them.
  get actionsShownMax() {
    return this.actionsNarrow ? NARROW_ACTIONS : WIDE_ACTIONS;
  }
  // Which fit when there are too many: Log a Call and Email first, then
  // New Event, New Task and any others; each group keeps the layout's order.
  get keptActionKeys() {
    const rank = (a) => {
      const at = ACTION_PRIORITY.indexOf(a.icon?.split(":")[1]);
      return at === -1 ? ACTION_PRIORITY.length : at;
    };
    const ranked = [...this.activityActions].sort((x, y) => rank(x) - rank(y));
    return new Set(ranked.slice(0, this.actionsShownMax).map((a) => a.key));
  }
  get shownActions() {
    const keep = this.keptActionKeys;
    return this.activityActions.filter((a) => keep.has(a.key));
  }
  get overflowActions() {
    const keep = this.keptActionKeys;
    return this.activityActions.filter((a) => !keep.has(a.key));
  }
  get hasOverflowActions() {
    return this.overflowActions.length > 0;
  }
  get actionsNarrow() {
    return this.narrow;
  }
  // The title row holds the Full actions (see fullActionsOwnRow).
  get actionsOnTitleRow() {
    return this.fullActionsOwnRow || this.fullActionsSkeleton;
  }
  // With them there, the filter summary moves down beside the tools.
  get summaryAfterTools() {
    return !this.actionsOnTitleRow;
  }
  get titleRowClass() {
    return this.actionsOnTitleRow ? "title-row title-row_actions" : "title-row";
  }
  get hasActivityActions() {
    return this._actionsMode !== "none" && this.actions.length > 0;
  }
  // One button always folds them into the + menu; Inline does when the card
  // is narrow.
  get actionsAsMenu() {
    return this._actionsMode === "one button" || (this.cardWidth > 0 && this.cardWidth < 480);
  }
  get showInlineActions() {
    return this.hasActivityActions && this._actionsMode !== "full" && !isPhone();
  }
  // Full: on the view's line, at its end, whatever the card's width.
  get fullActionsOwnRow() {
    return this.hasActivityActions && this._actionsMode === "full" && !isPhone();
  }
  get fullActionsSkeleton() {
    return this._actionsMode === "full" && this.firstLoad && !isPhone();
  }

  // Opens the action as Salesforce does (its own window or email composer);
  // when it saves, the page refreshes and so does the timeline.
  handleActivityAction(event) {
    const apiName = event.currentTarget?.dataset?.action ?? event.detail?.value;
    if (!apiName) return;
    this[NavigationMixin.Navigate]({
      type: "standard__quickAction",
      attributes: { apiName },
      state: { recordId: this.recordId }
    });
  }

  // The whole history as per-day counts (getSummary), and the full events of
  // the days fetched so far (getDays), by day key.
  summary;
  wired;
  loaded = false;
  // True until the first answer (or failure), when the header's title and
  // buttons are placeholders too; a refresh or a new filter keeps them.
  firstLoad = true;
  error;
  _dayCache = new Map();
  _loadingDays = new Set();
  _queryVersion = 0;
  // Bumped when days arrive, so the view re-renders with them.
  daysLoaded = 0;
  // Bumped when the summary changes, so derived views rebuild.
  daysVersion = 0;
  // What the server filters by (kept in step with the view and filters).
  // "No filter" is null, never undefined: the wire service holds a request
  // until every parameter is defined.
  queryCategories = null;
  queryHidden = [];
  // The App Builder window (History and Future, in years).
  queryHistory = "0.5";
  queryFuture = "None";

  view = "All";
  hiddenTypes = new Set();
  expanded = new Set();
  // Vertical: the drawn days are orderedDays[windowFrom, windowFrom + visibleDays).
  windowFrom = 0;
  visibleDays = DAY_PAGE;
  renderFrom = 0;
  renderTo = 8;
  isWide = false;
  // Vertical with the scrub tab: the list was clicked, so the wheel scrolls it.
  engaged = false;
  // The card's width, to the nearest 40px: how many minimap cells fit.
  cardWidth = 960;
  // The Filters panel: event types, drafted until Apply.
  // The view menu, under the view's name.
  viewMenuOpen = false;

  connectedCallback() {
    this._connectedAt = performance.now();
    trace("connected");
    // Open on the chosen lens; one that isn't a lens opens on All.
    const lens = viewFor(this.defaultLens).value;
    if (lens !== "All" && lens === this.defaultLens) this.view = lens;
    this.syncQuery();
    // Across or down is decided by the width, which the first request depends
    // on (it asks for the days around where the timeline opens): read it now,
    // not after the first draw.
    const width = this.template.host?.getBoundingClientRect?.().width;
    if (width > 0) {
      const wide = width >= WIDE_FROM;
      if (wide !== this.isWide) this.isWide = wide;
      this.noteWidth(width);
      this._widthKnown = true;
    }
    this._connected = true;
    this.requestTimeline();
    // What they last chose is read alongside; a different lens asks again.
    this.loadPreference();
    // A save on the page (a new task, a logged call, an edited record):
    // refresh quietly, in place.
    this._refreshId = registerRefreshHandler(this, () => {
      this.refreshQuietly();
      return Promise.resolve(true);
    });
    // Comfy or Compact spacing (see :host(.density_comfy)): the page's own
    // (Display Density on the component, else the page's spacing hooks), else
    // else Compact. No server call.
    if (this.densityOverride) {
      this.applyDensity(this.densityOverride);
    } else {
      const seen = this.cssDensity();
      this.applyDensity(seen ?? "compact");
    }
    // A press outside the panel (and its button) cancels it. Presses inside
    // flag themselves first, as the page can't see into the component.
    this._onDocumentPointer = () => {
      // A press anywhere but the list lets go of it (touch has no "leave").
      const inList = this._listPress;
      this._listPress = false;
      if (!inList && this.engaged) this.setEngaged(false);
      const inViews = this._viewPress;
      this._viewPress = false;
      if (!inViews && this.viewMenuOpen) this.closeViewMenu(false);
      const inRowMenu = this._rowMenuPress;
      this._rowMenuPress = false;
      if (!inRowMenu && this.rowMenu) this.rowMenu = null;
      if (!inRowMenu && this.headerMenu) this.headerMenu = null;
    };
    document.addEventListener("pointerdown", this._onDocumentPointer);
    // A scroll anywhere moves the row away from a fixed menu: close it.
    // The phone's list fits the screen: follow it as the phone turns and the
    // browser's bars come and go.
    this._onViewport = () => {
      const h = Math.round(window.visualViewport?.height ?? window.innerHeight);
      if (h !== this.viewportHeight) this.viewportHeight = h;
    };
    this._onViewport();
    window.addEventListener("resize", this._onViewport);
    window.visualViewport?.addEventListener("resize", this._onViewport);
    this._onDocumentScroll = () => {
      if (this.rowMenu) this.rowMenu = null;
      if (this.headerMenu) this.headerMenu = null;
    };
    document.addEventListener("scroll", this._onDocumentScroll, true);
  }

  // Width decides the layout when Layout is Auto. The observer starts once
  // the card is in the DOM.
  renderedCallback() {
    if (isPhone()) {
      const header = this.template.querySelector(".header");
      const h = header ? Math.round(header.getBoundingClientRect().height) : 0;
      if (h && h !== this.headerHeight) this.headerHeight = h;
    }
    if (this._focusRowMenu && (this.rowMenu || this.headerMenu)) {
      this._focusRowMenu = false;
      this.template.querySelector(".row-popover-item")?.focus();
    }
    // SLDS 1 draws icons and icon buttons as rounded squares, SLDS 2 as
    // circles: the card follows the page's, read once it's on the page.
    if (!this._sldsRead) {
      this._sldsRead = true;
      const slds1 = !isSlds2(this.template.host);
      if (slds1 !== this.slds1) this.slds1 = slds1;
    }
    fitIllustrations(this.template);
    this.measureBeforeFirstRequest();
    this.loadNeededDays();
    this.focusViewMenu();
    this.listenToWheel();
    // Cache what the brush and drag need, once per render, so scrolling and
    // dragging only do arithmetic.
    this._cells = (this.horizontal ? this.minimap : this.scrubber)?.cells ?? [];
    this._geometry = null;
    // Builds (or reuses) the day list, and with it the labels and times the
    // scrubber's bubble reads.
    dependOn(this.orderedDays);
    this._scrubUnit = (this.horizontal ? this.minimap : this.scrubber)?.unit;
    // The layout flipped, and with it the order: open at Open At again.
    if (this._focusLayout !== undefined && this._focusLayout !== this.horizontal) this._focusPending = true;
    this._focusLayout = this.horizontal;
    this.applyFocus();
    this.restoreAcross();
    if (!this.horizontal) {
      this.settleVertical();
      this.fillVertical();
    }
    this.measureOverflow();
    this.queueBrush();
    if (this.horizontal && this.hasEvents) {
      this.queuePills();
      // Icons and fonts can finish laying out after the first frame, so count
      // again once the first load has settled.
      if (!this._pillsSettled) {
        this._pillsSettled = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => this.queuePills(), 400);
      }
    }
    if (this._observer || typeof ResizeObserver === "undefined") return;
    const card = this.template.querySelector(".card");
    if (!card) return;
    // Measure now, before the first paint, so a wide region starts out
    // horizontal (and its loading placeholder is the right shape).
    const widthNow = card.getBoundingClientRect().width;
    const wideNow = widthNow >= WIDE_FROM;
    if (wideNow !== this.isWide) this.isWide = wideNow;
    this.noteWidth(widthNow);
    this._observer = new ResizeObserver((entries) => {
      trace("card resized", Math.round(entries[0].contentRect.width));
      this._geometry = null;
      const wide = entries[0].contentRect.width >= WIDE_FROM;
      if (wide !== this.isWide) this.isWide = wide;
      this.noteWidth(entries[0].contentRect.width);
      this.measureOverflow();
      this.queuePills();
    });
    this._observer.observe(card);
  }

  // Only a change of 40px or more redraws the minimap.
  noteWidth(width) {
    const rounded = Math.round(width / 40) * 40;
    if (rounded && rounded !== this.cardWidth) this.cardWidth = rounded;
  }

  // "comfy" or "compact" when the page sets one; null for Auto.
  get densityOverride() {
    const set = String(this.density ?? "").toLowerCase();
    return set === "comfy" || set === "compact" ? set : null;
  }

  applyDensity(density) {
    if (density !== "comfy" && density !== "compact") return;
    this.classList.toggle("density_compact", density === "compact");
    this.classList.toggle("density_comfy", density === "comfy");
  }

  disconnectedCallback() {
    this._gone = true;
    if (this._refreshId !== undefined) unregisterRefreshHandler(this._refreshId);
    document.removeEventListener("pointerdown", this._onDocumentPointer);
    document.removeEventListener("scroll", this._onDocumentScroll, true);
    window.removeEventListener("resize", this._onViewport);
    window.visualViewport?.removeEventListener("resize", this._onViewport);
    this._wheelTrack?.removeEventListener("wheel", this._onTrackWheel);
    this._wheelTrack = null;
    if (this._brushFrame) cancelAnimationFrame(this._brushFrame);
    if (this._pillFrame) cancelAnimationFrame(this._pillFrame);
    clearTimeout(this._windowTimer);
    clearTimeout(this._keyJumpTimer);
    clearTimeout(this._hintTimer);
    this._observer?.disconnect();
    this._observer = undefined;
  }

  // ---- loading the timeline: the summary, and the days it opens on, in one
  // request ---------------------------------------------------------------------

  _connected = false;
  _timelineKey = null;
  _timelineSeq = 0;

  // How many columns the horizontal layout reads and draws around where it
  // opens. Fixed, not worked out from the card's width: the request goes out
  // before the card is measured, and a window sized differently when the
  // answer lands left columns to fetch afterwards (a pause, then more days).
  // A column is a fifth of the card (17rem at least), so at most 6 show, even
  // part-way; with WINDOW_BUFFER either side the window the view settles on is
  // never more than this.
  get openingColumns() {
    return OPENING_COLUMNS;
  }

  // Asks for the timeline when what it is made of has changed (or when forced:
  // Refresh). A newer answer replaces an older one still on its way.
  // Whether the first request can say which way the timeline runs. With Layout
  // Auto that is the card's width, and the host has none until it is on the
  // page: asking before then would read the days for a list down (today and
  // older) when the card turns out to run across (the days around today),
  // and the columns ahead of today would load only afterwards.
  _widthKnown = false;
  get layoutKnown() {
    return this._widthKnown || this.layout === "Horizontal" || this.layout === "Vertical" || isPhone();
  }

  // The user's Display Density as the page's own spacing shows it: Lightning
  // sets its density-aware hooks for the user (Comfy 1rem, Compact 0.5rem for
  // the medium step), and they reach this host, so no server call is needed.
  // Null when the page sets none (a page without SLDS), and the server decides.
  cssDensity() {
    try {
      const style = getComputedStyle(this.template.host);
      const rems = (name) => {
        const raw = style.getPropertyValue(name).trim();
        return raw.endsWith("rem") ? parseFloat(raw) : raw.endsWith("px") ? parseFloat(raw) / 16 : NaN;
      };
      for (const [name, fixed] of DENSITY_HOOKS) {
        const rem = rems(name);
        if (!(rem > 0)) continue;
        const base = rems(fixed) > 0 ? rems(fixed) : 1;
        trace("density from css", name, rem, "against", base);
        return rem < base * 0.99 ? "compact" : "comfy";
      }
    } catch {
      // No styles to read.
    }
    return null;
  }

  // The host had no width when it connected: the card's, once drawn, says
  // which way to run, and the first request goes out.
  measureBeforeFirstRequest() {
    if (this._widthKnown) return;
    const card = this.template.querySelector(".card");
    if (!card) return;
    const width = card.getBoundingClientRect().width;
    const wide = width >= WIDE_FROM;
    if (wide !== this.isWide) this.isWide = wide;
    this.noteWidth(width);
    this._widthKnown = true;
    this.requestTimeline();
  }

  requestTimeline(force = false) {
    if (!this._connected || !this._recordId || this.queryCategories === undefined || !this.layoutKnown) {
      return Promise.resolve();
    }
    const key = JSON.stringify([
      this._recordId,
      this.queryCategories,
      this.queryHidden,
      this.queryHistory,
      this.queryFuture
    ]);
    if (!force && key === this._timelineKey) return Promise.resolve();
    this._timelineKey = key;
    const seq = ++this._timelineSeq;
    const centred = this.horizontal;
    const sentAt = performance.now();
    trace("getTimeline request", {
      centred,
      count: this._keepStale ? 0 : centred ? this.openingColumns : DAY_PAGE,
      cardWidth: this.cardWidth
    });
    const ask = this.diagnose ? getTimelineDiagnosed : getTimeline;
    return ask({
      contactId: this._recordId,
      categories: this.queryCategories,
      hiddenTypes: this.queryHidden,
      historyYears: this.queryHistory,
      futureYears: this.queryFuture,
      focus: this.openAt,
      newestFirst: this.newestFirst,
      centred,
      // A refresh stays where it is: the days it is on are asked for after.
      count: this._keepStale ? 0 : centred ? this.openingColumns : DAY_PAGE
    })
      .then((load) => {
        trace(
          "getTimeline returned",
          Math.round(performance.now() - sentAt),
          "ms after it was sent",
          // What Apex itself took, so the rest of the wait can be told apart.
          load?.serverMs === undefined || load?.serverMs === null
            ? ""
            : `(server ${load.serverMs} ms, ${load.queryCount} queries)`
        );
        if (seq === this._timelineSeq) {
          if (this.diagnose && load?.queries) this.reportToDiagnostics(load);
          this.receiveTimeline(load);
        }
      })
      .catch((error) => {
        if (seq !== this._timelineSeq) return;
        this.summaryPending = false;
        this.refreshHeight = null;
        this.error = this.reportError(error);
        this.loaded = true;
        this.firstLoad = false;
      });
  }

  // What the server did for this very request, for the Diagnostics page.
  reportToDiagnostics(load) {
    const events = load.events ?? [];
    setServerReport({
      serverMs: load.serverMs,
      cpuMs: load.cpuMs,
      queryCount: load.queryCount,
      queryRows: load.queryRows,
      payloadKb: Math.round(JSON.stringify(load).length / 1024),
      events: events.length,
      groupedRows: events.filter((e) => e.grouped).length,
      days: load.summary?.days?.length ?? 0,
      unit: load.summary?.unit,
      warnings: load.summary?.warnings ?? [],
      problems: (load.summary?.problems ?? []).map((p) => `${p.source}: ${p.kind}`),
      counted: load.summary?.counted ?? [],
      queries: load.queries,
      phases: load.phases ?? [],
      notes: load.notes ?? []
    });
  }

  receiveTimeline(load) {
    const data = load?.summary;
    if (!data) return;
    this.summaryPending = false;
    this.refreshHeight = null;
    this.error = undefined;
    this.summary = data;
    this.daysVersion++;
    // A new history opens at Open At; a refresh stays where it is.
    if (!this._keepStale) this._focusPending = true;
    this.resetDays();
    // Fewer days than the window starts at (a refresh found less): start over.
    if (this.windowFrom >= (data.days?.length ?? 0)) this.resetPaging();
    // The days it opens on arrived with it: set the window to them before the
    // first draw, so nothing is asked for twice.
    this.ingestDays(load.keys ?? [], load.events ?? []);
    this.presetWindow();
    trace("getTimeline answer", {
      days: data.days?.length,
      keys: load.keys ?? [],
      events: (load.events ?? []).length,
      window: [this.renderFrom, this.renderTo],
      focus: this.horizontal ? this.focusIndex() : null,
      budgetSpent: !(load.keys ?? []).length
    });
    this.loaded = true;
    this.firstLoad = false;
    if (!this._painted) {
      this._painted = true;
      /* eslint-disable @lwc/lwc/no-async-operation */
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          trace("first paint of the days", Math.round(performance.now() - this._connectedAt), "ms after connecting");
        });
      });
      /* eslint-enable @lwc/lwc/no-async-operation */
    }
  }

  // Opens on the Open At period now (the server read the days around it), not
  // after the first draw. Across, the columns are laid out only once drawn, so
  // that part waits for applyFocus; the columns to read are set here.
  presetWindow() {
    if (!this._focusPending || !this.allDays.length) return;
    if (this.horizontal) {
      const size = this.openingColumns;
      const from = Math.max(0, Math.min(this.focusIndex() - Math.floor(size / 2), this.allDays.length - size));
      this.renderFrom = from;
      this.renderTo = from + size - 1;
    } else {
      this.applyFocus();
    }
  }

  // ---- loading days ---------------------------------------------------------

  // "Last 6 months", "Last 2 years · next 3 months" (for the empty state).
  // True where the card is too narrow for words on its buttons.
  get narrow() {
    return this.cardWidth > 0 && this.cardWidth < WIDE_FROM;
  }

  // The filters as the server takes them: the lens viewed (All is a lens like the others).
  syncQuery() {
    const next = { categories: [this.view], hidden: [...this.hiddenTypes] };
    // A new query: its counts are on their way (the header says so until
    // the summary lands). The same query brings no new summary to wait for.
    const changed =
      JSON.stringify(next.categories) !== JSON.stringify(this.queryCategories) ||
      JSON.stringify([...next.hidden].sort()) !== JSON.stringify([...(this.queryHidden ?? [])].sort());
    if (changed) this.summaryPending = true;
    this.queryCategories = next.categories;
    this.queryHidden = next.hidden;
    this.requestTimeline();
    return changed;
  }
  // A new filter or view: the page says so at once. The days under the header
  // go to the loading skeleton, at the height they had, as the counts above
  // them already do, instead of showing the old days until the new ones land.
  // The same query again changes nothing, so it shows nothing.
  applyQueryChange() {
    this.resetPaging();
    if (this.syncQuery()) {
      this.holdHeight();
      this.loaded = false;
    }
  }
  // A filter or view applied, its summary not back yet.
  summaryPending = false;
  resetDays() {
    // After Refresh, the days already drawn stay on screen until their fresh
    // copies arrive, so nothing jumps (see handleRefresh).
    this._staleCache = this._keepStale ? this._dayCache : null;
    this._keepStale = false;
    this._dayCache = new Map();
    this._rights = new Map();
    this._loadingDays = new Set();
    this._openCore = undefined;
    this._moved = false;
    this._heading = undefined;
    this._queryVersion++;
    this.daysLoaded++;
  }
  // Fetch the days about to be drawn that haven't been fetched yet: the first
  // pages in the vertical layout, the columns near the view in the horizontal.
  loadNeededDays() {
    if (!this.summary || !this.recordId) return;
    const days = this.orderedDays;
    const unread = (day) => !day.placeholder && !this._dayCache.has(day.key) && !this._loadingDays.has(day.key);
    // The drawn window; the direction it last moved (index order), once it has.
    const [coreFrom, coreTo] = this.horizontal
      ? [this.renderFrom, this.renderTo]
      : [this.windowFrom, this.windowFrom + this.visibleDays - 1];
    const core = `${coreFrom}|${coreTo}`;
    const centre = (coreFrom + coreTo) / 2;
    if (this._openCore === undefined) {
      this._openCore = core;
      this._centre = centre;
    } else if (core !== this._openCore) {
      this._moved = true;
      if (centre !== this._centre) this._heading = Math.sign(centre - this._centre);
      this._openCore = core;
      this._centre = centre;
    }
    // Reading ahead starts once the window has moved: on opening, only the days
    // it opens on are read (more would be work for a timeline that may stay put).
    const heading = this._moved ? (this._heading ?? 0) : null;
    const edge = (side) => {
      if (heading === null) return [0, 0];
      const toward = heading === 0 || heading === side;
      return [toward ? PREFETCH_TRIGGER : 0, toward ? PREFETCH_FAR : PREFETCH_NEAR];
    };
    const [triggerBefore, reachBefore] = edge(-1);
    const [triggerAfter, reachAfter] = edge(1);
    const inZone = days.slice(Math.max(0, coreFrom - triggerBefore), coreTo + triggerAfter + 1);
    if (!inZone.some(unread)) return;
    const reach = days.slice(
      Math.max(0, coreFrom - Math.max(reachBefore, triggerBefore)),
      coreTo + Math.max(reachAfter, triggerAfter) + 1
    );
    // What the window needs first, then the rest nearest to it, up to the most
    // one request holds (the window's own days always).
    const distance = (d) => {
      const at = days.indexOf(d);
      return at < coreFrom ? coreFrom - at : at > coreTo ? at - coreTo : 0;
    };
    const unreadDays = reach.filter(unread).sort((x, y) => distance(x) - distance(y));
    const inWindow = unreadDays.filter((d) => distance(d) === 0).length;
    const keys = unreadDays.slice(0, Math.max(PREFETCH_MAX, inWindow)).map((d) => d.key);
    const wanted = reach;
    if (!keys.length) return;
    trace("getPageDays request", { keys, window: [this.renderFrom, this.renderTo] });
    keys.forEach((key) => this._loadingDays.add(key));
    // The days the summary already found busy: only they are counted, the
    // rest read as rows straight away (no count query for a quiet page).
    const over = this.summary.groupOver;
    const counts = new Map(wanted.map((d) => [d.key, d.count]));
    const busyKeys = over == null ? null : keys.filter((key) => (counts.get(key) ?? 0) > over);
    const version = this._queryVersion;
    const askedAt = performance.now();
    getDays({
      contactId: this.recordId,
      categories: this.queryCategories,
      hiddenTypes: this.queryHidden,
      historyYears: this.queryHistory,
      futureYears: this.queryFuture,
      dayKeys: keys,
      busyKeys,
      runs: this.runsOf(days, keys, busyKeys),
      ...this.summaryHints(wanted, keys, busyKeys)
    })
      .then((events) => {
        trace(
          "getPageDays returned",
          Math.round(performance.now() - askedAt),
          "ms,",
          events?.length,
          "events for",
          keys.length,
          "days"
        );
        if (version !== this._queryVersion) return;
        this.ingestDays(keys, events);
      })
      .catch((error) => {
        if (version !== this._queryVersion) return;
        this.error = this.reportError(error);
      })
      .finally(() => {
        if (version !== this._queryVersion) return;
        keys.forEach((key) => this._loadingDays.delete(key));
        // Landing part-way into a day that was still loading: land again now
        // it's drawn. Otherwise days landing above the view mustn't push it
        // down.
        const reland = this._relandOn;
        if (reland && keys.includes(reland.key)) {
          this._relandOn = null;
          this._jumpTo = reland.index;
          this._jumpFraction = reland.fraction;
        } else {
          this.holdPlace();
        }
        this.daysLoaded++;
      });
  }

  // What the summary already knows about the days being fetched, so the server
  // queries less: the counted sources it found nothing in (not asked again)
  // and, for busy days, how many each has (their grouped rows are built from
  // those, not counted again). Without the summary's source lists, none.
  summaryHints(wanted, keys, busyKeys) {
    const counted = this.summary?.counted;
    if (!counted) return {};
    const byKey = new Map(wanted.map((d) => [d.key, d]));
    const present = new Set();
    const busyCounts = [];
    let countsKnown = true;
    for (const key of keys) {
      const day = byKey.get(key);
      if (!Array.isArray(day?.src)) return {};
      const busy = busyKeys?.includes(key);
      if (busy && !Array.isArray(day.n)) countsKnown = false;
      for (let j = 0; j < day.src.length; j++) {
        present.add(day.src[j]);
        if (busy && countsKnown) busyCounts.push({ key, source: counted[day.src[j]], count: day.n[j] });
      }
    }
    return {
      emptySources: this.emptySourcesOf(counted, present),
      busyCounts: busyKeys?.length && countsKnown ? busyCounts : null
    };
  }
  // The days asked for that follow one another in the summary (it lists every
  // day with items, so none lies between them), each run as its keys joined
  // by commas: the server reads a run as one span of dates, not a range for
  // each day, which its database does many times faster. A busy day (counted,
  // not read) ends a run, so its items are never pulled in with the others.
  runsOf(days, keys, busyKeys) {
    const position = new Map();
    days.filter((d) => !d.placeholder).forEach((d, i) => position.set(d.key, i));
    const asked = keys.filter((key) => position.has(key)).sort((a, b) => position.get(a) - position.get(b));
    const busy = new Set(busyKeys ?? []);
    const runs = [];
    let run = [];
    let last = -2;
    for (const key of asked) {
      const at = position.get(key);
      if (busy.has(key) || at !== last + 1) {
        if (run.length) runs.push(run.join(","));
        run = [];
      }
      if (!busy.has(key)) run.push(key);
      last = busy.has(key) ? -2 : at;
    }
    if (run.length) runs.push(run.join(","));
    return runs;
  }
  emptySourcesOf(counted, present) {
    return counted.filter((_, index) => !present.has(index));
  }

  // Days' events, ready to draw: parsed, formatted and sorted (newest first)
  // once, here, not on every render, and kept by day. A day with none is kept
  // too (empty), so it isn't asked for again.
  ingestDays(keys, events) {
    // A week's or month's items say their day and time ("Tue 13, 09:00 AM"); a
    // day's, just the time.
    const grouped = this.unit !== "day";
    const timeFormat = grouped ? DAY_SHORT_TIME_FORMAT : TIME_FORMAT;
    const byDay = new Map(keys.map((key) => [key, []]));
    for (const e of events ?? []) {
      const at = new Date(e.occurredAt);
      // An all-day event has no time to show.
      byDay.get(e.dayKey)?.push({
        ...e,
        at: at.getTime(),
        timeText: e.allDay ? (grouped ? DAY_SHORT_FORMAT.format(at) : LABELS.allDay) : timeFormat.format(at)
      });
    }
    byDay.forEach((list) => list.sort((a, b) => b.at - a.at));
    byDay.forEach((list, key) => this._dayCache.set(key, list));
    this.trimDayCache();
    this.daysLoaded++;
  }

  // Keep the fetched days bounded: scrolling through years of history
  // shouldn't hold all of it. The days farthest from the view go first; they
  // load again (from the browser's cache of the call) if scrolled back to.
  trimDayCache() {
    const excess = this._dayCache.size - MAX_CACHED_DAYS;
    if (excess <= 0) return;
    const index = new Map(this.orderedDays.map((d, i) => [d.key, i]));
    const centre = this.horizontal ? (this.renderFrom + this.renderTo) / 2 : this.windowFrom + this.visibleDays / 2;
    const far = [...this._dayCache.keys()].sort(
      (a, b) => Math.abs((index.get(b) ?? 0) - centre) - Math.abs((index.get(a) ?? 0) - centre)
    );
    far.slice(0, excess).forEach((key) => this._dayCache.delete(key));
  }

  // ---- view model -----------------------------------------------------------

  get isLoading() {
    return !this.loaded;
  }
  // The user's text direction: rtl for Arabic, Hebrew, Farsi, Urdu.
  get textDir() {
    return DIR === "rtl" ? "rtl" : "ltr";
  }
  get horizontal() {
    // A phone is a column, whatever the Layout property says.
    if (isPhone()) return false;
    return this.layout === "Horizontal" || (this.layout !== "Vertical" && this.isWide);
  }
  get cardClass() {
    const fit = this.fitDensity ? ` card_fit card_fit-${this.fitDensity}` : "";
    return `card${this.horizontal ? " card_horizontal" : ""}${this.narrow ? " card_narrow" : ""}${isPhone() ? " card_phone" : ""}${fit}${this.slds1 ? " card_slds1" : ""}`;
  }

  // ---- fit mode: few days, filling the track ---------------------------------

  // "rows" when the days fit, else null.
  fitDensity = null;

  // After a render, horizontal only (the vertical list is as tall as its
  // days instead): whether every active day fits across, at least 15rem a
  // column.
  measureFit(track) {
    const days = this.allDays.length;
    const room = track?.clientWidth;
    let fits = false;
    if (this.horizontal && room && days >= 1 && days <= FIT_MAX_DAYS) {
      const rem = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16;
      fits = room >= days * FIT_MIN_REM * rem;
    }
    const density = fits ? "rows" : null;
    if (density !== this.fitDensity) this.fitDensity = density;
  }
  // The minimap is the horizontal scroller when it's shown; without it the
  // browser's own scrollbar stays.
  get trackClass() {
    if (!this.horizontal) {
      const scrub = this.scrubber ? ` track_scrub${this.engaged ? " track_engaged" : ""}` : "";
      return `track track_bounded${scrub}`;
    }
    return `track${this.minimap ? " track_minimap" : ""}`;
  }
  // The track and, in the vertical layout, the scrub tab over its edge.
  get frameClass() {
    if (!this.scrubber) return "frame";
    return this.engaged ? "frame frame_scrub frame_engaged" : "frame frame_scrub";
  }
  // Vertical: the list's height in pixels (Vertical Height, within limits).
  // Whether the days overflow the track (taller than the list, or wider
  // than the columns' track): the overview shows only then. Measured after
  // each render.
  overflowing = false;

  measureOverflow() {
    const track = this.template.querySelector(this.horizontal ? ".frame > .track" : ".track_bounded");
    let over = false;
    if (track) {
      over = this.horizontal
        ? track.scrollWidth > track.clientWidth + 1
        : track.scrollHeight > track.clientHeight + 1 || this.hasMore || this.hasEarlier;
    }
    if (over !== this.overflowing) this.overflowing = over;
    this.measureFit(track);
  }

  get listHeight() {
    if (isPhone()) {
      // What the screen has left under the header, so the card is one
      // screen tall wherever it was put.
      const fit = (this.viewportHeight || window.innerHeight) - this.headerHeight;
      return Math.min(1600, Math.max(240, Math.round(fit)));
    }
    return Math.min(1600, Math.max(320, Number(this.verticalHeight) || 560));
  }
  // The phone's header is its own (see the template); a phone has no room for
  // the full set of buttons.
  get phone() {
    return isPhone();
  }
  get notPhone() {
    return !isPhone();
  }
  get showLiteButton() {
    return this.hasEvents && !isPhone();
  }
  get showExpandButton() {
    return this.canExpand && !isPhone();
  }
  get trackStyle() {
    if (!this.horizontal) return `max-height: ${this.listHeight}px`;
    const px = Math.min(1000, Math.max(240, Number(this.horizontalHeight) || 260));
    return `height: ${px}px`;
  }
  // Loading placeholders, shaped like the loaded card.
  get skeletonRows() {
    return this.horizontal ? [1, 2, 3, 4, 5, 6] : [1, 2, 3, 4];
  }
  // The drag preview: two identical groups of skeleton days, so sliding one
  // group's height loops seamlessly.
  get previewGroups() {
    return [1, 2];
  }
  get skeletonPreviewDays() {
    return [1, 2, 3, 4, 5, 6];
  }
  get skeletonPreviewRows() {
    return [1, 2, 3];
  }
  // Vertical: enough days of rows to fill the tallest Vertical Height; the
  // track crops the rest.
  get skeletonDays() {
    return [1, 2, 3, 4, 5, 6, 7, 8];
  }
  get skeletonColumns() {
    return [1, 2, 3, 4, 5, 6];
  }
  get skeletonColumnRows() {
    return [1, 2, 3];
  }

  // Vertical lists the newest first (at the top), as Salesforce's activity
  // timeline does; horizontal runs earliest to latest, left to right, as a
  // calendar does.
  get newestFirst() {
    return !this.horizontal;
  }

  // Every day after the filters, from the summary, in the layout's order, with
  // its labels. Built once per summary and order (and minute, so "Today"
  // moves on at midnight): it's read many times a render and per scroll
  // frame, and dates in the user's locale are costly to format.
  get orderedDays() {
    const memo = `${this.daysVersion}|${this.newestFirst}|${Math.floor(Date.now() / 60000)}`;
    if (this._daysMemo?.key === memo) return this._daysMemo.value;
    const source = this.withPlaceholders(this.summary?.days ?? []);
    // Days in more than one year: every column header says its year.
    const years = new Set(source.map((d) => d.key.slice(0, 4)));
    const allYears = years.size > 1;
    const days = source.map((d) => {
      const time = keyTime(d.key);
      const label = periodLabel(time, this.unit);
      return { ...d, time, label, ...this.dateParts({ key: time, label }, allYears) };
    });
    if (!this.newestFirst) days.reverse();
    this._daysMemo = { key: memo, value: days };
    this._dayLabels = days.map((d) => d.label);
    this._dayTimes = days.map((d) => d.time);
    return days;
  }
  // The current day, week or month, when it has nothing: a placeholder in
  // its place among the days (newest first), so the timeline can open on it
  // and says so. Only among other days: with none, the empty state shows.
  // With the window's ends too, as days of their own (where History starts,
  // and where Future ends): the days are topped and tailed, in the time
  // range, sized like any other. A real day on an end is that end.
  withPlaceholders(days) {
    if (!days.length) return days;
    const keys = new Set(days.map((d) => d.key));
    const slots = [];
    const add = (key, kind, text) => {
      if (keys.has(key)) return;
      keys.add(key);
      slots.push({ key, count: 0, orders: 0, placeholder: kind, placeholderText: text });
    };
    const ends = windowEnds(this.queryHistory, this.queryFuture, this.unit);
    if (ends.end) add(ends.end.key, "end");
    add(currentPeriodKey(this.unit), "now", this.nothingNowText);
    add(ends.start.key, "start");
    if (!slots.length) return days;
    // Newest first, as the summary lists them.
    const all = [...days, ...slots].sort((a, b) => (a.key < b.key ? 1 : a.key > b.key ? -1 : 0));
    // An end says what it stands for: nothing between it and the nearest
    // day ("Nothing between 18 Dec 2026 and 22 Oct 2036").
    all.forEach((d, i) => {
      if (d.placeholder === "end") {
        d.placeholderText = format(LABELS.between, this.nearText(all[i + 1]), ends.end.date);
      } else if (d.placeholder === "start") {
        d.placeholderText = format(LABELS.between, ends.start.date, this.nearText(all[i - 1]));
      }
    });
    return all;
  }
  // The day next to an end, in words: its date, its week or month, or today.
  nearText(day) {
    if (!day) return LABELS.nearNow;
    if (day.placeholder === "now")
      return { week: LABELS.nearThisWeek, month: LABELS.nearThisMonth }[this.unit] ?? LABELS.nearToday;
    return periodDate(keyTime(day.key), this.unit);
  }
  // "Nothing today", "Nothing this week", "Nothing this month".
  get nothingNowText() {
    return { week: LABELS.nothingWeek, month: LABELS.nothingMonth }[this.unit] ?? LABELS.nothingToday;
  }

  // The events fetched so far.
  get loadedEvents() {
    // Read so the view re-renders as days arrive; flattened once per arrival,
    // not on every render and click.
    if (this._loadedFor !== this.daysLoaded) {
      this._loadedFor = this.daysLoaded;
      this._loaded = [...this._dayCache.values()].flat();
    }
    return this._loaded;
  }
  // A day's events are kept newest first; oldest first is the reverse.
  sortEvents(events) {
    return this.newestFirst ? events : [...events].reverse();
  }

  // The days drawn: the first pages of days in the vertical layout; every day
  // in the horizontal one, with events only for columns near the view. A day
  // still being fetched shows placeholder rows.
  get groups() {
    // Read so the view re-renders as days arrive.
    dependOn(this.daysLoaded);
    const all = this.orderedDays;
    const offset = this.horizontal ? 0 : this.windowFrom;
    const days = this.horizontal ? all : all.slice(offset, offset + this.visibleDays);
    const kept = new Set();
    // Today's key once, not once per day (it formats a date each time it is read).
    const todayKey = this.currentKey;
    const groups = days.map((day, position) => {
      const index = offset + position;
      const drawn = !this.horizontal || (index >= this.renderFrom && index <= this.renderTo);
      const cached = day.placeholder ? [] : (this._dayCache.get(day.key) ?? this._staleCache?.get(day.key));
      if (drawn && cached?.length) kept.add(day.key);
      return {
        key: day.time,
        label: day.label,
        index,
        id: `day-${day.key}`,
        meta: day.placeholder ? "" : this.metaFor(day),
        loading: drawn && !cached,
        placeholder: Boolean(day.placeholder),
        placeholderText: day.placeholderText,
        // Nothing to see: today with nothing, or the window's ends.
        // Horizontal columns outside the drawn window show a CSS skeleton.
        dayClass: `${drawn ? "day" : "day day_shell"}${day.key === todayKey ? " day_today" : ""}`,
        // Horizontal day headers read the date as a figure: 16 / FRI / Oct.
        dayNumber: day.dayNumber,
        dayWord: day.dayWord,
        monthWord: day.monthWord,
        dayWordClass: day.dayWordClass,
        events: drawn && cached ? this.dayEvents(day.key, cached) : []
      };
    });
    // Only the days drawn keep their built items.
    for (const key of [...this._builtDays.keys()]) if (!kept.has(key)) this._builtDays.delete(key);
    return groups;
  }

  // A day's items, built for the template, kept per day: opening or closing
  // one item rebuilds its own day only, not every day drawn. Rebuilt when the
  // day's events, its open or deleting items, or the layout change. (A Map,
  // changed in place: it isn't reactive, so keeping it doesn't re-render.)
  _builtDays = new Map();
  dayEvents(key, cached) {
    const open = cached
      .filter((e) => this.expanded.has(e.id))
      .map((e) => e.id)
      .join(",");
    const busy = cached
      .filter((e) => this.deleting.has(e.id))
      .map((e) => e.id)
      .join(",");
    const built = this._builtDays.get(key);
    if (
      built &&
      built.events === cached &&
      built.open === open &&
      built.busy === busy &&
      built.horizontal === this.horizontal
    ) {
      return built.value;
    }
    const value = this.sortEvents(cached).map((e, i, list) => {
      const next = list[i + 1];
      const prev = list[i - 1];
      // Each row draws the rail above and below its node: none above the
      // day's first event or below its last.
      // Vertical, the rail runs down from each day's first icon through its
      // last item, never up into the date; horizontal, between items only.
      return this.decorate(e, {
        first: !prev,
        last: this.horizontal && !next,
        above: prev
      });
    });
    this._builtDays.set(key, { events: cached, open, busy, horizontal: this.horizontal, value });
    return value;
  }
  // "4 items", from the summary.
  metaFor(day) {
    return day.count === 1 ? LABELS.itemsOne : format(LABELS.itemsMany, formatCount(day.count));
  }
  // The events currently drawn (for Expand all).
  // Read from the days drawn only (their items are kept per day), not by
  // building every day's group, which every read of it would do again.
  get shownEvents() {
    const days = this.orderedDays;
    const drawn = this.horizontal
      ? days.slice(this.renderFrom, this.renderTo + 1)
      : days.slice(this.windowFrom, this.windowFrom + this.visibleDays);
    // Read so the view re-renders as days arrive.
    dependOn(this.daysLoaded);
    const out = [];
    for (const day of drawn) {
      if (day.placeholder) continue;
      const cached = this._dayCache.get(day.key) ?? this._staleCache?.get(day.key);
      if (!cached) continue;
      for (const e of this.dayEvents(day.key, cached)) if (e.expandable) out.push(e);
    }
    return out;
  }
  // A day loading: three rows, as the first skeleton's columns and the
  // shells' rows, so nothing changes shape as the days arrive.
  get skeletonDayRows() {
    return [1, 2, 3];
  }

  // What the summary counted per: "day", or "week" or "month" on windows too
  // long to count by day. Each of its days is then a week or month.
  get unit() {
    return this.summary?.unit ?? "day";
  }

  // `allYears`: the timeline spans years, so every header says its year,
  // this one's too (else only other years' do).
  dateParts(group, allYears = false) {
    const date = new Date(group.key);
    const sameYear = !allYears && date.getFullYear() === new Date().getFullYear();
    // Horizontal headers for a week (8 / WEEK OF / Oct) or a month (Oct / 2026).
    if (this.unit === "week") {
      return {
        dayNumber: date.getDate(),
        dayWord: LABELS.weekOfWord,
        monthWord: sameYear ? MONTH_SHORT.format(date) : MONTH_YEAR.format(date),
        dayWordClass: "date-word"
      };
    }
    if (this.unit === "month") {
      return {
        dayNumber: MONTH_SHORT.format(date),
        dayWord: String(date.getFullYear()),
        monthWord: "",
        dayWordClass: "date-word"
      };
    }
    const near = relativeDay(group.key);
    const recent = near === 0 || near === -1;
    return {
      dayNumber: date.getDate(),
      dayWord: recent ? dayWord(near) : WEEKDAY_SHORT.format(date),
      monthWord: sameYear ? MONTH_SHORT.format(date) : MONTH_YEAR.format(date),
      dayWordClass: recent ? "date-word date-word_recent" : "date-word"
    };
  }
  decorate(event, { first, last, above }) {
    const info = typeInfo(event.type);
    if (event.grouped) return this.decorateGroup(event, info, { first, last, above });
    const open = this.expanded.has(event.id);
    // A blank title still needs words to click (Salesforce sources send the
    // blank field's label, "[Subject]"; others may send nothing).
    const title = event.title?.trim() ? event.title : LABELS.noTitle;
    const classes = ["event", `event_${info.tone}`];
    if (last) classes.push("event_last");
    if (open) classes.push("event_open");
    // Being deleted: dimmed, its menu a spinner, until it goes.
    const deleting = this.deleting.has(event.id);
    if (deleting) classes.push("event_deleting");
    const email = EMAIL_STATES[event.emailState];
    return {
      ...event,
      title,
      // Enhanced Email: opened (when, in the tooltip), unopened or bounced.
      emailIcon: email?.icon,
      emailIconClass: email ? `email-state email-state_${event.emailState}` : "",
      // The menu at the end of a Salesforce record's row: Edit and Delete as
      // the user's rights allow (the server says), none without either.
      menuRecordId: event.recordId && !event.grouped && (event.canEdit || event.canDelete) ? event.recordId : null,
      deleting,
      canEdit: event.canEdit === true,
      canDelete: event.canDelete === true,
      // Highlights from the source's rules: an icon (or a dot) and what it says.
      flags: (event.flags ?? []).map((f, i) => ({
        key: `${event.id}-flag${i}`,
        isDot: !f.icon || f.icon === "dot",
        icon: f.icon,
        text: f.text,
        style: f.colour ? `--flag: ${f.colour}` : ""
      })),
      emailStateText: email
        ? event.emailOpenedAt
          ? `${email.label} ${DATE_TIME_FORMAT.format(new Date(event.emailOpenedAt))}`
          : email.label
        : "",
      expandable: true,
      // The source's configured icon and colour, else the type's defaults.
      icon: event.icon || info.icon,
      typeLabel: event.typeLabel || info.label,
      nodeStyle: this.nodeStyleFor(event),
      itemStyle: this.itemStyleFor(event),
      // Time only: the day's sticky header carries the date.
      timeText: event.timeText,
      isoTime: event.occurredAt,
      // How long ago, when the source asks for it.
      open,
      ariaExpanded: String(open),
      detailId: `detail-${event.id}`,
      itemClass: classes.join(" "),
      nodeClass: `node node_${info.tone}`,
      railTopClass: `rail${first ? " rail_none" : ""}`,
      // The line between two items is the upper one's colour, top to bottom.
      railTopStyle: above ? `background: ${this.toneOf(above)}` : "",
      // An open event is its own surface: the rail pauses under its node.
      railBottomClass: `rail${last || open ? " rail_none" : ""}`,
      chevronClass: open ? "chevron chevron_open" : "chevron",
      hasDetails: event.details?.length > 0,
      // A fixed name; aria-expanded says whether it's open.
      toggleLabel: format(LABELS.detailsToggle, title),
      toggleTitle: open ? LABELS.detailsHide : LABELS.detailsShow,
      iconLabel: this.iconLabelFor(event, event.typeLabel || info.label),
      // CRM events link to their record; Data 360 events don't.
      recordUrl: event.recordId ? recordHref(event.recordId) : null
    };
  }
  // An event's colour: its source's, else its type's tone.
  toneOf(event) {
    return event.iconColour || `var(--tone-${typeInfo(event.type).tone}, var(--time-drive-rule))`;
  }

  // A configured colour paints the node and its rail.
  nodeStyleFor(event) {
    return event.iconColour ? `background: ${event.iconColour}` : "";
  }
  itemStyleFor(event) {
    return event.iconColour ? `--tone: ${event.iconColour}` : "";
  }
  // A busy day's row for many events of one type: a count and time span;
  // its title links to the items (View all) where they can be listed.
  decorateGroup(event, info, { first, last, above }) {
    const open = this.expanded.has(event.id);
    const from = new Date(event.firstAt ?? event.occurredAt);
    const to = new Date(event.occurredAt);
    const count = event.groupCount;
    const label = event.typeLabel || info.many;
    const classes = ["event", `event_${info.tone}`, "event_group"];
    if (last) classes.push("event_last");
    if (open) classes.push("event_open");
    return {
      ...event,
      title: `${formatCount(count)} ${label}`,
      icon: event.icon || info.icon,
      typeLabel: label,
      nodeStyle: this.nodeStyleFor(event),
      itemStyle: this.itemStyleFor(event),
      timeText: event.timeText,
      isoTime: event.occurredAt,
      // Expands to the span it stands for: "82 records grouped", from and to.
      expandable: true,
      open,
      ariaExpanded: String(open),
      detailId: `detail-${event.id}`,
      toggleLabel: format(LABELS.detailsToggle, `${formatCount(count)} ${label}`),
      toggleTitle: open ? LABELS.detailsHide : LABELS.detailsShow,
      iconLabel: "",
      chevronClass: open ? "chevron chevron_open" : "chevron",
      itemClass: classes.join(" "),
      // A stack of discs behind the icon: one row standing for many.
      nodeClass: `node node_${info.tone} node_stack`,
      railTopClass: `rail${first ? " rail_none" : ""}`,
      railTopStyle: above ? `background: ${this.toneOf(above)}` : "",
      railBottomClass: `rail${last || open ? " rail_none" : ""}`,
      recordUrl: null,
      groupUrl: event.pageable ? this.groupUrl(event, label) : null,
      groupLinkLabel: format(LABELS.groupViewAll, formatCount(count), label),
      groupSummary: count === 1 ? LABELS.groupSummaryOne : format(LABELS.groupSummaryMany, formatCount(count)),
      details: [
        { label: LABELS.groupFrom, value: DATE_TIME_FORMAT.format(from) },
        { label: LABELS.groupTo, value: DATE_TIME_FORMAT.format(to) }
      ],
      hasDetails: true
    };
  }

  // Every day after the filters (the track shows a page of them).
  get allDays() {
    return this.orderedDays;
  }
  // The seek bar's overview under the horizontal layout: a heat cell per
  // active day (or week, month...), quiet stretches compressed, labelled by
  // month or year. Built once per summary, order and width.
  get minimap() {
    if (!this.horizontal || !this.overflowing) return null;
    const days = this.allDays;
    // Every column fits, or too little to plot: the columns say it all.
    if (days.length < MINIMAP_MIN_DAYS) return null;
    const memo = `${this.daysVersion}|${this.newestFirst}|${this.cardWidth}`;
    if (this._minimapMemo?.key === memo) return this._minimapMemo.value;
    // Cells at least 6px wide (more on long histories), labels 56px apart, on
    // the bar's width.
    const strip = Math.max(200, this.cardWidth - 64);
    const cellSize = minCellSize(days, 6);
    const map = buildMinimap(
      days.map((d) => ({ key: d.time, label: d.label, count: d.count, orders: d.orders })),
      { maxCells: Math.floor(strip / cellSize), minLabelGap: (56 / strip) * 100, minUnit: this.unit }
    );
    // One cell says nothing about where the activity is.
    if (map.cells.length < 2) return null;
    const value = {
      count: days.length,
      unit: map.unit,
      cells: map.cells.map((cell) => ({
        ...cell,
        style: `left: ${cell.left}%; width: ${cell.width}%`,
        className: `heat heat_${cell.level}${cell.current ? " heat_today" : ""}`
      })),
      // Today, marked on the bar even when it has no items.
      now: map.now
        ? { style: `left: ${map.now.at}%`, className: `seek-now${map.now.onCell ? " seek-now_cell" : ""}` }
        : null,
      gaps: map.gaps.map((gap) => ({ ...gap, style: `left: ${gap.left}%; width: ${gap.width}%` })),
      months: map.months.map((m) => ({
        ...m,
        style: `left: ${m.left}%`,
        text: m.year ? `${m.label} ${m.year}` : m.label,
        className: m.year || /^\d{4}$/.test(m.label) ? "seek-label seek-label_year" : "seek-label"
      })),
      years: map.years.map((y) => ({ ...y, style: `left: ${y.left}%` }))
    };
    this._minimapMemo = { key: memo, value };
    return value;
  }
  // Expand all: only when the last answer showed something to open (it stays,
  // disabled, through a refresh; never flashes up for an empty timeline).
  get canExpand() {
    return this.hasEvents;
  }
  get hasEvents() {
    return (this.summary?.total ?? 0) > 0;
  }
  get hasMore() {
    return !this.horizontal && this.allDays.length > this.windowFrom + this.visibleDays;
  }
  // Vertical, after a jump: the days before the window, above it.
  get hasEarlier() {
    return !this.horizontal && this.windowFrom > 0;
  }
  // The vertical layout's scrub overlay: the minimap's heat cells, stacked
  // down the track's right edge in the list's order, with years or months.
  // Built once per summary, order and height (the template reads it often).
  get scrubber() {
    if (this.horizontal || !this.overflowing) return null;
    const days = this.allDays;
    // The whole list fits, or too little to plot: nothing to jump to.
    if (days.length < MINIMAP_MIN_DAYS) return null;
    const memo = `${this.daysVersion}|${this.newestFirst}|${this.listHeight}`;
    if (this._scrubberMemo?.key === memo) return this._scrubberMemo.value;
    // Cells at least 5px tall (more on long histories), labels 20px apart, on
    // the list's height.
    const strip = Math.max(200, this.listHeight - 12);
    const map = buildMinimap(
      days.map((d) => ({ key: d.time, label: d.label, count: d.count, orders: d.orders })),
      { maxCells: Math.floor(strip / minCellSize(days, 5)), minLabelGap: (20 / strip) * 100, minUnit: this.unit }
    );
    // One cell says nothing about where the activity is.
    if (map.cells.length < 2) return null;
    const value = {
      count: days.length,
      unit: map.unit,
      cells: map.cells.map((cell) => ({
        ...cell,
        style: `top: ${cell.left}%; height: ${cell.width}%`,
        className: `heat heat_${cell.level}${cell.current ? " heat_today" : ""}`
      })),
      now: map.now
        ? { style: `top: ${map.now.at}%`, className: `scrub-now${map.now.onCell ? " scrub-now_cell" : ""}` }
        : null,
      gaps: map.gaps.map((gap) => ({ ...gap, style: `top: ${gap.left}%; height: ${gap.width}%` })),
      // A label where each month (or year) starts; years stand out.
      months: map.months.map((m) => ({
        ...m,
        style: `top: ${m.left}%`,
        text: m.year ? `${m.label} ${m.year}` : m.label,
        className: m.year || /^\d{4}$/.test(m.label) ? "scrub-label scrub-label_year" : "scrub-label"
      })),
      years: map.years.map((y) => ({ ...y, style: `top: ${y.left}%` }))
    };
    this._scrubberMemo = { key: memo, value };
    return value;
  }

  get countText() {
    const n = this.summary?.total ?? 0;
    return n === 1 ? LABELS.itemsOne : format(LABELS.itemsMany, formatCount(n));
  }

  // The illustrations, one per kind of state: no results, setup and error.
  // lightning-illustration draws them in the page's SLDS, light or dark.
  art(state) {
    return illustrationName(state);
  }

  // An empty slot across (the start, the end, today): the "all done" drawing.
  get nothingArtName() {
    return illustrationName("nothing");
  }
  // Setup for what an admin can fix (a missing object or field, a permission
  // set not assigned); error for the rest.
  artFor(kind) {
    return this.art(illustrationState(kind));
  }
  get errorArtName() {
    return this.artFor(this.error?.kind);
  }
  get problemArtName() {
    return this.artFor(this.problemNotice?.kind);
  }
  // What the user sees of an error: its kind in plain words and a likely
  // cause. The technical summary (codes and messages, never a stack trace)
  // goes to the console for whoever is debugging.
  reportError(error) {
    const described = describeError(error);
    console.warn(`Time Drive: ${described.kind} error.`, described.detail);
    return described;
  }
  get emptyHeading() {
    if (this.noSources) return LABELS.emptySetupHeading;
    return LABELS.emptyNoMatch;
  }
  // The record's page has no active sources: it says so, and who can fix it.
  get noSources() {
    return this.summary?.noSources === true;
  }
  // The filter panel with no types to offer.
  get filterNoneText() {
    return this.noSources ? this.noSourcesText : LABELS.filterNone;
  }
  get noSourcesText() {
    return LABELS.noSources;
  }
  // A setup problem looks unlike no data or a failure: a gear on the page.
  get emptyIllustrationName() {
    if (this.noSources) return this.art("setup");
    return this.art(this.isFilteredOut ? "filtered" : "noresults");
  }
  get emptyBody() {
    if (this.noSources) return this.noSourcesText;
    if (this.isFilteredOut) return this.emptyText;
    // Each date stays on one line when the message wraps.
    const keep = (date) => date.replace(/ /g, "\u00a0");
    const { from, to } = windowDates(this.queryHistory, this.queryFuture);
    return format(LABELS.emptyWindow, keep(from), keep(to));
  }
  // The empty and error states keep the columns' height when horizontal;
  // vertical, they're as tall as they need.
  get emptyStyle() {
    return this.horizontal ? this.trackStyle : "";
  }
  // The filters hide everything shown: a source they hide isn't counted, so
  // the page can't tell that from a record with no history; it says the filters.
  get isFilteredOut() {
    return (this.view !== "All" || this.hiddenTypes.size > 0) && (this.summary?.total ?? 0) === 0;
  }
  get emptyText() {
    return this.isFilteredOut ? LABELS.emptyNothing : LABELS.emptyCustomer;
  }
  get warnings() {
    return (this.summary?.warnings ?? []).map((text, i) => ({ key: `w${i}`, text }));
  }
  // Sources that couldn't be read: one notice above what did load, or the
  // whole canvas when nothing could be.
  get problemNotice() {
    return describeProblems(this.summary?.problems, LIST_FORMAT);
  }
  get allFailed() {
    return Boolean(this.problemNotice) && !this.isFilteredOut;
  }
  get showProblemNotice() {
    return Boolean(this.problemNotice) && this.hasEvents;
  }
  get hasWarnings() {
    return this.warnings.length > 0;
  }

  // Header and toolbar.
  // The views as Time Drive Setup names them (Time Drive View), else
  // the built-in ones until they arrive.
  views;
  @wire(getViews)
  wiredViews({ data }) {
    if (!data?.length) return;
    this.views = data;
    // A default lens the org doesn't offer (switched off since the page was
    // built) opens on All.
    if (!data.some((v) => v.value === this.view)) {
      this.view = "All";
      this.applyQueryChange();
    }
  }
  get viewList() {
    return this.views ?? VIEWS;
  }
  viewNamed(value) {
    return this.viewList.find((v) => v.value === value) ?? this.viewList[0];
  }
  get viewLabel() {
    return this.viewNamed(this.view).label;
  }
  get viewOptions() {
    return this.viewList.map((v) => ({ ...v, ariaChecked: String(v.value === this.view) }));
  }
  get typeOptions() {
    // Every type in the view (the server lists them, with configured labels),
    // known types in their usual order first, then any others.
    const types = new Map((this.summary?.types ?? []).map((t) => [t.type, t]));
    for (const type of this.hiddenTypes) if (!types.has(type)) types.set(type, { type });
    const known = Object.keys(EVENT_TYPES);
    const ordered = [...types.keys()].sort((a, b) => {
      const ia = known.indexOf(a);
      const ib = known.indexOf(b);
      return (ia === -1 ? known.length : ia) - (ib === -1 ? known.length : ib) || a.localeCompare(b);
    });
    return ordered.map((type) => {
      const label = types.get(type).label || EVENT_TYPES[type]?.label || type;
      return {
        value: type,
        label,
        name: label,
        checked: !this.hiddenTypes.has(type)
      };
    });
  }

  // Filters button and panel.
  get filterCount() {
    return this.hiddenTypes.size ? 1 : 0;
  }
  get hasFilters() {
    return this.filterCount > 0;
  }
  get filterLabel() {
    return this.filterCount ? format(LABELS.filtersActive, this.filterCount) : LABELS.filters;
  }
  get filtersPressed() {
    return String(this.hasFilters);
  }
  get filterButtonClass() {
    return `slds-button slds-button_icon slds-button_icon-border-filled filter-button${
      this.hasFilters ? " filter-button_on" : ""
    }`;
  }
  // The event's type, said before its title, unless the title already
  // starts with it ("Order placed" after "Orders placed" is noise).
  iconLabelFor(event, label) {
    const stem = (text) => (text ?? "").trim().split(/\s+/)[0]?.toLowerCase().replace(/s$/, "");
    return label && stem(event.title) === stem(label) ? "" : label;
  }
  // "Added Fri 16 Oct to Thu 10 Oct", "Showing Tue 21 Jul".
  announceDays(first, last, verb) {
    const label = (i) => this.allDays[i]?.label;
    if (!label(first)) return;
    const one = first === last || !label(last);
    const added = verb === "Added";
    const text = added
      ? one
        ? format(LABELS.announceAdded, label(first))
        : format(LABELS.announceAddedRange, label(first), label(last))
      : one
        ? format(LABELS.announceShowing, label(first))
        : format(LABELS.announceShowingRange, label(first), label(last));
    this.announce(text);
  }
  // A polite announcement for screen readers (where the timeline moved to).
  announce(text) {
    const announcer = this.template.querySelector(".announcer");
    if (!announcer || !text) return;
    // Cleared first, so the same words are said again.
    announcer.textContent = "";
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    requestAnimationFrame(() => {
      announcer.textContent = text;
    });
  }
  get viewMenuExpanded() {
    return String(this.viewMenuOpen);
  }
  get typesText() {
    const hidden = this.typeOptions.filter((o) => !o.checked).length;
    return hidden === 0
      ? LABELS.typesAll
      : format(LABELS.typesSome, this.typeOptions.length - hidden, this.typeOptions.length);
  }
  // The App Builder's History and Future, as dates.
  get summaryWhen() {
    return windowRange(this.queryHistory, this.queryFuture, { short: this.cardWidth < WIDE_FROM });
  }
  // The types and the count after it (" · 1 of 6 types · 100 items"): a
  // skeleton while a new filter's counts are on their way.
  get summaryRest() {
    // Narrow too: "All types" says no filter is on.
    const parts = [this.typesText, this.countText];
    return parts
      .filter(Boolean)
      .map((p) => ` · ${p}`)
      .join("");
  }
  get allExpanded() {
    const shown = this.shownEvents;
    return shown.length > 0 && shown.every((e) => this.expanded.has(e.id));
  }
  get expandLabel() {
    return this.allExpanded ? LABELS.collapseAll : LABELS.expandAll;
  }
  // Expand all until every item is open, then Collapse all.
  get expandIcon() {
    return this.allExpanded ? "utility:collapse_all" : "utility:expand_all";
  }

  // ---- handlers -------------------------------------------------------------

  // The view menu: a menu of radio items, keyboard as SLDS menus (arrows,
  // Home and End move; Escape and Tab close).
  markViewPress() {
    this._viewPress = true;
  }
  toggleViewMenu() {
    if (this.viewMenuOpen) this.closeViewMenu(true);
    else this.openViewMenu("checked");
  }
  openViewMenu(focus) {
    this.filtersPanel?.close(false);
    this.viewMenuOpen = true;
    this._focusView = focus;
  }
  closeViewMenu(returnFocus) {
    this.viewMenuOpen = false;
    if (returnFocus) {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      requestAnimationFrame(() => this.template.querySelector(".view-button")?.focus());
    }
  }
  handleViewButtonKey(event) {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      this.openViewMenu(event.key === "ArrowUp" ? "last" : "checked");
    }
  }
  handleViewMenuKey(event) {
    const items = [...this.template.querySelectorAll(".view-option")];
    const at = items.indexOf(this.template.activeElement);
    const moves = {
      ArrowDown: (at + 1) % items.length,
      ArrowUp: (at - 1 + items.length) % items.length,
      Home: 0,
      End: items.length - 1
    };
    if (event.key in moves) {
      event.preventDefault();
      items[moves[event.key]]?.focus();
    } else if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      this.closeViewMenu(true);
    } else if (event.key === "Tab") {
      this.closeViewMenu(false);
    }
  }
  // Focus the item asked for once the menu is drawn.
  focusViewMenu() {
    const focus = this._focusView;
    if (!focus || !this.viewMenuOpen) return;
    this._focusView = null;
    const items = [...this.template.querySelectorAll(".view-option")];
    const item =
      focus === "last" ? items.at(-1) : (items.find((i) => i.getAttribute("aria-checked") === "true") ?? items[0]);
    item?.focus();
  }
  handleViewPick(event) {
    const value = event.currentTarget.dataset.value;
    this.closeViewMenu(true);
    if (value === this.view) return;
    this.view = value;
    this._picked = true;
    this.keepPreference(value, null);
    this.hiddenTypes = new Set();
    this.applyQueryChange();
  }
  get filtersPanel() {
    return this.template.querySelector("c-time-drive-filters");
  }
  // The Filters button: the panel opens and closes itself (see
  // timeDriveFilters), so the timeline doesn't re-render for it.
  markFilterPress() {
    this.filtersPanel?.notePress();
  }
  toggleFilters() {
    this.filtersPanel?.toggle();
  }
  handleFiltersOpenChange(event) {
    const { open, returnFocus } = event.detail;
    const button = this.template.querySelector(".filter-button");
    button?.setAttribute("aria-expanded", String(open));
    if (open && this.viewMenuOpen) this.viewMenuOpen = false;
    if (!open && returnFocus) {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      requestAnimationFrame(() => button?.focus());
    }
  }
  // Apply: the types to show, from the panel.
  // Apply: the types to show, from the panel.
  handleFiltersApply(event) {
    const shown = new Set(event.detail.shown);
    this.hiddenTypes = new Set(this.typeOptions.map((o) => o.value).filter((type) => !shown.has(type)));
    this.applyQueryChange();
  }
  // The Refresh button: the loading skeleton shows while it works, at the
  // height the timeline already has (so the card doesn't jump), then the
  // fresh days. After an error, the timeline loads again from the start.
  handleRefresh() {
    if (this.refreshing) {
      this._refreshAgain = true;
      return;
    }
    const failed = Boolean(this.error);
    // Across, the skeleton replaces the track (and its scroll): remember the
    // day at the view's left edge, and how far into it, to come back to.
    this._restoreAcross = failed ? null : this.placeAcross();
    this.error = undefined;
    this.holdHeight(!failed);
    this.loaded = false;
    this._keepStale = !failed;
    this.refreshing = true;
    this.requestTimeline(true).finally(() => {
      this.refreshing = false;
      this.loaded = true;
      this.refreshHeight = null;
      this.refreshQueued();
    });
  }

  // A save on the page: what's on screen stays, a thin line says it's
  // updating, and the fresh summary and days replace it as they arrive (the
  // days drawn now stay until their fresh copies come). After an error, or
  // before the timeline has loaded, it's an ordinary refresh.
  refreshQuietly() {
    if (this.refreshing) {
      this._refreshAgain = true;
      return;
    }
    if (this.error || !this.loaded) {
      this.handleRefresh();
      return;
    }
    this._keepStale = true;
    this.refreshing = true;
    this.updating = true;
    this.requestTimeline(true).finally(() => {
      this.refreshing = false;
      this.updating = false;
      this.refreshQueued();
    });
  }

  // A save that came while a refresh ran: one more, quietly, so it shows.
  refreshQueued() {
    if (!this._refreshAgain) return;
    this._refreshAgain = false;
    this.refreshQuietly();
  }

  updating = false;
  // The body's content height, which the skeleton keeps (it sits inside the
  // body's padding), so the card doesn't jump. Not measured after an error:
  // the error's height isn't the timeline's.
  holdHeight(measure = true) {
    const body = measure ? this.template.querySelector(".body") : null;
    let height = null;
    if (body) {
      const style = getComputedStyle(body);
      height = body.clientHeight - parseFloat(style.paddingTop || 0) - parseFloat(style.paddingBottom || 0);
    }
    this.refreshHeight = height > 0 ? height : null;
  }
  refreshing = false;
  refreshHeight = null;
  // While refreshing, the skeleton holds the timeline's height.
  get skeletonFrameStyle() {
    return this.refreshHeight ? `height: ${this.refreshHeight}px; overflow: hidden` : "";
  }
  // The title link: navigate within Lightning; Cmd/Ctrl-click and middle-click
  // keep the browser's own new-tab behaviour through the href.
  // The open row menu: { id (the item), recordId, canEdit, canDelete, top,
  // edge (px from the viewport's end edge) }, or null.
  rowMenu = null;
  _rowMenuPress = false;
  _focusRowMenu = false;

  // ---- the phone's header menu (⋯): what the full header's buttons did ------

  headerMenu = null;

  get headerMenuItems() {
    const items = [
      { value: "refresh", label: LABELS.buttonRefresh },
      ...(this.canExpand ? [{ value: "expand", label: this.expandLabel }] : []),
      ...(this.hasEvents ? [{ value: "lite", label: this.liteLabel }] : [])
    ];
    return items.map((i) => ({ ...i, key: i.value }));
  }

  get headerMenuStyle() {
    const m = this.headerMenu;
    if (!m) return "";
    const side = this.textDir === "rtl" ? "left" : "right";
    return `top: ${m.top}px; ${side}: ${m.edge}px`;
  }

  toggleHeaderMenu(event) {
    if (this.headerMenu) {
      this.headerMenu = null;
      return;
    }
    const button = event.currentTarget;
    const rect = button.getBoundingClientRect();
    const edge = this.textDir === "rtl" ? rect.left : window.innerWidth - rect.right;
    this.rowMenu = null;
    this._focusRowMenu = true;
    this._menuTrigger = button;
    this.headerMenu = { top: Math.round(rect.bottom + 4), edge: Math.max(0, Math.round(edge)) };
  }

  pickHeaderMenu(event) {
    const value = event.currentTarget.dataset.value;
    this.headerMenu = null;
    if (value === "refresh") this.handleRefresh();
    else if (value === "expand") this.toggleAll();
    else if (value === "lite") this.toggleLite();
  }

  // A press on the menu or its button isn't "outside" it.
  markRowMenuPress() {
    this._rowMenuPress = true;
  }

  get rowMenuStyle() {
    const m = this.rowMenu;
    if (!m) return "";
    const side = this.textDir === "rtl" ? "left" : "right";
    return `top: ${m.top}px; ${side}: ${m.edge}px`;
  }

  toggleRowMenu(event) {
    const button = event.currentTarget;
    const id = button.dataset.id;
    if (this.rowMenu?.id === id) {
      this.rowMenu = null;
      return;
    }
    const item = this.loadedEvents.find((e) => e.id === id);
    if (!item) return;
    const rect = button.getBoundingClientRect();
    const edge = this.textDir === "rtl" ? rect.left : window.innerWidth - rect.right;
    this._focusRowMenu = true;
    this._menuTrigger = button;
    const recordId = button.dataset.record;
    // The object's permissions come with the item; what this record allows
    // (sharing, Modify All Data) is asked for now, once per record.
    const known = this._rights.get(recordId);
    this.rowMenu = {
      id,
      recordId,
      canEdit: known ? known.canEdit : item.canEdit === true,
      canDelete: known ? known.canDelete : item.canDelete === true,
      checking: !known,
      objectLabel: item.objectLabel,
      top: Math.round(rect.bottom + 4),
      edge: Math.max(0, Math.round(edge))
    };
    if (!known) this.checkRights(id, recordId);
  }

  // Rights found for records this visit: { canEdit, canDelete }, by record Id.
  _rights = new Map();

  checkRights(id, recordId) {
    const settle = (canEdit, canDelete) => {
      if (this.rowMenu?.id === id) this.rowMenu = { ...this.rowMenu, canEdit, canDelete, checking: false };
    };
    getRights({ recordId })
      .then((rights) => {
        this._rights.set(recordId, { canEdit: rights.canEdit === true, canDelete: rights.canDelete === true });
        settle(rights.canEdit === true, rights.canDelete === true);
      })
      // Unknown: the object's permissions stand, and Salesforce has the last word.
      .catch(() => settle(this.rowMenu?.canEdit === true, this.rowMenu?.canDelete === true));
  }

  get rowMenuEmpty() {
    const m = this.rowMenu;
    return Boolean(m) && !m.checking && !m.canEdit && !m.canDelete;
  }

  handleRowMenuKey(event) {
    const items = [...this.template.querySelectorAll(".row-popover-item")];
    const at = items.indexOf(this.template.activeElement);
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      const next = event.key === "ArrowDown" ? (at + 1) % items.length : (at - 1 + items.length) % items.length;
      items[next]?.focus();
    } else if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      this.closeRowMenu(true);
    } else if (event.key === "Tab") {
      this.closeRowMenu(false);
    }
  }

  closeRowMenu(returnFocus) {
    this.rowMenu = null;
    this.headerMenu = null;
    if (returnFocus) {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      requestAnimationFrame(() => this._menuTrigger?.focus());
    }
  }

  pickRowMenu(event) {
    const { id, recordId, objectLabel } = this.rowMenu;
    const value = event.currentTarget.dataset.value;
    this.rowMenu = null;
    if (value === "edit") {
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: { recordId, actionName: "edit" }
      });
    } else if (value === "delete") {
      this.confirmDelete(id, recordId, objectLabel);
    }
  }

  // The rows being deleted, by event id.
  deleting = new Set();

  async confirmDelete(eventId, recordId, objectLabel) {
    // "Delete Event" / "Are you sure you want to delete this event?"
    const what = objectLabel || LABELS.deleteItem;
    const title = format(LABELS.deleteTitle, what);
    const message = format(LABELS.deleteConfirm, what.toLocaleLowerCase(LOCALE));
    // The mobile app's own confirm: a custom modal may not open there.
    const yes = isPhone()
      ? await LightningConfirm.open({ label: title, message, theme: "warning" })
      : await TimeDriveConfirm.open({ size: "small", confirmLabel: LABELS.actionDelete, title, message });
    if (!yes) return;
    const name = this.loadedEvents.find((e) => e.id === eventId)?.title?.trim();
    this.deleting = new Set([...this.deleting, eventId]);
    try {
      await deleteRecord(recordId);
      // Gone from what's loaded at once, the counts with it: nothing to reload.
      this.dropEvent(eventId);
      this.dispatchEvent(
        new ShowToastEvent({
          // Event "Menu tasting" was deleted.
          title: objectLabel && name ? format(LABELS.deleteDoneNamed, objectLabel, name) : LABELS.deleteDone,
          variant: "success"
        })
      );
    } catch (e) {
      this.dispatchEvent(
        new ShowToastEvent({ title: LABELS.deleteFailed, message: describeError(e).message, variant: "error" })
      );
    } finally {
      const left = new Set(this.deleting);
      left.delete(eventId);
      this.deleting = left;
    }
  }

  // An item deleted: out of its day, and one fewer in the day's, the type's
  // and the timeline's counts. A day left with nothing goes too.
  dropEvent(eventId) {
    let gone;
    for (const cache of [this._dayCache, this._staleCache]) {
      for (const [key, list] of cache ?? []) {
        const found = list.find((e) => e.id === eventId);
        if (found) {
          gone = gone ?? found;
          cache.set(
            key,
            list.filter((e) => e.id !== eventId)
          );
        }
      }
    }
    if (!gone || !this.summary) return;
    const summary = { ...this.summary };
    const at = (summary.days ?? []).findIndex((d) => d.key === gone.dayKey);
    if (at >= 0) {
      const day = { ...summary.days[at], count: Math.max(0, (summary.days[at].count ?? 1) - 1) };
      summary.days = day.count
        ? summary.days.map((d, i) => (i === at ? day : d))
        : summary.days.filter((d, i) => i !== at);
      if (!day.count) {
        this._dayCache.delete(gone.dayKey);
        if (this.windowFrom > at) this.windowFrom--;
      }
    }
    summary.types = (summary.types ?? []).map((t) => {
      return t.type === gone.type ? { ...t, count: Math.max(0, t.count - 1) } : t;
    });
    summary.total = Math.max(0, (summary.total ?? 1) - 1);
    summary.unfilteredTotal = Math.max(0, (summary.unfilteredTotal ?? 1) - 1);
    this.summary = summary;
    this.daysVersion++;
    this.daysLoaded++;
  }

  // In a console app, a record (or a file's preview) opens in a tab of its
  // own, focused, as Salesforce's own related lists open them; elsewhere the
  // page goes to it.
  @wire(IsConsoleNavigation) isConsoleNavigation;

  openRecord(event) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.button === 1) return;
    event.preventDefault();
    const recordId = event.currentTarget.dataset.record;
    const ref = isFileId(recordId)
      ? filePreviewRef(recordId)
      : { type: "standard__recordPage", attributes: { recordId, actionName: "view" } };
    if (this.isConsoleNavigation) openTab({ pageReference: ref, focus: true });
    else this[NavigationMixin.Navigate](ref);
  }
  // View all for a grouped row: its items a page at a time
  // (c/timeDriveGroup), its span and count in the page's state.
  groupPageRef(event, label) {
    const ns = (this.template.host?.tagName ?? "c-").split("-")[0].toLowerCase();
    const state = {
      recordId: this.recordId,
      type: event.type,
      from: event.firstAt ?? event.occurredAt,
      to: event.occurredAt,
      count: String(event.groupCount ?? ""),
      label,
      icon: event.icon || "",
      object: event.sourceObject ?? ""
    };
    return {
      type: "standard__component",
      attributes: { componentName: `${ns}__timeDriveGroup` },
      state: Object.fromEntries(Object.entries(state).map(([k, v]) => [`${ns}__${k}`, v]))
    };
  }
  groupUrl(event, label) {
    const ref = this.groupPageRef(event, label);
    this.groupRefs.set(event.id, ref);
    return `/lightning/cmp/${ref.attributes.componentName}?${new URLSearchParams(ref.state)}`;
  }
  // The page references behind the grouped rows' links, by row.
  groupRefs = new Map();
  openGroup(event) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.button === 1) return;
    const ref = this.groupRefs.get(event.currentTarget.dataset.id);
    if (!ref) return;
    event.preventDefault();
    this[NavigationMixin.Navigate](ref);
  }
  toggleEvent(event) {
    const id = event.currentTarget.dataset.id;
    const expanded = new Set(this.expanded);
    if (expanded.has(id)) expanded.delete(id);
    else expanded.add(id);
    this.expanded = expanded;
  }
  toggleAll() {
    this.expanded = this.allExpanded ? new Set() : new Set(this.shownEvents.map((e) => e.id));
  }
  // Recovery from an empty filtered view: back to the whole story.
  showEverything() {
    this.view = "All";
    this.hiddenTypes = new Set();
    this.applyQueryChange();
  }
  showMore() {
    const from = this.windowFrom + this.visibleDays;
    this.visibleDays += DAY_PAGE;
    this.announceDays(from, Math.min(this.allDays.length, from + DAY_PAGE) - 1, "Added");
    // Too many days drawn: drop the oldest from the top, keeping the view
    // where it is.
    const excess = this.visibleDays - MAX_WINDOW_DAYS;
    if (excess > 0) {
      this.holdPlace();
      this.windowFrom += excess;
      this.visibleDays -= excess;
    }
  }
  showEarlier() {
    const n = Math.min(DAY_PAGE, this.windowFrom);
    if (!n) return;
    this.announceDays(this.windowFrom - n, this.windowFrom - 1, "Added");
    this.holdPlace();
    this.windowFrom -= n;
    this.visibleDays = Math.min(MAX_WINDOW_DAYS, this.visibleDays + n);
  }

  // ---- vertical: keeping the view's place, and the scrubber -----------------

  // Before days are added or dropped above the view: remember the first day
  // in view and where it sits, so the next render can put it back.
  holdPlace() {
    if (this.horizontal || this._anchor) return;
    const track = this.template.querySelector(".track_bounded");
    if (!track) return;
    for (const day of track.querySelectorAll(".day")) {
      if (day.offsetTop + day.offsetHeight > track.scrollTop) {
        this._anchor = { index: day.dataset.index, offset: day.offsetTop - track.scrollTop };
        return;
      }
    }
  }
  // Days that don't fill the list can't be scrolled to the next ones: add
  // them until it scrolls (one page per render), later days first, then
  // earlier ones (after a jump near the end), or there are no more.
  fillVertical() {
    const track = this.template.querySelector(".track_bounded");
    if (!track?.clientHeight || track.scrollHeight >= this.listHeight) return;
    if (this.hasMore) this.showMore();
    else if (this.hasEarlier) this.showEarlier();
  }
  // Vertical: where a page starting at a day begins, so the page is full
  // even near the end of the days.
  pageStartFor(index) {
    return Math.max(0, Math.min(index, this.allDays.length - DAY_PAGE));
  }
  // After a render: scroll to the day jumped to, or back to the held place.
  settleVertical(behavior = "auto") {
    const track = this.template.querySelector(".track_bounded");
    if (!track) return;
    if (this._jumpTo != null) {
      const index = this._jumpTo;
      const day = track.querySelector(`.day[data-index="${index}"]`);
      const fraction = this._jumpFraction ?? 0;
      this._jumpTo = null;
      this._anchor = null;
      if (day) {
        // Into the day by the fraction, but never past where its last rows
        // fill the list.
        const into = fraction * Math.max(0, day.offsetHeight - track.clientHeight / 2);
        let top = day.offsetTop + into;
        // In the last stretch, the inverse of placeScrubber's: the tab lands
        // where it was dropped, and the end of the rail is the end of the list.
        const tail = this.tailOf(track);
        const at = index + fraction;
        if (tail && at > tail.column) {
          const end = this.allDays.length;
          top = tail.start + ((at - tail.column) / (end - tail.column)) * (tail.max - tail.start);
        }
        track.scrollTo?.({ top, behavior });
      }
      // A day still loading is skeleton height: land again once it's drawn.
      const key = this.orderedDays[index]?.key;
      this._relandOn = fraction > 0 && key && !this._dayCache.has(key) ? { index, key, fraction } : null;
      if (this._endPreviewOnSettle) {
        this._endPreviewOnSettle = false;
        this.setPreview(false);
      }
      return;
    }
    if (this._anchor) {
      const { index, offset } = this._anchor;
      this._anchor = null;
      const day = track.querySelector(`.day[data-index="${index}"]`);
      if (day) track.scrollTop = day.offsetTop - offset;
    }
  }
  // Near either end of the list, the next days load by themselves (the
  // keyboard scrolls the list too, so it loads them the same way).
  handleVerticalScroll(track) {
    if (this._loadingEdge) return;
    const nearBottom = track.scrollTop + track.clientHeight > track.scrollHeight - NEAR_END;
    const nearTop = track.scrollTop < NEAR_END;
    if (nearBottom && this.hasMore) this.showMore();
    else if (nearTop && this.hasEarlier) this.showEarlier();
    else return;
    // One step per render: wait for it before checking again.
    this._loadingEdge = true;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    requestAnimationFrame(() => {
      this._loadingEdge = false;
    });
  }
  // The days drawn, as the minimap arithmetic expects (left/width are the
  // vertical offsets here).
  rows(track) {
    return [...track.querySelectorAll(".day")].map((day) => ({
      index: Number(day.dataset.index),
      left: day.offsetTop,
      width: day.offsetHeight
    }));
  }
  // The tab follows the first day in view, written straight to the DOM (no
  // re-render while scrolling). It stays put while it's being dragged.
  placeScrubber() {
    const track = this.template.querySelector(".track_bounded");
    const rail = this.template.querySelector(".scrub-rail");
    const cells = this._cells;
    if (!track || !rail || !cells?.length) return;
    const rows = this.rows(track);
    if (!rows.length) return;
    let first = this.columnAt(rows, track.scrollTop);
    // The last stretch of the scroll runs on to the end of the days, so the
    // tab reaches the foot of the rail at the bottom (the top of the view
    // never gets past the start of the last rows).
    const tail = this.tailOf(track, rows);
    if (tail && track.scrollTop > tail.start) {
      const end = this.allDays.length;
      first = tail.column + ((end - tail.column) * (track.scrollTop - tail.start)) / (tail.max - tail.start);
    }
    const index = Math.min(this.allDays.length - 1, Math.max(0, Math.floor(first)));
    this._brushIndex = index;
    rail.setAttribute("aria-valuenow", String(index + 1));
    rail.setAttribute("aria-valuetext", this._dayLabels?.[index] ?? "");
    if (!this._scrubbing) this.placeTab(this.cellX(cells, first));
  }
  // The last viewport of the scroll, once the days drawn reach the last one:
  // where it starts (scroll position and fractional day) and the greatest
  // scroll position. Null while later days are still to load.
  tailOf(track, rows = this.rows(track)) {
    const max = track.scrollHeight - track.clientHeight;
    if (this.hasMore || !rows.length || max <= 0) return null;
    const start = Math.max(0, max - track.clientHeight);
    return max > start ? { start, max, column: this.columnAt(rows, start) } : null;
  }
  // The tab at a point down the rail, in percent, kept inside the rail.
  placeTab(percent) {
    const tab = this.template.querySelector(".scrub-tab");
    if (!tab) return;
    const p = Math.min(100, Math.max(0, percent));
    tab.style.top = `${p}%`;
    tab.style.transform = `translateY(-${p}%)`;
  }
  // The day under the pointer on the rail.
  dayAtPointer(event) {
    const rail = this.template.querySelector(".scrub-rail");
    const cells = this._cells ?? [];
    if (!rail || !cells.length) return 0;
    const rect = rail.getBoundingClientRect();
    return Math.floor(dayAtPercent(cells, ((event.clientY - rect.top) / rect.height) * 100));
  }
  pointerPercent(event) {
    const rail = this.template.querySelector(".scrub-rail");
    const rect = rail.getBoundingClientRect();
    return Math.min(100, Math.max(0, ((event.clientY - rect.top) / rect.height) * 100));
  }
  // What the bubble says: the day and month on shorter histories, the month
  // and year once the overlay shows years.
  scrubText(index) {
    const time = this._dayTimes?.[index];
    if (time == null) return "";
    const byDay = this._scrubUnit === "day" || this._scrubUnit === "week";
    return byDay ? this._dayLabels[index] : MONTH_YEAR.format(new Date(time));
  }
  showBubble(percent, index) {
    const bubble = this.template.querySelector(".scrub-bubble");
    if (!bubble) return;
    const p = Math.min(100, Math.max(0, percent));
    bubble.style.top = `${p}%`;
    bubble.style.transform = `translateY(-${p}%)`;
    bubble.textContent = this.scrubText(index);
    bubble.hidden = false;
  }
  setScrubActive(active) {
    this.template.querySelector(".scrub")?.classList.toggle("scrub_active", active);
  }
  // Grab the tab (or anywhere on the edge): the overlay opens and the tab and
  // bubble follow the pointer; letting go jumps to that day and closes it.
  handleScrubDown(event) {
    event.preventDefault();
    const rail = event.currentTarget;
    rail.dataset.pointer = "true";
    rail.focus?.({ preventScroll: true, focusVisible: false });
    rail.setPointerCapture?.(event.pointerId);
    this._scrubbing = true;
    this._previewFrom = this.dayAtPointer(event);
    this.setScrubActive(true);
    this.followPointer(event);
  }
  handleScrubMove(event) {
    if (!this._scrubbing) return;
    // Released out of earshot (see handleMinimapMove): end the scrub.
    if (event.buttons === 0) {
      this.handleScrubUp(event);
      return;
    }
    // Once the pointer moves to another day, the list gives way to the
    // moving skeleton (a press and release in place just jumps).
    if (!this._previewing && this.dayAtPointer(event) !== this._previewFrom) {
      this._previewing = true;
      this.setPreview(true);
    }
    this.followPointer(event);
  }
  followPointer(event) {
    const percent = this.pointerPercent(event);
    this.placeTab(percent);
    const day = this.dayAtPointer(event);
    this.showBubble(percent, day);
    this.movePreview(dayAtPercent(this._cells ?? [], percent));
  }
  // The skeleton list slides as if scrolling through the days passed over:
  // about a day's height per day, looping one group's height.
  movePreview(day) {
    const inner = this.template.querySelector(".scrub-preview-inner");
    if (!inner || !Number.isFinite(day)) return;
    if (!this._previewHeight) this._previewHeight = inner.firstElementChild?.offsetHeight || 0;
    const loop = this._previewHeight;
    const distance = day * PREVIEW_DAY_PX;
    const offset = loop ? ((distance % loop) + loop) % loop : 0;
    inner.style.transform = `translateY(-${offset}px)`;
  }
  setPreview(on) {
    this.template.querySelector(".frame_scrub")?.classList.toggle("frame_previewing", on);
    if (!on) this._previewHeight = 0;
  }
  handleScrubUp(event) {
    if (!this._scrubbing) return;
    this._scrubbing = false;
    this.setScrubActive(false);
    const bubble = this.template.querySelector(".scrub-bubble");
    if (bubble) bubble.hidden = true;
    if (event.type === "pointerup") {
      // The skeleton stays until the jump has drawn the day (settleVertical).
      this._endPreviewOnSettle = this._previewing;
      const at = dayAtPercent(this._cells ?? [], this.pointerPercent(event));
      const index = Math.floor(at);
      this.jumpToDay(index, "auto", at - index);
      this.announceDays(index, index, "Showing");
    } else {
      this.setPreview(false);
      this.queueBrush();
    }
    this._previewing = false;
  }
  // Keyboard: the overlay opens while the tab has focus; the arrows, Page and
  // Home/End keys jump, and the bubble names the day.
  handleScrubKey(event) {
    delete event.currentTarget.dataset.pointer;
    const steps = { ArrowUp: -1, ArrowDown: 1, PageUp: -DAY_PAGE, PageDown: DAY_PAGE };
    const last = this.allDays.length - 1;
    const current = this._brushIndex ?? 0;
    let target = null;
    if (event.key in steps) target = current + steps[event.key];
    else if (event.key === "Home") target = 0;
    else if (event.key === "End") target = last;
    if (target === null) return;
    event.preventDefault();
    target = Math.max(0, Math.min(target, last));
    this.setScrubActive(true);
    this.showBubble(percentAtDay(this._cells ?? [], target + 0.5), target);
    this.placeTab(percentAtDay(this._cells ?? [], target));
    // Held or repeated keys move the bubble and tab; the jump (and its
    // fetch) waits until they pause.
    this._brushIndex = target;
    clearTimeout(this._keyJumpTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._keyJumpTimer = setTimeout(() => this.jumpToDay(target), SETTLE_MS);
  }
  // ---- vertical, with the scrub tab: click to engage the list ---------------
  // Until the list is clicked (or tapped), the wheel and touch over it scroll
  // the page; after, they scroll the list, finely, until the pointer leaves
  // the card or the page is pressed elsewhere.
  handleTrackPointerDown() {
    this._listPress = true;
    if (this.scrubber && !this.engaged) this.setEngaged(true);
  }
  handleFramePointerLeave(event) {
    if (event.pointerType !== "touch") this.setEngaged(false);
    this._hinted = false;
  }
  // The wheel over the list, listened to passively: a template onwheel makes
  // the browser wait on JavaScript before every wheel scroll, and this never
  // cancels one. The list is redrawn on layout changes, so check each render.
  listenToWheel() {
    const track = this.template.querySelector(".track");
    if (!track || track === this._wheelTrack) return;
    this._wheelTrack = track;
    this._onTrackWheel ??= () => this.handleTrackWheel();
    track.addEventListener("wheel", this._onTrackWheel, { passive: true });
  }
  // The first wheel over a list that isn't engaged says how to engage it.
  handleTrackWheel() {
    if (!this.scrubber || this.engaged || this._hinted) return;
    this._hinted = true;
    const hint = this.template.querySelector(".scroll-hint");
    if (!hint) return;
    hint.classList.add("scroll-hint_on");
    clearTimeout(this._hintTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._hintTimer = setTimeout(() => hint.classList.remove("scroll-hint_on"), HINT_MS);
  }
  setEngaged(on) {
    if (this.engaged === on) return;
    this.engaged = on;
    if (on) this.template.querySelector(".scroll-hint")?.classList.remove("scroll-hint_on");
  }
  // The wheel over the tab scrolls the list (it doesn't over the list itself).
  handleScrubWheel(event) {
    const track = this.template.querySelector(".track_bounded");
    if (!track) return;
    event.preventDefault();
    track.scrollTop += event.deltaY;
  }
  // With the scrub tab, the list doesn't scroll by wheel or touch; from the
  // keyboard it still does.
  handleTrackKey(event) {
    if (!this.scrubber) return;
    const track = event.currentTarget;
    const page = track.clientHeight * 0.9;
    const moves = { ArrowDown: 40, ArrowUp: -40, PageDown: page, PageUp: -page, " ": page };
    if (event.target !== track) return;
    if (event.key in moves) track.scrollTop += moves[event.key];
    else if (event.key === "Home") track.scrollTop = 0;
    else if (event.key === "End") track.scrollTop = track.scrollHeight;
    else return;
    event.preventDefault();
  }
  handleScrubBlur() {
    if (this._scrubbing) return;
    this.setScrubActive(false);
    const bubble = this.template.querySelector(".scrub-bubble");
    if (bubble) bubble.hidden = true;
  }
  // ---- minimap -----------------------------------------------------------------

  // The viewport box follows the track's scroll to the fraction of a column,
  // written straight to the DOM each frame: no re-render while scrolling or
  // dragging, so it stays smooth.
  queueBrush() {
    if (this._brushFrame) return;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._brushFrame = requestAnimationFrame(() => {
      this._brushFrame = null;
      if (!this.horizontal) {
        this.placeScrubber();
        return;
      }
      this.placeBrush();
      this.scheduleWindow();
    });
  }
  placeBrush() {
    const track = this.template.querySelector(".track");
    const strip = this.template.querySelector(".seek-rail");
    const thumb = this.template.querySelector(".seek-thumb");
    const cells = this._cells;
    if (!track || !strip || !thumb || !cells?.length) return;
    const geometry = this.columnGeometry();
    // Not laid out yet: the slider still needs a value.
    if (!geometry) {
      this.setSeekValue(strip, this._brushIndex ?? 0);
      return;
    }
    const first = this.columnAtX(geometry, track.scrollLeft);
    const last = this.columnAtX(geometry, track.scrollLeft + track.clientWidth);
    const left = this.cellX(cells, first);
    const width = Math.max(this.cellX(cells, last) - left, cells[0].width);
    // The handle spans the days in view (2rem at least), kept on the bar.
    thumb.style.width = `${width}%`;
    thumb.style.left = `min(${left}%, calc(100% - max(${width}%, 2rem)))`;
    this.setSeekValue(strip, Math.min(this.allDays.length - 1, Math.max(0, Math.round(first))));
  }
  setSeekValue(strip, index) {
    this._brushIndex = index;
    strip.setAttribute("aria-valuenow", String(index + 1));
    strip.setAttribute("aria-valuetext", this._dayLabels?.[index] ?? "");
  }
  // Horizontal: while the seek handle is dragged or the columns move fast,
  // hold the drawn window (and its fetches) until movement pauses for
  // SETTLE_MS or stops; otherwise move it straight away.
  scheduleWindow() {
    const track = this.template.querySelector(".track");
    if (!track) return;
    const now = Date.now();
    const last = this._lastScroll;
    const speed = last ? Math.abs(track.scrollLeft - last.x) / Math.max(1, now - last.t) : 0;
    this._lastScroll = { x: track.scrollLeft, t: now };
    clearTimeout(this._windowTimer);
    if (!this._press?.dragging && speed < FAST_SCROLL) {
      this.updateWindow();
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._windowTimer = setTimeout(() => {
      this._windowTimer = null;
      this._lastScroll = null;
      this.updateWindow();
    }, SETTLE_MS);
  }
  // Horizontal: draw events for the columns in view plus a few either side;
  // re-centre the window once the view nears its edge.
  updateWindow() {
    const track = this.template.querySelector(".track");
    const geometry = this.columnGeometry();
    // Not laid out yet (no widths): keep the window where it is.
    if (!track || !geometry) return;
    const first = Math.floor(this.columnAtX(geometry, track.scrollLeft));
    const last = Math.ceil(this.columnAtX(geometry, track.scrollLeft + track.clientWidth));
    if (first > this.renderFrom && last < this.renderTo) return;
    const from = Math.max(0, first - WINDOW_BUFFER);
    const to = last + WINDOW_BUFFER;
    trace("window moves", {
      view: [first, last],
      from: [this.renderFrom, this.renderTo],
      to: [from, to],
      scrollLeft: track.scrollLeft
    });
    if (from !== this.renderFrom || to !== this.renderTo) {
      this.renderFrom = from;
      this.renderTo = to;
      // Ask for what the new window needs now, not after the next render.
      this.loadNeededDays();
    }
  }
  // Horizontal: every day column is the same width, so the first two place
  // them all. Measured once per render or resize, not per scroll frame (that
  // read every column's layout, twice a frame).
  columnGeometry() {
    if (this._geometry) return this._geometry;
    const first = this.template.querySelector(".card_horizontal .day");
    if (!first?.offsetWidth) return null;
    const next = first.nextElementSibling;
    const pitch = next?.classList.contains("day") ? next.offsetLeft - first.offsetLeft : first.offsetWidth;
    this._geometry = { left: first.offsetLeft, pitch: pitch || first.offsetWidth, width: first.offsetWidth };
    return this._geometry;
  }
  // The fractional column at a scroll position (3.5 is halfway through the
  // fourth), by arithmetic on the geometry.
  columnAtX(geometry, x) {
    const count = this.allDays.length;
    if (x <= geometry.left) return 0;
    const i = Math.floor((x - geometry.left) / geometry.pitch);
    if (i >= count) return count;
    const into = x - (geometry.left + i * geometry.pitch);
    return i + Math.min(1, into / geometry.width);
  }
  // The fractional column at a scroll position: 3.5 is halfway through the
  // fourth column.
  columnAt(columns, x) {
    for (const col of columns) {
      if (x < col.left + col.width) return col.index + Math.max(0, (x - col.left) / col.width);
    }
    const end = columns[columns.length - 1];
    return end.index + 1;
  }
  // A fractional column's position on the minimap, in percent.
  cellX(cells, column) {
    return percentAtDay(cells, column);
  }
  // The scroll position that centres a fractional column.
  scrollFor(geometry, column, track) {
    const at = Math.min(this.allDays.length - 1, Math.max(0, column));
    return geometry.left + at * geometry.pitch + geometry.width / 2 - track.clientWidth / 2;
  }
  // The fractional column under a point on the minimap (by cell centres).
  columnAtPointer(event) {
    const strip = this.template.querySelector(".seek-rail");
    const cells = this._cells ?? [];
    if (!strip || !cells.length) return 0;
    const rect = strip.getBoundingClientRect();
    return dayAtPercent(cells, ((event.clientX - rect.left) / rect.width) * 100);
  }
  // Horizontal only: a "N more" pill at the foot of any day column with
  // events hidden below, kept in step with the column's scroll. Written
  // straight to the DOM so scrolling never re-renders.
  queuePills() {
    if (this._pillFrame) return;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._pillFrame = requestAnimationFrame(() => {
      this._pillFrame = null;
      // Measure every column first, then write: interleaving reads and writes
      // would force a layout per column.
      const updates = [];
      // Only drawn columns have events (and a pill); shells have neither.
      this.template.querySelectorAll(".day:not(.day_shell)").forEach((day) => {
        const list = day.querySelector(".events");
        const pill = day.querySelector(".scroll-pill");
        if (!list || !pill) return;
        const bottom = list.scrollTop + list.clientHeight;
        let hidden = 0;
        for (const item of list.children) {
          if (item.offsetTop + item.offsetHeight / 2 > bottom) hidden++;
        }
        updates.push({ pill, hidden });
      });
      for (const { pill, hidden } of updates) {
        const hide = hidden === 0;
        if (pill.hidden !== hide) pill.hidden = hide;
        const text = hidden === 1 ? LABELS.moreOne : format(LABELS.moreMany, formatCount(hidden));
        const count = pill.querySelector(".scroll-pill-count");
        if (count && count.textContent !== text) count.textContent = text;
        // Said in full: which day, and what pressing it does.
        const day = this._dayLabels?.[Number(pill.closest(".day")?.dataset.index)];
        const name =
          hidden === 1
            ? day
              ? format(LABELS.moreAriaOneOn, day)
              : LABELS.moreAriaOne
            : day
              ? format(LABELS.moreAriaManyOn, formatCount(hidden), day)
              : format(LABELS.moreAriaMany, formatCount(hidden));
        if (pill.getAttribute("aria-label") !== name) pill.setAttribute("aria-label", name);
      }
    });
  }
  handleColumnScroll() {
    this.queuePills();
  }
  // A ticket finished opening or closing: the column's height changed, so
  // count what's hidden again (the click's own recount ran mid-animation).
  handleColumnResize(event) {
    if (event.propertyName === "grid-template-rows") this.queuePills();
  }
  scrollColumn(event) {
    const list = event.currentTarget.closest(".day")?.querySelector(".events");
    list?.scrollBy({ top: list.clientHeight * 0.8, behavior: "smooth" });
  }
  handleTrackScroll(event) {
    // Only the brush: sideways scrolling doesn't change what each column hides.
    this.queueBrush();
    if (!this.horizontal) this.handleVerticalScroll(event.currentTarget);
  }
  // Bring a day column into view (every day has a column; its events draw as
  // it comes near).
  // Vertical: `fraction` is how far into the day to land (0 its top, 0.5
  // its middle), so the scrub tab can reach any row of a long day.
  jumpToDay(index, behavior = "smooth", fraction = 0) {
    const target = Math.max(0, Math.min(index, this.allDays.length - 1));
    if (!this.horizontal) {
      this._jumpFraction = Math.min(1, Math.max(0, fraction || 0));
      // Vertical: draw a page of days from the one chosen, and put it at the
      // top of the list; the days around it load as the list is scrolled.
      const inWindow = target >= this.windowFrom && target < this.windowFrom + this.visibleDays;
      if (!inWindow) {
        // A full page, the day chosen at its top, or as near as the end allows.
        this.windowFrom = this.pageStartFor(target);
        this.visibleDays = DAY_PAGE;
      }
      this._jumpTo = target;
      if (inWindow) this.settleVertical(behavior);
      return;
    }
    this.scrollToDay(target, behavior);
  }
  scrollToDay(index, behavior) {
    const track = this.template.querySelector(".track");
    const day = this.template.querySelector(`.day[data-index="${index}"]`);
    if (!track || !day) return;
    track.scrollTo?.({ left: day.offsetLeft - (track.clientWidth - day.offsetWidth) / 2, behavior });
  }
  // Press, then drag to scrub (the track follows the pointer frame by frame),
  // or just click to glide to a day.
  handleMinimapDown(event) {
    // Keep the browser from starting a text selection or its own drag and
    // drop (the globe cursor) from the strip; the minimap owns the gesture.
    event.preventDefault();
    // Focus it so the arrow keys work next, but marked as pointer focus: the
    // focus ring is for keyboard use and shows once a key is pressed.
    const strip = event.currentTarget;
    strip.dataset.pointer = "true";
    strip.focus?.({ preventScroll: true, focusVisible: false });
    this._press = { x: event.clientX, dragging: false };
    event.currentTarget.setPointerCapture?.(event.pointerId);
    this.setSeekActive(true);
    this.showSeekBubble(event);
  }
  setSeekActive(active) {
    this.template.querySelector(".seek")?.classList.toggle("seek_active", active);
  }
  // The bubble over the bar names the day under the pointer (or, by key, the
  // day jumped to): the day and month, or the month and year on long spans.
  showSeekBubble(event, index) {
    const bubble = this.template.querySelector(".seek-bubble");
    const rail = this.template.querySelector(".seek-rail");
    const cells = this._cells ?? [];
    if (!bubble || !rail || !cells.length) return;
    let percent;
    let day = index;
    if (event) {
      const rect = rail.getBoundingClientRect();
      percent = Math.min(100, Math.max(0, ((event.clientX - rect.left) / rect.width) * 100));
      day = Math.floor(dayAtPercent(cells, percent));
    } else {
      percent = percentAtDay(cells, day + 0.5);
    }
    if (!Number.isFinite(percent)) percent = 0;
    bubble.style.left = `${percent}%`;
    bubble.style.transform = `translateX(-${percent}%)`;
    bubble.textContent = this.scrubText(Math.max(0, Math.min(this.allDays.length - 1, day ?? 0)));
    bubble.hidden = false;
  }
  hideSeekBubble() {
    const bubble = this.template.querySelector(".seek-bubble");
    if (bubble) bubble.hidden = true;
  }
  handleSeekBlur() {
    if (this._press) return;
    this.setSeekActive(false);
    this.hideSeekBubble();
  }
  handleMinimapDragStart(event) {
    event.preventDefault();
  }
  handleMinimapMove(event) {
    if (!this._press) return;
    // The button came up where we couldn't hear it (off the window, or the
    // pointer capture was lost): the press is over, not still dragging.
    if (event.buttons === 0) {
      this.handleMinimapUp(event);
      return;
    }
    if (!this._press.dragging) {
      if (Math.abs(event.clientX - this._press.x) < 4) return;
      this._press.dragging = true;
      this.template.querySelector(".track")?.classList.add("track_dragging");
    }
    this.showSeekBubble(event);
    const column = this.columnAtPointer(event);
    const track = this.template.querySelector(".track");
    const geometry = this.columnGeometry();
    if (!track || !geometry) return;
    track.scrollLeft = this.scrollFor(geometry, column, track);
  }
  handleMinimapUp(event) {
    const press = this._press;
    this._press = null;
    this.template.querySelector(".track")?.classList.remove("track_dragging");
    this.setSeekActive(false);
    this.hideSeekBubble();
    // Let go: draw and fetch where the columns stopped, now.
    if (press?.dragging) {
      clearTimeout(this._windowTimer);
      this._lastScroll = null;
      this.updateWindow();
      this.announceDays(this._brushIndex ?? 0, this._brushIndex ?? 0, "Showing");
    }
    if (press && !press.dragging && event.type === "pointerup") {
      const day = Math.round(this.columnAtPointer(event));
      this.jumpToDay(day);
      this.announceDays(day, day, "Showing");
    }
  }
  handleMinimapKey(event) {
    delete event.currentTarget.dataset.pointer;
    const steps = { ArrowLeft: -1, ArrowRight: 1, PageUp: -5, PageDown: 5 };
    const last = this.allDays.length - 1;
    const current = this._brushIndex ?? 0;
    let target = null;
    if (event.key in steps) target = current + steps[event.key];
    else if (event.key === "Home") target = 0;
    else if (event.key === "End") target = last;
    if (target === null) return;
    event.preventDefault();
    target = Math.max(0, Math.min(target, last));
    this.setSeekActive(true);
    this.showSeekBubble(null, target);
    this.jumpToDay(target);
  }

  // Horizontal: the day at the left edge of the view and the offset into
  // its column, by key (Refresh may add or remove days before it).
  placeAcross() {
    if (!this.horizontal) return null;
    const track = this.template.querySelector(".track:not(.track_skeleton)");
    const geometry = this.columnGeometry();
    if (!track || !geometry) return null;
    const index = Math.floor(this.columnAtX(geometry, track.scrollLeft));
    const day = this.allDays[index];
    if (!day) return null;
    return { key: day.key, offset: track.scrollLeft - (geometry.left + index * geometry.pitch) };
  }

  // After Refresh, once the fresh columns are laid out: back to that day.
  restoreAcross() {
    const place = this._restoreAcross;
    if (!place || !this.horizontal || this.isLoading) return;
    const track = this.template.querySelector(".track:not(.track_skeleton)");
    const geometry = this.columnGeometry();
    if (!track || !geometry) return;
    this._restoreAcross = null;
    const index = this.allDays.findIndex((d) => d.key === place.key);
    if (index < 0) return;
    track.scrollLeft = geometry.left + index * geometry.pitch + place.offset;
  }

  // ---- Open At: where the timeline opens --------------------------------------

  _focusPending = true;

  // Today's day, week or month key: its slot is always among the days (real,
  // or the placeholder) once there are any.
  get currentKey() {
    return currentPeriodKey(this.unit);
  }

  // Once the days are drawn, bring the Open At day into view. Horizontal
  // centres its column (the first and last sit at the ends). Vertical puts
  // it at the top: when every day fits in the first page (low volumes) by
  // scrolling the list, so nothing newer is hidden; else by starting the
  // list there, newer days loading as it's scrolled up.
  applyFocus() {
    if (!this._focusPending || !this.summary || !this.allDays.length) return;
    const index = this.focusIndex();
    if (this.horizontal) {
      // Not laid out yet: try again after the next render.
      if (!this.columnGeometry()) return;
      this._focusPending = false;
      trace("focus scroll", { index, geometry: this.columnGeometry(), window: [this.renderFrom, this.renderTo] });
      this.scrollToDay(index, "auto");
      return;
    }
    this._focusPending = false;
    if (index <= 0) return;
    if (index < DAY_PAGE) {
      // Within the first page: keep the days above it in the window and
      // scroll to it, so none load in above the view later (the list and the
      // scrub tab would shift when they did).
      this.visibleDays = Math.max(this.visibleDays, index + DAY_PAGE);
    } else if (this.allDays.length > this.visibleDays) {
      this.windowFrom = this.pageStartFor(index);
      this.visibleDays = DAY_PAGE;
    }
    this._jumpTo = index;
    this._jumpFraction = 0;
  }

  // The Today button: today's slot into view, as Open At = Today opens on it
  // (centred across; at the top of the list down).
  goToToday() {
    const index = this.allDays.findIndex((d) => d.key === this.currentKey);
    if (index < 0) return;
    this.jumpToDay(index, "smooth");
    this.announce(LABELS.announceToday);
  }

  // The Open At day's index among the days in their drawn order.
  focusIndex() {
    const days = this.allDays;
    // The earliest and latest items: days with items, not the placeholders.
    const real = days.map((d, i) => ({ time: d.time, i })).filter(({ i }) => !days[i].placeholder);
    const pick = (better) => (real.length ? real.reduce((a, b) => (better(b.time, a.time) ? b : a)).i : 0);
    const earliest = pick((x, y) => x < y);
    const latest = pick((x, y) => x > y);
    if (this.openAt === "Earliest item") return earliest;
    if (this.openAt === "Latest item") return latest;
    const today = days.findIndex((d) => d.key === this.currentKey);
    return today >= 0 ? today : latest;
  }

  resetPaging() {
    this._focusPending = true;
    this.windowFrom = 0;
    this.visibleDays = DAY_PAGE;
    this._anchor = null;
    this._jumpTo = null;
    const track = this.template.querySelector(".track_bounded");
    if (track) track.scrollTop = 0;
  }
}
