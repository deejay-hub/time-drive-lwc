// lightning-illustration (beta) isn't in sfdx-lwc-jest's stubs yet: a stand-in
// that keeps its two attributes, so templates using it render.
import { LightningElement, api } from "lwc";

export default class Illustration extends LightningElement {
  @api illustrationName;
  @api alternativeText;
}
