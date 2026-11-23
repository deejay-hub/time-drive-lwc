// lightning-select isn't in sfdx-lwc-jest's stubs: a stand-in that keeps its
// attributes, so templates using it render and tests can read and set them.
import { LightningElement, api } from "lwc";

export default class Select extends LightningElement {
  @api label;
  @api name;
  @api options;
  @api value;
  @api variant;
  @api disabled;
  @api required;
  @api multiple;
  @api focus() {}
}
