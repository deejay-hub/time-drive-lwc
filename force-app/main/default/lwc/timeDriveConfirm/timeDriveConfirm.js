/**
 * A question before something is done, as Salesforce asks it: a title, the
 * question, Cancel and the action's own name ("Delete", "Remove"). Used
 * instead of LightningConfirm, whose buttons can't be renamed. With an
 * acknowledgement, a box to tick says it was read: the action waits for it.
 */
import LightningModal from "lightning/modal";
import { api } from "lwc";
import { LABELS } from "c/timeDriveLabels";

export default class TimeDriveConfirm extends LightningModal {
  @api title;
  @api message;
  @api confirmLabel = "OK";
  // Cancel, in the user's language.
  @api cancelLabel = LABELS.filtersCancel;
  // What the person confirms by ticking the box; none, no box.
  @api acknowledgement;

  acknowledged = false;

  // A short question sits centred; a longer note to read and tick, from the left.
  get messageClass() {
    return this.acknowledgement ? "message message_note" : "message";
  }

  get confirmDisabled() {
    return Boolean(this.acknowledgement) && !this.acknowledged;
  }

  handleAcknowledge(event) {
    this.acknowledged = event.target.checked;
  }

  handleCancel() {
    this.close(false);
  }

  handleConfirm() {
    this.close(true);
  }
}
