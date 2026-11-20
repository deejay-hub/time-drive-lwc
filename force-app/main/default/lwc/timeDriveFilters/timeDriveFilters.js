/**
 * The timeline's Filters panel: the date range and the event types to show,
 * applied together with Apply. Its own component, so opening it, ticking types and closing it
 * re-render only the panel, not the timeline and every item it draws; the
 * timeline hears once, on Apply.
 *
 * The Filters button stays in the timeline's button group; it calls
 * toggle(), notePress() and close(), and hears openchange.
 *
 * The panel is a sheet inside the card, under its header and down to its
 * foot: on a wide card at the card's end, the types in as many columns as fit
 * (up to three); on a
 * narrow one over the whole timeline, in one. It uses the card's height,
 * scrolling only when the types are longer than that, and says how tall it
 * would like to be (panelsize) so a short timeline can make room for it.
 */
import { LightningElement, api } from "lwc";
import { LABELS } from "c/timeDriveLabels";

// The most room the panel asks a short timeline for (px); past that its list scrolls.
const MOST_ROOM = 480;

export default class TimeDriveFilters extends LightningElement {
  labels = LABELS;
  // The types: { value, label, checked } (checked: shown now).
  @api options = [];
  // How far back and ahead the page lets people narrow it to ({ value,
  // label }, months); none: no Date range section. The months in use now.
  @api backOptions = [];
  @api aheadOptions = [];
  @api back = "";
  @api ahead = "";
  // What to say when there are no types to offer.
  @api noneText = "";
  // The lens being filtered: each lens keeps its own filter, so the title names it.
  @api lensLabel = "";
  // A wide card: the panel sits at its end, the types in up to three columns; narrow,
  // it covers the timeline, in one.
  @api wide = false;

  isOpen = false;
  draft = [];
  draftBack = "";
  draftAhead = "";
  // What was shown when the panel opened: Apply and Cancel appear once the
  // draft differs from it.
  opened = [];

  @api
  toggle() {
    if (this.isOpen) this.close(true);
    else this.open();
  }

  @api
  close(returnFocus = false) {
    if (!this.isOpen) return;
    this.isOpen = false;
    this._room = 0;
    this.dispatchEvent(new CustomEvent("panelsize", { detail: { height: 0 } }));
    this.dispatchEvent(new CustomEvent("openchange", { detail: { open: false, returnFocus } }));
  }

  // A press on the Filters button: not a press outside the panel.
  @api
  notePress() {
    this._press = true;
  }

  open() {
    this.draft = (this.options ?? []).filter((o) => o.checked).map((o) => o.value);
    this.opened = [...this.draft];
    this.draftBack = String(this.back ?? "");
    this.draftAhead = String(this.ahead ?? "");
    this.isOpen = true;
    this._focusFirst = true;
    this.dispatchEvent(new CustomEvent("openchange", { detail: { open: true } }));
  }

  connectedCallback() {
    // A press anywhere outside the panel (and its button) cancels it.
    this._onDocumentPointer = () => {
      if (this._press) {
        this._press = false;
        return;
      }
      this.close(false);
    };
    document.addEventListener("pointerdown", this._onDocumentPointer);
  }

  disconnectedCallback() {
    document.removeEventListener("pointerdown", this._onDocumentPointer);
  }

  // How tall the panel would be with nothing scrolling (its head, padding and
  // the whole list), up to MOST_ROOM: the timeline gives it at least that.
  measure() {
    const panel = this.template.querySelector(".filter-panel");
    const body = this.template.querySelector(".filter-body");
    if (!panel || !body) return;
    const room = Math.min(MOST_ROOM, Math.ceil(panel.offsetHeight - body.clientHeight + body.scrollHeight));
    if (room === this._room) return;
    this._room = room;
    this.dispatchEvent(new CustomEvent("panelsize", { detail: { height: room } }));
  }

  renderedCallback() {
    if (this.isOpen) this.measure();
    if (this._focusFirst) {
      this._focusFirst = false;
      (this.template.querySelector(".range-back") ?? this.template.querySelector(".all-types"))?.focus();
    }
  }

  get panelClass() {
    return `filter-panel ${this.wide ? "filter-panel_wide" : "filter-panel_narrow"}`;
  }
  get choices() {
    const draft = new Set(this.draft);
    return (this.options ?? []).map((o) => ({ label: o.label, value: o.value, checked: draft.has(o.value) }));
  }
  get hasChoices() {
    return this.choices.length > 0;
  }
  // Only when either side has a choice to make (more than None).
  get hasRanges() {
    return (this.backOptions ?? []).length > 1 || (this.aheadOptions ?? []).length > 1;
  }
  // The lengths, the one picked marked selected (native selects).
  get backChoices() {
    return (this.backOptions ?? []).map((o) => ({ ...o, selected: o.value === this.draftBack }));
  }
  get aheadChoices() {
    return (this.aheadOptions ?? []).map((o) => ({ ...o, selected: o.value === this.draftAhead }));
  }
  // Something was ticked or cleared, or the range changed, since the panel opened.
  get changed() {
    const was = [...this.opened].sort();
    const now = [...this.draft].sort();
    return (
      this.draftBack !== String(this.back ?? "") ||
      this.draftAhead !== String(this.ahead ?? "") ||
      was.length !== now.length ||
      was.some((value, i) => value !== now[i])
    );
  }
  get allChecked() {
    return this.hasChoices && this.draft.length === this.choices.length;
  }

  handlePanelPress() {
    this._press = true;
  }
  handleKey(event) {
    if (event.key === "Escape") {
      event.stopPropagation();
      this.close(true);
    }
  }
  // "All types": every type, or none.
  toggleAll(event) {
    this.draft = event.target.checked ? this.choices.map((o) => o.value) : [];
  }
  // One type ticked or cleared; the draft keeps the types' own order.
  handleChange(event) {
    const value = event.target.dataset.value;
    const on = new Set(this.draft);
    if (event.target.checked) on.add(value);
    else on.delete(value);
    this.draft = (this.options ?? []).map((o) => o.value).filter((v) => on.has(v));
  }
  handleBack(event) {
    this.draftBack = event.target.value;
  }
  handleAhead(event) {
    this.draftAhead = event.target.value;
  }
  apply() {
    const shown = [...this.draft];
    const back = Number(this.draftBack);
    const ahead = Number(this.draftAhead);
    this.close(true);
    // The panel goes first, painted before the timeline updates (which can
    // take a moment on a busy page): after the next frame, then a task.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    requestAnimationFrame(() => {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(() => this.dispatchEvent(new CustomEvent("apply", { detail: { shown, back, ahead } })), 0);
    });
  }
  cancel() {
    this.close(true);
  }
}
