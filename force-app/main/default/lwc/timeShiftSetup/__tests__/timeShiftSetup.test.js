import { createElement } from "lwc";
import TimeShiftSetup from "c/timeShiftSetup";
import getSources from "@salesforce/apex/TimeShiftSetupController.getSources";
import getSource from "@salesforce/apex/TimeShiftSetupController.getSource";
import getObjects from "@salesforce/apex/TimeShiftSetupController.getObjects";
import getDataSpaces from "@salesforce/apex/TimeShiftSetupController.getDataSpaces";
import getData360Status from "@salesforce/apex/TimeShiftSetupController.getData360Status";
import getFields from "@salesforce/apex/TimeShiftSetupController.getFields";
import getLinks from "@salesforce/apex/TimeShiftSetupController.getLinks";
import setActive from "@salesforce/apex/TimeShiftSetupController.setActive";
import save from "@salesforce/apex/TimeShiftSetupController.save";
import TimeShiftConfirm from "c/timeShiftConfirm";
import { subscribe } from "lightning/empApi";
import getOrgFit from "@salesforce/apex/TimeShiftSetupController.getOrgFit";
import applyOrgFit from "@salesforce/apex/TimeShiftSetupController.applyOrgFit";

// The Diagnostics page has its own tests; here it is a stand-in.
jest.mock(
  "c/timeShiftDiagnostics",
  () => {
    const { LightningElement } = require("lwc");
    return { __esModule: true, default: class Diagnostics extends LightningElement {} };
  },
  { virtual: true }
);
jest.mock("@salesforce/apex/TimeShiftSetupController.getSources", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeShiftSetupController.getSource", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeShiftSetupController.getObjects", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeShiftSetupController.getDataSpaces", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeShiftSetupController.getData360Status", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeShiftSetupController.getApexProviders", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeShiftSetupController.getLinks", () => ({ default: jest.fn() }), { virtual: true });
jest.mock("@salesforce/apex/TimeShiftSetupController.getFields", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeShiftSetupController.getVolumes", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeShiftSetupController.preview", () => ({ default: jest.fn() }), { virtual: true });
jest.mock("@salesforce/apex/TimeShiftSetupController.save", () => ({ default: jest.fn() }), { virtual: true });

