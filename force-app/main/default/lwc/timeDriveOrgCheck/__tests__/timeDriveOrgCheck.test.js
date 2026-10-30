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

  it("says what it will do first, then ticks each check off in turn and reports what it found and added", async () => {
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

    const cards = [...root.querySelectorAll(".check-card")];
    expect(cards.map((c) => c.querySelector(".check-card-title").textContent)).toEqual([
      "Shared Activities",
      "Person Accounts"
    ]);
    expect(cards[0].textContent).toContain("Tasks can have several contacts.");
    expect(cards[0].querySelector(".check-badge_on").textContent).toBe("On");
    // The exact setting, where it is, and which way it is (the badge).
    expect(cards[0].querySelector(".check-card-setting").textContent).toBe(
      "Allow Users to Relate Multiple Contacts to Tasks and Events"
    );
    expect(cards[0].querySelector(".check-card-where").textContent).toBe("Setup › Activity Settings");
    expect(cards[0].querySelector(".check-card-adds").textContent).toContain("Contact Tasks");
    expect(cards[0].querySelector(".check-card-adds-label").textContent).toBe("Added");
    // The recommended sources were added without asking.
    expect(quickStart).toHaveBeenCalledWith({ parentObject: null });
    expect(root.querySelector(".check-add .summary-title").textContent).toBe("We added 2 sources on 1 record page");
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
    expect(report.added).toEqual([{ page: "Contact", label: "Contact", items: ["Tasks (every contact)", "Events"] }]);
  });

  it("closes with nothing from the start when cancelled", () => {
    LightningModal.closed.length = 0;
    const element = mount();
    element.shadowRoot.querySelector("lightning-button:not(.start)").click();
    expect(LightningModal.closed).toEqual([undefined]);
  });

  it("adds nothing when everything recommended is already there", async () => {
    quickStart.mockResolvedValue({ added: [], switched: [] });
    const element = mount();
    const root = element.shadowRoot;
    root.querySelector("lightning-button.start").click();
    await flushes(12);
    // Asked every time: a setting may have changed since the last check.
    expect(quickStart).toHaveBeenCalledWith({ parentObject: null });
    // Nothing new to add: no "We added" heading, and the cards say "Adds" not "Added".
    expect(root.querySelector(".check-add .summary-title")).toBeNull();
    expect(root.querySelector(".check-card-adds-label").textContent).toBe("Adds");
  });

  it("says which sources it switched for the variant that fits now, and reports them", async () => {
    LightningModal.closed.length = 0;
    quickStart.mockResolvedValue({
      added: [],
      switched: [{ parentObject: "Contact", offLabel: "Tasks", onLabel: "Tasks (every contact)", onKey: "Tasks_Every" }]
    });
    const element = mount();
    const root = element.shadowRoot;
    root.querySelector("lightning-button.start").click();
    await flushes(12);
    const block = root.querySelector(".check-switch");
    expect(block.querySelector(".summary-title").textContent).toBe("We switched 1 source to fit your org");
    expect(block.textContent).toContain("nothing shows twice");
    expect(block.querySelector(".check-add-page").textContent).toBe("Contact");
    expect(block.querySelector(".badge_off").textContent).toBe("Tasks");
    expect(block.querySelector(".badge:not(.badge_off)").textContent).toBe("Tasks (every contact)");

    root.querySelector("lightning-button.done").click();
    expect(LightningModal.closed[0].switched).toEqual([
      { page: "Contact", offLabel: "Tasks", onLabel: "Tasks (every contact)" }
    ]);
  });
});
