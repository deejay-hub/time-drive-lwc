// lightning/modal isn't stubbed by sfdx-lwc-jest: a base class with open and close.
import { LightningElement } from "lwc";

export default class LightningModal extends LightningElement {
  static open = jest.fn();
  close = jest.fn();
}
