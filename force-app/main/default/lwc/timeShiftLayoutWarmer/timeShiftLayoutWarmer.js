/**
 * Asks for an object's compact layout, and shows nothing. Lightning Data
 * Service keeps the answer, so when an item of that object is expanded its
 * details already have the layout and only wait for the record.
 */
import { LightningElement, api, wire } from "lwc";
import { getLayout } from "lightning/uiLayoutApi";

export default class TimeShiftLayoutWarmer extends LightningElement {
  @api objectApiName;

  // The same request the details make (same object, type and mode), so
  // they share one cache entry. Failures are the details' to report.
  @wire(getLayout, { objectApiName: "$objectApiName", layoutType: "Compact", mode: "View" })
  layout() {}
}