jest.mock("@salesforce/apex/TimeShiftSetupController.getOrgFit", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeShiftSetupController.applyOrgFit", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  "@salesforce/apex/TimeShiftSetupController.getViewDrafts",
  () => ({
    default: jest.fn(() =>
      Promise.resolve([
        {
          developerName: "All",
          name: "All",
          labelName: "Time_Shift_View_All",
          shown: "All items",
          active: true
        },
        {
          developerName: "Commerce",
          name: "Commerce",
          labelName: "Time_Shift_View_Commerce",
          shown: "Commerce timeline",
          active: true
        },
        {
          developerName: "Marketing",
          name: "Marketing",
          labelName: "Time_Shift_View_Marketing",
          shown: "Marketing timeline",
          active: true
        }
      ])
    )
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TimeShiftSetupController.saveViews",
  () => ({ default: jest.fn(() => Promise.resolve({ jobId: null, developerName: "Views" })) }),
  { virtual: true }
);
jest.mock("@salesforce/apex/TimeShiftSetupController.remove", () => ({ default: jest.fn() }), { virtual: true });
jest.mock("@salesforce/apex/TimeShiftSetupController.setActive", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  "lightning/empApi",
  () => ({ subscribe: jest.fn(() => Promise.resolve({})), unsubscribe: jest.fn(), onError: jest.fn() }),
  { virtual: true }
);

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

// Setup opens on its home page straight away; this lets the first reads land.
// eslint-disable-next-line @lwc/lwc/no-async-operation
const splash = () => new Promise((resolve) => setTimeout(resolve, 50));
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

// Home's Get started leads to the record pages.
async function toPages(root) {
  root.querySelector(".kh-slide_on .kh-actions .primary").click();
  await flush();
}

// The GitHub tests read through fetch, not the bundled mock docs.
jest.mock("../bundledDocs", () => ({ BUNDLED_DOCS: null }));

function mount() {
  const element = createElement("c-time-shift-setup", { is: TimeShiftSetup });
  document.body.appendChild(element);
  return element;
}

describe("c-time-shift-setup", () => {
  beforeEach(() => {
    // The question before something is done: answered yes.
    TimeShiftConfirm.open = jest.fn(() => Promise.resolve(true));
    getSources.mockResolvedValue(SOURCES);
    getDataSpaces.mockResolvedValue([]);
    getData360Status.mockResolvedValue({ ready: true });
    getOrgFit.mockResolvedValue({
      features: [
        {
          key: "SharedActivities",
          label: "Shared Activities",
          enabled: true,
          used: false,
          turnsOn: ["Contact Tasks (every contact)"],
          turnsOff: ["Contact Tasks"]
        },
        {
          key: "PersonAccounts",
          label: "Person Accounts",
          enabled: false,
          used: false,
          turnsOn: ["Person Account Tasks"],
          turnsOff: []
        }
      ]
    });
    applyOrgFit.mockResolvedValue({ jobId: null, developerName: "Org_Fit" });
  });
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  const crumbs = (root) => [...root.querySelectorAll(".crumb-link, .crumb-here")].map((c) => c.textContent);

  it("opens on the home page; Get started leads to the record pages, then one's own page", async () => {
    const element = mount();
    await splash();
    const root = element.shadowRoot;
    // The menu: Home, Dashboard and Setup; Home is the carousel, how it works and the FAQs.
    expect(root.querySelector(".crumbs")).toBeNull();
    expect([...root.querySelectorAll(".site-link")].map((l) => l.textContent.trim())).toEqual([
      "Home",
      "Dashboard",
      "Setup",
      "Customize",
      "Diagnostics",
      "Docs"
    ]);
    expect(root.querySelector('.site-link[data-to="home"]').getAttribute("aria-current")).toBe("page");
    expect(root.querySelector(".kd")).toBeNull();
    expect(root.querySelector(".kh-title").textContent.replace(/\s+/g, " ").trim()).toBe(
      "Scroll through related records and identify clusters of engagement"
    );
    expect(root.querySelector(".kh-hero-image").getAttribute("src")).toContain("timeline-hero.gif");
    expect(root.querySelector(".kh-wide .kh-section-title").textContent).toBe("Works in horizontal too");
    expect(root.querySelectorAll(".kh-step")).toHaveLength(3);
    expect(root.querySelectorAll(".kh-faq-item")).toHaveLength(10);

    // How it works: each step brings its own picture.
    expect(root.querySelector(".kh-how-caption-title").textContent).toBe("One timeline per record page");
    root.querySelector('.kh-step-button[data-index="2"]').click();
    await flush();
    expect(root.querySelector(".kh-how-caption-title").textContent).toBe("A busy day stays one row");
    expect(root.querySelector('.kh-step-button[data-index="2"]').getAttribute("aria-pressed")).toBe("true");

    // Dashboard: the metrics.
    root.querySelector('.site-link[data-to="dashboard"]').click();
    await flush();
    expect(root.querySelector("h1.page-title").textContent).toBe("Dashboard");
    expect(root.querySelector(".kd-number").textContent).toBe("1");
    expect(root.querySelector(".kd-of").textContent).toBe("of 2");
    expect(root.querySelector(".kd-row .pill").textContent).toBe("1 active");
    expect(root.querySelector('.kd-row[data-name="Data_360_Email"] .kd-row-name').textContent).toBe("Email");

    // Setup: guided steps; what Setup can see ticks itself off. The menu's
    // Get started goes there too.
    root.querySelector(".site-bar .site-action").click();
    await flush();
    expect(root.querySelector("h1.page-title").textContent).toBe("Guided setup");
    // In order: the video, permission sets, what's set up, your sources,
    // your users' access, and the record pages.
    expect([...root.querySelectorAll(".guided-step")].map((st) => st.dataset.key)).toEqual([
      "video",
      "perms",
      "fit-SharedActivities",
      "views",
      "review",
      "source",
      "users",
      "page"
    ]);
    // Sources of your own tick "Add your sources"; the rest are the user's.
    expect(root.querySelector(".guided-count-number").textContent).toBe("1 of 8");
    // A step per org setting with a decision: Shared Activities is on here
    // but unused, so switching is recommended; Person Accounts is off and
    // unused, so it has no step.
    const cards = [...root.querySelectorAll(".fit-card")];
    expect(cards.length).toBe(1);
    expect(root.querySelector('.guided-step[data-key="fit-SharedActivities"] .guided-title').textContent.trim()).toBe(
      "Decide on Shared Activities"
    );
    expect(cards[0].classList.contains("fit-card_recommend")).toBe(true);
    expect(cards[0].querySelector(".fit-card-advice").textContent).toBe("Recommended: use it.");
    // Ticking it lists what changes; Apply asks first, then fits.
    const use = cards[0].querySelector(".fit-use");
    use.checked = true;
    use.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect([...root.querySelectorAll(".fit-changes li")].map((li) => li.textContent)).toEqual([
      "Turns on Contact Tasks (every contact)",
      "Turns off Contact Tasks"
    ]);
    root.querySelector('.guided-step[data-key="fit-SharedActivities"] .guided-button').click();
    await flush();
    await flush();
    expect(TimeShiftConfirm.open).toHaveBeenCalled();
    expect(applyOrgFit).toHaveBeenCalledWith({ usedFeatures: ["SharedActivities"] });
    expect(root.querySelector(".guided-count-number").textContent).toBe("2 of 8");
    expect(root.querySelector(".guided-progress_done")).toBeNull();
    expect(root.querySelector(".guided-step_on .guided-title").textContent.trim()).toBe("Watch the how-to video");
    // What the users must be able to read, and which record pages need it.
    expect(root.querySelector('.guided-step[data-key="users"] .guided-status').textContent).toContain("Invoice__c");
    expect(
      [...root.querySelectorAll('.guided-step[data-key="page"] .guided-button')].map((b) => b.textContent.trim())
    ).toEqual(["Contact pages"]);
    // A done step still shows its help, from anywhere on its row.
    root.querySelector('.guided-step[data-key="source"] .guided-text').click();
    await flush();
    expect(root.querySelector(".guided-aside .aside-title").textContent).toBe("Add your sources");
    expect(root.querySelector(".guided-aside-step").textContent).toBe("Step 6 · Done");
    expect(root.querySelector(".guided-aside-head").textContent).toBe("What it did");

    const tick = async (key) => {
      const box = root.querySelector(`.guided-check[data-key="${key}"]`);
      box.checked = true;
      box.dispatchEvent(new CustomEvent("change"));
      await flush();
    };
    await tick("video");
    expect(root.querySelector(".guided-count-number").textContent).toBe("3 of 8");
    for (const key of ["perms", "review", "users", "page"]) await tick(key);
    // Views come from custom labels; Setup only makes them inactive, never All.
    const viewRows = [...root.querySelectorAll(".view-name-row")];
    expect(viewRows.map((r) => r.querySelector(".view-name-text").textContent)).toEqual([
      "All items",
      "Commerce timeline",
      "Marketing timeline"
    ]);
    expect(viewRows[0].querySelector(".view-label").textContent).toBe("Time_Shift_View_All");
    expect(viewRows[0].querySelector(".view-active").disabled).toBe(true);
    const marketing = viewRows[2].querySelector(".view-active");
    marketing.checked = false;
    marketing.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(root.querySelector('.guided-step[data-key="views"] .guided-button').textContent.trim()).toBe(
      "Save the views"
    );
    marketing.checked = true;
    marketing.dispatchEvent(new CustomEvent("change"));
    await flush();
    // The views stay as they are: saved as they are.
    root.querySelector('.guided-step[data-key="views"] .guided-button').click();
    await flush();
    await flush();
    // All done: the bar says so itself; there's no separate banner.
    expect(root.querySelector(".guided-progress_done")).not.toBeNull();
    expect(root.querySelector(".guided-count-number").textContent).toBe("Setup complete");
    expect(root.querySelectorAll(".guided-segment_done")).toHaveLength(8);

    root.querySelector('.site-link[data-to="home"]').click();
    await flush();
    await toPages(root);
    expect(crumbs(root)).toEqual([]);
    expect(root.querySelector('.site-link[data-to="pages"]').getAttribute("aria-current")).toBe("page");
    // Person Account pages stay out of sight until the timeline uses Person
    // Accounts.
    const pages = [...root.querySelectorAll("button.pcard")];
    expect(pages.map((c) => c.querySelector(".pcard-name").textContent)).toEqual(["Contact", "Account"]);
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
    expect(facts["When it is opened"]).toBe("Its own details");
    expect(facts["When its title is clicked"]).toBe("Its own record");
    // One diagram of the interactions: the opened item, then where a click lands.
    expect(facts.Interactions).toBeDefined();
    expect(root.querySelector(".fact_preview .mock-page")).not.toBeNull();
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
      },
      { name: "Task.ActivityDate", label: "Task › Due Date", type: "date", filterable: true, values: [] }
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
    save.mockResolvedValue({ developerName: "Order_Placed", jobId: "0Af000000000001" });
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
    expect(root.querySelector(".look-warning")).toBeNull();
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

    // Details: its own details, a related record's, or chosen fields; the
    // preview shows an opened item with sample values.
    expect(root.querySelector(".question").textContent).toBe("What happens when someone opens or clicks an item?");
    const openTitles = () => [...root.querySelectorAll(".options .option-label")].map((o) => o.textContent);
    // Opening and clicking are asked together, over one diagram.
    expect(openTitles()).toEqual([
      "Its own details",
      "A related record's details",
      "Fields you choose",
      "Its own record",
      "A related record"
    ]);
    expect(root.querySelectorAll(".mock")).toHaveLength(1);
    // The choice sits at the top of its list, the other options out of the way
    // until the X brings them back.
    expect(root.querySelectorAll(".link-chosen")).toHaveLength(2);
    expect(root.querySelectorAll(".options_hidden")).toHaveLength(2);
    root.querySelectorAll(".link-chosen .link-close")[0].click();
    await flush();
    expect(root.querySelectorAll(".options_hidden")).toHaveLength(1);
    expect(root.querySelectorAll(".link-chosen")).toHaveLength(1);
    // Closing it leaves its options unselected, and Save waits for a choice.
    expect(root.querySelectorAll(".options .option_on")).toHaveLength(1);
    expect(root.querySelector(".wz-foot .save").disabled).toBe(true);
    expect(root.querySelector(".mock-page")).not.toBeNull();
    expect(root.querySelector(".mock-title").textContent).toBe("Order placed");
    root.querySelector('.option[data-value="related"]').click();
    await flush();
    // The page's own record comes last; the Location is suggested first.
    expect([...root.querySelectorAll(".behave-related .chip-choice")].map((c) => c.textContent.trim())).toEqual([
      "Location",
      "Customer (this page's record)"
    ]);
    expect(root.querySelector(".behave-related .chip-choice_on").textContent.trim()).toBe("Location");

    // The same step goes on to a click: its own record or a related one, with
    // where it lands in the same diagram.
    expect(root.querySelector(".mock-title_link")).not.toBeNull();
    root.querySelectorAll('.option[data-value="related"]')[1].click();
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
    // The lens was asked under the date, not here.
    expect(root.querySelector(".tune-view .chips")).toBeNull();
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
    name.value = "Orders";
    name.dispatchEvent(new CustomEvent("input"));
    await flush();
    expect(legend()).toEqual(["Email", "Orders"]);
    expect(root.querySelector(".legend-row_mine .legend-name").textContent).toBe("Orders");
    root.querySelector('.legend-row_mine lightning-button-icon[data-dir="-1"]').click();
    await flush();
    expect(legend()).toEqual(["Orders", "Email"]);
    root.querySelector('.knot-button[data-step="open"]').click();
    await flush();
    root.querySelector(".wz-foot .save").click();
    await flush();
    const sent = JSON.parse(save.mock.calls[0][0].draftJson);
    expect(sent).toMatchObject({
      useCompactLayout: true,
      detailsRecordField: "Location__c",
      detailsObject: "Location__c",
      recordIdField: "Location__c",
      iconColour: "#014486",
      eventLabel: "Orders",
      label: "Orders",
      legendOrder: ["__this__", "Data_360_Email"]
    });
  });

  it("lists the docs, reads one from GitHub with a breadcrumb back, and follows a link to the other", async () => {
    const files = {
      "config-guide.md":
        "# Config Guide\n\nIntro.\n\n## Before you start\n\nYou need **Customize Application**.\n\n- One\n- Two\n\n## Add a source\n\nSee the [FAQs](faqs.md#saving).",
      "faqs.md": "# FAQs\n\n## Saving\n\nIt deploys.\n\n## Access\n\nAs the user."
    };
    global.fetch = jest.fn((url) => {
      const file = url.split("/").pop();
      return Promise.resolve(
        files[file]
          ? { ok: true, status: 200, text: () => Promise.resolve(files[file]) }
          : { ok: false, status: 404, text: () => Promise.resolve("") }
      );
    });
    const element = mount();
    await splash();
    const root = element.shadowRoot;
    root.querySelector('.site-link[data-to="docs"]').click();
    await flush();
    expect(root.querySelector(".page-title").textContent).toBe("Docs");
    expect(crumbs(root)).toEqual([]);
    expect([...root.querySelectorAll(".docs-card-title")].map((t) => t.textContent)).toEqual(["Config Guide", "FAQs"]);

    root.querySelector('.docs-card[data-doc="guide"]').click();
    await flush();
    await flush();
    expect(global.fetch).toHaveBeenCalledWith(
      "https://raw.githubusercontent.com/deejay-hub/time-shift-lwc/main/docs/config-guide.md",
      expect.anything()
    );
    expect(root.querySelector(".page-title").textContent).toBe("Config Guide");
    expect(crumbs(root)).toEqual(["Docs", "Config Guide"]);
    expect(root.querySelector('.site-link[data-to="docs"]').getAttribute("aria-current")).toBe("page");
    expect([...root.querySelectorAll(".doc-h2")].map((h) => h.textContent)).toEqual([
      "1. Before you start",
      "2. Add a source"
    ]);
    expect([...root.querySelectorAll(".doc-toc-link")].map((l) => l.textContent.trim())).toEqual([
      "Before you start",
      "Add a source"
    ]);
    const blocks = root.querySelector(
      '.doc-section[data-section="before-you-start"] c-time-shift-doc-blocks'
    ).shadowRoot;
    expect(blocks.querySelectorAll(".doc-list li")).toHaveLength(2);

    // A link to the other doc opens it in Setup.
    const link = root
      .querySelector('.doc-section[data-section="add-a-source"] c-time-shift-doc-blocks')
      .shadowRoot.querySelector("c-time-shift-doc-text")
      .shadowRoot.querySelector(".doc-link");
    expect(link.dataset.doc).toBe("faqs");
    link.click();
    await flush();
    await flush();
    expect(crumbs(root)).toEqual(["Docs", "FAQs"]);
    expect([...root.querySelectorAll(".doc-faq .kh-faq-question span")].map((q) => q.textContent)).toEqual([
      "Saving",
      "Access"
    ]);
    // A search over questions and answers: "user" is only in Access's answer.
    const search = root.querySelector(".faq-search input");
    search.value = "user";
    search.dispatchEvent(new CustomEvent("input"));
    await flush();
    expect([...root.querySelectorAll(".doc-faq .kh-faq-question span")].map((q) => q.textContent)).toEqual(["Access"]);
    expect(root.querySelector(".doc-faq details").open).toBe(true);
    expect(root.querySelector(".faq-count").textContent).toBe("1 of 2 questions");
    search.value = "nothing at all";
    search.dispatchEvent(new CustomEvent("input"));
    await flush();
    expect(root.querySelector(".doc-faq-wrap .problem-title").textContent).toBe("No questions match");
    root.querySelector(".doc-faq-wrap .empty-state button").click();
    await flush();
    expect(root.querySelectorAll(".doc-faq details")).toHaveLength(2);
    // The FAQs have their own "On this page", one entry per question.
    expect([...root.querySelectorAll(".doc-toc-link")].map((l) => l.textContent.trim())).toEqual(["Saving", "Access"]);

    root.querySelector('.crumb-link[data-to="docs"]').click();
    await flush();
    expect(root.querySelector(".page-title").textContent).toBe("Docs");
    delete global.fetch;
  });

  it("offers GitHub itself when a doc can't be read", async () => {
    global.fetch = jest.fn(() => Promise.reject(new TypeError("Failed to fetch")));
    const element = mount();
    await splash();
    const root = element.shadowRoot;
    root.querySelector('.site-link[data-to="docs"]').click();
    await flush();
    root.querySelector('.docs-card[data-doc="faqs"]').click();
    await flush();
    await flush();
    expect(root.querySelector(".doc-failed-title").textContent).toBe("FAQs didn't load from GitHub");
    expect(root.querySelector(".doc-failed a").getAttribute("href")).toBe(
      "https://github.com/deejay-hub/time-shift-lwc/blob/main/docs/faqs.md"
    );
    delete global.fetch;
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

  it("switches a source off in place and waits for the save", async () => {
    setActive.mockResolvedValue({ jobId: "0Af000000000001AAA", developerName: "Order_Placed" });
    let deliver;
    subscribe.mockImplementation((channel, replay, handler) => {
      deliver = handler;
      return Promise.resolve({});
    });
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
    deliver({ data: { payload: { Job_Id__c: "0Af000000000001AAA", Status__c: "Succeeded" } } });
    await flush();
    expect(element.shadowRoot.querySelector(".pending")).toBeNull();
    expect(element.shadowRoot.querySelector('lightning-input[data-name="Order_Placed"]').checked).toBe(false);
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
    const wait = () => new Promise((resolve) => setTimeout(resolve, 300)); // eslint-disable-line @lwc/lwc/no-async-operation
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
    // The only link is chosen for you: shown as the choice, with what it means
    // over a diagram of the two objects.
    expect(root.querySelector(".auto-note")).toBeNull();
    expect(root.querySelector(".link-chosen .option-label").textContent).toBe("Orders whose Customer is this Contact");
    // No diagram: the words say what it means, and "all or some" sits under it.
    expect(root.querySelector(".erd")).toBeNull();
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
    // Once a date is chosen, its lens is asked under it.
    expect(root.querySelector(".tune-view .chips")).toBeNull();
    root.querySelector(".result").click();
    await flush();
    expect(root.querySelector(".link-question").textContent).toBe("Which lens?");
    expect(root.querySelector(".tune-view .chips")).not.toBeNull();
    // The steps along the top name each step; the answers are in So far
    // (and in each step's label, for screen readers).
    const done = [...root.querySelectorAll(".knot_done")];
    expect(done.map((k) => k.querySelector(".knot-name").textContent)).toEqual(["Source", "Records"]);
    expect(root.querySelector(".knot-answer")).toBeNull();
    expect(done[0].querySelector(".knot-button").getAttribute("aria-label")).toBe("Source: A custom object");
    expect(done[1].querySelector(".knot-button").getAttribute("aria-label")).toContain("Customer");
    expect(root.querySelector(".knot_current .knot-name").textContent).toBe("Date");
    expect(root.querySelector(".foot-step").textContent).toBe("Step 3 of 6");

    // Back along the thread: a done knot returns to its question.
    root.querySelector('.knot-button[data-step="kind"]').click();
    await flush();
    expect(root.querySelector(".question").textContent).toBe("Where are the related records being sourced?");
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
    const wait = () => new Promise((resolve) => setTimeout(resolve, 300)); // eslint-disable-line @lwc/lwc/no-async-operation
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
    const wait = () => new Promise((resolve) => setTimeout(resolve, 300)); // eslint-disable-line @lwc/lwc/no-async-operation
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

    // Then just the date, and the lens under it.
    root.querySelector(".wz-foot .primary").click();
    await wait();
    expect(root.querySelector(".knot_current .knot-name").textContent).toBe("Date");
    expect(root.querySelector('[aria-label="Which records"]')).toBeNull();
  });

  it("asks for the data space of a Data 360 source only when there's a choice", async () => {
    getObjects.mockResolvedValue([{ value: "Reservation__dlm", label: "Reservation", detail: "Reservation__dlm" }]);
    const wait = () => new Promise((resolve) => setTimeout(resolve, 300)); // eslint-disable-line @lwc/lwc/no-async-operation
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
      reason: "Install the Time Trail Data 360 add-on package to use Data 360."
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
      "Install the Time Trail Data 360 add-on package to use Data 360."
    );
    // The other kinds stay open, and a disabled one can't be clicked into.
    expect(root.querySelector('.option[data-value="standard"]').disabled).toBe(false);
    tile.click();
    await flush();
    expect(tile.getAttribute("aria-checked")).toBe("false");
  });

  it("shows a plain error, not the raw one, when sources can't load", async () => {
    getSources.mockRejectedValue({
      body: { message: "Only admins (with Customize Application) can manage timeline sources." }
    });
    const element = mount();
    await splash();
    expect(element.shadowRoot.querySelector(".kh-notice .notice-title").textContent).toBe(
      "Only admins (with Customize Application) can manage timeline sources."
    );
  });
});
