import { createElement } from "lwc";
import TimeDriveSetup from "c/timeDriveSetup";
import getProgress from "@salesforce/apex/TimeDriveSetupController.getProgress";
import saveProgress from "@salesforce/apex/TimeDriveSetupController.saveProgress";
import getSources from "@salesforce/apex/TimeDriveSetupController.getSources";
import getProblems from "@salesforce/apex/TimeDriveSetupController.getProblems";
import clearProblems from "@salesforce/apex/TimeDriveSetupController.clearProblems";
import getSource from "@salesforce/apex/TimeDriveSetupController.getSource";
import getObjects from "@salesforce/apex/TimeDriveSetupController.getObjects";
import getDataSpaces from "@salesforce/apex/TimeDriveSetupController.getDataSpaces";
import getData360Status from "@salesforce/apex/TimeDriveSetupController.getData360Status";
import getFields from "@salesforce/apex/TimeDriveSetupController.getFields";
import getLinks from "@salesforce/apex/TimeDriveSetupController.getLinks";
import setActive from "@salesforce/apex/TimeDriveSetupController.setActive";
import setLenses from "@salesforce/apex/TimeDriveSetupController.setLenses";
import save from "@salesforce/apex/TimeDriveSetupController.save";
import TimeDriveConfirm from "c/timeDriveConfirm";
import saveViews from "@salesforce/apex/TimeDriveSetupController.saveViews";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import getLabelText from "@salesforce/apex/TimeDriveSetupController.getLabelText";
import TimeDriveOrgCheck from "c/timeDriveOrgCheck";

