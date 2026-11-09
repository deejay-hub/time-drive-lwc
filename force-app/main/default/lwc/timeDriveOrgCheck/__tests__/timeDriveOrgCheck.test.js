import { createElement } from "lwc";
import TimeDriveOrgCheck from "c/timeDriveOrgCheck";
import LightningModal from "lightning/modal";
import getOrgCheckSteps from "@salesforce/apex/TimeDriveSetupController.getOrgCheckSteps";
import runOrgCheck from "@salesforce/apex/TimeDriveSetupController.runOrgCheck";
import quickStart from "@salesforce/apex/TimeDriveSetupController.quickStart";

jest.mock("@salesforce/apex/TimeDriveSetupController.getOrgCheckSteps", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeDriveSetupController.runOrgCheck", () => ({ default: jest.fn() }), { virtual: true });
jest.mock("@salesforce/apex/TimeDriveSetupController.quickStart", () => ({ default: jest.fn() }), { virtual: true });

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const flushes = (n) => (n > 0 ? flush().then(() => flushes(n - 1)) : Promise.resolve());

function mount() {
  const element = createElement("c-time-drive-org-check", { is: TimeDriveOrgCheck });
  document.body.appendChild(element);
  return element;
}

describe("c-time-drive-org-check", () => {
  beforeEach(() => {
    // No waiting between ticks.
    window.matchMedia = jest.fn(() => ({ matches: true }));
    getOrgCheckSteps.mockResolvedValue([
      { key: "SharedActivities", label: "Shared Activities" },
      { key: "PersonAccounts", label: "Person Accounts" }
    ]);
    runOrgCheck.mockImplementation(({ key }) =>
      Promise.resolve(
        key === "SharedActivities"
          ? {
              key,
              present: true,
              found: "On",
              setting: "Allow Users to Relate Multiple Contacts to Tasks and Events",
              settingWhere: "Setup › Activity Settings",
              meaning: "Tasks can have several contacts.",
              adds: ["Contact Tasks"]
            }
          : { key, present: false, found: "Off", meaning: "There are no Person Accounts.", adds: [] }
      )
    );
    quickStart.mockResolvedValue({
      added: [
        { key: "Tasks_Every", label: "Tasks (every contact)", parentObject: "Contact" },
        { key: "Events", label: "Events", parentObject: "Contact" }
      ],
      switched: []
    });
  });
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    delete window.matchMedia;
    jest.clearAllMocks();
  });

  it("says what it will do first, then ticks each check off in turn and says which features are in use", async () => {
    const element = mount();
    const root = element.shadowRoot;
    // The popup is the same height at every stage; the start pads with the component's own mark.
    expect(root.querySelector(".frame")).not.toBeNull();
    expect(root.querySelector(".art img").getAttribute("src")).toMatch(/logo\/time-drive\.svg$/);
    expect(root.querySelector(".intro-lede").textContent).toContain("is Tailored to you");
    // Three steps say what happens: check, see, add.
    expect([...root.querySelectorAll(".step-title")].map((n) => n.textContent)).toEqual([
      "We check how your org is set up",
      "We'll give you a summary",
      "We'll get you set up quickly"
    ]);
    expect(runOrgCheck).not.toHaveBeenCalled();

    root.querySelector("lightning-button.start").click();
    await flushes(12);
    expect(runOrgCheck.mock.calls.map((c) => c[0].key)).toEqual(["SharedActivities", "PersonAccounts"]);

    // One line each: the feature, and whether it is in use. Nothing about the sources.
    const cards = [...root.querySelectorAll(".check-card")];
    expect(cards.map((c) => c.querySelector(".check-card-title").textContent)).toEqual([
      "Shared Activities",
      "Person Accounts"
    ]);
    expect(cards[0].querySelector(".check-badge_on").textContent).toBe("On");
    expect(cards[1].querySelector(".check-badge").textContent).toBe("Off");
    expect(cards[0].textContent).not.toContain("Tasks can have several contacts.");
    expect(root.querySelector(".summary-title").textContent).toBe("What we found");
    expect(root.textContent).not.toContain("We added");
    // The recommended sources were still added without asking.
    expect(quickStart).toHaveBeenCalledWith({ parentObject: null });
    expect(root.querySelector("lightning-button.start")).toBeNull();
    expect(root.querySelector("lightning-button.done")).not.toBeNull();
  });

  it("Done closes it with the report once it has checked (close is blocked while it is checking)", async () => {
    LightningModal.closed.length = 0;
    const element = mount();
    const root = element.shadowRoot;
    root.querySelector("lightning-button.start").click();
    await flushes(12);

    root.querySelector("lightning-button.done").click();
    expect(LightningModal.closed).toHaveLength(1);
    const report = LightningModal.closed[0];
    expect(report.checks.map((c) => c.key)).toEqual(["SharedActivities", "PersonAccounts"]);
    expect(report.checks[0]).toMatchObject({ found: "On", present: true });
    expect(report.added).toBeUndefined();
  });

  it("closes with nothing from the start when cancelled", () => {
    LightningModal.closed.length = 0;
    const element = mount();
    element.shadowRoot.querySelector("lightning-button:not(.start)").click();
    expect(LightningModal.closed).toEqual([undefined]);
  });

  it("says so when the recommended sources couldn't be added", async () => {
    quickStart.mockRejectedValue({ body: { message: "No access." } });
    const element = mount();
    const root = element.shadowRoot;
    root.querySelector("lightning-button.start").click();
    await flushes(12);
    expect(root.querySelector(".notice-title").textContent).toBe("The recommended sources couldn't be added");
    // What was found still shows.
    expect(root.querySelectorAll(".check-card")).toHaveLength(2);
  });
});
