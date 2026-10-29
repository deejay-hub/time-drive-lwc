import { LightningElement, api } from "lwc";

// A doc's blocks, ready to draw (see present() in Time Drive Setup's
// markdown.js): headings, paragraphs, lists, notes, code, images, rules.
export default class TimeDriveDocBlocks extends LightningElement {
  @api blocks = [];
}