jest.mock("@salesforce/apex/TimeDriveSetupController.getProgress", () => ({ default: jest.fn() }), { virtual: true });
jest.mock("@salesforce/apex/TimeDriveSetupController.saveProgress", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeDriveSetupController.getSources", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeDriveSetupController.getSource", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeDriveSetupController.getObjects", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeDriveSetupController.getDataSpaces", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeDriveSetupController.getData360Status", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeDriveSetupController.getApexProviders", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeDriveSetupController.getLinks", () => ({ default: jest.fn() }), { virtual: true });
jest.mock("@salesforce/apex/TimeDriveSetupController.getFields", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeDriveSetupController.getLabelText", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeDriveSetupController.getVolumes", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeDriveSetupController.getProblems", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeDriveSetupController.clearProblems", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeDriveSetupController.save", () => ({ default: jest.fn() }), { virtual: true });

jest.mock(
  "@salesforce/apex/TimeDriveSetupController.getViewDrafts",
  () => ({
    default: jest.fn(() =>
      Promise.resolve([
        {
          developerName: "All",
          name: "All",
          labelName: "Time_Drive_View_All",
          shown: "All items",
          active: true
        },
        {
          developerName: "Commerce",
          name: "Commerce",
          labelName: "Time_Drive_View_Commerce",
          shown: "Commerce",
          active: true
        },
        {
          developerName: "Marketing",
          name: "Marketing",
          labelName: "Time_Drive_View_Marketing",
          shown: "Marketing",
          active: true
        }
      ])
    )
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TimeDriveSetupController.saveViews",
  () => ({ default: jest.fn(() => Promise.resolve({ developerName: "Views" })) }),
  { virtual: true }
);
jest.mock("@salesforce/apex/TimeDriveSetupController.remove", () => ({ default: jest.fn() }), { virtual: true });
jest.mock("@salesforce/apex/TimeDriveSetupController.setLenses", () => ({ default: jest.fn() }), { virtual: true });
jest.mock(
  "@salesforce/apex/TimeDriveSetupController.getTemplates",
  () => ({ default: jest.fn(() => Promise.resolve([])) }),
  {
    virtual: true
  }
);
jest.mock("@salesforce/apex/TimeDriveSetupController.useTemplate", () => ({ default: jest.fn() }), { virtual: true });
jest.mock("@salesforce/apex/TimeDriveSetupController.quickStart", () => ({ default: jest.fn() }), { virtual: true });
jest.mock("@salesforce/apex/TimeDriveSetupController.getOrgCheckSteps", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeDriveSetupController.runOrgCheck", () => ({ default: jest.fn() }), { virtual: true });
jest.mock("@salesforce/apex/TimeDriveSetupController.setActive", () => ({ default: jest.fn() }), {
  virtual: true
});
const SOURCES = [
  {
    developerName: "Order_Placed",
    parentObject: "Contact",
    type: "custom",
    objectName: "Invoice__c",
    label: "Order placed",
    kind: "Salesforce",
    active: true,
    category: "Commerce",
    summary: "Customer Order records whose Customer is this Contact, dated by Order Time."
  },
  {
    developerName: "Data_360_Email",
    parentObject: "Contact",
    type: "dmo",
    label: "Email",
    kind: "Data 360",
    active: false,
    category: "Marketing",
    summary: "Email Engagement records for this Contact's unified profile."
  }
];

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

// Several turns of the event loop, one after another.
const flushes = (n) => (n > 0 ? flush().then(() => flushes(n - 1)) : Promise.resolve());

// Setup opens on its home page straight away; this lets the first reads land.
const splash = () => flushes(4);
// A wizard step's reads and render (nothing in the tests needs real time).
const wait = () => flushes(4);

// The menu's Customize: the record pages.
async function toPages(root) {
  root.querySelector('.site-link[data-to="pages"]').click();
  await flush();
}

function mount() {
  const element = createElement("c-time-drive-setup", { is: TimeDriveSetup });
  document.body.appendChild(element);
  return element;
}

describe("c-time-drive-setup", () => {
  beforeEach(() => {
    getProgress.mockResolvedValue({ steps: ["orgcheck"], report: null });
    saveProgress.mockResolvedValue();
    // The question before something is done: answered yes.
    TimeDriveConfirm.open = jest.fn(() => Promise.resolve(true));
    getSources.mockResolvedValue(SOURCES);
    getDataSpaces.mockResolvedValue([]);
    getData360Status.mockResolvedValue({ ready: true });
    getProblems.mockResolvedValue([]);
    clearProblems.mockResolvedValue();
  });
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  const crumbs = (root) => [...root.querySelectorAll(".crumb-link, .crumb-here")].map((c) => c.textContent);

  it("lists what failed on record pages at the top of Guided setup, and clears it", async () => {
    getProblems.mockResolvedValue([
      {
        sourceKey: SOURCES[0].developerName,
        source: SOURCES[0].label,
        kind: "access",
        cause: "A field this source uses doesn't exist, or the user can't see it.",
        errorType: "System.QueryException",
        message: "No such column 'Due__c' on entity 'Task'",
        count: 3,
        lastSeen: "2026-11-21T10:00:00.000Z"
      },
      { sourceKey: null, source: null, kind: "busy", cause: "Too much to read.", count: 1 }
    ]);
    const element = mount();
    await splash();
    const root = element.shadowRoot;
    const card = root.querySelector(".kd-card_problems");
    expect(card.querySelector("h2").textContent).toBe("Problems");
    const rows = card.querySelectorAll(".kd-row_problem");
    expect(rows).toHaveLength(2);
    // A source that still exists opens; the error is there on hover.
    expect(rows[0].tagName).toBe("BUTTON");
    expect(rows[0].dataset.name).toBe(SOURCES[0].developerName);
    expect(rows[0].title).toBe("System.QueryException: No such column 'Due__c' on entity 'Task'");
    expect(rows[0].textContent).toContain("A field this source uses doesn't exist");
    expect(rows[0].textContent).toContain("3 times");
    // A whole request that failed: named as such, nothing to open.
    expect(rows[1].tagName).toBe("DIV");
    expect(rows[1].textContent).toContain("Loading the timeline");
    expect(rows[1].textContent).toContain("Once");

    [...card.querySelectorAll("button.ghost")].find((b) => b.textContent.trim() === "Clear").click();
    await flush();
    expect(clearProblems).toHaveBeenCalled();
    expect(root.querySelector(".kd-card_problems")).toBeNull();
  });

  it("shows no Problems card when nothing has failed", async () => {
    const element = mount();
    await splash();
    expect(element.shadowRoot.querySelector(".kd-card_problems")).toBeNull();
    expect(getProblems).toHaveBeenCalled();
  });

  it("welcomes a new org with nothing but Get started, which checks the org in a popup and then opens Setup", async () => {
    getProgress.mockResolvedValue({ steps: [], report: null });
    getSources.mockResolvedValue([]);
    const report = {
      checks: [
        { key: "SharedActivities", label: "Shared Activities", found: "On", present: true, unknown: false },
        { key: "PersonAccounts", label: "Person Accounts", found: "Off", present: false, unknown: false }
      ],
      added: [{ page: "Contact", label: "Contact", items: ["Tasks (every contact)", "Events"] }]
    };
    TimeDriveOrgCheck.open = jest.fn(() => Promise.resolve(report));
    const element = mount();
    await splash();
    const root = element.shadowRoot;
    // No menu, no other page: the product, a welcome and one button.
    expect(root.querySelector(".site-link")).toBeNull();
    expect(root.querySelector(".welcome-logo")).not.toBeNull();
    expect(root.querySelector("h1.page-title").textContent).toBe("Welcome to Time Drive");
    expect(root.querySelectorAll(".welcome button")).toHaveLength(1);

    root.querySelector(".welcome-start").click();
    await flushes(4);
    expect(TimeDriveOrgCheck.open).toHaveBeenCalled();
    // The org has it: the step and the report are kept for every admin.
    expect(saveProgress).toHaveBeenCalledWith({ steps: ["orgcheck"], report: JSON.stringify(report) });

    // Closing the popup lands on Setup, with the menu open.
    expect(root.querySelector(".welcome")).toBeNull();
    expect(root.querySelector("h1.page-title").textContent).toBe("Guided setup");
    expect([...root.querySelectorAll(".site-link")].map((l) => l.textContent.trim())).toEqual([
      "Setup",
      "Customize",
      "Lenses",
      "Docs"
    ]);
    // Step 1 is the check, done, and says briefly what was found and added.
    expect([...root.querySelectorAll(".guided-step")].map((st) => st.dataset.key).slice(0, 3)).toEqual([
      "orgcheck",
      "video",
      "perms"
    ]);
    const step = root.querySelector('.guided-step[data-key="orgcheck"]');
    expect(step.classList.contains("guided-step_done")).toBe(true);
    expect([...step.querySelectorAll(".guided-report li")].map((li) => li.textContent)).toEqual([
      "Shared Activities: On",
      "Person Accounts: Off"
    ]);
    // The aside says in a sentence what the settings mean for the timeline.
    root.querySelector('.guided-step[data-key="orgcheck"] .guided-text').click();
    await flush();
    const parts = [...root.querySelectorAll(".guided-aside .guided-aside-part")];
    expect(parts.map((p) => p.querySelector(".guided-aside-head").textContent)).toEqual([
      "What it did",
      "Why it matters",
      "What it meant for your sources"
    ]);
    expect(parts[2].querySelector("p").textContent).toBe(
      "Because of what is on in your org, tasks and events include every contact on them, and emails come from email tasks."
    );
  });

  it("stays on the welcome page unless the org says the check is done", async () => {
    getProgress.mockResolvedValue({ steps: [], report: null });
    // Sources of its own don't make the check done: only the org's record of it does.
    getSources.mockResolvedValue([{ developerName: "Mine", parentObject: "Contact", label: "Mine", active: true }]);
    TimeDriveOrgCheck.open = jest.fn(() => Promise.resolve({ checks: [], added: [] }));
    saveProgress.mockRejectedValueOnce({ body: { message: "No access" } });
    const element = mount();
    await splash();
    const root = element.shadowRoot;
    expect(root.querySelector(".welcome")).not.toBeNull();
    root.querySelector(".welcome-start").click();
    await flushes(4);
    // It couldn't be kept: not done, still the welcome page, no menu.
    expect(root.querySelector(".welcome")).not.toBeNull();
    expect(root.querySelector(".site-link")).toBeNull();
  });

  it("stays on the welcome page when the popup is closed before checking", async () => {
    getProgress.mockResolvedValue({ steps: [], report: null });
    getSources.mockResolvedValue([]);
    TimeDriveOrgCheck.open = jest.fn(() => Promise.resolve(undefined));
    const element = mount();
    await splash();
    const root = element.shadowRoot;
    root.querySelector(".welcome-start").click();
    await flushes(4);
    expect(root.querySelector(".welcome")).not.toBeNull();
    expect(root.querySelector(".site-link")).toBeNull();
    expect(saveProgress).not.toHaveBeenCalled();
  });

  it("opens on Setup once the org is checked, with every step enabled, and lets the check be run again", async () => {
    TimeDriveOrgCheck.open = jest.fn(() => Promise.resolve({ checks: [], added: [] }));
    const element = mount();
    await splash();
    const root = element.shadowRoot;
    expect(root.querySelector(".welcome")).toBeNull();
    expect(root.querySelector("h1.page-title").textContent).toBe("Guided setup");
    // Nothing waits for anything (the steps' order has its own test).
    expect(root.querySelector('.guided-step[data-key="views"] .guided-button').disabled).toBe(false);
    expect(root.querySelector('.guided-step[data-key="views"] .guided-check').disabled).toBeFalsy();

    const again = root.querySelector('.guided-step[data-key="orgcheck"] .guided-button');
    expect(again.textContent.trim()).toBe("Check again");
    again.click();
    await flushes(4);
    expect(TimeDriveOrgCheck.open).toHaveBeenCalledTimes(1);
  });

  it("opens on Setup; Customize leads to the record pages, then one's own page", async () => {
    const element = mount();
    await splash();
    const root = element.shadowRoot;
    // The menu: Setup, Customize, Lenses and Docs.
    expect(root.querySelector(".crumbs")).toBeNull();
    expect([...root.querySelectorAll(".site-link")].map((l) => l.textContent.trim())).toEqual([
      "Setup",
      "Customize",
      "Lenses",
      "Docs"
    ]);
    expect(root.querySelector('.site-link[data-to="setup"]').getAttribute("aria-current")).toBe("page");
    expect(root.querySelector("h1.page-title").textContent).toBe("Guided setup");
    // In order: the org check, the video, permission sets, the lenses, what's
    // set up, your users' access, and the record pages.
    expect([...root.querySelectorAll(".guided-step")].map((st) => st.dataset.key)).toEqual([
      "orgcheck",
      "video",
      "perms",
      "views",
      "review",
      "users",
      "page"
    ]);
    // The org check is done.
    expect(root.querySelector(".guided-count-number").textContent).toBe("1 of 7");
    expect(root.querySelector(".guided-progress_done")).toBeNull();
    expect(root.querySelector(".guided-step_on .guided-title").textContent.trim()).toBe("Watch the how-to video");
    // What the users must be able to read, and which record pages need it.
    expect(root.querySelector('.guided-step[data-key="users"] .guided-status').textContent).toContain("Invoice__c");
    expect(
      [...root.querySelectorAll('.guided-step[data-key="page"] .guided-button')].map((b) => b.textContent.trim())
    ).toEqual(["Contact pages"]);
    // A done step still shows its help, from anywhere on its row.
    root.querySelector('.guided-step[data-key="orgcheck"] .guided-text').click();
    await flush();
    expect(root.querySelector(".guided-aside .aside-title").textContent).toBe("Check your org");
    expect(root.querySelector(".guided-aside-step").textContent).toBe("Step 1 · Done");
    expect(root.querySelector(".guided-aside-head").textContent).toBe("What it did");

    const tick = async (key) => {
      const box = root.querySelector(`.guided-check[data-key="${key}"]`);
      box.checked = true;
      box.dispatchEvent(new CustomEvent("change"));
      await flush();
    };
    await tick("video");
    expect(root.querySelector(".guided-count-number").textContent).toBe("2 of 7");
    for (const key of ["perms", "review", "users", "page"]) await tick(key);
    // Lenses: a question and a button to them, ticked by you. (They're managed
    // on the Lenses page.)
    expect(root.querySelector('.guided-step[data-key="views"] .guided-text').textContent).toBe(
      "Have you reviewed the categories for your lenses?"
    );
    expect(root.querySelector('.guided-step[data-key="views"] .guided-button').textContent.trim()).toBe("Open Lenses");
    await tick("views");
    // All done: the bar says so.
    expect(root.querySelector(".guided-progress_done")).not.toBeNull();
    expect(root.querySelector(".guided-count-number").textContent).toBe("Setup complete");
    expect(root.querySelectorAll(".guided-segment_done")).toHaveLength(7);

    await toPages(root);
    expect(crumbs(root)).toEqual([]);
    expect(root.querySelector('.site-link[data-to="pages"]').getAttribute("aria-current")).toBe("page");
    // Person Account pages stay out of sight until the timeline uses Person
    // Accounts.
    const pages = [...root.querySelectorAll("button.pcard")];
    expect(pages.map((c) => c.querySelector(".pcard-name").textContent)).toEqual(["Contact", "Account", "Lead"]);
    expect(pages[0].querySelector(".pcard-count").textContent).toBe("2 sources · 1 active");

    pages[0].click();
    await flush();
    expect(crumbs(root)).toEqual(["Customize", "Contact"]);
    expect(root.querySelector("button.pcard")).toBeNull();
    expect(root.querySelector(".page-title").textContent).toBe("Contact timeline");
    // One list, no groups by type.
    expect([...root.querySelectorAll(".row-name")].map((n) => n.textContent)).toEqual(["Order placed", "Email"]);
    expect(root.querySelector(".row-summary").textContent).toContain("whose Customer is this Contact");
    expect(root.querySelector(".row_off .badge_off").textContent).toBe("Inactive");

    // The breadcrumb goes back.
    root.querySelector('.crumb-link[data-to="pages"]').click();
    await flush();
    expect(root.querySelector("button.pcard")).not.toBeNull();
  });

  it("opens a source as its own page, under its record page", async () => {
    getSource.mockResolvedValue({ developerName: "Order_Placed", historyMonths: 12, title: "Order placed" });
    const element = mount();
    await splash();
    const root = element.shadowRoot;
    await toPages(root);
    root.querySelector("button.pcard").click();
    await flush();
    root.querySelector('.row-main[data-name="Order_Placed"]').click();
    await flush();
    expect(crumbs(root)).toEqual(["Customize", "Contact", "Order placed"]);
    expect(root.querySelector(".page-title").textContent).toBe("Order placed");
    expect([...root.querySelectorAll(".fact dt")].map((d) => d.textContent)).not.toContain("Looks back");
    expect(root.querySelector(".head-toggle").checked).toBe(true);

    root.querySelector('.crumb-link[data-to="parent"]').click();
    await flush();
    expect(root.querySelector(".page-title").textContent).toBe("Contact timeline");
  });

  it("names the fields an opened item shows, in order, a label of its own first", async () => {
    getFields.mockResolvedValue([
      { name: "Name", label: "Order Number", type: "string", filterable: true, values: [] },
      { name: "Status__c", label: "Status", type: "string", filterable: true, values: [] },
      { name: "Order_Time__c", label: "Order Time", type: "datetime", filterable: true, values: [] }
    ]);
    getLinks.mockResolvedValue([
      { key: "Customer__c", parentField: "Customer__c", label: "Orders whose Customer is this Contact" }
    ]);
    getSource.mockResolvedValue({
      developerName: "Order_Placed",
      label: "Order placed",
      kind: "Salesforce",
      parentObject: "Contact",
      objectName: "Invoice__c",
      parentField: "Customer__c",
      dateField: "Order_Time__c",
      title: "Order placed",
      active: true,
      details: [
        { field: "Status__c", label: "", format: "Text" },
        { field: "Name", label: "Invoice", format: "Text" }
      ]
    });
    const element = mount();
    await splash();
    const root = element.shadowRoot;
    await toPages(root);
    root.querySelector("button.pcard").click();
    await flush();
    root.querySelector('.row-main[data-name="Order_Placed"]').click();
    await splash();
    const opened = [...root.querySelectorAll(".fact")].find(
      (f) => f.querySelector("dt")?.textContent === "When it is opened"
    );
    expect(opened.querySelector("dd").textContent.trim()).toBe("Status, Invoice");
  });

  it("shows a source's link, date, filter and interactions on its page", async () => {
    getFields.mockResolvedValue([
      { name: "Name", label: "Order Number", type: "string", filterable: true, values: [] },
      { name: "Status__c", label: "Status", type: "string", filterable: true, values: [] },
      { name: "Order_Time__c", label: "Order Time", type: "datetime", filterable: true, values: [] }
    ]);
    getLinks.mockResolvedValue([
      { key: "Customer__c", parentField: "Customer__c", label: "Orders whose Customer is this Contact" }
    ]);
    getSource.mockResolvedValue({
      developerName: "Order_Placed",
      label: "Order placed",
      kind: "Salesforce",
      parentObject: "Contact",
      objectName: "Invoice__c",
      parentField: "Customer__c",
      dateField: "Order_Time__c",
      conditions: [{ field: "Status__c", operator: "notEquals", value: "Canceled", valueType: "text" }],
      title: "Order placed",
      active: true,
      details: []
    });
    const element = mount();
    await splash();
    const root = element.shadowRoot;
    await toPages(root);
    root.querySelector("button.pcard").click();
    await flush();
    root.querySelector('.row-main[data-name="Order_Placed"]').click();
    await splash();
    const facts = Object.fromEntries(
      [...root.querySelectorAll(".fact")]
        .filter((f) => f.querySelector("dt") && f.querySelector("dd"))
        .map((f) => [f.querySelector("dt").textContent, f.querySelector("dd").textContent.trim()])
    );
    expect(facts["Linked to the Contact by"]).toBe("Orders whose Customer is this Contact");
    expect(facts["Plotted by date"]).toBe("Order Time");
    expect(facts["Only the records where"]).toBe("Status isn't Canceled");
    expect(facts["When it is opened"]).toBe("No fields");
    expect(facts["When its title is clicked"]).toBe("Its own record");
    // One diagram of the interactions: the opened item, then where a click lands.
    expect(facts.Interactions).toBeDefined();
    expect(root.querySelector(".fact_preview .mock-page")).not.toBeNull();
    // The opened item and the page it opens share one column, so one width.
    expect(root.querySelector(".fact-preview-stack .mock-item")).not.toBeNull();
    expect(root.querySelector(".fact-preview-stack .mock-page")).not.toBeNull();
  });

  it("lets you pick a typed name after trying a custom label", async () => {
    getObjects.mockResolvedValue([{ value: "Invoice__c", label: "Invoice", detail: "Invoice__c" }]);
    getSource.mockResolvedValue({
      developerName: "Order_Placed",
      label: "Order placed",
      kind: "Salesforce",
      parentObject: "Contact",
      objectName: "Invoice__c",
      parentField: "Customer__c",
      dateField: "Order_Time__c",
      eventLabel: "Orders",
      title: "Order placed",
      active: true,
      details: []
    });
    getFields.mockResolvedValue([
      { name: "Name", label: "Order Number", type: "string", filterable: true, values: [] },
      { name: "Order_Time__c", label: "Order Time", type: "datetime", filterable: true, values: [] }
    ]);
    getLinks.mockResolvedValue([
      { key: "Customer__c", parentField: "Customer__c", label: "Orders whose Customer is this Contact" }
    ]);
    const element = mount();
    await splash();
    const root = element.shadowRoot;
    await toPages(root);
    root.querySelector("button.pcard").click();
    await flush();
    root.querySelector('.row-main[data-name="Order_Placed"]').click();
    await flush();
    root.querySelector(".head-actions .primary").click();
    await flush();
    await flush();
    root.querySelector('.knot-button[data-step="name"]').click();
    await flush();
    const checked = () => root.querySelector(".tune .options .option_on")?.dataset.value;
    // Open on the typed name it was saved with.
    expect(checked()).toBe("text");

    // Try a custom label (still nothing typed), then go back to typing: the
    // first click must take.
    root.querySelector('.tune .option[data-value="label"]').click();
    await flush();
    expect(checked()).toBe("label");
    root.querySelector('.tune .option[data-value="text"]').click();
    await flush();
    expect(checked()).toBe("text");
    expect(root.querySelector(".legend-name-input")).not.toBeNull();

    // The X clears the choice: nothing is selected, and it has to be made again.
    root.querySelector(".tune .link-close").click();
    await flush();
    expect(checked()).toBeUndefined();
    expect(root.querySelector(".legend-name-input")).toBeNull();
    expect(root.querySelector(".foot-hint").textContent).toContain("Choose how to name it to continue.");
    expect(root.querySelector(".wz-foot .primary").disabled).toBe(true);
    root.querySelector('.tune .option[data-value="auto"]').click();
    await flush();
    expect(checked()).toBe("auto");
  });

  it("names a junction source after the object it joins", async () => {
    getObjects.mockResolvedValue([{ value: "TaskRelation", label: "Task Relation", detail: "TaskRelation" }]);
    getSource.mockResolvedValue({
      developerName: "Order_Placed",
      label: "Task Relations",
      kind: "Salesforce",
      parentObject: "Contact",
      objectName: "TaskRelation",
      parentField: "RelationId",
      dateField: "Task.ActivityDate",
      title: "{Task.Subject}",
      active: true,
      details: []
    });
    getFields.mockResolvedValue([
      {
        name: "TaskId",
        label: "Task ID",
        type: "reference",
        referenceTo: "Task",
        relationshipName: "Task",
        referenceLabel: "Task",
        referencePlural: "Tasks",
        values: []
      },
      {
        name: "CreatedById",
        label: "Created By ID",
        type: "reference",
        referenceTo: "User",
        relationshipName: "CreatedBy",
        referenceLabel: "User",
        referencePlural: "Users",
        values: []
      }
    ]);
    getLinks.mockResolvedValue([
      { key: "RelationId", parentField: "RelationId", label: "Task Relations whose Relation is this Contact" }
    ]);
    const element = mount();
    await splash();
    const root = element.shadowRoot;
    await toPages(root);
    root.querySelector("button.pcard").click();
    await flush();
    root.querySelector('.row-main[data-name="Order_Placed"]').click();
    await flush();
    root.querySelector(".head-actions .primary").click();
    await flush();
    await flush();
    root.querySelector('.knot-button[data-step="name"]').click();
    await flush();
    const checked = () => root.querySelector(".tune .options .option_on")?.dataset.value;

    // The object's own name, or the object it joins: not who created it.
    root.querySelector('.tune .option[data-value="related"]').click();
    await flush();
    expect(checked()).toBe("related");
    const chips = [...root.querySelectorAll('.chips[aria-label="The related object to name it after"] button')];
    expect(chips.map((c) => c.textContent.trim())).toEqual(["Tasks"]);
    expect(chips[0].getAttribute("aria-pressed")).toBe("true");
    expect(root.querySelector(".legend-row_mine .legend-name").textContent).toBe("Tasks");
  });

  describe("a junction source's related record", () => {
    const task = [
      { name: "Subject", label: "Subject", type: "string", filterable: true, values: [] },
      { name: "ActivityDate", label: "Due Date", type: "date", filterable: true, values: [] },
      {
        name: "TaskSubtype",
        label: "Task Subtype",
        type: "picklist",
        filterable: true,
        values: [
          { value: "Call", label: "Call" },
          { value: "Email", label: "Email" }
        ]
      }
    ];
    const relation = [
      { name: "CreatedDate", label: "Created Date", type: "datetime", filterable: true, values: [] },
      {
        name: "TaskId",
        label: "Task ID",
        type: "reference",
        filterable: true,
        referenceTo: "Task",
        relationshipName: "Task",
        referenceLabel: "Task",
        referencePlural: "Tasks",
        values: []
      }
    ];

    async function openStep(
      step,
      draft = {},
      fieldsFor = ({ objectName }) => (objectName === "Task" ? task : relation)
    ) {
      getObjects.mockResolvedValue([{ value: "TaskRelation", label: "Task Relation", detail: "TaskRelation" }]);
      getSource.mockResolvedValue({
        developerName: "Order_Placed",
        label: "Task Relations",
        kind: "Salesforce",
        parentObject: "Contact",
        objectName: "TaskRelation",
        parentField: "RelationId",
        dateField: "CreatedDate",
        title: "{Task.Subject}",
        active: true,
        details: [],
        ...draft
      });
      getFields.mockImplementation((args) => Promise.resolve(fieldsFor(args)));
      getLinks.mockResolvedValue([
        { key: "RelationId", parentField: "RelationId", label: "Task Relations whose Relation is this Contact" }
      ]);
      const element = mount();
      await splash();
      const root = element.shadowRoot;
      await toPages(root);
      root.querySelector("button.pcard").click();
      await flush();
      root.querySelector('.row-main[data-name="Order_Placed"]').click();
      await flush();
      root.querySelector(".head-actions .primary").click();
      await flush();
      await flush();
      root.querySelector(`.knot-button[data-step="${step}"]`).click();
      await flush();
      return root;
    }

    const names = (root) =>
      [...root.querySelectorAll("c-time-drive-field-picker")].flatMap((p) =>
        [...p.shadowRoot.querySelectorAll(".token-result")].map((b) => b.dataset.name)
      );
    const settle = async () => {
      await flush();
      await flush();
    };

    it("picks a date from one box: the object's own, or a related record's through a lookup in the list", async () => {
      const root = await openStep("date");
      // The box shows the date it opened with.
      expect(root.querySelector(".picker-input").value).toBe("Created Date");
      expect(root.querySelector(".related-date")).toBeNull();

      root.querySelector(".picker-input").click();
      await flush();
      // Its own dates, then the lookup that leads to more.
      const rows = [...root.querySelectorAll(".result")].map((r) => r.querySelector(".result-label").textContent);
      expect(rows).toContain("Created Date");
      expect(rows.at(-1)).toBe("Task ›");
      expect(root.querySelector(".result:last-child .result-detail").textContent).toBe("A date on the related Task");
      root.querySelector(".result:last-child").click();
      await settle();
      const picker = root.querySelector("c-time-drive-field-picker");
      expect(picker).not.toBeNull();
      expect(picker.closest(".date-pick")).not.toBeNull();
      // Straight to the task's dates, none of its other fields.
      expect(names(root)).toEqual(["ActivityDate"]);
      picker.shadowRoot.querySelector('.token-result[data-name="ActivityDate"]').click();
      await settle();
      expect(root.querySelector("c-time-drive-field-picker")).toBeNull();
      expect(root.querySelector(".picker-input").value).toBe("Task › Due Date");
    });

    it("lets an Apex source highlight by a key it types, and saves it", async () => {
      const root = await openStep("open", {
        kind: "Apex",
        providerClass: "MemoItemSource",
        objectName: null,
        parentField: null,
        dateField: null,
        title: null,
        details: [{ field: "Status__c", label: "", format: "Text" }],
        highlights: [{ field: "", icon: "utility:flag", colour: "#DD7A01" }]
      });
      await settle();
      // No fields to list for a class: a box to type the key in.
      const input = root.querySelector("lightning-input.highlight-field");
      expect(input).not.toBeNull();
      expect(root.querySelector("lightning-combobox.highlight-field")).toBeNull();
      input.dispatchEvent(new CustomEvent("change", { detail: { value: "Flagged__c" } }));
      await settle();
      TimeDriveConfirm.open.mockResolvedValueOnce(true);
      root.querySelector(".wz-foot .save").click();
      await settle();
      const sent = JSON.parse(save.mock.calls.at(-1)[0].draftJson);
      expect(sent.highlights[0].field).toBe("Flagged__c");
    });

    it("asks an Apex source's admin to vouch for how it scales before it's saved", async () => {
      const root = await openStep("open", {
        kind: "Apex",
        providerClass: "TimeDriveOpportunityProducts",
        objectName: null,
        parentField: null,
        dateField: null,
        title: null,
        details: [{ field: "Quantity", label: "", format: "Number" }]
      });
      await settle();
      // Cancelled (or not ticked): nothing is saved.
      TimeDriveConfirm.open.mockResolvedValueOnce(false);
      root.querySelector(".wz-foot .save").click();
      await settle();
      expect(TimeDriveConfirm.open).toHaveBeenCalledWith(
        expect.objectContaining({
          title: "Before you save an Apex source",
          confirmLabel: "Save",
          acknowledgement: expect.stringContaining("scales and performs")
        })
      );
      expect(TimeDriveConfirm.open.mock.calls.at(-1)[0].message).toContain("TimeDriveOpportunityProducts");
      expect(save).not.toHaveBeenCalled();
      // Ticked and confirmed: saved.
      TimeDriveConfirm.open.mockResolvedValueOnce(true);
      root.querySelector(".wz-foot .save").click();
      await settle();
      expect(save).toHaveBeenCalledTimes(1);
    });

    it("gives the title and subtitle one field each: a choice replaces the one there, and × takes it off", async () => {
      const plain = [
        { name: "CreatedDate", label: "Created Date", type: "datetime", filterable: true, values: [] },
        { name: "Subject", label: "Subject", type: "string", filterable: true, values: [] },
        { name: "Status", label: "Status", type: "picklist", filterable: true, values: [] }
      ];
      const root = await openStep("look", { title: "", subtitle: "" }, () => plain);
      await settle();
      const choice = (field) => root.querySelector(`.field-choice[data-field="${field}"] .field-choice-name`);
      // None yet: the title shows the source's name, the subtitle nothing.
      expect(choice("title").textContent).toBe("None: its name");
      expect(choice("subtitle").textContent).toBe("None");
      expect(root.querySelector('.field-clear[data-field="title"]')).toBeNull();
      // No box to type in.
      expect(root.querySelector(".word-input")).toBeNull();

      const pick = async (field, index) => {
        root.querySelector(`.field-choice[data-field="${field}"]`).click();
        await settle();
        const picker = root.querySelector("c-time-drive-field-picker");
        // A plain field, not a lookup that leads on.
        const result = [...picker.shadowRoot.querySelectorAll(".token-result")].filter(
          (b) => !b.querySelector(".token-go")
        )[index];
        const label = result.querySelector("span").textContent;
        result.click();
        await settle();
        return label;
      };
      const first = await pick("title", 0);
      expect(choice("title").textContent).toBe(first);
      const second = await pick("title", 1);
      // The second takes the first's place: one field, never two.
      expect(second).not.toBe(first);
      expect(choice("title").textContent).toBe(second);
      expect(root.querySelectorAll(".sample-title .token")).toHaveLength(1);

      root.querySelector('.field-clear[data-field="title"]').click();
      await settle();
      expect(choice("title").textContent).toBe("None: its name");
    });

    it("says when a title or subtitle field is long or rich text, and will be shortened", async () => {
      const fields = [
        { name: "CreatedDate", label: "Created Date", type: "datetime", filterable: true, values: [] },
        { name: "Subject", label: "Subject", type: "string", filterable: true, values: [], length: 255 },
        { name: "Notes__c", label: "Notes", type: "textarea", filterable: false, values: [], length: 32768 },
        { name: "Body__c", label: "Body", type: "textarea", filterable: false, values: [], length: 32768, html: true },
        { name: "Code__c", label: "Code", type: "string", filterable: true, values: [], length: 20 }
      ];
      const root = await openStep("look", { title: "{Notes__c}", subtitle: "{Code__c} · {Body__c}" }, () => fields);
      await settle();
      const notes = [...root.querySelectorAll(".word-field .word-note")].map((n) => n.textContent);
      expect(notes).toContain("Long text: shown cut to 150 characters.");
      expect(notes).toContain("Rich text: shown as plain words, up to 150 characters.");
    });

    it("gives the subtitle up to two fields, read with a dot between them", async () => {
      const plain = [
        { name: "CreatedDate", label: "Created Date", type: "datetime", filterable: true, values: [] },
        { name: "Subject", label: "Subject", type: "string", filterable: true, values: [] },
        { name: "Status", label: "Status", type: "picklist", filterable: true, values: [] }
      ];
      const root = await openStep("look", { title: "{Subject}", subtitle: "" }, () => plain);
      await settle();
      const choice = (field) => root.querySelector(`.field-choice[data-field="${field}"] .field-choice-name`);
      // No first field yet: no second to add.
      expect(root.querySelector('.field-choice[data-field="subtitle2"]')).toBeNull();

      const pick = async (field, name) => {
        root.querySelector(`.field-choice[data-field="${field}"]`).click();
        await settle();
        const picker = root.querySelector("c-time-drive-field-picker");
        picker.shadowRoot.querySelector(`.token-result[data-name="${name}"]`).click();
        await settle();
      };
      await pick("subtitle", "Status");
      expect(choice("subtitle").textContent).toBe("Status");
      expect(choice("subtitle2").textContent).toBe("Add a second field");
      await pick("subtitle2", "CreatedDate");
      expect(choice("subtitle2").textContent).toBe("Created Date");
      // The sample reads both, a dot between.
      expect([...root.querySelectorAll(".sample-sub .token")].map((t) => t.textContent)).toEqual([
        "Status",
        "Created Date"
      ]);
      expect(root.querySelector(".sample-sub").textContent).toContain("·");

      // Taking the first off moves the second up.
      root.querySelector('.field-clear[data-field="subtitle"]').click();
      await settle();
      expect(choice("subtitle").textContent).toBe("Created Date");
      expect(choice("subtitle2").textContent).toBe("Add a second field");
    });

    it("lays out the look: the icon preview with the title and subtitle beside it, the pickers side by side below", async () => {
      const root = await openStep("look", { icon: "utility:record", iconColour: "#0B5CAB" });
      await settle();
      const card = root.querySelector(".sample");
      // Top left the icon; top right the title and subtitle, to write.
      expect(card.firstElementChild.classList.contains("node_large")).toBe(true);
      expect(card.querySelector(".sample-body .sample-text")).not.toBeNull();
      expect([...card.querySelectorAll(".word-label")].map((l) => l.textContent)).toEqual(["Title", "Subtitle"]);
      // Underneath, the icon and the colour, as two panels of one row.
      const look = root.querySelector(".look");
      expect(card.contains(look)).toBe(false);
      expect(card.compareDocumentPosition(look) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
      expect([...look.querySelectorAll(":scope > .look-panel h3")].map((h) => h.textContent)).toEqual([
        "Icon",
        "Colour"
      ]);
    });

    it("offers the object's own icon and colour, and puts them back after they're changed", async () => {
      // A TaskRelation's items are tasks: they wear the Task's icon and colour.
      const root = await openStep("look", { icon: "utility:record", iconColour: "#0B5CAB" });
      await settle();
      expect(root.querySelector(".look-restore")).toBeNull();
      getObjectInfo.emit({
        apiName: "Task",
        label: "Task",
        themeInfo: {
          color: "4BC076",
          iconUrl: "https://example.my.salesforce.com/img/icon/t4v35/standard/task_120.png"
        }
      });
      await settle();
      // Different from what's chosen: the way back is offered.
      const restore = root.querySelector(".look-restore lightning-button");
      expect(restore).not.toBeNull();
      expect(restore.label).toBe("Use Task's icon and colour");
      restore.click();
      await settle();
      expect(root.querySelector(".look-current").textContent).toContain("standard:task");
      // Salesforce's green is too light for the white icon: darkened until it can be seen.
      const chip = root.querySelector(".node_large").getAttribute("style");
      expect(chip).toMatch(/--chip: #[0-9A-F]{6}/);
      expect(chip).not.toContain("#4BC076");
      expect(root.querySelector(".look-restore")).toBeNull();
      // Choosing another icon is the person's: the button returns.
      root.querySelector('.icon-choice[data-value="utility:email"], .icons button:not(.icon-choice_on)').click();
      await settle();
      expect(root.querySelector(".look-restore")).not.toBeNull();
    });

    it("fixes a file's opening and click: its chosen fields, and the file preview", async () => {
      const root = await openStep("open", {
        objectName: "ContentDocumentLink",
        parentField: "LinkedEntityId",
        dateField: "ContentDocument.CreatedDate",
        title: "{ContentDocument.Title}",
        useCompactLayout: true,
        recordIdField: null,
        details: [{ field: "ContentDocument.Title", label: "", format: "Text" }]
      });
      await settle();
      // Opening: fields only. Nothing to choose between, so no options, no layouts.
      expect(root.querySelector('[aria-label="What opening an item shows"]')).toBeNull();
      // A click: the file preview, as the one answer, and no way to take it back.
      const clicks = [...root.querySelectorAll('[aria-label="What a click opens"] .option')];
      expect(clicks.map((o) => o.dataset.value)).toEqual(["file"]);
      expect(root.textContent).toContain("The file preview");
      expect(root.querySelector(".link-chosen .link-close")).toBeNull();
      expect(root.textContent).not.toContain("A related record");
    });

    it("says it's access, not dates, when none of the object's fields can be read", async () => {
      const root = await openStep("date", { objectName: "Claim", dateField: null }, () => []);
      await settle();
      root.querySelector(".picker-input").click();
      await flush();
      const text = [...root.querySelectorAll("p.quiet")].map((p) => p.textContent).join(" ");
      expect(text).toContain("can't read any of");
      expect(text).toContain("read access");
      expect(text).not.toContain("no date fields");
    });

    it("reads a saved related date's label once the related fields are in", async () => {
      const root = await openStep("date", { dateField: "Task.ActivityDate" });
      await settle();
      expect(root.querySelector(".picker-input").value).toBe("Task › Due Date");
    });

    it("filters on a field of the related record, picked object first", async () => {
      const root = await openStep("object");
      root.querySelector('.option[data-value="some"]').click();
      await flush();
      const field = root.querySelector(".condition-field");
      expect(field.options.map((o) => o.label)).toEqual(["Created Date", "Task ID", "A field on a related record…"]);
      field.dispatchEvent(new CustomEvent("change", { detail: { value: "__related__" } }));
      await settle();
      const picker = root.querySelector("c-time-drive-field-picker");
      expect(picker).not.toBeNull();
      // The list opens from a box of its own, so it has something to hang from.
      expect(picker.closest(".related-filter")).not.toBeNull();
      expect(names(root)).toEqual(["TaskId"]);
      picker.shadowRoot.querySelector('.token-result[data-name="TaskId"]').click();
      await settle();
      picker.shadowRoot.querySelector('.token-result[data-name="TaskSubtype"]').click();
      await settle();
      expect(root.querySelector("c-time-drive-field-picker")).toBeNull();
      const chosen = root.querySelector(".condition-field");
      expect(chosen.value).toBe("Task.TaskSubtype");
      expect(chosen.options.map((o) => o.label)).toContain("Task › Task Subtype");
      // Its values are the task's own, as a picklist.
      expect(root.querySelector(".condition-value lightning-combobox").options.map((o) => o.value)).toEqual([
        "Call",
        "Email"
      ]);
    });
  });

  it("won't go past Look with a colour the white icon can't be seen on", async () => {
    getObjects.mockResolvedValue([{ value: "Invoice__c", label: "Invoice", detail: "Invoice__c" }]);
    getSource.mockResolvedValue({
      developerName: "Order_Placed",
      label: "Order placed",
      kind: "Salesforce",
      parentObject: "Contact",
      objectName: "Invoice__c",
      parentField: "Customer__c",
      dateField: "Order_Time__c",
      title: "Order placed",
      icon: "utility:cart",
      iconColour: "#0B5CAB",
      active: true,
      details: []
    });
    getFields.mockResolvedValue([
      { name: "Name", label: "Order Number", type: "string", filterable: true, values: [] },
      { name: "Order_Time__c", label: "Order Time", type: "datetime", filterable: true, values: [] },
      {
        name: "Customer__c",
        label: "Customer",
        type: "reference",
        referenceTo: "Contact",
        relationshipName: "Customer__r",
        values: []
      },
      {
        name: "Location__c",
        label: "Location",
        type: "reference",
        referenceTo: "Location__c",
        relationshipName: "Location__r",
        values: []
      }
    ]);
    getLinks.mockResolvedValue([
      { key: "Customer__c", parentField: "Customer__c", label: "Orders whose Customer is this Contact" }
    ]);
    save.mockResolvedValue({ developerName: "Order_Placed" });
    const element = mount();
    const toasts = [];
    element.addEventListener("lightning__showtoast", (e) => toasts.push(e.detail));
    await splash();
    const root = element.shadowRoot;
    await toPages(root);
    root.querySelector("button.pcard").click();
    await flush();
    root.querySelector('.row-main[data-name="Order_Placed"]').click();
    await flush();
    root.querySelector(".head-actions .primary").click();
    await flush();
    await flush();
    root.querySelector('.knot-button[data-step="look"]').click();
    await flush();
    const lookQuestion = root.querySelector(".question").textContent;

    // A pale yellow: the white icon on it is about 1.1:1.
    const any = root.querySelector(".look-custom lightning-input");
    any.dispatchEvent(new CustomEvent("change", { detail: { value: "#FFF59D" } }));
    await flush();
    root.querySelector(".wz-foot .primary").click();
    await flush();
    expect(toasts).toHaveLength(1);
    expect(toasts[0]).toMatchObject({ variant: "error", title: "Choose a darker colour" });
    expect(toasts[0].message).toContain("#FFF59D");
    expect(root.querySelector(".question").textContent).toBe(lookQuestion);

    // A palette colour passes, and Next goes on.
    root.querySelector('.swatch[data-value="#014486"]').click();
    await flush();
    root.querySelector(".wz-foot .primary").click();
    await flush();
    expect(toasts).toHaveLength(1);

    // Opening shows the fields chosen here (no compact layouts); a click goes
    // to the item's own record or a related one. The preview shows an opened
    // item with sample values.
    expect(root.querySelector(".question").textContent).toBe("What happens when someone opens or clicks an item?");
    const openTitles = () => [...root.querySelectorAll(".options .option-label")].map((o) => o.textContent);
    expect(openTitles()).toEqual(["Its own record", "A related record"]);
    expect(root.querySelector('[aria-label="What opening an item shows"]')).toBeNull();
    expect(root.querySelector(".details-box")).not.toBeNull();
    expect(root.querySelectorAll(".mock")).toHaveLength(1);
    // Save waits for a field, and a click's choice.
    expect(root.querySelector(".wz-foot .save").disabled).toBe(true);
    expect(root.querySelector(".mock-page")).not.toBeNull();
    expect(root.querySelector(".mock-title").textContent).toBe("Order placed");

    // The same step goes on to a click: its own record or a related one, with
    // where it lands in the same diagram.
    expect(root.querySelector(".mock-title_link")).not.toBeNull();
    root.querySelector('.option[data-value="related"]').click();
    await flush();

    // Opening is the last question: Save takes the place of Next, with Active.
    expect(root.querySelector(".wz-foot .primary")).toBeNull();
    expect(root.querySelector(".wz-foot .save")).not.toBeNull();
    expect(root.querySelector(".switch-on")).not.toBeNull();
    expect(root.querySelector('.knot-button[data-step="review"]')).toBeNull();

    // The Name step: the legend name, the view, and the order in the legend.
    root.querySelector('.knot-button[data-step="name"]').click();
    await flush();
    expect(root.querySelector(".tune")).not.toBeNull();
    // Every source on the page in legend order, this one marked; the name
    // shows live, and a move takes it up a place.
    const legend = () => [...root.querySelectorAll(".legend-row .legend-name")].map((n) => n.textContent);
    // A Salesforce object's legend name is its own (translated) by default.
    expect(legend()).toEqual(["Email", "Invoice"]);
    expect(root.querySelector(".tune .options .option_on").dataset.value).toBe("auto");
    // Typing one instead: the name shows live.
    root.querySelector('.tune .option[data-value="text"]').click();
    await flush();
    const name = root.querySelector(".legend-name-input");
    // A lightning-input reports typing as change, with the text in detail.
    name.dispatchEvent(new CustomEvent("change", { detail: { value: "Orders" } }));
    await flush();
    expect(legend()).toEqual(["Email", "Orders"]);
    expect(root.querySelector(".legend-row_mine .legend-name").textContent).toBe("Orders");
    root.querySelector('.legend-row_mine lightning-button-icon[data-dir="-1"]').click();
    await flush();
    expect(legend()).toEqual(["Orders", "Email"]);
    root.querySelector('.knot-button[data-step="open"]').click();
    await flush();
    // Opening shows chosen fields: Save waits for one.
    expect(root.querySelector(".wz-foot .save").disabled).toBe(true);
    root.querySelector(".details-box lightning-button").click();
    await flush();
    root.querySelector(".detail-field_button").click();
    await flush();
    root
      .querySelector("c-time-drive-field-picker")
      .dispatchEvent(new CustomEvent("pick", { detail: { path: "Status__c", label: "Status", type: "picklist" } }));
    await flush();
    root.querySelector(".wz-foot .save").click();
    await flush();
    const sent = JSON.parse(save.mock.calls[0][0].draftJson);
    expect(sent).toMatchObject({
      details: [expect.objectContaining({ field: "Status__c" })],
      recordIdField: "Location__c",
      iconColour: "#014486",
      eventLabel: "Orders",
      label: "Orders",
      legendOrder: ["__this__", "Data_360_Email"]
    });
  });

  it("links each doc to its page on GitHub, in a new tab, and reads nothing into the org", async () => {
    global.fetch = jest.fn();
    try {
      const element = mount();
      await splash();
      const root = element.shadowRoot;
      root.querySelector('.site-link[data-to="docs"]').click();
      await flush();
      const cards = [...root.querySelectorAll("a.docs-card")];
      expect(cards.map((c) => c.querySelector(".docs-card-title").textContent)).toEqual(["Config Guide", "FAQs"]);
      expect(cards.map((c) => c.getAttribute("href"))).toEqual([
        "https://github.com/deejay-hub/time-drive-lwc/blob/main/docs/config-guide.md",
        "https://github.com/deejay-hub/time-drive-lwc/blob/main/docs/faqs.md"
      ]);
      for (const card of cards) {
        expect(card.getAttribute("target")).toBe("_blank");
        expect(card.getAttribute("rel")).toBe("noopener");
      }
      expect(global.fetch).not.toHaveBeenCalled();
    } finally {
      delete global.fetch;
    }
  });

  it("finds a page's sources by search and by type, in one list", async () => {
    const element = mount();
    await splash();
    const root = element.shadowRoot;
    await toPages(root);
    root.querySelector("button.pcard").click();
    await flush();
    const names = () => [...root.querySelectorAll(".row-name")].map((n) => n.textContent);
    expect(root.querySelector(".group")).toBeNull();
    expect(names()).toEqual(["Order placed", "Email"]);
    expect(
      [...root.querySelectorAll('[aria-label="Source type"] .chip-choice')].map((b) => b.textContent.trim())
    ).toEqual(["All 2", "Standard 0", "Custom 1", "Data 360 DMO 1", "Apex 0"]);

    expect([...root.querySelectorAll('[aria-label="Status"] .chip-choice')].map((b) => b.textContent.trim())).toEqual([
      "Any 2",
      "Active 1",
      "Inactive 1"
    ]);
    root.querySelector('[aria-label="Source type"] .chip-choice[data-value="dmo"]').click();
    await flush();
    expect(names()).toEqual(["Email"]);
    expect(root.querySelector(".source-count").textContent).toBe("Showing 1 of 2 sources");

    // Type and status combine: Data 360 sources that are active — none here.
    root.querySelector('[aria-label="Status"] .chip-choice[data-value="active"]').click();
    await flush();
    expect(root.querySelector(".empty-state_filter")).not.toBeNull();
    root.querySelector('[aria-label="Status"] .chip-choice[data-value="inactive"]').click();
    await flush();
    expect(names()).toEqual(["Email"]);
    // Each pill counts what it would show alongside the others.
    expect(
      [...root.querySelectorAll('[aria-label="Source type"] .chip-choice')].map((b) => b.textContent.trim())
    ).toEqual(["All 1", "Standard 0", "Custom 0", "Data 360 DMO 1", "Apex 0"]);
    root.querySelector('[aria-label="Status"] .chip-choice[data-value="all"]').click();

    root.querySelector('[aria-label="Source type"] .chip-choice[data-value="all"]').click();
    const search = root.querySelector(".source-search input");
    search.value = "commerce";
    search.dispatchEvent(new CustomEvent("input"));
    await flush();
    expect(names()).toEqual(["Order placed"]);

    search.value = "nothing like this";
    search.dispatchEvent(new CustomEvent("input"));
    await flush();
    expect(root.querySelector(".empty-state_filter .problem-title").textContent).toBe("No sources match");
    root.querySelector(".empty-state_filter button").click();
    await flush();
    expect(names()).toEqual(["Order placed", "Email"]);
  });

  describe("the Lenses page", () => {
    const SOURCES_IN_LENSES = [
      {
        developerName: "Order_Placed",
        parentObject: "Contact",
        type: "custom",
        objectName: "Invoice__c",
        objectLabel: "Invoice",
        label: "Order placed",
        legendName: "Orders",
        kind: "Salesforce",
        active: true,
        category: "Commerce",
        lenses: ["Commerce"],
        filter: "Status__c = 'Placed'",
        summary: "Invoice records."
      },
      {
        developerName: "Tasks",
        parentObject: "Contact",
        type: "standard",
        objectName: "Task",
        objectLabel: "Task",
        label: "Tasks",
        legendName: "Task",
        kind: "Salesforce",
        active: false,
        category: "Marketing",
        lenses: ["Marketing"],
        summary: "Task records."
      },
      {
        developerName: "Cases",
        parentObject: "Account",
        type: "standard",
        objectName: "Case",
        objectLabel: "Case",
        label: "Cases",
        legendName: "Cases",
        kind: "Salesforce",
        active: true,
        category: null,
        lenses: [],
        summary: "Case records."
      }
    ];

    async function openLenses() {
      getSources.mockResolvedValue(SOURCES_IN_LENSES);
      const element = mount();
      await splash();
      const root = element.shadowRoot;
      root.querySelector('.site-link[data-to="lenses"]').click();
      await flush();
      await flush();
      return { root };
    }
    const cell = (root, source, lens) =>
      root.querySelector(`.lens-cell lightning-input[data-source="${source}"][data-lens="${lens}"]`);

    it("saves a lens switched off at once, and says so", async () => {
      const { root } = await openLenses();
      const toasts = [];
      root.host.addEventListener("lightning__showtoast", (e) => toasts.push(e.detail));
      const marketing = root.querySelector('lightning-input.lens-active[data-key="Marketing"]');
      marketing.checked = false;
      marketing.dispatchEvent(new CustomEvent("change"));
      await flush();
      await flush();
      expect(saveViews).toHaveBeenLastCalledWith({
        viewsJson: JSON.stringify([
          { developerName: "All", active: true },
          { developerName: "Commerce", active: true },
          { developerName: "Marketing", active: false }
        ])
      });
      expect(toasts.map((t) => t.title)).toContain("Views saved");
      expect(root.querySelector('lightning-input.lens-active[data-key="Marketing"]').checked).toBe(false);
    });

    it("is in the menu, and the guided step opens it", async () => {
      const element = mount();
      await splash();
      const root = element.shadowRoot;
      root.querySelector('.guided-step[data-key="views"] .guided-button').click();
      await flush();
      expect(root.querySelector("h1.page-title").textContent).toBe("Lenses");
      expect(root.querySelector('.site-link[data-to="lenses"]').getAttribute("aria-current")).toBe("page");
      expect(root.querySelector(".crumbs")).toBeNull();
    });

    it("is a grid: the page's sources down the side, the lenses across, a tick where a source is in one", async () => {
      const { root } = await openLenses();
      expect(root.querySelector("h1.page-title").textContent).toBe("Lenses");
      // What the picker will offer, as people see it.
      expect([...root.querySelectorAll(".lens-pill")].map((p) => p.textContent)).toEqual([
        "All items",
        "Commerce",
        "Marketing"
      ]);
      // All is a lens like the others, first; it is always offered, so it has no switch.
      expect([...root.querySelectorAll("thead .lens-col-name")].map((n) => n.textContent)).toEqual([
        "All items",
        "Commerce",
        "Marketing"
      ]);
      expect(root.querySelectorAll("thead lightning-input.lens-active")).toHaveLength(2);
      // The first page's sources, with a tick where each is in a lens; an inactive one says so.
      expect([...root.querySelectorAll("tbody .lens-source-object")].map((n) => n.textContent)).toEqual([
        "Invoice (Orders)",
        "Task"
      ]);
      expect(cell(root, "Order_Placed", "Commerce").checked).toBe(true);
      expect(cell(root, "Order_Placed", "Marketing").checked).toBe(false);
      expect(cell(root, "Tasks", "Marketing").checked).toBe(true);
      // An info icon after each name says its filter, to tell apart sources on one object.
      const filterOf = (name) =>
        [...root.querySelectorAll("tbody .lens-grid-row")]
          .find((r) => r.querySelector(".lens-source-object").textContent === name)
          .querySelector("lightning-helptext.lens-source-filter").content;
      expect(filterOf("Invoice (Orders)")).toBe("Filter: Status__c = 'Placed'");
      expect(filterOf("Task")).toBe("No filter: every record");
      // In a lens of its own, a source is in All only when ticked there.
      expect(cell(root, "Order_Placed", "All").checked).toBe(false);
      expect(root.querySelectorAll("tbody .badge_off")).toHaveLength(1);
      // The record page's tabs switch which sources are listed.
      expect([...root.querySelectorAll(".lens-tab")].map((b) => b.textContent.trim())).toEqual(["Contact", "Account"]);
      root.querySelector('.lens-tab[data-value="Account"]').click();
      await flush();
      expect([...root.querySelectorAll("tbody .lens-source-object")].map((n) => n.textContent)).toEqual([
        "Case (Cases)"
      ]);
      expect(cell(root, "Cases", "Commerce").checked).toBe(false);
      // Renaming is a custom label.
      expect([...root.querySelectorAll(".lens-names a")].map((a) => a.getAttribute("href"))).toEqual([
        "/lightning/setup/ExternalStrings/home",
        "/lightning/setup/LabelWorkbenchTranslate/home"
      ]);
    });

    it("puts a source in a lens as its cell is ticked, in addition to the ones it is in, and saves at once", async () => {
      setLenses.mockResolvedValue({ developerName: "Order_Placed" });
      const { root } = await openLenses();
      const marketing = cell(root, "Order_Placed", "Marketing");
      marketing.checked = true;
      marketing.dispatchEvent(new CustomEvent("change"));
      await flush();
      expect(setLenses).toHaveBeenCalledWith({ developerName: "Order_Placed", lenses: ["Commerce", "Marketing"] });
      expect(cell(root, "Order_Placed", "Commerce").checked).toBe(true);
      expect(cell(root, "Order_Placed", "Marketing").checked).toBe(true);
    });

    it("takes a source out of one lens and leaves the others", async () => {
      setLenses.mockResolvedValue({ developerName: "Tasks" });
      getSources.mockResolvedValue([
        {
          ...SOURCES_IN_LENSES[1],
          active: true,
          category: "Commerce",
          lenses: ["Commerce", "Marketing"]
        }
      ]);
      const element = mount();
      await splash();
      const root = element.shadowRoot;
      root.querySelector('.site-link[data-to="lenses"]').click();
      await flush();
      await flush();
      expect(cell(root, "Tasks", "Commerce").checked).toBe(true);
      expect(cell(root, "Tasks", "Marketing").checked).toBe(true);
      const commerce = cell(root, "Tasks", "Commerce");
      commerce.checked = false;
      commerce.dispatchEvent(new CustomEvent("change"));
      await flush();
      expect(setLenses).toHaveBeenCalledWith({ developerName: "Tasks", lenses: ["Marketing"] });
    });

    it("takes a tick back when the save fails, and says so", async () => {
      setLenses.mockRejectedValue({ body: { message: "No access" } });
      const { root } = await openLenses();
      const toasts = [];
      root.host.addEventListener("lightning__showtoast", (e) => toasts.push(e.detail));
      const marketing = cell(root, "Order_Placed", "Marketing");
      marketing.checked = true;
      marketing.dispatchEvent(new CustomEvent("change"));
      await flush();
      await flush();
      expect(cell(root, "Order_Placed", "Marketing").checked).toBe(false);
      expect(toasts).toHaveLength(1);
      expect(toasts[0]).toMatchObject({ variant: "error", message: "No access" });
      expect(toasts[0].title).toMatch(/couldn't be changed$/);
    });
  });

  it("switches a source off in place and waits for the save", async () => {
    let finish;
    setActive.mockReturnValue(
      new Promise((resolve) => {
        finish = () => resolve({ developerName: "Order_Placed" });
      })
    );
    const element = mount();
    await splash();
    await toPages(element.shadowRoot);
    element.shadowRoot.querySelector("button.pcard").click();
    await flush();
    const toggle = element.shadowRoot.querySelector('lightning-input[data-name="Order_Placed"]');
    toggle.checked = false;
    toggle.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(setActive).toHaveBeenCalledWith({ developerName: "Order_Placed", active: false });
    expect(element.shadowRoot.querySelector(".pending").textContent).toContain("Making inactive");

    // The save lands while the list is still being read again: the row shows
    // the new state at once, not the old one for a moment.
    getSources.mockReturnValue(new Promise(() => {}));
    finish();
    await flush();
    expect(element.shadowRoot.querySelector(".pending")).toBeNull();
    expect(element.shadowRoot.querySelector('lightning-input[data-name="Order_Placed"]').checked).toBe(false);
  });

  it("starts a Files source named with its custom label, chosen, and takes that back for another object", async () => {
    getObjects.mockResolvedValue([
      { value: "ContentDocumentLink", label: "Content Document Link", detail: "Linked by Linked Entity" },
      { value: "Case", label: "Case", detail: "Linked by Contact" }
    ]);
    getFields.mockResolvedValue([
      { name: "CreatedDate", label: "Created Date", type: "datetime", filterable: true, values: [] },
      { name: "SystemModstamp", label: "System Modstamp", type: "datetime", filterable: true, values: [] }
    ]);
    getLinks.mockResolvedValue([
      { key: "LinkedEntityId", parentField: "LinkedEntityId", label: "Files linked to this Contact" }
    ]);
    getLabelText.mockResolvedValue("Files & Notes");
    const element = mount();
    await flush();
    const root = element.shadowRoot;
    await splash();
    await toPages(root);
    root.querySelector("button.pcard").click();
    await flush();
    root.querySelector(".page-head .primary").click();
    await flush();
    root.querySelector('.option[data-value="standard"]').click();
    await wait();
    root.querySelector(".wz-foot .primary").click();
    await wait();
    const pickObject = async (term) => {
      const search = root.querySelector(".picker-input");
      search.value = term;
      search.dispatchEvent(new CustomEvent("input"));
      await flush();
      search.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }));
      await wait();
    };
    const toName = async () => {
      root.querySelector(".wz-foot .primary").click();
      await wait();
      // A file starts with its date answered; any other object asks for one.
      root.querySelector(".result")?.click();
      await flush();
      root.querySelector(".wz-foot .primary").click();
      await wait();
      // Past the lenses, which are optional.
      root.querySelector(".wz-foot .primary").click();
      await wait();
    };
    await pickObject("content");
    root.querySelector(".wz-foot .primary").click();
    await wait();
    // Dated by when the document was created, already.
    expect(root.querySelector(".picker-input").value).toBe("Content Document › Created Date");
    root.querySelector(".wz-foot .primary").click();
    await wait();
    // The lenses come before the name: none is needed.
    expect(root.querySelector(".question").textContent).toBe("Which lenses should it be part of?");
    root.querySelector(".wz-foot .primary").click();
    await wait();
    const checked = () => root.querySelector(".tune .options .option_on")?.dataset.value;
    // Chosen already: "A custom label", with its API name and what it reads as.
    expect(checked()).toBe("label");
    expect(root.querySelector(".custom-label-input").value).toBe("Time_Drive_Legend_Files");
    expect(getLabelText).toHaveBeenCalledWith({ name: "Time_Drive_Legend_Files" });
    expect(root.querySelector(".legend-row_mine .legend-name").textContent).toBe("Files & Notes");
    // And the file icon's colour (darkened to be seen), not the grey of nothing chosen.
    expect(root.querySelector(".legend-row_mine .chip").getAttribute("style")).toMatch(/--chip: #[0-9A-F]{6}/);

    // Back to the object: another one takes the choice back.
    root.querySelector('.knot-button[data-step="object"]').click();
    await flush();
    await pickObject("case");
    await toName();
    expect(checked()).toBeUndefined();
  });

  it("starts a Task filtered to Calls or Emails on that kind's custom label, and takes it back when the filter goes", async () => {
    getObjects.mockResolvedValue([{ value: "Task", label: "Task", detail: "Linked by Name" }]);
    getFields.mockResolvedValue([
      { name: "ActivityDate", label: "Due Date", type: "date", filterable: true, values: [] },
      {
        name: "TaskSubtype",
        label: "Task Subtype",
        type: "picklist",
        filterable: true,
        values: [
          { label: "Call", value: "Call" },
          { label: "Email", value: "Email" }
        ]
      }
    ]);
    getLinks.mockResolvedValue([{ key: "WhoId", parentField: "WhoId", label: "Tasks for this Contact" }]);
    getLabelText.mockImplementation(({ name }) =>
      Promise.resolve(name === "Time_Drive_Legend_Calls" ? "Calls" : "Emails")
    );
    const element = mount();
    await flush();
    const root = element.shadowRoot;
    await splash();
    await toPages(root);
    root.querySelector("button.pcard").click();
    await flush();
    root.querySelector(".page-head .primary").click();
    await flush();
    root.querySelector('.option[data-value="standard"]').click();
    await wait();
    root.querySelector(".wz-foot .primary").click();
    await wait();
    const search = root.querySelector(".picker-input");
    search.value = "task";
    search.dispatchEvent(new CustomEvent("input"));
    await flush();
    search.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }));
    await wait();
    // Only some of them: the ones whose subtype is Call.
    root.querySelector('[aria-label="Which records"] .option[data-value="some"]').click();
    await flush();
    const change = async (selector, value) => {
      root.querySelector(selector).dispatchEvent(new CustomEvent("change", { detail: { value } }));
      await flush();
    };
    await change(".condition-field", "TaskSubtype");
    const toName = async () => {
      root.querySelector(".wz-foot .primary").click();
      await wait();
      root.querySelector(".result")?.click();
      await flush();
      root.querySelector(".wz-foot .primary").click();
      await wait();
      root.querySelector(".wz-foot .primary").click();
      await wait();
    };
    const label = () => root.querySelector(".tune .options .option_on")?.dataset.value;
    const backToFilter = async () => {
      root.querySelector('.knot-button[data-step="object"]').click();
      await flush();
    };

    await change(".condition-value lightning-combobox", "Call");
    await toName();
    expect(label()).toBe("label");
    expect(root.querySelector(".custom-label-input").value).toBe("Time_Drive_Legend_Calls");

    await backToFilter();
    await change(".condition-value lightning-combobox", "Email");
    await toName();
    expect(root.querySelector(".custom-label-input").value).toBe("Time_Drive_Legend_Emails");

    // No kind in the filter any more: nothing is chosen for it.
    await backToFilter();
    root.querySelector(".condition lightning-button-icon[data-index='0']").click();
    await flush();
    await toName();
    expect(label()).toBeUndefined();

    // One of several values: the picklist's values to tick.
    await backToFilter();
    root.querySelector('[aria-label="Which records"] .option[data-value="some"]').click();
    await flush();
    await change(".condition-field", "TaskSubtype");
    await change(".condition-op", "oneOf");
    const values = root.querySelector(".condition-values");
    expect(values.options.map((o) => o.value)).toEqual(expect.arrayContaining(["Call", "Email"]));
    await change(".condition-values", ["Call", "Email"]);
    expect(root.querySelector(".conditions-match")).toBeNull();

    // A second condition: all of them, or any.
    root.querySelector(".box-actions lightning-button").click();
    await flush();
    expect([...root.querySelectorAll(".condition-join")].map((j) => j.textContent)).toEqual(["Where", "and"]);
    await change(".conditions-match", "any");
    expect([...root.querySelectorAll(".condition-join")].map((j) => j.textContent)).toEqual(["Where", "or"]);
  });

  it("lists a source by the records it reads, and says on its page what the filter calls it", async () => {
    getSources.mockResolvedValue([
      {
        developerName: "Shared_Tasks",
        parentObject: "Contact",
        type: "standard",
        objectName: "TaskRelation",
        objectLabel: "Task Relation",
        label: "Tasks",
        legendName: "Tasks",
        eventLabel: "$Object.Task",
        kind: "Salesforce",
        active: true,
        summary: "Task Relation records this Contact is on."
      },
      {
        developerName: "Files",
        parentObject: "Contact",
        type: "standard",
        objectName: "ContentDocumentLink",
        objectLabel: "Content Document Link",
        label: "Files & Notes",
        legendName: "Files & Notes",
        eventLabel: "$Label.Time_Drive_Legend_Files",
        kind: "Salesforce",
        active: true,
        summary: "Content Document Link records."
      },
      {
        developerName: "Apex_One",
        parentObject: "Contact",
        type: "apex",
        label: "Loyalty events",
        legendName: "Loyalty events",
        kind: "Apex",
        active: true,
        summary: "Events from the Apex class Loyalty."
      }
    ]);
    getSource.mockResolvedValue({
      developerName: "Shared_Tasks",
      label: "Tasks",
      kind: "Salesforce",
      parentObject: "Contact",
      objectName: "TaskRelation",
      parentField: "RelationId",
      dateField: "CreatedDate",
      eventLabel: "$Object.Task",
      title: "{Task.Subject}",
      active: true,
      details: []
    });
    const element = mount();
    await splash();
    const root = element.shadowRoot;
    await toPages(root);
    root.querySelector("button.pcard").click();
    await flush();
    // The child record's name, with what the filter calls it in brackets; Apex has no object.
    expect([...root.querySelectorAll(".row-name")].map((n) => n.textContent)).toEqual([
      "Task Relation (Tasks)",
      "Content Document Link (Files & Notes)",
      "Loyalty events"
    ]);
    root.querySelector('.row-main[data-name="Shared_Tasks"]').click();
    await flush();
    await flush();
    expect(root.querySelector(".page-title").textContent).toBe("Task Relation");
    const facts = Object.fromEntries(
      [...root.querySelectorAll(".facts .fact")].map((f) => [
        f.querySelector("dt").textContent,
        f.querySelector("dd").textContent.trim()
      ])
    );
    expect(facts["Name in the filter"]).toBe("Tasks");
  });

  it("asks one question at a time and threads the answers along the top", async () => {
    getObjects.mockResolvedValue([
      { value: "Order_Item__c", label: "Order Item", detail: "Order_Item__c" },
      { value: "Invoice__c", label: "Invoice", detail: "Invoice__c" }
    ]);
    getFields.mockResolvedValue([
      { name: "Name", label: "Order Number", type: "string", filterable: true, values: [] },
      { name: "Customer__c", label: "Customer", type: "reference", filterable: true, values: [] },
      { name: "Order_Time__c", label: "Order Time", type: "datetime", filterable: true, values: [] },
      { name: "CreatedDate", label: "Created Date", type: "datetime", filterable: true, values: [] }
    ]);
    getLinks.mockResolvedValue([
      { key: "Customer__c", parentField: "Customer__c", label: "Orders whose Customer is this Contact" }
    ]);
    const element = mount();
    await flush();
    const root = element.shadowRoot;
    await splash();
    await toPages(root);
    root.querySelector("button.pcard").click();
    await flush();
    // New from a chosen record page: its parent is already answered.
    root.querySelector(".page-head .primary").click();
    await flush();
    expect(crumbs(root)).toEqual(["Customize", "Contact", "New source"]);
    expect(root.querySelector(".question").textContent).toBe("Where are the related records being sourced?");
    // The record page is the breadcrumb's, not a step.
    expect(root.querySelector('.knot-button[data-step="parent"]')).toBeNull();
    expect(root.querySelector(".knot_current .knot-name").textContent).toBe("Source");

    // A pick is selected, but never moves on by itself: Next does.
    root.querySelector('.option[data-value="custom"]').click();
    await wait();
    expect(root.querySelector(".question").textContent).toBe("Where are the related records being sourced?");
    expect(root.querySelector('.option[data-value="custom"]').getAttribute("aria-checked")).toBe("true");
    root.querySelector(".wz-foot .primary").click();
    await wait();
    expect(getObjects).toHaveBeenCalledWith({ kind: "custom", parentObject: "Contact", dataSpace: null });
    expect(root.querySelector(".question").textContent).toBe("Which object should we use?");

    // Hundreds of objects: a search, not a wall of boxes.
    const search = root.querySelector(".picker-input");
    search.value = "invo";
    search.dispatchEvent(new CustomEvent("input"));
    await flush();
    expect([...root.querySelectorAll(".result-label")].map((r) => r.textContent)).toEqual(["Invoice"]);
    search.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }));
    await wait();
    expect(getLinks).toHaveBeenCalledWith({ parentObject: "Contact", objectName: "Invoice__c" });
    // A pick closes the list, like a picklist, and the box shows the choice.
    expect(root.querySelector(".results")).toBeNull();
    expect(root.querySelector(".picker-input").value).toBe("Invoice");

    // How they link is asked on the same screen, under the object.
    expect(root.querySelector(".question").textContent).toBe("Which object should we use?");
    expect(root.querySelector(".link-question").textContent).toBe("How do they link to the Contact?");
    // The only link is chosen for you, and shown as the choice.
    expect(root.querySelector(".link-chosen .option-label").textContent).toBe("Orders whose Customer is this Contact");
    // The words say what it means, and "all or some" sits under it.
    expect(root.querySelector(".link-story")).not.toBeNull();
    expect(root.querySelector('[aria-label="Which records"]')).not.toBeNull();
    expect(root.querySelector(".options_hidden")).not.toBeNull();
    root.querySelector(".link-close").click();
    await flush();
    expect(root.querySelector(".link-chosen")).toBeNull();
    expect(root.querySelector(".options_hidden")).toBeNull();
    root.querySelector(".wz-foot .primary").click();
    await wait();
    expect(root.querySelector(".question").textContent).toBe(
      "Which date should we use to determine where to plot the records on a timeline?"
    );
    expect(root.querySelector(".result-label").textContent).toBe("Order Time");
    expect(root.querySelector(".result-tag").textContent).toBe("Suggested");
    root.querySelector(".result").click();
    await flush();
    // The steps along the top name each step; the answers are in So far
    // (and in each step's label, for screen readers).
    const done = [...root.querySelectorAll(".knot_done")];
    expect(done.map((k) => k.querySelector(".knot-name").textContent)).toEqual(["Source", "Records"]);
    expect(done[0].querySelector(".knot-button").getAttribute("aria-label")).toBe("Source: A custom object");
    expect(done[1].querySelector(".knot-button").getAttribute("aria-label")).toContain("Customer");
    expect(root.querySelector(".knot_current .knot-name").textContent).toBe("Date");
    expect(root.querySelector(".foot-step").textContent).toBe("Step 3 of 7");

    // Back along the thread: a done knot returns to its question.
    root.querySelector('.knot-button[data-step="kind"]').click();
    await flush();
    expect(root.querySelector(".question").textContent).toBe("Where are the related records being sourced?");
  });

  it("asks which lenses an item belongs to, one or more, and says where it will show", async () => {
    getObjects.mockResolvedValue([{ value: "Invoice__c", label: "Invoice", detail: "Invoice__c" }]);
    getFields.mockResolvedValue([
      { name: "Name", label: "Name", type: "string", filterable: true, values: [] },
      { name: "CreatedDate", label: "Created Date", type: "datetime", filterable: true, values: [] }
    ]);
    getLinks.mockResolvedValue([
      { key: "Customer__c", parentField: "Customer__c", label: "Invoices whose Customer is this Contact" }
    ]);
    const element = mount();
    await flush();
    const root = element.shadowRoot;
    await splash();
    await toPages(root);
    root.querySelector("button.pcard").click();
    await flush();
    root.querySelector(".page-head .primary").click();
    await flush();
    root.querySelector('.option[data-value="custom"]').click();
    await wait();
    root.querySelector(".wz-foot .primary").click();
    await wait();
    const search = root.querySelector(".picker-input");
    search.value = "invo";
    search.dispatchEvent(new CustomEvent("input"));
    await flush();
    search.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }));
    await wait();
    root.querySelector(".wz-foot .primary").click();
    await wait();
    root.querySelector(".result")?.click();
    await flush();
    root.querySelector(".wz-foot .primary").click();
    await wait();

    // A step of its own, saying what a lens is for.
    expect(root.querySelector(".question").textContent).toBe("Which lenses should it be part of?");
    expect(root.querySelector(".lens-step-about").textContent).toContain("Choosing a lens there");
    const chips = () => [...root.querySelectorAll(".lens-step .chip-choice")];
    // All is a choice like the others, and a new source starts in it.
    expect(chips().map((c) => c.textContent.trim())).toEqual(["All items", "Commerce", "Marketing"]);
    expect(chips().map((c) => c.getAttribute("aria-pressed"))).toEqual(["true", "false", "false"]);
    expect(root.querySelector(".lens-step-names").textContent).toBe("All items");
    // Several at once, in the picker's order.
    chips()[2].click();
    await flush();
    chips()[1].click();
    await flush();
    expect(chips().map((c) => c.getAttribute("aria-pressed"))).toEqual(["true", "true", "true"]);
    expect(root.querySelector(".lens-step-names").textContent).toBe("All items \u00b7 Commerce \u00b7 Marketing");
    // And one taken out again.
    chips()[2].click();
    await flush();
    expect(root.querySelector(".lens-step-names").textContent).toBe("All items \u00b7 Commerce");
    // All can be left out, so the items show only in Commerce.
    chips()[0].click();
    await flush();
    expect(root.querySelector(".lens-step-names").textContent).toBe("Commerce");
    // The last lens stays: a source in none would be in All anyway.
    chips()[1].click();
    await flush();
    expect(root.querySelector(".lens-step-names").textContent).toBe("Commerce");
    // The thread says so, and Continue is open (lenses are optional).
    expect(root.querySelector(".wz-foot .primary").disabled).toBe(false);
  });

  it("lists many ways to link as a searchable, grouped list", async () => {
    getObjects.mockResolvedValue([{ value: "Invoice__c", label: "Invoice", detail: "Invoice__c" }]);
    getFields.mockResolvedValue([{ name: "Name", label: "Name", type: "string", filterable: true, values: [] }]);
    const lookups = ["Billing", "Buyer", "Customer", "Delivery", "Referrer", "Sponsor", "Witness"].map((n) => ({
      key: `${n}__c`,
      parentField: `${n}__c`,
      fieldLabel: n,
      label: `Invoices whose ${n} is this Contact`
    }));
    getLinks.mockResolvedValue([
      ...lookups,
      {
        key: "Owner__c",
        parentField: "Owner__c",
        fieldLabel: "Owner",
        masterDetail: true,
        label: "Invoices owned by this Contact"
      }
    ]);
    const element = mount();
    await flush();
    const root = element.shadowRoot;
    await splash();
    await toPages(root);
    root.querySelector("button.pcard").click();
    await flush();
    root.querySelector(".page-head .primary").click();
    await flush();
    root.querySelector('.option[data-value="custom"]').click();
    await wait();
    root.querySelector(".wz-foot .primary").click();
    await wait();
    const search = root.querySelector(".picker-input");
    search.value = "invo";
    search.dispatchEvent(new CustomEvent("input"));
    await flush();
    search.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }));
    await wait();

    // Eight ways: a search and groups, master-detail first, nothing chosen for you.
    expect(root.querySelector(".link-search")).not.toBeNull();
    expect([...root.querySelectorAll(".link-group")].map((g) => g.textContent)).toEqual(["Master-detail", "Lookups"]);
    expect(root.querySelectorAll(".options_many .option")).toHaveLength(8);
    expect(root.querySelector(".options_many .option .option-label").textContent).toBe(
      "Invoices owned by this Contact"
    );
    expect(root.querySelector(".link-chosen")).toBeNull();
    expect(root.querySelector(".wz-foot .primary").disabled).toBe(true);

    // Searching narrows the list.
    const find = root.querySelector(".link-search lightning-input");
    find.dispatchEvent(new CustomEvent("change", { detail: { value: "spon" } }));
    await flush();
    expect(root.querySelectorAll(".options_many .option")).toHaveLength(1);
    expect(root.querySelector(".link-search .quiet").textContent).toBe("1 of 8 ways they link");
  });

  it("asks a Data 360 source the same way: the object, its individual field and the filter on one screen", async () => {
    getObjects.mockResolvedValue([{ value: "Reservation__dlm", label: "Reservation", detail: "Reservation__dlm" }]);
    getDataSpaces.mockResolvedValue([{ value: "default", label: "default", detail: "" }]);
    getFields.mockResolvedValue([
      { name: "ssot__IndividualId__c", label: "Individual Id", type: "string", filterable: true, values: [] },
      { name: "ssot__EngagementDateTm__c", label: "Engagement Date", type: "datetime", filterable: true, values: [] }
    ]);
    const element = mount();
    await flush();
    const root = element.shadowRoot;
    await splash();
    await toPages(root);
    root.querySelector("button.pcard").click();
    await flush();
    root.querySelector(".page-head .primary").click();
    await flush();
    root.querySelector('.option[data-value="dmo"]').click();
    await wait();
    root.querySelector(".wz-foot .primary").click();
    await wait();
    expect(root.querySelector(".question").textContent).toBe("Which engagement should the timeline show?");
    const search = root.querySelector(".picker-input");
    search.value = "res";
    search.dispatchEvent(new CustomEvent("input"));
    await flush();
    search.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }));
    await wait();

    // The individual field is chosen for you, with the filter under it.
    expect(root.querySelector(".link-question").textContent).toBe("Which field holds the individual?");
    expect(root.querySelector(".individual-field").value).toBe("ssot__IndividualId__c");
    expect(root.querySelector('[aria-label="Which records"]')).not.toBeNull();
    expect(root.querySelector(".wz-foot .primary").disabled).toBe(false);

    // Then just the date.
    root.querySelector(".wz-foot .primary").click();
    await wait();
    expect(root.querySelector(".knot_current .knot-name").textContent).toBe("Date");
    expect(root.querySelector('[aria-label="Which records"]')).toBeNull();
  });

  it("asks for the data space of a Data 360 source only when there's a choice", async () => {
    getObjects.mockResolvedValue([{ value: "Reservation__dlm", label: "Reservation", detail: "Reservation__dlm" }]);
    const startDmo = async (root) => {
      await splash();
      await toPages(root);
      root.querySelector("button.pcard").click();
      await flush();
      root.querySelector(".page-head .primary").click();
      await flush();
      root.querySelector('.option[data-value="dmo"]').click();
      await wait();
      root.querySelector(".wz-foot .primary").click();
      await wait();
    };

    // Two: asked above the objects, and the DMOs listed are that space's.
    getDataSpaces.mockResolvedValue([
      { value: "default", label: "default", detail: "" },
      { value: "Europe", label: "Europe", detail: "" }
    ]);
    let element = mount();
    await flush();
    let root = element.shadowRoot;
    await startDmo(root);
    // On the Records step, above the objects, which wait for it.
    expect(root.querySelector(".question").textContent).toBe("Which engagement should the timeline show?");
    expect(root.querySelector(".space-field")).not.toBeNull();
    expect(root.querySelector(".picker-input")).toBeNull();
    expect(root.querySelector(".wz-foot .primary").disabled).toBe(true);
    root.querySelector(".space-field").dispatchEvent(new CustomEvent("change", { detail: { value: "Europe" } }));
    await wait();
    expect(getObjects).toHaveBeenCalledWith({ kind: "dmo", parentObject: "Contact", dataSpace: "Europe" });
    expect(root.querySelector(".picker-input")).not.toBeNull();
    document.body.removeChild(element);
    getObjects.mockClear();

    // One: not asked, and that space is used.
    getDataSpaces.mockResolvedValue([{ value: "default", label: "default", detail: "" }]);
    element = mount();
    await flush();
    root = element.shadowRoot;
    await startDmo(root);
    expect(root.querySelector(".question").textContent).toBe("Which engagement should the timeline show?");
    expect(root.querySelector(".space-field")).toBeNull();
    expect(getObjects).toHaveBeenCalledWith({ kind: "dmo", parentObject: "Contact", dataSpace: "default" });
  });

  it("shows the Data 360 kind disabled, with the reason, until the add-on is installed", async () => {
    getData360Status.mockResolvedValue({
      ready: false,
      reason: "Install the Time Drive Data Extension package to use Data 360."
    });
    const element = mount();
    await splash();
    const root = element.shadowRoot;
    await toPages(root);
    root.querySelector("button.pcard").click();
    await flush();
    root.querySelector(".page-head .primary").click();
    await flush();

    const tile = root.querySelector('.option[data-value="dmo"]');
    expect(tile.disabled).toBe(true);
    expect(tile.querySelector(".option-detail").textContent).toBe(
      "Install the Time Drive Data Extension package to use Data 360."
    );
    // The other kinds stay open, and a disabled one can't be clicked into.
    expect(root.querySelector('.option[data-value="standard"]').disabled).toBe(false);
    tile.click();
    await flush();
    expect(tile.getAttribute("aria-checked")).toBe("false");
  });

  it("shows the server's message when sources can't load", async () => {
    getSources.mockRejectedValue({
      body: { message: "Only admins (with Customize Application) can manage timeline sources." }
    });
    const element = mount();
    await splash();
    expect(element.shadowRoot.querySelector(".notice .notice-title").textContent).toBe(
      "Only admins (with Customize Application) can manage timeline sources."
    );
  });
});
