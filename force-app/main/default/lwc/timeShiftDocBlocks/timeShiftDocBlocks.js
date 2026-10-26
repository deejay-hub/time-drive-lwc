import { LightningElement, api } from "lwc";

// A doc's blocks, ready to draw (see present() in Time Trail Setup's
// markdown.js): headings, paragraphs, lists, notes, code, images, rules.
export default class TimeShiftDocBlocks extends LightningElement {
  @api blocks = [];
}
