/**
 * Checking the org, as a popup from Setup: what we'll do, a checklist ticked
 * off one real check at a time, then what was found and what that means. The
 * recommended sources are added as soon as the checks are done, and where a
 * setting changed since the last check, a source is switched for the variant
 * that fits now, so the same records are never plotted twice. The summary
 * says which features are in use; closing it hands Setup that report.
 */
import LightningModal from "lightning/modal";
import { api } from "lwc";
import ASSETS from "@salesforce/resourceUrl/timeDriveAssets";
import getOrgCheckSteps from "@salesforce/apex/TimeDriveSetupController.getOrgCheckSteps";
import runOrgCheck from "@salesforce/apex/TimeDriveSetupController.runOrgCheck";
import quickStart from "@salesforce/apex/TimeDriveSetupController.quickStart";
import { describeError } from "c/timeDriveErrors";

// How long a finished check shows before the next starts, so each tick is seen.
const CHECK_PAUSE = 450;

export default class TimeDriveOrgCheck extends LightningModal {
  // Shown in the header.
  @api label = "Check your org";

  // The component's own mark (the same drawing as its icon in App Builder).
  logoUrl = `${ASSETS}/logo/time-drive.svg`;

  stage = "intro";
  checks = [];
  error;

  get isIntro() {
    return this.stage === "intro";
  }

  get isRunning() {
    return this.stage === "running";
  }

  get isSummary() {
    return this.stage === "summary";
  }

  handleCancel() {
    this.close(undefined);
  }

  async handleStart() {
    this.stage = "running";
    this.error = undefined;
    // Closing now would leave a check half done.
    this.disableClose = true;
    try {
      const steps = await getOrgCheckSteps();
      this.checks = steps.map((st) => ({
        key: st.key,
        label: st.label,
        setting: st.setting,
        settingWhere: st.settingWhere,
        state: "waiting"
      }));
      await this.runFrom(0);
      await this.addRecommended();
    } catch (e) {
      this.error = describeError(e);
      this.disableClose = false;
      this.stage = "intro";
      return;
    }
    // Done, and the header's close, work again: close does nothing while it is set.
    this.disableClose = false;
    this.stage = "summary";
  }

  // One at a time, so each tick is a real check done.
  async runFrom(index) {
    if (index >= this.checks.length) return;
    this.setCheck(index, { state: "running" });
    const result = await runOrgCheck({ key: this.checks[index].key });
    await this.pause(CHECK_PAUSE);
    this.setCheck(index, {
      state: "done",
      present: result.present,
      unknown: result.unknown,
      found: result.found,
      setting: result.setting,
      settingWhere: result.settingWhere
    });
    await this.runFrom(index + 1);
  }

  setCheck(index, patch) {
    this.checks = this.checks.map((st, i) => (i === index ? { ...st, ...patch } : st));
  }

  pause(ms) {
    const reduced = typeof window !== "undefined" && window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    return new Promise((resolve) => setTimeout(resolve, reduced ? 0 : ms));
  }

  // The recommended sources, added (and switched for the variant that fits) without asking.
  async addRecommended() {
    try {
      await quickStart({ parentObject: null });
    } catch (e) {
      this.addError = describeError(e);
    }
  }

  addError;

  get rows() {
    return this.checks.map((st) => ({
      ...st,
      className: `check-row check-row_${st.state}`,
      isRunning: st.state === "running",
      isDone: st.state === "done",
      badgeClass: `check-badge${st.present ? " check-badge_on" : ""}${st.unknown ? " check-badge_unknown" : ""}`
    }));
  }

  get progressStyle() {
    const done = this.checks.filter((st) => st.state === "done").length;
    return `width: ${this.checks.length ? Math.round((done / this.checks.length) * 100) : 0}%`;
  }

  get progressText() {
    const done = this.checks.filter((st) => st.state === "done").length;
    return `${done} of ${this.checks.length} checked`;
  }

  // What Setup keeps: a brief report of what was found.
  handleDone() {
    this.close({
      checks: this.checks.map((st) => ({
        key: st.key,
        label: st.label,
        found: st.found,
        setting: st.setting,
        present: st.present === true,
        unknown: st.unknown === true
      })),
      error: this.addError?.message
    });
  }
}
