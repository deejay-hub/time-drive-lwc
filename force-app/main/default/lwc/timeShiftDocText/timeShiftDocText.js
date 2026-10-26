import { LightningElement, api } from "lwc";

// A line of doc text. A link to another doc, or to a section, stays in
// Setup: it says so with a doclink event rather than leaving the page.
export default class TimeShiftDocText extends LightningElement {
  @api parts = [];

  handleLink(event) {
    const { doc, anchor } = event.currentTarget.dataset;
    if (!doc && !anchor) return;
    event.preventDefault();
    this.dispatchEvent(new CustomEvent("doclink", { detail: { doc, anchor }, bubbles: true, composed: true }));
  }
}
