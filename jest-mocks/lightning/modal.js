// lightning/modal isn't stubbed by sfdx-lwc-jest: a base class with open and close.
// close behaves as Salesforce's does: it does nothing while disableClose is set,
// and otherwise records what it was given in LightningModal.closed.
import { LightningElement } from "lwc";

export default class LightningModal extends LightningElement {
  static open = jest.fn();
  static closed = [];
  disableClose = false;
  close = (result) => {
    if (this.disableClose) return;
    LightningModal.closed.push(result);
  };
}
