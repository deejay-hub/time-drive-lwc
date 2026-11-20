/**
 * The timeline's Filters panel: the date range and the event types to show,
 * applied together with Apply. Its own component, so opening it, ticking types and closing it
 * re-render only the panel, not the timeline and every item it draws; the
 * timeline hears once, on Apply.
 *
 * The Filters button stays in the timeline's button group; it calls
 * toggle(), notePress() and close(), and hears openchange.
 *
 * The panel floats over the page, fixed to the button (toggle() is given
 * where it is), so the card's clipped corners don't cut a long list short:
 * below the button, or above it when there's more room there, no taller than
 * the room, its list scrolling inside. It follows the button as the page
 * scrolls.
 */
import { LightningElement, api } from "lwc";
import { LABELS } from "c/timeDriveLabels";

// Room kept between the panel and the button, and the window's edges (px).
const GAP = 6;
const MARGIN = 8;
// Less room than this below the button, and more above: the panel opens up.
const ENOUGH_BELOW = 240;
// The panel's widest (18rem).
const WIDTH = 288;

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
  // SLDS 1's corners on the panel.
  @api slds1 = false;

  isOpen = false;
  draft = [];
  draftBack = "";
  draftAhead = "";
  // What was shown when the panel opened: Apply and Cancel appear once the
  // draft differs from it.
  opened = [];

  // anchor: where the Filters button is now (a function returning its
  // rectangle); without one the panel sits where the page puts it.
  @api
  toggle(anchor) {
    this._anchor = typeof anchor === "function" ? anchor : null;
    if (this.isOpen) this.close(true);
    else this.open();
  }

  @api
  close(returnFocus = false) {
    if (!this.isOpen) return;
    this.isOpen = false;
    this.unfollow();
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
    this.follow();
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
    this.unfollow();
  }

  // While open, the panel keeps to the button as the page scrolls (any
  // scrolling box: captured) or the window changes size.
  follow() {
    if (this._onMove || !this._anchor) return;
    this._onMove = () => {
      if (this._moveFrame) return;
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      this._moveFrame = requestAnimationFrame(() => {
        this._moveFrame = null;
        this.place();
      });
    };
    window.addEventListener("scroll", this._onMove, true);
    window.addEventListener("resize", this._onMove);
  }
  unfollow() {
    if (!this._onMove) return;
    window.removeEventListener("scroll", this._onMove, true);
    window.removeEventListener("resize", this._onMove);
    if (this._moveFrame) cancelAnimationFrame(this._moveFrame);
    this._onMove = null;
    this._moveFrame = null;
  }

  // Puts the panel by the button: its end edge under the button's end (start
  // to start right to left), below it or above, inside the window.
  place() {
    const panel = this.template.querySelector(".filter-panel");
    const button = this._anchor?.();
    if (!panel || !button || !button.width) return;
    const width = Math.min(WIDTH, window.innerWidth - 2 * MARGIN);
    const below = window.innerHeight - button.bottom - GAP - MARGIN;
    const above = button.top - GAP - MARGIN;
    const up = below < ENOUGH_BELOW && above > below;
    panel.style.width = `${width}px`;
    panel.style.maxHeight = `${Math.max(120, up ? above : below)}px`;
    const rtl = getComputedStyle(panel).direction === "rtl";
    const left = Math.min(
      Math.max(MARGIN, rtl ? button.left : button.right - width),
      window.innerWidth - width - MARGIN
    );
    const top = up ? button.top - GAP - panel.offsetHeight : button.bottom + GAP;
    panel.style.left = `${left}px`;
    panel.style.top = `${top}px`;
    // A transformed parent moves "fixed" off the window: put it right.
    const at = panel.getBoundingClientRect();
    const dx = left - at.left;
    const dy = top - at.top;
    if (Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5) {
      panel.style.left = `${left + dx}px`;
      panel.style.top = `${top + dy}px`;
    }
  }

  renderedCallback() {
    // Placed before it's painted, and again as it grows or shrinks.
    if (this.isOpen) this.place();
    if (this._focusFirst) {
      this._focusFirst = false;
      (this.template.querySelector(".range-back") ?? this.template.querySelector(".all-types"))?.focus();
    }
  }

  get panelClass() {
    return `filter-panel${this.slds1 ? " filter-panel_slds1" : ""}`;
  }
  get choices() {
    return (this.options ?? []).map((o) => ({ label: o.label, value: o.value }));
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
  handleChange(event) {
    this.draft = event.detail.value;
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
