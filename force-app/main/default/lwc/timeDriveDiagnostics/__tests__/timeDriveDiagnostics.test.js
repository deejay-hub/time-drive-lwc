import { createElement } from "lwc";
import TimeDriveDiagnostics from "c/timeDriveDiagnostics";
import run from "@salesforce/apex/TimeDriveDiagnosticController.run";
import { note, clear, setServerReport } from "c/timeDriveTraceLog";

jest.mock("@salesforce/apex/TimeDriveDiagnosticController.run", () => ({ default: jest.fn() }), { virtual: true });
// The card drawn underneath is the real one; these are what it asks of Apex.
jest.mock(
  "@salesforce/apex/TimeDriveController.getTimeline",
  () => ({ default: jest.fn(() => new Promise(() => {})) }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/TimeDriveController.getTimelineDiagnosed",
  () => ({ default: jest.fn(() => new Promise(() => {})) }),
  { virtual: true }
);
jest.mock("@salesforce/apex/TimeDriveController.getPageDays", () => ({ default: jest.fn(() => Promise.resolve([])) }), {
  virtual: true
});
jest.mock(
  "@salesforce/apex/TimeDriveController.getRights",
  () => ({ default: jest.fn(() => Promise.resolve({ canEdit: true, canDelete: true })) }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TimeDriveController.getActivityActions",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const ID = "003000000000001AAA";

const REPORT = {
  mode: "config",
  what: "How the timeline is set up for this record.",
  totals: null,
  page: [{ label: "Record", value: "Carol Tezak", detail: `${ID} · Contact`, tone: null }],
  permissions: [
    { label: "Modify All Data", value: "no", detail: "Edit and Delete need only the object's permission.", tone: null },
    { label: "This record: read / edit / delete", value: "yes / yes / no", detail: "UserRecordAccess", tone: "good" }
  ],
  sources: [
    {
      developerName: "Tasks",
      label: "Tasks",
      kind: "Salesforce",
      objectName: "Task",
      status: "used",
      reason: "Used for this page.",
      access: "read yes · create yes · edit yes · delete yes",
      missing: "Priority (no read access)",
      counted: false,
      queries: 0,
      queryMs: 0,
      rows: 0,
      phaseMs: 0,
      sequence: 1
    },
    {
      developerName: "Old_Calls",
      label: "Old calls",
      kind: "Salesforce",
      objectName: "Task",
      status: "ignored",
      reason: "Inactive (Active is off).",
      access: null,
      missing: null,
      counted: false,
      queries: 0,
      queryMs: 0,
      rows: 0,
      phaseMs: 0,
      sequence: 2
    }
  ],
  queries: [],
  phases: [],
  notes: [],
  asked: [],
  warnings: [],
  problems: []
};

// What the server reported for the card's own opening request.
const PERF = {
  serverMs: 2094,
  cpuMs: 377,
  queryCount: 14,
  queryRows: 612,
  payloadKb: 44,
  events: 48,
  groupedRows: 2,
  days: 423,
  unit: "day",
  warnings: ["Events couldn't be read."],
  problems: [],
  counted: ["Tasks"],
  queries: [
    {
      seq: 1,
      source: "Tasks",
      kind: "count",
      soql: "SELECT ActivityDate g0, COUNT(Id) n FROM Task WHERE WhoId = :parentId GROUP BY ActivityDate",
      binds: ":parentId = 003…",
      rows: 120,
      ms: 900,
      startedMs: 5,
      error: null
    },
    {
      seq: 2,
      source: "Tasks",
      kind: "rows",
      soql: "SELECT Id, Subject FROM Task WHERE WhoId = :parentId LIMIT 1000",
      binds: "",
      rows: 40,
      ms: 400,
      startedMs: 910,
      error: null
    },
    {
      seq: 3,
      source: "Events",
      kind: "rows",
      soql: "SELECT Id FROM Event",
      binds: "",
      rows: 0,
      ms: 12,
      startedMs: 1320,
      error: "No access to Event"
    }
  ],
  phases: [{ source: "Tasks", name: "count by day", ms: 1400, startedMs: 5, items: 120 }],
  notes: [{ source: "Calls", what: "Not queried", reason: "The summary found nothing in it for these days." }]
};

const flush = async () => {
  for (let i = 0; i < 4; i++) {
    // eslint-disable-next-line no-await-in-loop, @lwc/lwc/no-async-operation
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
};

const mount = () => {
  const element = createElement("c-time-drive-diagnostics", { is: TimeDriveDiagnostics });
  document.body.appendChild(element);
  return element;
};

const enter = async (root, id) => {
  const input = root.querySelector("lightning-input.form-id");
  input.value = id;
  input.dispatchEvent(new CustomEvent("change"));
  await flush();
};

describe("c-time-drive-diagnostics", () => {
  beforeEach(() => {
    run.mockReset();
    run.mockResolvedValue(REPORT);
    clear();
  });
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });

  const runIt = async (root, { reported = true } = {}) => {
    await enter(root, ID);
    root.querySelector("lightning-button.run-load").click();
    await flush();
    // The card's own opening request, with what it ran.
    if (reported) setServerReport(PERF);
    await flush();
  };
  const bigs = (root) =>
    new Map(
      [...root.querySelectorAll(".big")].map((b) => [
        b.querySelector(".big-label").textContent,
        b.querySelector(".big-value").textContent
      ])
    );

  it("will not run until it has an Id, and has no scroll to diagnose", async () => {
    const root = mount().shadowRoot;
    expect(root.querySelector("lightning-button.run-load").disabled).toBe(true);
    expect(root.querySelector("lightning-button.run-scroll")).toBeNull();
    await enter(root, "not an id");
    expect(root.querySelector("lightning-button.run-load").disabled).toBe(true);
    await enter(root, ID);
    expect(root.querySelector("lightning-button.run-load").disabled).toBe(false);
    expect(root.querySelector("c-time-drive")).toBeNull();
  });

  it("opens on Performance and draws the actual timeline for the record", async () => {
    const root = mount().shadowRoot;
    await runIt(root);
    expect(run).toHaveBeenCalledWith({
      recordId: ID,
      mode: "config",
      layout: "Across",
      historyYears: "0.5",
      futureYears: "None"
    });
    const tabs = [...root.querySelectorAll(".tab")];
    expect(tabs.map((t) => t.textContent.trim())).toEqual(["Config", "Performance", "Output"]);
    expect(root.querySelector(".tab_on").textContent.trim()).toBe("Performance");
    const card = root.querySelector("c-time-drive");
    expect(card.recordId).toBe(ID);
    expect(card.layout).toBe("Horizontal");
    // Asked to report its own request, so the figures are that request's.
    expect(card.diagnose).toBe(true);
  });

  it("says the load time in plain numbers once the card has painted: server, network, browser", async () => {
    const root = mount().shadowRoot;
    await runIt(root, { reported: false });
    // The card hasn't painted: the total is still being waited for.
    expect(bigs(root).get("Load time (total)")).toBe("…");
    note(1000, "connected");
    setServerReport(PERF);
    note(2400, "getTimeline returned 3229 ms after it was sent (server 2094 ms, 14 queries)");
    note(3400, "first paint of the days 4374 ms after connecting");
    await flush();
    const figures = bigs(root);
    expect(figures.get("Load time (total)")).toBe("4.4 s");
    expect(figures.get("Server time (Apex)")).toBe("2.1 s");
    // The round trip less the server: 3229 - 2094.
    expect(figures.get("Network time (approx.)")).toBe("1.1 s");
    // The rest of the wait: 4374 - 3229.
    expect(figures.get("Browser time")).toBe("1.1 s");
    const legend = [...root.querySelectorAll(".legend li")].map((l) => l.textContent.replace(/\s+/g, " ").trim());
    expect(legend).toEqual(["Server (Apex): 2.1 s", "Network (approx.): 1.1 s", "Browser: 1.1 s"]);
    expect(root.querySelector(".sentence").textContent).toBe(
      "You waited 4.4 s. The server spent 2.1 s of that (14 queries), the network about 1.1 s, and the browser 1.1 s. Network and browser together are the 2.3 s that isn't the server."
    );
    expect(root.querySelectorAll(".bar .share")).toHaveLength(3);
  });

  it("lists every query with its SOQL, time and rows, the slow and failed marked", async () => {
    const root = mount().shadowRoot;
    await runIt(root);
    const rows = [...root.querySelectorAll("table.queries tbody tr")];
    expect(rows).toHaveLength(3);
    expect(rows[0].classList).toContain("row_slow");
    expect(rows[2].classList).toContain("row_error");
    expect(rows[0].querySelector(".soql").textContent).toContain("GROUP BY ActivityDate");
    expect(rows[0].querySelector(".binds").textContent).toContain(":parentId");
    expect(root.querySelector('[data-panel="queries"] .panel-title').textContent).toContain("1312 ms in all");
    // The time each used source took, and what the server left out.
    const bySource = [...root.querySelectorAll("table.by-source tbody tr")];
    expect(bySource.map((r) => r.querySelector("td").textContent.trim())).toEqual(["Tasks", "Events"]);
    expect(bySource[0].textContent).toContain("counted, then rows");
    expect(root.querySelector('[data-panel="notes"]').textContent).toContain("Not queried");
    expect(root.querySelector(".problems").textContent).toContain("Events couldn't be read.");
    expect(root.querySelector('[data-panel="stats"]').textContent).toContain("14 of 100");
  });

  it("shows the data sources and the user's permissions on the Config tab", async () => {
    const root = mount().shadowRoot;
    await runIt(root);
    root.querySelector('.tab[data-tab="config"]').click();
    await flush();
    expect(root.querySelector(".tab_on").textContent.trim()).toBe("Config");
    expect(root.querySelector('[data-panel="queries"]')).toBeNull();
    const sources = [...root.querySelectorAll("table.sources tbody tr")];
    expect(sources).toHaveLength(2);
    expect(sources[0].textContent).toContain("Priority (no read access)");
    expect(sources[1].classList).toContain("row_muted");
    expect(sources[1].textContent).toContain("Inactive (Active is off).");
    expect(root.querySelector('[data-panel="page"]').textContent).toContain("Carol Tezak");
    expect(root.querySelector('[data-panel="permissions"]').textContent).toContain("Modify All Data");
  });

  it("keeps the timeline on the page whichever tab is showing, and shows it on Output", async () => {
    const root = mount().shadowRoot;
    await runIt(root);
    const output = () => root.querySelector(".tabpanel_output");
    // Out of sight, but still there to be timed.
    expect(root.querySelector("c-time-drive")).not.toBeNull();
    expect(output().classList).toContain("tabpanel_off");
    root.querySelector('.tab[data-tab="output"]').click();
    await flush();
    expect(output().classList).not.toContain("tabpanel_off");
    expect(root.querySelector(".summary").textContent).toContain("48 items");
    // Back to Config and the same card is still there, not drawn again.
    const card = root.querySelector("c-time-drive");
    root.querySelector('.tab[data-tab="config"]').click();
    await flush();
    expect(root.querySelector("c-time-drive")).toBe(card);
  });

  it("moves between the tabs with the arrow keys", async () => {
    const root = mount().shadowRoot;
    await runIt(root);
    const list = root.querySelector('[role="tablist"]');
    list.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true }));
    await flush();
    expect(root.querySelector(".tab_on").textContent.trim()).toBe("Output");
    list.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true }));
    await flush();
    expect(root.querySelector(".tab_on").textContent.trim()).toBe("Config");
  });

  it("draws the vertical card for Down", async () => {
    const root = mount().shadowRoot;
    await enter(root, ID);
    root.querySelector("lightning-combobox").dispatchEvent(new CustomEvent("change", { detail: { value: "Down" } }));
    await flush();
    root.querySelector("lightning-button.run-load").click();
    await flush();
    expect(run).toHaveBeenLastCalledWith(expect.objectContaining({ layout: "Down" }));
    expect(root.querySelector("c-time-drive").layout).toBe("Vertical");
  });

  it("says why a run failed", async () => {
    run.mockRejectedValue({ body: { message: "Only admins (with Customize Application) can run diagnostics." } });
    const root = mount().shadowRoot;
    await runIt(root, { reported: false });
    expect(root.querySelector(".error").textContent).toContain("Customize Application");
    expect(root.querySelector("table.queries")).toBeNull();
  });
});
