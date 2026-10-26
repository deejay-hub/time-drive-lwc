/**
 * A Salesforce record's compact layout, read-only: the layout's fields in
 * order (getLayout) with this record's values (getRecord for just those
 * fields), so an admin chooses the fields in Object Manager and Lightning
 * Data Service applies field-level security. Drawn in the timeline's own
 * label/value style.
 */
import { LightningElement, api, wire } from "lwc";
import { getLayout } from "lightning/uiLayoutApi";
import { getRecord } from "lightning/uiRecordApi";
import ASSETS from "@salesforce/resourceUrl/timeShiftAssets";
import { describeError, illustrationState, illustrationUrl } from "c/timeShiftErrors";
import { LABELS, format } from "c/timeShiftLabels";

// A field's text: its display value (a picklist's label, a date in the
// user's locale), else the value. A lookup shows the Id it holds: asking for
// its name makes the server resolve every relationship, which is slow.
function textOf(values, name) {
  const field = values[name];
  return field.displayValue ?? field.value;
}

export default class TimeShiftRecordDetails extends LightningElement {
  labels = LABELS;

  get failedText() {
    return format(LABELS.rdFailed, this.error?.message ?? "");
  }

  @api recordId;
  @api objectApiName;

  layout;
  record;
  error;

  @wire(getLayout, { objectApiName: "$objectApiName", layoutType: "Compact", mode: "View" })
  wiredLayout({ data, error }) {
    if (data) this.layout = data;
    if (error) this.report(error);
  }

  // Only the layout's fields, asked for by name (optional, so one the user
  // can't read is left out, not an error). The layout comes first.
  get layoutFields() {
    if (!this.layout) return undefined;
    const names = new Set();
    for (const section of this.layout.sections ?? []) {
      for (const row of section.layoutRows ?? []) {
        for (const item of row.layoutItems ?? []) {
          for (const c of item.layoutComponents ?? []) {
            if (c.componentType === "Field" && c.apiName) names.add(`${this.objectApiName}.${c.apiName}`);
          }
        }
      }
    }
    return [...names];
  }

  @wire(getRecord, { recordId: "$recordId", optionalFields: "$layoutFields" })
  wiredRecord({ data, error }) {
    if (data) this.record = data;
    if (error) this.report(error);
  }

  // Setup or error, in the page's SLDS (see illustrationUrl).
  get errorIllustrationUrl() {
    return illustrationUrl(ASSETS, illustrationState(this.error?.kind), this.template.host);
  }
  // Plain words for the user; the technical summary (never a stack trace)
  // to the console.
  report(error) {
    this.error = describeError(error);
    console.warn(`Time Trail details: ${this.error.kind} error.`, this.error.detail);
  }

  get isLoading() {
    return !this.error && (!this.layout || !this.record);
  }
  // Layout items in order; a field the user can't see isn't in the record
  // and is left out.
  get fields() {
    if (!this.layout || !this.record) return [];
    const values = this.record.fields ?? {};
    const out = [];
    for (const section of this.layout.sections ?? []) {
      for (const row of section.layoutRows ?? []) {
        for (const item of row.layoutItems ?? []) {
          const names = (item.layoutComponents ?? [])
            .filter((c) => c.componentType === "Field" && c.apiName)
            .map((c) => c.apiName);
          const shown = names.filter((name) => name in values);
          if (!item.label || shown.length === 0) continue;
          const value = shown
            .map((name) => textOf(values, name))
            .filter((v) => v !== null && v !== undefined && v !== "")
            .join(" ");
          out.push({ key: `${item.label}-${shown.join(",")}`, label: item.label, value: value || "—" });
        }
      }
    }
    return out;
  }
  get hasFields() {
    return this.fields.length > 0;
  }
}
