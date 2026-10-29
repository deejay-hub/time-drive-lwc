/**
 * A question before something is done, as Salesforce asks it: a title, the
 * question, Cancel and the action's own name ("Delete", "Remove"). Used
 * instead of LightningConfirm, whose buttons can't be renamed.
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

  handleCancel() {
    this.close(false);
  }

  handleConfirm() {
    this.close(true);
  }
}
