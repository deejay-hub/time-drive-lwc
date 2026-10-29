/**
 * Checking the org, as a popup from Setup: what we'll do, a checklist ticked
 * off one real check at a time, then what was found and what that means. The
 * recommended sources are added as soon as the checks are done; closing it
 * hands Setup the report (what each check found, and what was added).
 */
import LightningModal from "lightning/modal";
import { api } from "lwc";
import ASSETS from "@salesforce/resourceUrl/timeDriveAssets";
import getOrgCheckSteps from "@salesforce/apex/TimeDriveSetupController.getOrgCheckSteps";
import runOrgCheck from "@salesforce/apex/TimeDriveSetupController.runOrgCheck";
import getTemplates from "@salesforce/apex/TimeDriveSetupController.getTemplates";
import quickStart from "@salesforce/apex/TimeDriveSetupController.quickStart";
import { describeError } from "c/timeDriveErrors";

// How long a finished check shows before the next starts, so each tick is seen.
const CHECK_PAUSE = 450;
const PAGE_LABELS = { Contact: "Contact", Account: "Account", PersonAccount: "Person Account" };

export default class TimeDriveOrgCheck extends LightningModal {
  // Shown in the header.
  @api label = "Check your org";

  // The component's own mark (the same drawing as its icon in App Builder).
  logoUrl = `${ASSETS}/logo/time-drive.svg`;

  stage = "intro";
  checks = [];
  added = [];
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
      settingWhere: result.settingWhere,
      meaning: result.meaning,
      adds: result.adds ?? []
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

  // The recommended sources, added without asking; what was added is listed.
  async addRecommended() {
    const templates = await getTemplates({ parentObject: null });
    const toAdd = templates.filter((t) => !t.added);
    this.added = [];
    if (!toAdd.length) return;
    try {
      await quickStart({ parentObject: null });
    } catch (e) {
      this.addError = describeError(e);
      return;
    }
    const groups = [];
    for (const t of toAdd) {
      let group = groups.find((g) => g.page === t.parentObject);
      if (!group) {
        group = { page: t.parentObject, label: PAGE_LABELS[t.parentObject] ?? t.parentObject, items: [] };
        groups.push(group);
      }
      group.items.push({ key: t.key, label: t.label });
    }
    this.added = groups;
  }

  addError;

  get rows() {
    return this.checks.map((st) => ({
      ...st,
      className: `check-row check-row_${st.state}`,
      isRunning: st.state === "running",
      isDone: st.state === "done",
      badgeClass: `check-badge${st.present ? " check-badge_on" : ""}${st.unknown ? " check-badge_unknown" : ""}`,
      hasAdds: (st.adds ?? []).length > 0,
      // "Added" once we have added sources; "Adds" for what a setting would bring.
      addsLabel: this.hasAdded ? "Added" : "Adds",
      addsText: (st.adds ?? []).join(", ")
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

  get addedCount() {
    return this.added.reduce((n, g) => n + g.items.length, 0);
  }

  // The block above the findings: what was added, or why it couldn't be.
  get showAdded() {
    return this.hasAdded || Boolean(this.addError);
  }

  get hasAdded() {
    return this.addedCount > 0;
  }

  get addedText() {
    const n = this.addedCount;
    const pages = this.added.length;
    return `${n} ${n === 1 ? "source" : "sources"} on ${pages} record ${pages === 1 ? "page" : "pages"}`;
  }

  // What Setup keeps: a brief report of what was found and added.
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
      added: this.added.map((g) => ({ page: g.page, label: g.label, items: g.items.map((i) => i.label) })),
      error: this.addError?.message
    });
  }
}
