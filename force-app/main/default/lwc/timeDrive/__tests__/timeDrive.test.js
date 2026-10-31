import { createElement } from "lwc";
import TIME_ZONE from "@salesforce/i18n/timeZone";
import { setup as setupAccessibility } from "@sa11y/jest";
import TimeDrive from "c/timeDrive";
import getTimeline from "@salesforce/apex/TimeDriveController.getTimeline";
import getTimelineDiagnosed from "@salesforce/apex/TimeDriveController.getTimelineDiagnosed";
import { currentServerReport, clear as clearTraceLog } from "c/timeDriveTraceLog";
import getDays from "@salesforce/apex/TimeDriveController.getPageDays";
import getRights from "@salesforce/apex/TimeDriveController.getRights";
import getPreference from "@salesforce/apex/TimeDriveController.getPreference";
import savePreference from "@salesforce/apex/TimeDriveController.savePreference";
import getActivityActions from "@salesforce/apex/TimeDriveController.getActivityActions";
import TimeDriveConfirm from "c/timeDriveConfirm";
import { deleteRecord } from "lightning/uiRecordApi";
import { registerRefreshHandler } from "lightning/refresh";
import { navigated } from "lightning/navigation";
import { IsConsoleNavigation, openTab } from "lightning/platformWorkspaceApi";
import {
  ago,
  buildMinimap,
  dayAtPercent,
  percentAtDay,
  dayLabel,
  periodLabel,
  todayKey,
  windowEnds,
  windowRange
} from "../timeDriveModel";
import { describeError } from "c/timeDriveErrors";

jest.mock(
  "@salesforce/apex/TimeDriveController.getPreference",
  () => ({ default: jest.fn(() => Promise.resolve({})) }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/TimeDriveController.savePreference",
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  {
    virtual: true
  }
);
jest.mock("@salesforce/apex/TimeDriveController.getTimeline", () => ({ default: jest.fn() }), { virtual: true });
jest.mock(
  "@salesforce/apex/TimeDriveController.getRights",
  () => ({ default: jest.fn(() => Promise.resolve({ canEdit: true, canDelete: true })) }),
  {
    virtual: true
  }
);
jest.mock("@salesforce/apex/TimeDriveController.getTimelineDiagnosed", () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeDriveController.getPageDays", () => ({ default: jest.fn() }), {
  virtual: true
});
// Navigation that records where the component asked to go.
jest.mock("lightning/navigation", () => {
  const Navigate = Symbol("Navigate");
  const GenerateUrl = Symbol("GenerateUrl");
  const record = jest.fn();
  const NavigationMixin = (Base) =>
    class extends Base {
      [Navigate](pageReference) {
        record(pageReference);
      }
      [GenerateUrl]() {
        return Promise.resolve("https://www.example.com");
      }
    };
  NavigationMixin.Navigate = Navigate;
  NavigationMixin.GenerateUrl = GenerateUrl;
  return { NavigationMixin, navigated: record };
});
jest.mock(
  "@salesforce/apex/TimeDriveController.getActivityActions",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

// The summary half of getTimeline, answered like the wire it replaced: the
// calls waiting for an answer are kept, and emit/error settle them.
const waiting = [];
const getSummary = {
  getLastConfig: () => getTimeline.mock.calls[getTimeline.mock.calls.length - 1]?.[0],
  emit: (summary, extra = {}) => {
    for (const call of waiting.splice(0)) call.resolve({ summary, keys: [], events: [], ...extra });
  },
  error: (error) => {
    for (const call of waiting.splice(0)) call.reject(error);
  }
};
getTimeline.mockImplementation(() => new Promise((resolve, reject) => waiting.push({ resolve, reject })));

// Asks the card for the timeline again, as its Refresh button does: the next
// answer is then taken as a new one.
const refresh = async (element) => {
  element.shadowRoot.querySelector('lightning-button-icon[title="Refresh"]').click();
  await Promise.resolve();
};

// The Filters panel lives in its own component, inside the timeline.
const filtersRoot = (root) => root.querySelector("c-time-drive-filters").shadowRoot;

// ---- a small fake server: the summary and day pages, filtered like Apex ----

// Day keys in Salesforce's time zone, as the server works them out.
const DAY_KEY = new Intl.DateTimeFormat("en-CA", {
  timeZone: TIME_ZONE,
  year: "numeric",
  month: "2-digit",
  day: "2-digit"
});
const dayKeyOf = (e) => DAY_KEY.format(new Date(e.occurredAt));
// History and Future in years, as the server reads them: Future None is up to
// the end of today.
const windowOf = ({ historyYears, futureYears }) => {
  const month = 30.44 * 86400000;
  const endOfToday = new Date(new Date().setHours(23, 59, 59, 999)).getTime();
  const back = Number(historyYears) || 0.5;
  const ahead = Number(futureYears) || 0;
  return { since: Date.now() - back * 12 * month, until: endOfToday + ahead * 12 * month };
};
const serverFilter = (events, { categories, hiddenTypes, rangeDays, search, historyYears, futureYears } = {}) => {
  const { since, until } = windowOf({ historyYears, futureYears });
  const after = rangeDays ? Date.now() - rangeDays * 86400000 : null;
  const needle = (search ?? "").trim().toLowerCase();
  return events.filter((e) => {
    // The fixtures' sources are all in All, as well as their own lens.
    if (categories?.length && !categories.includes("All") && !categories.includes(e.category)) return false;
    if (hiddenTypes?.includes(e.type)) return false;
    const time = new Date(e.occurredAt).getTime();
    if (time < since || time > until) return false;
    if (after && new Date(e.occurredAt).getTime() < after) return false;
    if (!needle) return true;
    return [e.title, e.subtitle, e.sourceLabel, ...(e.details ?? []).map((d) => d.value)]
      .join(" ")
      .toLowerCase()
      .includes(needle);
  });
};
let served = { events: [], warnings: [] };
const summarise = (config = {}) => {
  const all = [...served.events].sort((a, b) => new Date(b.occurredAt) - new Date(a.occurredAt));
  const kept = serverFilter(all, config);
  const days = [];
  for (const e of kept) {
    const key = dayKeyOf(e);
    let day = days[days.length - 1];
    if (!day || day.key !== key) {
      day = { key, count: 0, orders: 0, spent: 0 };
      days.push(day);
    }
    day.count++;
    if (e.type === "purchase") {
      day.orders++;
      day.spent += e.amount ?? 0;
    }
  }
  // Like Apex: one entry per type in the view, with the source's label.
  const firstOfType = new Map();
  const perType = new Map();
  for (const e of serverFilter(all, { categories: config.categories })) {
    if (!firstOfType.has(e.type)) firstOfType.set(e.type, e);
    perType.set(e.type, (perType.get(e.type) ?? 0) + 1);
  }
  const types = [...firstOfType.values()].map((e) => ({
    type: e.type,
    count: perType.get(e.type),
    label: e.typeLabel,
    icon: e.icon,
    iconColour: e.iconColour
  }));
  return {
    warnings: served.warnings ?? [],
    problems: served.problems ?? [],
    total: kept.length,
    unfilteredTotal: all.length,
    days,
    types,
    groupOver: 50
  };
};
// Like Apex: a day with more than 50 events comes back one row per type.
const groupBusyDays = (events) => {
  const byDay = new Map();
  for (const e of events) byDay.set(e.dayKey, [...(byDay.get(e.dayKey) ?? []), e]);
  const rows = [];
  for (const [day, list] of byDay) {
    if (list.length <= 50) {
      rows.push(...list);
      continue;
    }
    const groups = new Map();
    for (const e of list) {
      const g = groups.get(e.type) ?? {
        id: `group-${day}-${e.type}`,
        type: e.type,
        category: e.category,
        dayKey: day,
        grouped: true,
        // Listed page by page (View all): emails stand in for a CRM type.
        pageable: e.type === "email",
        groupCount: 0,
        occurredAt: e.occurredAt,
        firstAt: e.occurredAt
      };
      g.groupCount++;
      if (e.occurredAt > g.occurredAt) g.occurredAt = e.occurredAt;
      if (e.occurredAt < g.firstAt) g.firstAt = e.occurredAt;
      groups.set(e.type, g);
    }
    rows.push(...groups.values());
  }
  return rows;
};

// Serve these events: answer the timeline requests and every day-page request.
let answered = null;
// What makes two timeline requests the same query (the rest of a request says
// where the card opens, not what it asks for).
const queryOf = (p = {}) => JSON.stringify([p.categories, p.hiddenTypes, p.historyYears, p.futureYears]);
const answer = () => {
  const config = getSummary.getLastConfig() ?? {};
  answered = queryOf(config);
  getSummary.emit(summarise(config));
};
const emitEvents = (data) => {
  served = data;
  getDays.mockImplementation((params) =>
    Promise.resolve(
      groupBusyDays(
        serverFilter(served.events, params)
          .filter((e) => params.dayKeys.includes(dayKeyOf(e)))
          .map((e) => ({ ...e, dayKey: dayKeyOf(e) }))
      )
    )
  );
  answer();
};
// The component changed its query (filters, view, search): answer it.
const reemit = () => answer();
// Let the component render and fetch, answering any new timeline request on the way.
const flush = async () => {
  for (let i = 0; i < 6; i++) {
    await new Promise((resolve) => setTimeout(resolve, 0));
    if (answered !== null && queryOf(getSummary.getLastConfig()) !== answered) answer();
  }
};

// Wait out the pause after which held keys and drags draw and fetch.
const settle = async () => {
  await new Promise((resolve) => setTimeout(resolve, 300));
  await flush();
};

// Scrolls the vertical list to an end, as the wheel or keyboard would, with
// the sizes jsdom doesn't lay out.
const scrollList = async (root, edge) => {
  const track = root.querySelector(".track_bounded");
  Object.defineProperty(track, "clientHeight", { configurable: true, value: 560 });
  Object.defineProperty(track, "scrollHeight", { configurable: true, value: 2000 });
  Object.defineProperty(track, "scrollTop", { configurable: true, writable: true, value: edge === "top" ? 0 : 1440 });
  track.dispatchEvent(new CustomEvent("scroll"));
  await new Promise((resolve) => requestAnimationFrame(resolve));
  await flush();
};

const NOW = new Date(2026, 9, 18, 12, 0).getTime();
const at = (daysAgo, hour = 12) => new Date(new Date(NOW).setHours(hour, 0, 0, 0) - daysAgo * 86400000).toISOString();

const EVENTS = [
  {
    id: "o1",
    recordId: "a01000000000001AAA",
    type: "purchase",
    category: "Commerce",
    title: "Order placed",
    subtitle: "The Savory Spot · $48.00",
    occurredAt: at(0, 11),
    details: [{ label: "Order", value: "O-1" }],
    sourceObject: "Invoice__c",
    sourceLabel: "Sales Cloud · Order"
  },
  {
    id: "e1",
    type: "email",
    category: "Marketing",
    title: "Email opened",
    subtitle: "Free delivery this Friday",
    occurredAt: at(0, 9),
    details: [],
    sourceObject: "ssot__EmailEngagement__dlm",
    sourceLabel: "Data 360 · Email Engagement"
  },
  {
    id: "w1",
    type: "web",
    category: "Digital",
    title: "Page view",
    subtitle: "Menu · Bella Napoli",
    occurredAt: at(1),
    details: [],
    sourceObject: "ssot__WebsiteEngagement__dlm",
    sourceLabel: "Data 360 · Website Engagement"
  },
  {
    id: "c1",
    type: "case",
    category: "Service",
    title: "Case opened",
    subtitle: "Late delivery",
    occurredAt: at(40),
    details: [],
    sourceObject: "Case",
    sourceLabel: "Service Cloud · Case"
  }
];

describe("c-time-drive", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });

  const render = async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    document.body.appendChild(element);
    emitEvents({ events: EVENTS, warnings: [] });
    await flush();
    return element;
  };

  it("shows every event, grouped by day", async () => {
    const element = await render();
    expect(element.shadowRoot.querySelectorAll(".event")).toHaveLength(4);
    // Three days with items, and today (with none) as a placeholder first.
    // And the window's start, an end of its own, last.
    const days = element.shadowRoot.querySelectorAll(".day");
    expect(days).toHaveLength(5);
    // From History's start to the earliest item.
    expect(days[4].querySelector(".nothing-now-text").textContent).toMatch(
      /^Nothing between \w{3} \d+, \d{4} and Sep 7, 2026$/
    );
    expect(days[0].querySelector(".nothing-now-text").textContent).toBe("Nothing today");
    expect(days[0].querySelector(".day-meta").textContent).toBe("");
    expect(days[1].querySelector(".nothing-now")).toBeNull();
    expect(element.shadowRoot.querySelector(".summary").textContent).toContain("4 items");
  });

  it("expands an event to show its details and source label", async () => {
    const element = await render();
    const row = element.shadowRoot.querySelector('.chevron-button[data-id="o1"]');
    expect(row.getAttribute("aria-expanded")).toBe("false");
    row.click();
    await flush();
    expect(row.getAttribute("aria-expanded")).toBe("true");
    expect(row.closest(".event").classList).toContain("event_open");
    const detail = element.shadowRoot.querySelector(".event-detail");
    expect(detail.textContent).toContain("O-1");
    expect(detail.textContent).toContain("Sales Cloud · Order");
    expect(detail.textContent).not.toContain("Invoice__c");
  });

  it("tells the server which days are busy, so it counts only those", async () => {
    const busy = Array.from({ length: 60 }, (_, i) => ({
      ...EVENTS[1],
      id: `b${i}`,
      occurredAt: EVENTS[1].occurredAt
    }));
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Vertical";
    document.body.appendChild(element);
    emitEvents({ events: [...EVENTS, ...busy], warnings: [] });
    await flush();
    const { dayKeys, busyKeys } = getDays.mock.calls.at(-1)[0];
    // The 60 on one day are busy; the other days are quiet, read as rows.
    expect(busyKeys).toHaveLength(1);
    expect(dayKeys).toContain(busyKeys[0]);
    expect(dayKeys.length).toBeGreaterThan(busyKeys.length);
  });

  it("opens and closes items day by day, each day keeping its own", async () => {
    const element = await render();
    const root = element.shadowRoot;
    const open = () =>
      [...root.querySelectorAll(".event_open")].map((e) => e.querySelector(".chevron-button").dataset.id);
    // One item on 17 Oct, one on 16 Oct.
    root.querySelector('.chevron-button[data-id="o1"]').click();
    await flush();
    root.querySelector('.chevron-button[data-id="w1"]').click();
    await flush();
    expect(open().sort()).toEqual(["o1", "w1"]);
    // Closing one leaves the other day's open, and its own day's rail back.
    root.querySelector('.chevron-button[data-id="o1"]').click();
    await flush();
    expect(open()).toEqual(["w1"]);
    expect(root.querySelector('.chevron-button[data-id="o1"]').getAttribute("aria-expanded")).toBe("false");
    expect(root.querySelector('.chevron-button[data-id="w1"]').getAttribute("aria-expanded")).toBe("true");
  });

  it("expands and collapses everything", async () => {
    const element = await render();
    const toggle = element.shadowRoot.querySelector(".expand-button");
    expect(toggle.title).toBe("Expand all");
    expect(toggle.selected).toBe(false);
    expect(toggle.iconName).toBe("utility:expand_all");
    toggle.click();
    await flush();
    expect(element.shadowRoot.querySelectorAll(".event_open")).toHaveLength(4);
    expect(toggle.title).toBe("Collapse all");
    // Stateful: it shows as on (blue) while everything is open.
    expect(toggle.selected).toBe(true);
    // The icon turns to Collapse all, and back.
    expect(toggle.iconName).toBe("utility:collapse_all");
    toggle.click();
    await flush();
    expect(element.shadowRoot.querySelectorAll(".event_open")).toHaveLength(0);
    expect(toggle.iconName).toBe("utility:expand_all");
  });

  it("never shows Expand all for an empty timeline, even while it refreshes", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    document.body.appendChild(element);
    emitEvents({ events: [], warnings: [] });
    await flush();
    expect(element.shadowRoot.querySelector(".expand-button")).toBeNull();
    element.shadowRoot.querySelector('lightning-button-icon[title="Refresh"]').click();
    await Promise.resolve();
    expect(element.shadowRoot.querySelector(".expand-button")).toBeNull();
  });

  it("draws a source's highlights after the title, as an icon or a dot, each saying what it means", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    document.body.appendChild(element);
    emitEvents({
      events: [
        {
          ...EVENTS[0],
          flags: [
            { icon: "utility:priority", colour: "#C23934", text: "Priority: High" },
            { icon: "dot", colour: "#2E844A", text: "Closed" }
          ]
        },
        EVENTS[1]
      ],
      warnings: []
    });
    await flush();
    const flags = [...element.shadowRoot.querySelectorAll(".flag")];
    expect(flags.map((f) => f.getAttribute("aria-label"))).toEqual(["Priority: High", "Closed"]);
    expect(flags[0].getAttribute("style")).toBe("--flag: #C23934");
    expect(flags[0].querySelector("lightning-icon").iconName).toBe("utility:priority");
    expect(flags[1].querySelector(".flag-dot")).not.toBeNull();
    expect(flags[1].querySelector("lightning-icon")).toBeNull();
  });

  it("switches to titles only with the button after Today, and keeps it as the user's own", async () => {
    savePreference.mockClear();
    const element = await render();
    const root = element.shadowRoot;
    expect(root.querySelectorAll(".event-time").length).toBeGreaterThan(0);
    const button = root.querySelector(".lite-button");
    expect(button.iconName).toBe("utility:hide");
    expect(button.selected).toBe(false);
    expect(button.title).toBe("Titles only");
    button.click();
    await flush();
    expect(root.querySelectorAll(".event-time")).toHaveLength(0);
    expect(root.querySelector(".event-title")).not.toBeNull();
    expect(root.querySelector(".lite-button").selected).toBe(true);
    expect(root.querySelector(".lite-button").title).toBe("Show times and dates");
    // Kept in the org for this user, not in the browser; nothing else is.
    expect(savePreference).toHaveBeenCalledTimes(1);
    expect(savePreference).toHaveBeenCalledWith({ lens: null, itemDetail: "lite" });
  });

  it("starts the way the user left it, whatever the page's default", async () => {
    getPreference.mockResolvedValueOnce({ itemDetail: "Lite", lens: "Service" });
    const element = await render();
    expect(element.shadowRoot.querySelectorAll(".event-time")).toHaveLength(0);
    expect(getSummary.getLastConfig()).toMatchObject({ categories: ["Service"] });
    expect(element.shadowRoot.querySelector(".view-button").textContent).toContain("Service");
  });

  it("ignores a kept lens the org no longer offers, and a preference that can't be read", async () => {
    getPreference.mockResolvedValueOnce({ lens: "Gone" });
    const element = await render();
    expect(element.shadowRoot.querySelector(".view-button").textContent).toContain("All items");
    getPreference.mockRejectedValueOnce(new Error("no access"));
    const again = await render();
    expect(again.shadowRoot.querySelector(".view-button").textContent).toContain("All items");
  });

  it("offers only what the user may do: Edit and Delete, Edit alone, or no menu at all", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    document.body.appendChild(element);
    const at1 = EVENTS[0].occurredAt;
    emitEvents({
      events: [
        { ...EVENTS[0], id: "both", recordId: "a01000000000001AAA", canEdit: true, canDelete: true },
        { ...EVENTS[0], id: "edit", recordId: "a01000000000002AAA", canEdit: true, canDelete: false, occurredAt: at1 },
        { ...EVENTS[0], id: "none", recordId: "a01000000000003AAA", canEdit: false, canDelete: false, occurredAt: at1 },
        EVENTS[1]
      ],
      warnings: []
    });
    await flush();
    const buttons = [...element.shadowRoot.querySelectorAll(".row-menu-button")];
    // Edit and Delete, or Edit alone, get an ellipsis; no rights, no menu: the
    // third record and the Data 360 email have only the spot.
    expect(buttons.map((m) => m.dataset.record)).toEqual(["a01000000000001AAA", "a01000000000002AAA"]);
    expect(element.shadowRoot.querySelectorAll(".row-menu-spacer").length).toBeGreaterThan(0);
    expect(buttons[0].querySelector("lightning-icon").iconName).toBe("utility:threedots_vertical");
    // Both items for the first.
    buttons[0].click();
    await flush();
    expect([...element.shadowRoot.querySelectorAll(".row-popover-item")].map((i) => i.dataset.value)).toEqual([
      "edit",
      "delete"
    ]);
  });

  it("opens a menu with only what the user may do, and Edit opens the record's edit form", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    document.body.appendChild(element);
    emitEvents({
      events: [{ ...EVENTS[0], id: "edit-only", recordId: "a01000000000002AAA", canEdit: true, canDelete: false }],
      warnings: []
    });
    await flush();
    const root = element.shadowRoot;
    expect(root.querySelector(".row-popover")).toBeNull();
    getRights.mockResolvedValueOnce({ canEdit: true, canDelete: false });
    root.querySelector(".row-menu-button").click();
    await flush();
    const items = [...root.querySelectorAll(".row-popover-item")];
    expect(items.map((i) => i.textContent.trim())).toEqual(["Edit"]);
    items[0].click();
    await flush();
    expect(navigated).toHaveBeenLastCalledWith({
      type: "standard__recordPage",
      attributes: { recordId: "a01000000000002AAA", actionName: "edit" }
    });
    expect(root.querySelector(".row-popover")).toBeNull();
  });

  it("asks what the user may do with a record only when its menu opens, once", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    document.body.appendChild(element);
    getRights.mockClear();
    emitEvents({ events: [{ ...EVENTS[0], canEdit: true, canDelete: true, objectLabel: "Event" }], warnings: [] });
    await flush();
    const root = element.shadowRoot;
    // Drawing the days asked nothing about the record.
    expect(getRights).not.toHaveBeenCalled();
    // The record allows less than the object: Delete goes once that is known.
    let release;
    getRights.mockReturnValueOnce(new Promise((resolve) => (release = resolve)));
    root.querySelector(".row-menu-button").click();
    await flush();
    expect(getRights).toHaveBeenCalledWith({ recordId: "a01000000000001AAA" });
    // While it is asked: a spinner, and nothing else in the menu.
    expect(root.querySelector(".row-popover-wait lightning-spinner")).not.toBeNull();
    expect(root.querySelectorAll(".row-popover-item")).toHaveLength(0);
    expect(root.querySelector(".row-popover-note")).toBeNull();
    release({ canEdit: true, canDelete: false });
    await flush();
    expect(root.querySelector(".row-popover-wait")).toBeNull();
    expect(root.querySelector('.row-popover-item[data-value="delete"]')).toBeNull();
    expect(root.querySelector('.row-popover-item[data-value="edit"]')).not.toBeNull();
    // Closed and opened again: known, so not asked again.
    root.querySelector(".row-menu-button").click();
    await flush();
    root.querySelector(".row-menu-button").click();
    await flush();
    expect(getRights).toHaveBeenCalledTimes(1);
    expect(root.querySelector('.row-popover-item[data-value="edit"]')).not.toBeNull();
  });

  it("says so when the record allows neither Edit nor Delete", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    document.body.appendChild(element);
    emitEvents({ events: [{ ...EVENTS[0], canEdit: true, canDelete: true, objectLabel: "Event" }], warnings: [] });
    await flush();
    const root = element.shadowRoot;
    getRights.mockResolvedValueOnce({ canEdit: false, canDelete: false });
    root.querySelector(".row-menu-button").click();
    await flush();
    expect(root.querySelectorAll(".row-popover-item")).toHaveLength(0);
    expect(root.querySelector(".row-popover-note").textContent).toMatch(/can't edit or delete/);
  });

  it("deletes after a confirm, and not when it is declined", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    document.body.appendChild(element);
    emitEvents({ events: [{ ...EVENTS[0], canEdit: true, canDelete: true, objectLabel: "Event" }], warnings: [] });
    await flush();
    const root = element.shadowRoot;
    const pickDelete = async () => {
      root.querySelector(".row-menu-button").click();
      await flush();
      root.querySelector('.row-popover-item[data-value="delete"]').click();
      await flush();
    };
    deleteRecord.mockClear();
    TimeDriveConfirm.open = jest.fn().mockResolvedValueOnce(false);
    await pickDelete();
    expect(deleteRecord).not.toHaveBeenCalled();
    // While it deletes: the row dims and its menu is a spinner, read out as Deleting.
    let finish;
    deleteRecord.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          finish = resolve;
        })
    );
    const toasts = [];
    element.addEventListener("lightning__showtoast", (e) => toasts.push(e.detail));
    TimeDriveConfirm.open = jest.fn().mockResolvedValueOnce(true);
    await pickDelete();
    expect(deleteRecord).toHaveBeenCalledWith("a01000000000001AAA");
    const row = root.querySelector(".event_deleting");
    expect(row).not.toBeNull();
    expect(row.getAttribute("aria-busy")).toBe("true");
    expect(row.querySelector(".row-menu_busy lightning-spinner").alternativeText).toBe("Deleting…");
    expect(row.querySelector(".row-menu-button")).toBeNull();
    // Done: the item goes at once, without reloading the timeline, and the toast names it.
    finish();
    await flush();
    expect(root.querySelector(".event_deleting")).toBeNull();
    expect([...root.querySelectorAll(".event-title")].map((n) => n.textContent)).not.toContain(EVENTS[0].title);
    expect(root.querySelector(".skeleton-frame")).toBeNull();
    expect(toasts.at(-1)).toMatchObject({ title: `Event "${EVENTS[0].title}" was deleted.`, variant: "success" });
    // Asked as Salesforce asks it.
    expect(TimeDriveConfirm.open).toHaveBeenCalledWith({
      size: "small",
      confirmLabel: "Delete",
      title: "Delete Event",
      message: "Are you sure you want to delete this event?"
    });
  });

  it("asks for the days it opens on with the summary, and draws them without asking again", async () => {
    getDays.mockClear();
    getDays.mockImplementation(() => Promise.resolve([]));
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Vertical";
    document.body.appendChild(element);
    // Where it opens, so the server can read those days with the summary.
    expect(getSummary.getLastConfig()).toMatchObject({ focus: "Today", newestFirst: true, centred: false, count: 7 });
    served = { events: EVENTS, warnings: [] };
    const summary = summarise({});
    const keys = summary.days.map((d) => d.key);
    const events = EVENTS.map((e) => ({ ...e, dayKey: dayKeyOf(e) }));
    getSummary.emit(summary, { keys, events });
    await flush();
    expect(element.shadowRoot.querySelectorAll(".event")).toHaveLength(events.length);
    expect(getDays).not.toHaveBeenCalled();
  });

  it("asks only for the summary when it refreshes, and then for the days it is on", async () => {
    const element = await render();
    getDays.mockClear();
    await refresh(element);
    expect(getSummary.getLastConfig()).toMatchObject({ count: 0 });
  });

  it("uses the horizontal layout when asked", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Horizontal";
    document.body.appendChild(element);
    emitEvents({ events: EVENTS, warnings: [] });
    await flush();
    expect(element.shadowRoot.querySelector(".card").classList).toContain("card_horizontal");
    // A fixed height in the horizontal layout (default 260px), clamped.
    expect(element.shadowRoot.querySelector(".track").style.height).toBe("260px");
    element.horizontalHeight = 5000;
    await flush();
    expect(element.shadowRoot.querySelector(".track").style.height).toBe("1000px");
  });

  it("puts the year on every horizontal column when the days span years", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Horizontal";
    element.historyYears = "2";
    document.body.appendChild(element);
    const lastYear = { ...EVENTS[0], id: "old", occurredAt: new Date(Date.now() - 400 * 86400000).toISOString() };
    emitEvents({ events: [...EVENTS, lastYear], warnings: [] });
    await flush();
    const months = [...element.shadowRoot.querySelectorAll(".date-month")].map((m) => m.textContent);
    expect(months.length).toBeGreaterThan(2);
    // This year's columns too, not only last year's.
    for (const month of months) expect(month).toMatch(/\d{4}/);
  });

  it("draws rounded squares in SLDS 1 and circles in SLDS 2", async () => {
    // SLDS 1: no global styling hooks on the page.
    let element = await render();
    expect(element.shadowRoot.querySelector(".card").classList).toContain("card_slds1");
    document.body.removeChild(element);
    // SLDS 2 defines them.
    element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.style.setProperty("--slds-g-color-surface-1", "#ffffff");
    document.body.appendChild(element);
    emitEvents({ events: EVENTS, warnings: [] });
    await flush();
    expect(element.shadowRoot.querySelector(".card").classList).not.toContain("card_slds1");
  });

  it("shows warnings and an error", async () => {
    const element = await render();
    await refresh(element);
    emitEvents({ events: [], warnings: ["Data 360 isn't available in this org"] });
    await flush();
    expect(element.shadowRoot.querySelector(".warning").textContent).toContain("Data 360");
    expect(element.shadowRoot.querySelector(".empty").textContent).toContain("No data found");
    // Dates, and where to look next; nothing to expand.
    expect(element.shadowRoot.querySelector(".empty").textContent).toMatch(
      /No data found between .+ and .+\. Check your filters and try again\./
    );
    expect([...element.shadowRoot.querySelectorAll(".expand-button")]).toHaveLength(0);
    // Set up, just nothing found: the no-results illustration.
    expect(element.shadowRoot.querySelector(".empty lightning-illustration").illustrationName).toBe("noresults:search");
  });

  it("says when a page has no sources set up, in the timeline and its filters", async () => {
    const element = await render();
    served = { events: [], warnings: [] };
    await refresh(element);
    getSummary.emit({
      total: 0,
      unfilteredTotal: 0,
      days: [],
      types: [],
      noSources: true,
      page: "Person Account"
    });
    await flush();
    const root = element.shadowRoot;
    // A setup error, with its own illustration.
    expect(root.querySelector(".empty h3").textContent).toBe("Setup Error");
    expect(root.querySelector(".empty").textContent).toContain("This object has not been setup by your admin.");
    expect(root.querySelector(".empty lightning-illustration").illustrationName).toBe("access:request");
    root.querySelector(".filter-button").click();
    await flush();
    expect(filtersRoot(root).querySelector(".filter-none").textContent).toBe(
      "This object has not been setup by your admin."
    );
    // Vertical, the empty state is as tall as it needs.
    expect(element.shadowRoot.querySelector(".empty").style.height).toBe("");
    const warn = jest.spyOn(console, "warn").mockImplementation(() => {});
    await refresh(element);
    getSummary.error({
      message: "System.QueryException: No such column 'Secret__c' on entity 'Invoice__c'",
      stackTrace: "Class.TimeDriveSoqlProvider.getRows: line 84, column 1"
    });
    await flush();
    const state = element.shadowRoot.querySelector(".empty_error");
    expect(state.getAttribute("role")).toBe("alert");
    // A missing column is for an admin to set up: the setup illustration.
    expect(state.querySelector("lightning-illustration").illustrationName).toBe("access:request");
    expect(state.textContent).toContain("isn't set up in this org");
    expect(state.textContent).not.toContain("Possible cause");
    // Never the raw message or the stack trace.
    expect(state.textContent).not.toMatch(/QueryException|Secret__c|line 84/);
    // The technical summary goes to the console, without the stack trace.
    expect(warn.mock.calls[0][1]).toContain("No such column");
    expect(warn.mock.calls[0][1]).not.toContain("line 84");
    // The error state, too.
    expect(state.style.height).toBe("");
    warn.mockRestore();
  });
});

describe("c-time-drive sources that couldn't be read", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });
  const problems = [
    { source: "Order placed", kind: "access" },
    { source: "Order delivered", kind: "access" },
    { source: "Order canceled", kind: "access" }
  ];
  const mountWith = async (events) => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Vertical";
    document.body.appendChild(element);
    emitEvents({ events, warnings: [], problems });
    await flush();
    return element.shadowRoot;
  };

  it("names them in one notice, above what did load", async () => {
    const root = await mountWith(EVENTS);
    const notice = root.querySelector(".issue");
    expect(notice.textContent).toContain("Order placed, Order delivered, and Order canceled couldn't be read.");
    expect(notice.textContent).not.toMatch(/Possible cause|To fix/);
    expect(root.querySelectorAll(".warning")).toHaveLength(0);
    expect(root.querySelectorAll(".event").length).toBeGreaterThan(0);
  });

  it("fills the canvas with the error when nothing could be read", async () => {
    const root = await mountWith([]);
    expect(root.querySelector(".issue")).toBeNull();
    const state = root.querySelector(".empty_error");
    expect(state.textContent).toContain("The timeline couldn't be read");
    expect(state.textContent).toContain("Order canceled couldn't be read.");
    expect(state.querySelector("button").textContent).toBe("Try again");
  });
});

describe("describeError", () => {
  it("says what went wrong and why, never the raw message", () => {
    // A GraphQL error: a field the user can't filter on.
    const graphql = describeError([
      {
        message:
          "Validation error (WrongType@[uiapi/query/Survey__c]) : argument 'where' contains a field not in 'Survey__c_Filter': 'Customer__c'"
      }
    ]);
    expect(graphql.kind).toBe("access");
    expect(graphql.message).not.toContain("Survey__c");
    expect(
      describeError({
        status: 500,
        body: { message: "Operation failed due to fields being inaccessible on Sobject Invoice__c" }
      }).kind
    ).toBe("access");
    expect(
      describeError({
        status: 404,
        body: [{ errorCode: "NOT_FOUND", message: "The requested resource does not exist" }]
      }).kind
    ).toBe("notFound");
    expect(describeError({ status: 0, body: { message: "Failed to fetch" } }).kind).toBe("offline");
    expect(describeError({ status: 500, body: { message: "Apex CPU time limit exceeded" } }).kind).toBe("busy");
    expect(describeError(new Error("Invalid type: Location__c")).kind).toBe("setup");
    // The timeline's server names the kind outright.
    expect(describeError({ status: 500, body: { message: "timedrive:access" } }).kind).toBe("access");
    const unknown = describeError({ body: { message: "Boom", stackTrace: "Class.X: line 1" } });
    expect(unknown).toMatchObject({ kind: "unknown", message: "Something went wrong." });
    expect(unknown.detail).toBe("Boom");
  });
});

describe("recency", () => {
  const minutes = (m) => new Date(NOW - m * 60000).toISOString();

  it("says how long ago", () => {
    expect(ago(minutes(5), NOW)).toBe("5 minutes ago");
    expect(ago(new Date(NOW - 26 * 3600000).toISOString(), NOW)).toBe("yesterday");
  });
});

describe("c-time-drive delight", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });

  it("offers a way back when filters hide everything", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    document.body.appendChild(element);
    emitEvents({ warnings: [], events: EVENTS.filter((e) => e.category !== "Service") });
    await flush();
    element.shadowRoot.querySelector("h2 .view-button").click();
    await flush();
    [...element.shadowRoot.querySelectorAll(".view-option")].find((i) => i.dataset.value === "Service").click();
    await flush();
    expect(element.shadowRoot.querySelector(".empty").textContent).toContain(
      "No data found with those filters applied."
    );
    // Filters took everything away: the filter illustration, not the search one.
    expect(element.shadowRoot.querySelector(".empty lightning-illustration").illustrationName).toBe("noresults:filter");
    element.shadowRoot.querySelector(".empty .more-button").click();
    await flush();
    expect(element.shadowRoot.querySelectorAll(".event")).toHaveLength(3);
  });

  it("opens on the lens chosen in App Builder, and on All when it isn't one", async () => {
    const open = async (defaultLens) => {
      const element = createElement("c-time-drive", { is: TimeDrive });
      element.recordId = "003000000000001AAA";
      element.defaultLens = defaultLens;
      document.body.appendChild(element);
      emitEvents({ events: EVENTS, warnings: [] });
      await flush();
      return element;
    };
    const service = await open("Service");
    expect(getSummary.getLastConfig()).toMatchObject({ categories: ["Service"] });
    expect(service.shadowRoot.querySelector(".view-button").textContent).toContain("Service");
    const other = await open("No_Such_Lens");
    expect(getSummary.getLastConfig()).toMatchObject({ categories: ["All"] });
    expect(other.shadowRoot.querySelector(".view-button").textContent).toContain("All items");
  });

  it("names the view as the heading and switches it from its menu", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    document.body.appendChild(element);
    emitEvents({ events: EVENTS, warnings: [] });
    await flush();
    const root = element.shadowRoot;
    // No search box; the card is named by its Title, the heading by the view.
    expect(root.querySelector("lightning-input[type='search']")).toBeNull();
    expect(root.querySelector("article").getAttribute("aria-label")).toBe("Time Drive");
    const button = root.querySelector("h2 .view-button");
    expect(button.textContent).toContain("All items");
    expect(button.getAttribute("aria-expanded")).toBe("false");

    // Arrow down opens it on the current view; arrows move; Escape closes.
    button.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }));
    await flush();
    const menu = root.querySelector("[role='menu']");
    const items = [...menu.querySelectorAll("[role='menuitemradio']")];
    expect(button.getAttribute("aria-expanded")).toBe("true");
    expect(items[0].getAttribute("aria-checked")).toBe("true");
    expect(root.activeElement).toBe(items[0]);
    menu.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowUp", bubbles: true }));
    expect(root.activeElement).toBe(items.at(-1));
    menu.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    await flush();
    expect(root.querySelector("[role='menu']")).toBeNull();

    // Picking a view filters the timeline to it and renames the heading.
    button.click();
    await flush();
    const service = [...root.querySelectorAll(".view-option")].find((i) => i.dataset.value === "Service");
    savePreference.mockClear();
    service.click();
    await flush();
    expect(savePreference).toHaveBeenCalledWith({ lens: "Service", itemDetail: null });
    expect(root.querySelector("[role='menu']")).toBeNull();
    expect(getSummary.getLastConfig()).toMatchObject({ categories: ["Service"] });
    expect(root.querySelector(".view-button").textContent).toContain("Service");
    expect(root.querySelectorAll(".event")).toHaveLength(1);
  });

  it("closes the view menu on a press outside it", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    document.body.appendChild(element);
    emitEvents({ events: EVENTS, warnings: [] });
    await flush();
    const root = element.shadowRoot;
    root.querySelector(".view-button").click();
    await flush();
    expect(root.querySelector("[role='menu']")).not.toBeNull();
    document.body.dispatchEvent(new CustomEvent("pointerdown", { bubbles: true }));
    await flush();
    expect(root.querySelector("[role='menu']")).toBeNull();
  });
});

describe("buildMinimap", () => {
  const day = (daysAgo, n, order = false) => ({
    key: new Date(2026, 9, 18 - daysAgo).getTime(),
    label: `d${daysAgo}`,
    events: Array.from({ length: n }, (_, i) => ({ type: order && i === 0 ? "purchase" : "email" }))
  });

  it("gives every active day one cell and compresses quiet stretches", () => {
    const map = buildMinimap([day(0, 4, true), day(1, 1), day(9, 2), day(100, 1)]);
    expect(map.cells).toHaveLength(4);
    const [a, b, c, d] = map.cells;
    const gap = (x, y) => y.left - (x.left + x.width);
    // Back-to-back days nearly touch; a week apart leaves more; three months
    // apart leaves more again, but far less than three months' worth.
    expect(gap(a, b)).toBeLessThan(gap(b, c));
    expect(gap(b, c)).toBeLessThan(gap(c, d));
    expect(gap(c, d)).toBeLessThan(a.width * 3);
    // Cells span the strip.
    expect(d.left + d.width).toBeCloseTo(100, 5);
  });

  it("shades by activity, marks order days and long gaps, and labels months", () => {
    const map = buildMinimap([day(0, 4, true), day(1, 1), day(9, 2), day(100, 1)]);
    // Log scale: counts 4, 1, 2, 1 against a busiest day of 4.
    expect(map.cells.map((c) => c.level)).toEqual([4, 2, 3, 2]);
    expect(map.cells.map((c) => c.hasOrder)).toEqual([true, false, false, false]);
    expect(map.gaps.map((g) => g.days)).toEqual([7, 90]);
    expect(map.months.length).toBeGreaterThanOrEqual(2);
    expect(buildMinimap([])).toEqual({ cells: [], gaps: [], months: [], years: [], now: null });
  });

  it("marks today: its cell when it has items, else a point between the cells", () => {
    // An instant on 18 October in Salesforce's time zone too.
    const local = new Date(2026, 9, 18).getTime();
    let now = local + 12 * 3600000;
    for (let h = -24; h < 48 && todayKey(now) !== local; h++) now = local + h * 3600000;
    // Today has items: its cell, and the marker on it.
    let map = buildMinimap([day(0, 4), day(1, 1), day(9, 2)], { now });
    expect(map.cells.map((c) => c.current)).toEqual([true, false, false]);
    expect(map.now.onCell).toBe(true);
    // Today has none, between two that do: a point between them, in either order.
    map = buildMinimap([day(-3, 1), day(5, 1)], { now });
    expect(map.cells.every((c) => !c.current)).toBe(true);
    expect(map.now.onCell).toBe(false);
    expect(map.now.at).toBeGreaterThan(map.cells[0].left + map.cells[0].width);
    expect(map.now.at).toBeLessThan(map.cells[1].left);
    // Before every item (all in the future), at the start of a newest-first strip's end.
    map = buildMinimap([day(-9, 1), day(-3, 1)], { now });
    expect(map.now.at).toBe(100);
  });
});

describe("buildMinimap on long histories", () => {
  // Every other day for ten years, newest first.
  const decade = Array.from({ length: 1826 }, (_, i) => ({
    key: new Date(2026, 9, 18 - i * 2).getTime(),
    label: `d${i}`,
    count: 1 + (i % 9),
    orders: i % 5 === 0 ? 1 : 0
  }));

  it("groups days into the finest unit that keeps cells readable", () => {
    expect(buildMinimap(decade.slice(0, 40), { maxCells: 120 }).unit).toBe("day");
    const map = buildMinimap(decade, { maxCells: 130 });
    // 1826 days over ten years: too many days or weeks for 130 cells; the
    // 121 months fit.
    expect(map.unit).toBe("month");
    expect(map.cells.length).toBeLessThanOrEqual(130);
    expect(map.cells[0].width).toBeGreaterThan(100 / 200);
    // Every day is in exactly one cell, in order.
    expect(map.cells[0].from).toBe(0);
    expect(map.cells.at(-1).to).toBe(decade.length - 1);
    map.cells.slice(1).forEach((cell, i) => expect(cell.from).toBe(map.cells[i].to + 1));
    expect(map.cells[0].title).toMatch(/items, \d+ orders? on \d+ days$/);
    // A tight strip falls back to quarters, then half-years, then years.
    expect(buildMinimap(decade, { maxCells: 45 }).unit).toBe("quarter");
    const half = buildMinimap(decade, { maxCells: 30 });
    expect(half.unit).toBe("half");
    expect(half.cells[0].title).toMatch(/^H[12] \d{4}: /);
    expect(buildMinimap(decade, { maxCells: 15 }).unit).toBe("year");
  });

  it("labels years on long histories and keeps labels apart", () => {
    const map = buildMinimap(decade, { maxCells: 130, minLabelGap: 6 });
    expect(map.months.every((m) => /^\d{4}$/.test(m.label))).toBe(true);
    map.months.slice(1).forEach((m, i) => expect(m.left - map.months[i].left).toBeGreaterThanOrEqual(6));
    // Short histories still label months.
    const recent = buildMinimap(decade.slice(0, 60), { maxCells: 120, minLabelGap: 6 });
    expect(recent.months.some((m) => /^[A-Za-z]/.test(m.label))).toBe(true);
  });

  it("maps between days and positions inside grouped cells", () => {
    const { cells } = buildMinimap(decade, { maxCells: 130 });
    const cell = cells[10];
    const middle = cell.left + cell.width / 2;
    const day = dayAtPercent(cells, middle);
    expect(day).toBeGreaterThanOrEqual(cell.from);
    expect(day).toBeLessThan(cell.to + 1);
    expect(percentAtDay(cells, day)).toBeCloseTo(middle, 5);
    expect(dayAtPercent(cells, -5)).toBe(0);
    expect(Math.floor(dayAtPercent(cells, 105))).toBe(decade.length - 1);
  });
});

describe("buildMinimap years", () => {
  const onDay = (y, m, d) => ({ key: new Date(y, m, d).getTime(), label: "", events: [{ type: "email" }] });

  it("marks only where one year meets the next", () => {
    const map = buildMinimap([onDay(2026, 0, 3), onDay(2025, 11, 30), onDay(2025, 11, 2), onDay(2024, 10, 5)]);
    expect(map.years.map((y) => y.year)).toEqual([2025, 2024]);
    expect(map.months.filter((m) => m.year).map((m) => `${m.label} ${m.year}`)).toHaveLength(2);
    expect(map.months[0].year).toBeNull();
    const [first, second] = map.cells;
    expect(map.years[0].left).toBeGreaterThan(first.left + first.width - 0.001);
    expect(map.years[0].left).toBeLessThan(second.left + 0.001);
  });

  it("adds no year marks within one year", () => {
    expect(buildMinimap([onDay(2026, 9, 3), onDay(2026, 2, 1)]).years).toEqual([]);
  });
});

describe("c-time-drive summary query", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });

  it("sends every parameter defined, so the wire service makes the request", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    document.body.appendChild(element);
    await flush();
    const config = getSummary.getLastConfig();
    for (const name of ["contactId", "categories", "hiddenTypes", "historyYears", "futureYears"]) {
      expect(config[name]).not.toBeUndefined();
    }
  });
});

describe("c-time-drive loading", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });

  it("holds the horizontal layout's height and seek bar while loading", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Horizontal";
    element.horizontalHeight = 500;
    document.body.appendChild(element);
    await flush();
    const root = element.shadowRoot;
    expect(root.querySelector(".track_skeleton").style.height).toBe("500px");
    expect(root.querySelectorAll(".track_skeleton .day")).toHaveLength(6);
    expect(root.querySelector(".skeleton-frame .seek")).not.toBeNull();
  });

  it("holds the vertical layout's fixed height while loading", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Vertical";
    element.verticalHeight = 480;
    document.body.appendChild(element);
    await flush();
    const root = element.shadowRoot;
    // Up to the height the loaded list can have, filled with days of rows.
    expect(root.querySelector(".track_skeleton").style.maxHeight).toBe("480px");
    expect(root.querySelectorAll(".track_skeleton .day")).toHaveLength(8);
    expect(root.querySelectorAll(".track_skeleton .skeleton-row")).toHaveLength(32);
  });
});

describe("c-time-drive filters panel", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });
  const mount = async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Vertical";
    document.body.appendChild(element);
    emitEvents({ events: EVENTS, warnings: [] });
    await flush();
    return element;
  };
  it("plots the App Builder's History and Future, and says so", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Vertical";
    document.body.appendChild(element);
    const ahead = {
      ...EVENTS[0],
      id: "o2",
      title: "Order scheduled",
      occurredAt: new Date(Date.now() + 20 * 86400000).toISOString()
    };
    emitEvents({ events: [...EVENTS, ahead], warnings: [] });
    await flush();
    const root = element.shadowRoot;
    // Defaults: half a year back, nothing ahead.
    expect(getSummary.getLastConfig()).toMatchObject({ historyYears: "0.5", futureYears: "None" });
    expect(root.querySelector(".summary").textContent).toContain(windowRange("0.5", "None"));
    expect(root.querySelectorAll(".event")).toHaveLength(4);

    element.historyYears = "2";
    element.futureYears = "0.25";
    await flush();
    expect(getSummary.getLastConfig()).toMatchObject({ historyYears: "2", futureYears: "0.25" });
    expect(getDays.mock.calls.at(-1)[0]).toMatchObject({ historyYears: "2", futureYears: "0.25" });
    expect(root.querySelector(".summary").textContent).toContain(windowRange("2", "0.25"));
    // The order 20 days ahead is in the window now.
    expect(root.querySelectorAll(".event")).toHaveLength(5);
  });

  it("shortens the summary in a narrow card", async () => {
    let resize;
    global.ResizeObserver = class {
      constructor(callback) {
        resize = callback;
      }
      observe() {}
      disconnect() {}
    };
    try {
      const element = await mount();
      const root = element.shadowRoot;
      expect(root.querySelector(".summary").textContent).toContain("All types");
      resize([{ contentRect: { width: 360 } }]);
      await flush();
      expect(root.querySelector(".summary").textContent).toBe(
        `${windowRange("0.5", "None", { short: true })} · All types · 4 items`
      );
    } finally {
      delete global.ResizeObserver;
    }
  });

  it("says Today in words on a wide card and with an icon on a narrow one, named either way", async () => {
    let resize;
    global.ResizeObserver = class {
      constructor(callback) {
        resize = callback;
      }
      observe() {}
      disconnect() {}
    };
    try {
      const element = await mount();
      const root = element.shadowRoot;
      expect(root.querySelector("lightning-button.today-button").label).toBe("Today");
      expect(root.querySelector("lightning-button-icon.today-button")).toBeNull();
      resize([{ contentRect: { width: 360 } }]);
      await flush();
      expect(root.querySelector("lightning-button.today-button")).toBeNull();
      const icon = root.querySelector("lightning-button-icon.today-button");
      expect(icon.iconName).toBe("utility:key_dates");
      expect(icon.alternativeText).toBe("Today");
      expect(icon.title).toBe("Today");
    } finally {
      delete global.ResizeObserver;
    }
  });

  const open = async (root) => {
    root.querySelector(".filter-button").click();
    await flush();
    return filtersRoot(root).querySelector(".filter-panel");
  };
  const buttonByLabel = (panel, label) =>
    [...panel.querySelectorAll("lightning-button")].find((b) => b.label === label);

  it("opens in its own component: the button says so, and Escape closes it", async () => {
    const element = await mount();
    const root = element.shadowRoot;
    const button = root.querySelector(".filter-button");
    expect(button.getAttribute("aria-expanded")).toBe("false");
    const panel = await open(root);
    expect(button.getAttribute("aria-expanded")).toBe("true");
    // Focus starts on All types.
    expect(filtersRoot(root).activeElement ?? filtersRoot(root).querySelector(".all-types")).not.toBeNull();
    panel.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    await flush();
    expect(filtersRoot(root).querySelector(".filter-panel")).toBeNull();
    expect(button.getAttribute("aria-expanded")).toBe("false");
  });

  it("drafts changes and discards them on Cancel", async () => {
    const element = await mount();
    const root = element.shadowRoot;
    const panel = await open(root);
    expect(panel).not.toBeNull();
    panel
      .querySelector("lightning-checkbox-group")
      .dispatchEvent(new CustomEvent("change", { detail: { value: ["purchase"] } }));
    await flush();
    buttonByLabel(filtersRoot(root).querySelector(".filter-panel"), "Cancel").click();
    await flush();
    expect(filtersRoot(root).querySelector(".filter-panel")).toBeNull();
    expect(root.querySelectorAll(".event")).toHaveLength(4);
    expect(root.querySelector(".filter-button").getAttribute("aria-pressed")).toBe("false");
  });

  it("opens with the title only, and swaps it for Cancel and Apply once a type changes", async () => {
    const element = await mount();
    const root = element.shadowRoot;
    const panel = await open(root);
    expect(panel.querySelector(".filter-title")).not.toBeNull();
    expect(buttonByLabel(panel, "Apply")).toBeUndefined();
    expect(buttonByLabel(panel, "Cancel")).toBeUndefined();
    // A small close icon at the end of the header.
    expect(panel.querySelector("lightning-button-icon.filter-close").iconName).toBe("utility:close");
    const group = () => filtersRoot(root).querySelector("lightning-checkbox-group");
    const current = group().value;
    group().dispatchEvent(new CustomEvent("change", { detail: { value: ["purchase"] } }));
    await flush();
    const changed = filtersRoot(root).querySelector(".filter-panel");
    expect(changed.querySelector(".filter-title")).toBeNull();
    expect(changed.querySelector(".filter-close")).toBeNull();
    // Cancel first (at the start), Apply last (at the end).
    const labelled = [...changed.querySelectorAll(".filter-head lightning-button")].map((b) => b.label);
    expect(labelled).toEqual(["Cancel", "Apply"]);
    expect(buttonByLabel(changed, "Apply")).toBeDefined();
    expect(buttonByLabel(changed, "Cancel")).toBeDefined();
    // Put back as it was: nothing to apply, so the title returns.
    group().dispatchEvent(new CustomEvent("change", { detail: { value: [...current] } }));
    await flush();
    const same = filtersRoot(root).querySelector(".filter-panel");
    expect(same.querySelector(".filter-title")).not.toBeNull();
    expect(buttonByLabel(same, "Apply")).toBeUndefined();
  });

  it("closes from the icon on the title, without applying", async () => {
    const element = await mount();
    const root = element.shadowRoot;
    const panel = await open(root);
    panel.querySelector("lightning-button-icon.filter-close").click();
    await flush();
    expect(filtersRoot(root).querySelector(".filter-panel")).toBeNull();
    expect(root.querySelector(".filter-button").getAttribute("aria-expanded")).toBe("false");
  });

  it("applies event types on Apply", async () => {
    const element = await mount();
    const root = element.shadowRoot;
    const panel = await open(root);
    // The panel has event types only: no date range.
    expect(panel.querySelector("lightning-radio-group")).toBeNull();
    panel
      .querySelector("lightning-checkbox-group")
      .dispatchEvent(new CustomEvent("change", { detail: { value: ["purchase", "web"] } }));
    await flush();
    buttonByLabel(filtersRoot(root).querySelector(".filter-panel"), "Apply").click();
    // Apply goes out after the panel is painted (a frame, then a task).
    await settle();
    reemit();
    await flush();
    expect([...root.querySelectorAll(".chevron-button")].map((r) => r.dataset.id)).toEqual(["o1", "w1"]);
    const button = root.querySelector(".filter-button");
    expect(button.getAttribute("aria-pressed")).toBe("true");
    expect(button.getAttribute("aria-label")).toBe("Filters, 1 active");
    expect(button.getAttribute("aria-expanded")).toBe("false");
  });

  it("shows a skeleton for the types and count until a filter's counts land", async () => {
    const element = await mount();
    const root = element.shadowRoot;
    const summary = () => root.querySelector(".summary");
    expect(summary().querySelector(".skeleton_summary")).toBeNull();
    const panel = await open(root);
    panel
      .querySelector("lightning-checkbox-group")
      .dispatchEvent(new CustomEvent("change", { detail: { value: ["purchase", "web"] } }));
    await flush();
    buttonByLabel(filtersRoot(root).querySelector(".filter-panel"), "Apply").click();
    await Promise.resolve();
    // The panel goes at once, before the timeline updates.
    expect(filtersRoot(root).querySelector(".filter-panel")).toBeNull();
    await new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
    await Promise.resolve();
    // Asked, not answered: the dates stay, the rest is a skeleton.
    expect(summary().querySelector(".skeleton_summary")).not.toBeNull();
    expect(summary().textContent).not.toMatch(/items/);
    await flush();
    expect(summary().querySelector(".skeleton_summary")).toBeNull();
    expect(summary().textContent).toMatch(/2 of \d+ types · 2 items/);
  });
});

describe("c-time-drive a save on the page", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });

  it("refreshes in place, quietly, and keeps a save that comes while it does", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Vertical";
    document.body.appendChild(element);
    emitEvents({ events: EVENTS, warnings: [] });
    await flush();
    const root = element.shadowRoot;
    const titles = () => root.querySelectorAll(".event-title").length;
    const shown = titles();
    expect(shown).toBeGreaterThan(0);
    // Salesforce's refresh after a quick action saves (a new task, a logged call).
    const pageRefresh = registerRefreshHandler.mock.calls.at(-1)[1];
    const asked = getTimeline.mock.calls.length;
    pageRefresh();
    await flush();
    expect(getTimeline.mock.calls.length).toBe(asked + 1);
    // No skeleton: the timeline stays, with a thin line saying it's updating.
    expect(root.querySelector(".skeleton-frame")).toBeNull();
    expect(titles()).toBe(shown);
    expect(root.querySelector(".updating .assistive-text").textContent).toBe("Updating…");
    // A second save while it updates isn't lost: one more refresh follows.
    pageRefresh();
    await flush();
    expect(getTimeline.mock.calls.length).toBe(asked + 1);
    answer();
    await flush();
    expect(getTimeline.mock.calls.length).toBe(asked + 2);
    answer();
    await flush();
    expect(root.querySelector(".updating")).toBeNull();
    expect(titles()).toBe(shown);
  });
});

describe("c-time-drive a file", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  const mountWith = async (events) => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Vertical";
    document.body.appendChild(element);
    emitEvents({ events, warnings: [] });
    await flush();
    return element.shadowRoot;
  };
  const FILE = {
    ...EVENTS[0],
    id: "f1",
    recordId: "069000000000001AAA",
    title: "Contract.pdf",
    sourceObject: "ContentDocumentLink"
  };

  it("opens the file preview from its title, as Salesforce does, not a record page", async () => {
    const root = await mountWith([FILE]);
    const link = root.querySelector(".event-link");
    // A copied link or a new tab goes to the document.
    expect(link.getAttribute("href")).toBe("/lightning/r/ContentDocument/069000000000001AAA/view");
    link.click();
    expect(navigated).toHaveBeenLastCalledWith({
      type: "standard__namedPage",
      attributes: { pageName: "filePreview" },
      state: { selectedRecordId: "069000000000001AAA" }
    });
    expect(openTab).not.toHaveBeenCalled();
  });

  it("opens the preview in a tab of its own in a console app", async () => {
    const root = await mountWith([FILE]);
    IsConsoleNavigation.emit(true);
    await flush();
    navigated.mockClear();
    root.querySelector(".event-link").click();
    expect(openTab).toHaveBeenCalledWith({
      pageReference: {
        type: "standard__namedPage",
        attributes: { pageName: "filePreview" },
        state: { selectedRecordId: "069000000000001AAA" }
      },
      focus: true
    });
    expect(navigated).not.toHaveBeenCalled();
  });

  it("leaves every other record going to its page", async () => {
    const root = await mountWith([EVENTS[0]]);
    root.querySelector(".event-link").click();
    expect(navigated).toHaveBeenLastCalledWith({
      type: "standard__recordPage",
      attributes: { recordId: "a01000000000001AAA", actionName: "view" }
    });
    expect(root.querySelector(".event-link").getAttribute("href")).toBe("/lightning/r/a01000000000001AAA/view");
    expect(openTab).not.toHaveBeenCalled();
  });

  it("opens every other record in a tab of its own in a console app, as Time Warp does", async () => {
    const root = await mountWith([EVENTS[0]]);
    IsConsoleNavigation.emit(true);
    await flush();
    navigated.mockClear();
    root.querySelector(".event-link").click();
    expect(openTab).toHaveBeenCalledWith({
      pageReference: {
        type: "standard__recordPage",
        attributes: { recordId: "a01000000000001AAA", actionName: "view" }
      },
      focus: true
    });
    expect(navigated).not.toHaveBeenCalled();
  });
});

describe("c-time-drive a new filter", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });

  const buttonByLabel = (panel, label) =>
    [...panel.querySelectorAll("lightning-button")].find((b) => b.label === label);

  const applyTypes = async (root, value) => {
    root.querySelector(".filter-button").click();
    await flush();
    filtersRoot(root)
      .querySelector("lightning-checkbox-group")
      .dispatchEvent(new CustomEvent("change", { detail: { value } }));
    await flush();
    buttonByLabel(filtersRoot(root).querySelector(".filter-panel"), "Apply").click();
    // Apply goes out after the panel is painted (a frame, then a task).
    await new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
    await Promise.resolve();
  };

  it("puts the days into the loading skeleton at once, as the counts do, until the new ones land", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Vertical";
    document.body.appendChild(element);
    emitEvents({ events: EVENTS, warnings: [] });
    await flush();
    const root = element.shadowRoot;
    expect(root.querySelector(".skeleton-frame")).toBeNull();
    expect(root.querySelectorAll(".event").length).toBeGreaterThan(0);

    await applyTypes(root, ["purchase", "web"]);
    // Asked, not answered: the counts are a skeleton, and so are the days.
    expect(root.querySelector(".summary .skeleton_summary")).not.toBeNull();
    expect(root.querySelector(".skeleton-frame")).not.toBeNull();
    expect(root.querySelectorAll(".event")).toHaveLength(0);

    reemit();
    await flush();
    expect(root.querySelector(".skeleton-frame")).toBeNull();
    expect([...root.querySelectorAll(".chevron-button")].map((r) => r.dataset.id)).toEqual(["o1", "w1"]);
  });

  it("shows nothing new when Apply changes nothing", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Vertical";
    document.body.appendChild(element);
    emitEvents({ events: EVENTS, warnings: [] });
    await flush();
    const root = element.shadowRoot;
    root.querySelector(".filter-button").click();
    await flush();
    const all = filtersRoot(root)
      .querySelector("lightning-checkbox-group")
      .options.map((o) => o.value);
    // The same types back again: the panel offers nothing to apply, and the days stay.
    expect(buttonByLabel(filtersRoot(root).querySelector(".filter-panel"), "Apply")).toBeUndefined();
    expect(all.length).toBeGreaterThan(0);
    expect(root.querySelector(".skeleton-frame")).toBeNull();
  });
});

describe("c-time-drive all types", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });

  it("selects or clears every type at once", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Vertical";
    document.body.appendChild(element);
    emitEvents({ events: EVENTS, warnings: [] });
    await flush();
    const root = element.shadowRoot;
    root.querySelector(".filter-button").click();
    await flush();
    const all = filtersRoot(root).querySelector(".all-types");
    const group = () => filtersRoot(root).querySelector("lightning-checkbox-group");
    expect(all.checked).toBe(true);
    all.checked = false;
    all.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(group().value).toEqual([]);
    expect(filtersRoot(root).querySelector(".all-types").checked).toBe(false);
    all.checked = true;
    all.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(group().value).toHaveLength(4);
  });
});

describe("c-time-drive record links", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });

  it("links CRM events to their record and expands only from the chevron", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Vertical";
    document.body.appendChild(element);
    emitEvents({ events: EVENTS, warnings: [] });
    await flush();
    const root = element.shadowRoot;
    const link = root.querySelector(".event-link");
    expect(link.textContent).toBe("Order placed");
    expect(link.getAttribute("href")).toBe("/lightning/r/a01000000000001AAA/view");
    // Mocked events have no record: plain titles.
    expect(root.querySelectorAll(".event-link")).toHaveLength(1);
    // Clicking the row itself doesn't expand it.
    root.querySelector(".event-row").click();
    await flush();
    expect(root.querySelectorAll(".event_open")).toHaveLength(0);
    root.querySelector(".chevron-button").click();
    await flush();
    expect(root.querySelectorAll(".event_open")).toHaveLength(1);
    expect(root.querySelector(".chevron-button").getAttribute("aria-label")).toBe("Details: Order placed");
    expect(root.querySelector(".chevron-button").getAttribute("aria-expanded")).toBe("true");
  });
});

describe("c-time-drive drawing less", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });
  // One event a day for 20 days.
  const DAYS = Array.from({ length: 20 }, (_, d) => ({
    id: `d${d}`,
    type: "web",
    category: "Digital",
    title: "Page view",
    subtitle: `Day ${d}`,
    occurredAt: new Date(Date.now() - d * 86400000).toISOString(),
    details: []
  }));
  // jsdom lays nothing out: horizontally, the columns report themselves
  // wider than the track, as 20 days of them are.
  let savedScrollWidth;
  beforeEach(() => {
    savedScrollWidth = Object.getOwnPropertyDescriptor(Element.prototype, "scrollWidth");
    Object.defineProperty(Element.prototype, "scrollWidth", { configurable: true, get: () => 3000 });
  });
  afterEach(() => {
    if (savedScrollWidth) Object.defineProperty(Element.prototype, "scrollWidth", savedScrollWidth);
    else delete Element.prototype.scrollWidth;
  });
  const mount = async (layout, events = DAYS) => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = layout;
    document.body.appendChild(element);
    emitEvents({ events, warnings: [] });
    await flush();
    return element;
  };

  it("fills the track when every day fits, its design set by how many", async () => {
    const proto = Element.prototype;
    const saved = ["clientWidth", "clientHeight", "scrollHeight"].map((n) => [
      n,
      Object.getOwnPropertyDescriptor(proto, n)
    ]);
    Object.defineProperty(proto, "scrollWidth", { configurable: true, get: () => 0 });
    Object.defineProperty(proto, "clientWidth", { configurable: true, get: () => 1200 });
    Object.defineProperty(proto, "clientHeight", { configurable: true, get: () => 560 });
    Object.defineProperty(proto, "scrollHeight", { configurable: true, get: () => 300 });
    try {
      // Three days across 1200px: columns share the width, as rows.
      let root = (await mount("Horizontal", DAYS.slice(0, 3))).shadowRoot;
      await flush();
      expect(root.querySelector(".card").classList).toContain("card_fit-rows");
      // History's start is a column of its own, first; today (with items) is
      // the latest, with no Future to end after it.
      const columns = [...root.querySelectorAll(".day")];
      expect(columns).toHaveLength(4);
      expect(columns[0].querySelector(".nothing-now-text").textContent).toMatch(/^Nothing between /);
      // Across, the window's ends show the base component's "all done" drawing, in a slot of its own.
      const art = columns[0].querySelector(".nothing-now-illustration lightning-illustration");
      expect(art.illustrationName).toBe("success:selfassigned");
      expect(columns.at(-1).querySelector(".nothing-now")).toBeNull();
      document.body.removeChild(root.host);
      // Six days: more than the five across, so the usual columns.
      root = (await mount("Horizontal", DAYS.slice(0, 6))).shadowRoot;
      await flush();
      expect(root.querySelector(".card").classList).not.toContain("card_fit");
      document.body.removeChild(root.host);
      // Two days down the list: no fit mode (the list hugs its days), and
      // nothing opened.
      root = (await mount("Vertical", DAYS.slice(0, 2))).shadowRoot;
      await flush();
      expect(root.querySelector(".card").classList).not.toContain("card_fit");
      expect(root.querySelectorAll(".event_open")).toHaveLength(0);
      document.body.removeChild(root.host);
      // Twenty days: too many to fit, the usual timeline.
      root = (await mount("Vertical")).shadowRoot;
      await flush();
      expect(root.querySelector(".card").classList).not.toContain("card_fit");
    } finally {
      for (const [name, descriptor] of saved) {
        if (descriptor) Object.defineProperty(proto, name, descriptor);
        else delete proto[name];
      }
    }
  });

  it("says All-Day instead of a time for an all-day event", async () => {
    const day = new Date(Date.now() - 2 * 3600000).toISOString();
    const root = (
      await mount("Vertical", [
        { id: "a", type: "event", category: "Sales", title: "Offsite", occurredAt: day, allDay: true, details: [] },
        { id: "b", type: "event", category: "Sales", title: "Standup", occurredAt: day, details: [] }
      ])
    ).shadowRoot;
    const times = [...root.querySelectorAll(".event")].map((e) => [
      e.querySelector(".event-title").textContent,
      e.querySelector(".event-time").textContent
    ]);
    expect(times.find(([title]) => title === "Offsite")[1]).toBe("All-Day");
    expect(times.find(([title]) => title === "Standup")[1]).not.toBe("All-Day");
  });

  it("marks an email opened, unopened or bounced with an icon after its title", async () => {
    const sentAt = new Date(Date.now() - 3600000).toISOString();
    const email = (id, emailState, extra = {}) => ({
      id,
      type: "sales_email",
      category: "Sales",
      title: `Email ${id}`,
      subtitle: "Me · Sent to: Sam Lee and 1 other",
      occurredAt: sentAt,
      recordId: "02s000000000001AAA",
      emailState,
      details: [],
      ...extra
    });
    const root = (
      await mount("Vertical", [
        email("a", "opened", { emailOpenedAt: sentAt }),
        email("b", "unopened"),
        email("c", "bounced"),
        email("d", undefined)
      ])
    ).shadowRoot;
    const icons = [...root.querySelectorAll(".event-head")].map((h) => h.querySelector(".email-state"));
    expect(icons.map((i) => i?.iconName ?? null)).toEqual(["utility:preview", "utility:hide", "utility:warning", null]);
    expect(icons[0].alternativeText).toMatch(/^Opened /);
    expect(icons[1].alternativeText).toBe("Not opened yet");
    expect(root.querySelector(".event-subtitle").textContent).toContain("Sent to: Sam Lee and 1 other");
  });

  it("shows the loading skeleton while refreshing, then the days again", async () => {
    const root = (await mount("Vertical", DAYS.slice(0, 3))).shadowRoot;
    expect(root.querySelectorAll(".event")).toHaveLength(3);
    root.querySelector('lightning-button-icon[title="Refresh"]').click();
    await Promise.resolve();
    // Mid-refresh: the skeleton says it's working.
    expect(root.querySelector(".skeleton-frame")).not.toBeNull();
    reemit();
    await flush();
    expect(root.querySelector(".skeleton-frame")).toBeNull();
    expect(root.querySelectorAll(".event")).toHaveLength(3);
  });

  it("leaves the overview off when every day fits", async () => {
    // Three days: the list is as tall as they are, up to its height, and
    // ends on an anchor bar, with no scrub tab.
    let root = (await mount("Vertical", DAYS.slice(0, 3))).shadowRoot;
    // Three days, and the window's start as a day of its own.
    expect(root.querySelectorAll(".day")).toHaveLength(4);
    expect(root.querySelector(".scrub")).toBeNull();
    expect(root.querySelector(".track").getAttribute("style")).toBe("max-height: 560px");
    // Vertical, no Future: today tops the list; History's start ends it.
    const slots = [...root.querySelectorAll(".nothing-now-text")].map((t) => t.textContent);
    expect(slots).toEqual([expect.stringMatching(/^Nothing between /)]);
    // Down the list: a grey bar with an info icon, no picture.
    expect(root.querySelector(".nothing-now .nothing-now-icon")).not.toBeNull();
    expect(root.querySelector(".nothing-now-illustration")).toBeNull();
    document.body.removeChild(root.host);
    // Horizontal columns that fit the track: no seek bar.
    Object.defineProperty(Element.prototype, "scrollWidth", { configurable: true, get: () => 0 });
    root = (await mount("Horizontal")).shadowRoot;
    expect(root.querySelector(".seek")).toBeNull();
  });

  it("opens at Today, the earliest item or the latest, as App Builder says", async () => {
    const future = {
      ...DAYS[0],
      id: "f1",
      subtitle: "Next week",
      occurredAt: new Date(Date.now() + 7 * 86400000).toISOString()
    };
    let last;
    const open = async (openAt, events = [future, ...DAYS]) => {
      const element = createElement("c-time-drive", { is: TimeDrive });
      element.recordId = "003000000000001AAA";
      element.layout = "Vertical";
      element.futureYears = "1";
      if (openAt) element.openAt = openAt;
      document.body.appendChild(element);
      emitEvents({ events, warnings: [] });
      await flush();
      await settle();
      const root = element.shadowRoot;
      const shown = [...root.querySelectorAll(".day")].map((d) => Number(d.dataset.index));
      last = root.querySelectorAll(".scrub-heat .heat").length - 1;
      const today = root.querySelector(".day_today");
      const result = { shown, today: today ? Number(today.dataset.index) : null, root };
      document.body.removeChild(element);
      return result;
    };
    // Future's end is a day of its own (0), then next week's item (1), then today.
    // Today (the default): today's day drawn and highlighted.
    let opened = await open();
    expect(opened.shown).toContain(2);
    expect(opened.today).toBe(2);
    // The latest item: next week's, not the window's end.
    expect((await open("Latest item")).shown).toContain(1);
    // The earliest item: the oldest day with items, just before History's start.
    opened = await open("Earliest item");
    expect(opened.shown).toContain(last - 1);
    // Nothing today: Today opens on the placeholder, highlighted all the same.
    opened = await open(undefined, [future, ...DAYS.slice(1)]);
    expect(opened.today).toBe(2);
  });

  it("stays on the same day across after Refresh", async () => {
    // jsdom lays nothing out: columns 200px wide, 220px apart, and a scroll
    // offset each element keeps.
    // (offsetWidth and offsetLeft are HTMLElement's; scrollLeft is Element's.)
    const proto = HTMLElement.prototype;
    const saved = ["offsetWidth", "offsetLeft"].map((n) => [proto, n, Object.getOwnPropertyDescriptor(proto, n)]);
    saved.push([Element.prototype, "scrollLeft", Object.getOwnPropertyDescriptor(Element.prototype, "scrollLeft")]);
    const scrolled = new WeakMap();
    Object.defineProperty(proto, "offsetWidth", {
      configurable: true,
      get() {
        return this.classList?.contains("day") ? 200 : 0;
      }
    });
    Object.defineProperty(proto, "offsetLeft", {
      configurable: true,
      get() {
        return this.classList?.contains("day") ? Number(this.dataset?.index ?? 0) * 220 : 0;
      }
    });
    Object.defineProperty(Element.prototype, "scrollLeft", {
      configurable: true,
      get() {
        return scrolled.get(this) ?? 0;
      },
      set(v) {
        scrolled.set(this, v);
      }
    });
    try {
      const element = createElement("c-time-drive", { is: TimeDrive });
      element.recordId = "003000000000001AAA";
      element.layout = "Horizontal";
      element.openAt = "Earliest item";
      document.body.appendChild(element);
      emitEvents({ events: DAYS, warnings: [] });
      await flush();
      const root = element.shadowRoot;
      root.querySelector(".track").scrollLeft = 5 * 220 + 30;
      root.querySelector('lightning-button-icon[title="Refresh"]').click();
      reemit();
      await flush();
      // A fresh track (the skeleton replaced the old one), back on the 6th day.
      expect(root.querySelector(".track").scrollLeft).toBe(5 * 220 + 30);
    } finally {
      for (const [owner, name, descriptor] of saved) {
        if (descriptor) Object.defineProperty(owner, name, descriptor);
        else delete owner[name];
      }
    }
  });

  it("goes back to today with the Today button", async () => {
    // Opened at the earliest item, far from today.
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Vertical";
    element.openAt = "Earliest item";
    document.body.appendChild(element);
    emitEvents({ events: DAYS, warnings: [] });
    await flush();
    await settle();
    const root = element.shadowRoot;
    expect(root.querySelector(".day_today")).toBeNull();
    root.querySelector("lightning-button.today-button").click();
    await settle();
    // Today's slot is drawn again, at the top of the list.
    expect(root.querySelector(".day_today")).not.toBeNull();
    document.body.removeChild(element);

    // Across: today's column is scrolled into the middle.
    const across = createElement("c-time-drive", { is: TimeDrive });
    across.recordId = "003000000000001AAA";
    across.layout = "Horizontal";
    across.openAt = "Earliest item";
    document.body.appendChild(across);
    emitEvents({ events: DAYS, warnings: [] });
    await flush();
    const track = across.shadowRoot.querySelector(".track");
    track.scrollTo = jest.fn();
    across.shadowRoot.querySelector("lightning-button.today-button").click();
    expect(track.scrollTo).toHaveBeenCalledWith(expect.objectContaining({ behavior: "smooth" }));
  });

  it("tops and tails the days with the window's ends, as days of their own", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Vertical";
    element.futureYears = "1";
    document.body.appendChild(element);
    emitEvents({ events: DAYS.slice(0, 3), warnings: [] });
    await flush();
    // Vertical with a Future: Future's end first, History's start last, each
    // a day like any other (and a cell on the strip).
    const days = [...element.shadowRoot.querySelectorAll(".day")];
    expect(days).toHaveLength(5);
    // From the latest item (here today's) to Future's end.
    expect(days[0].querySelector(".nothing-now-text").textContent).toMatch(
      /^Nothing between \w{3} \d+, \d{4} and \w{3} \d+, \d{4}$/
    );
    expect(days.at(-1).querySelector(".nothing-now-text").textContent).toMatch(/^Nothing between /);
    expect(days[0].querySelector(".day-meta").textContent).toBe("");
  });

  it("lists newest first vertically, earliest first horizontally, with no sort button", async () => {
    let root = (await mount("Vertical")).shadowRoot;
    expect(root.querySelector(".day-label").textContent).toContain("Today");
    expect(root.querySelector('lightning-button-icon[title*="first"]')).toBeNull();
    // Today's cell is ringed on the scrub strip.
    expect(root.querySelectorAll(".scrub-heat .heat_today")).toHaveLength(1);
    document.body.removeChild(root.host);

    root = (await mount("Horizontal")).shadowRoot;
    const columns = [...root.querySelectorAll(".card_horizontal .day")];
    expect(columns).toHaveLength(21);
    expect(columns.at(-1).textContent).toContain("Today");
    expect(columns[0].textContent).not.toContain("Today");
  });

  it("shows a week of days in the vertical layout, then a week more as it scrolls near the end", async () => {
    const root = (await mount("Vertical")).shadowRoot;
    expect(root.querySelectorAll(".day")).toHaveLength(7);
    // No buttons: scrolling loads the next days.
    expect(root.querySelector(".more-button")).toBeNull();
    await scrollList(root, "bottom");
    expect(root.querySelectorAll(".day")).toHaveLength(14);
    await scrollList(root, "bottom");
    expect(root.querySelectorAll(".day")).toHaveLength(21);
  });

  it("adds days to a list too short to scroll until it fills", async () => {
    // Every element reports a 560px box holding 300px: nothing to scroll.
    const proto = Element.prototype;
    const saved = ["clientHeight", "scrollHeight"].map((name) => [name, Object.getOwnPropertyDescriptor(proto, name)]);
    Object.defineProperty(proto, "clientHeight", { configurable: true, get: () => 560 });
    Object.defineProperty(proto, "scrollHeight", { configurable: true, get: () => 300 });
    try {
      const root = (await mount("Vertical")).shadowRoot;
      await flush();
      expect(root.querySelectorAll(".day")).toHaveLength(21);
    } finally {
      for (const [name, descriptor] of saved) {
        if (descriptor) Object.defineProperty(proto, name, descriptor);
        else delete proto[name];
      }
    }
  });

  it("puts a scrub tab on the vertical list's edge that jumps to any day", async () => {
    const root = (await mount("Vertical")).shadowRoot;
    const track = root.querySelector(".track");
    expect(track.classList).toContain("track_bounded");
    expect(track.getAttribute("style")).toBe("max-height: 560px");
    // Every day on the scrubber, though only a week is drawn.
    expect(root.querySelectorAll(".scrub-heat .heat")).toHaveLength(21);
    expect(root.querySelectorAll(".day")).toHaveLength(7);

    // End: History's start, the oldest slot, with a full page above it (not
    // the one day alone); scrolling up loads the newer days.
    root.querySelector(".scrub-rail").dispatchEvent(new KeyboardEvent("keydown", { key: "End" }));
    await settle();
    let days = [...root.querySelectorAll(".day")].map((d) => Number(d.dataset.index));
    expect(days).toEqual([14, 15, 16, 17, 18, 19, 20]);

    await scrollList(root, "top");
    days = [...root.querySelectorAll(".day")].map((d) => Number(d.dataset.index));
    expect(days).toEqual([7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]);
    // Their events were fetched as they came into the window (the start has none).
    expect(root.querySelectorAll(".event")).toHaveLength(13);

    // Home: back to the newest, from the top.
    root.querySelector(".scrub-rail").dispatchEvent(new KeyboardEvent("keydown", { key: "Home" }));
    await settle();
    expect(root.querySelector(".day").dataset.index).toBe("0");
    expect(root.querySelector(".more_top")).toBeNull();
  });

  it("jumps once held keys pause, not on every press", async () => {
    const root = (await mount("Vertical")).shadowRoot;
    const rail = root.querySelector(".scrub-rail");
    const fetches = getDays.mock.calls.length;
    for (let i = 0; i < 12; i++) rail.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown" }));
    await flush();
    // Still on the first week: nothing jumped or fetched yet.
    expect(root.querySelector(".track .day").dataset.index).toBe("0");
    expect(getDays.mock.calls.length).toBe(fetches);
    await settle();
    // One jump (further on; jsdom has no layout to say exactly where the tab
    // started), and at most one fetch for it: the first request read ahead, so
    // a short jump lands on days already here.
    expect(Number(root.querySelector(".track .day").dataset.index)).toBeGreaterThan(0);
    expect(getDays.mock.calls.length).toBeLessThanOrEqual(fetches + 1);
  });

  it("opens the overlay while the tab is held, and closes it on release", async () => {
    const root = (await mount("Vertical")).shadowRoot;
    const scrub = root.querySelector(".scrub");
    const rail = root.querySelector(".scrub-rail");
    const bubble = root.querySelector(".scrub-bubble");
    expect(scrub.classList).not.toContain("scrub_active");
    expect(bubble.hidden).toBe(true);
    // The overlay holds the whole history and its labels.
    expect(root.querySelectorAll(".scrub-overlay .heat")).toHaveLength(21);
    expect(root.querySelectorAll(".scrub-label").length).toBeGreaterThan(0);

    rail.dispatchEvent(new MouseEvent("pointerdown", { clientY: 0 }));
    expect(scrub.classList).toContain("scrub_active");
    expect(bubble.hidden).toBe(false);
    expect(bubble.textContent).not.toBe("");
    rail.dispatchEvent(new MouseEvent("pointerup", { clientY: 0 }));
    await flush();
    expect(scrub.classList).not.toContain("scrub_active");
    expect(bubble.hidden).toBe(true);

    // From the keyboard: the overlay opens and the bubble names the day.
    rail.dispatchEvent(new KeyboardEvent("keydown", { key: "End" }));
    expect(scrub.classList).toContain("scrub_active");
    await flush();
    rail.dispatchEvent(new FocusEvent("blur"));
    expect(scrub.classList).not.toContain("scrub_active");
  });

  it("slides skeleton days in place of the list while dragging, until the jump lands", async () => {
    const root = (await mount("Vertical")).shadowRoot;
    const rail = root.querySelector(".scrub-rail");
    const frame = root.querySelector(".frame_scrub");
    // jsdom has no layout: give the rail a size.
    rail.getBoundingClientRect = () => ({ top: 0, height: 100, left: 0, width: 20, right: 20, bottom: 100 });
    rail.dispatchEvent(new MouseEvent("pointerdown", { clientY: 0 }));
    // A press in place doesn't swap the list out.
    expect(frame.classList).not.toContain("frame_previewing");
    rail.dispatchEvent(new MouseEvent("pointermove", { clientY: 80, buttons: 1 }));
    expect(frame.classList).toContain("frame_previewing");
    expect(root.querySelectorAll(".scrub-preview .preview-day").length).toBeGreaterThan(0);
    rail.dispatchEvent(new MouseEvent("pointerup", { clientY: 80 }));
    await flush();
    // Landed: the real days for that point are back.
    expect(frame.classList).not.toContain("frame_previewing");
    expect(Number(root.querySelector(".track .day").dataset.index)).toBeGreaterThan(10);
  });

  it("scrolls the page until the list is clicked, then the list until the pointer leaves", async () => {
    const root = (await mount("Vertical")).shadowRoot;
    const track = root.querySelector(".track");
    const hint = root.querySelector(".scroll-hint");
    // Not engaged: the first wheel shows the hint, once.
    track.dispatchEvent(new WheelEvent("wheel", { deltaY: 40 }));
    expect(hint.classList).toContain("scroll-hint_on");
    expect(track.classList).not.toContain("track_engaged");
    // Clicked: the list takes the wheel, and the hint goes.
    track.dispatchEvent(new MouseEvent("pointerdown", { bubbles: true, composed: true }));
    await flush();
    expect(track.classList).toContain("track_engaged");
    expect(hint.classList).not.toContain("scroll-hint_on");
    // The mouse leaves the card: back to scrolling the page.
    root.querySelector(".frame_scrub").dispatchEvent(new MouseEvent("pointerleave"));
    await flush();
    expect(track.classList).not.toContain("track_engaged");
    // Tapping elsewhere on the page lets go too.
    track.dispatchEvent(new MouseEvent("pointerdown", { bubbles: true, composed: true }));
    await flush();
    expect(track.classList).toContain("track_engaged");
    document.body.dispatchEvent(new MouseEvent("pointerdown", { bubbles: true }));
    await flush();
    expect(track.classList).not.toContain("track_engaged");
  });

  it("draws every day once they are all shown, under the four-week window", async () => {
    const root = (await mount("Vertical")).shadowRoot;
    expect(root.querySelector(".scrub")).not.toBeNull();
    await scrollList(root, "bottom");
    await scrollList(root, "bottom");
    // 20 days is under the cap: all drawn, nothing dropped.
    expect(root.querySelectorAll(".day")).toHaveLength(21);
    expect(root.querySelector(".day").dataset.index).toBe("0");
  });

  it("gives every day a column in the horizontal layout but draws events only near the view", async () => {
    const root = (await mount("Horizontal")).shadowRoot;
    expect(root.querySelectorAll(".day")).toHaveLength(21);
    // Opening at Today (the last column), the twelve columns around it (six in
    // view and the buffer either side) are drawn, the days read with the
    // summary; the rest are date-only shells.
    expect(root.querySelectorAll(".event")).toHaveLength(12);
    expect(root.querySelector(".more-button")).toBeNull();
    // The seek bar's overview still covers every day, the start included.
    expect(root.querySelectorAll(".seek-heat .heat")).toHaveLength(21);
  });

  it("ends the seek drag when the button was released out of earshot", async () => {
    const root = (await mount("Horizontal")).shadowRoot;
    const seek = root.querySelector(".seek");
    const rail = root.querySelector(".seek-rail");
    const bubble = root.querySelector(".seek-bubble");
    rail.getBoundingClientRect = () => ({ left: 0, width: 200, top: 0, height: 24, right: 200, bottom: 24 });
    rail.dispatchEvent(new MouseEvent("pointerdown", { clientX: 10 }));
    rail.dispatchEvent(new MouseEvent("pointermove", { clientX: 100, buttons: 1 }));
    expect(seek.classList).toContain("seek_active");
    // No pointerup ever came; the next move arrives with no button down.
    rail.dispatchEvent(new MouseEvent("pointermove", { clientX: 150, buttons: 0 }));
    expect(seek.classList).not.toContain("seek_active");
    expect(bubble.hidden).toBe(true);
    // And later moves no longer drag it.
    rail.dispatchEvent(new MouseEvent("pointermove", { clientX: 190, buttons: 0 }));
    expect(seek.classList).not.toContain("seek_active");
  });

  it("opens the seek overlay while the handle is held, and the columns follow", async () => {
    const root = (await mount("Horizontal")).shadowRoot;
    const seek = root.querySelector(".seek");
    const rail = root.querySelector(".seek-rail");
    const bubble = root.querySelector(".seek-bubble");
    rail.getBoundingClientRect = () => ({ left: 0, width: 200, top: 0, height: 24, right: 200, bottom: 24 });
    expect(seek.classList).not.toContain("seek_active");
    expect(root.querySelector(".seek-thumb")).not.toBeNull();

    rail.dispatchEvent(new MouseEvent("pointerdown", { clientX: 10 }));
    expect(seek.classList).toContain("seek_active");
    expect(bubble.hidden).toBe(false);
    const first = bubble.textContent;
    rail.dispatchEvent(new MouseEvent("pointermove", { clientX: 190, buttons: 1 }));
    // The bubble names a different (older) day further along.
    expect(bubble.textContent).not.toBe(first);
    rail.dispatchEvent(new MouseEvent("pointerup", { clientX: 190 }));
    expect(seek.classList).not.toContain("seek_active");
    expect(bubble.hidden).toBe(true);

    // From the keyboard: the overlay opens until focus leaves.
    rail.dispatchEvent(new KeyboardEvent("keydown", { key: "End" }));
    expect(seek.classList).toContain("seek_active");
    rail.dispatchEvent(new FocusEvent("blur"));
    expect(seek.classList).not.toContain("seek_active");
  });

  // The server's half of the opening request: the twelve slots around Today
  // (with History's start and the placeholder for Today), read with the summary.
  const openingLoad = (config, days) => {
    const summary = summarise(config);
    const real = new Set(summary.days.map((d) => d.key));
    const today = DAY_KEY.format(new Date());
    const all = new Set([...real, today, windowEnds(config.historyYears, config.futureYears, "day").start.key]);
    const ordered = [...all].sort();
    const index = ordered.indexOf(today);
    const startAt = Math.max(0, Math.min(index - 6, ordered.length - 12));
    const keys = ordered.slice(startAt, startAt + 12).filter((k) => real.has(k));
    const events = groupBusyDays(
      serverFilter(days, config)
        .map((e) => ({ ...e, dayKey: dayKeyOf(e) }))
        .filter((e) => keys.includes(e.dayKey))
    );
    return { summary, keys, events };
  };

  it("reads the columns around Today with the first request, so none load after it", async () => {
    // jsdom lays nothing out: columns 200px wide, 220px apart, a track 1100px
    // across, scrolled where it is told to.
    const proto = HTMLElement.prototype;
    const saved = ["offsetWidth", "offsetLeft"].map((n) => [proto, n, Object.getOwnPropertyDescriptor(proto, n)]);
    saved.push([Element.prototype, "scrollLeft", Object.getOwnPropertyDescriptor(Element.prototype, "scrollLeft")]);
    saved.push([Element.prototype, "clientWidth", Object.getOwnPropertyDescriptor(Element.prototype, "clientWidth")]);
    const scrolled = new WeakMap();
    Object.defineProperty(proto, "offsetWidth", {
      configurable: true,
      get() {
        return this.classList?.contains("day") ? 200 : 0;
      }
    });
    Object.defineProperty(proto, "offsetLeft", {
      configurable: true,
      get() {
        return this.classList?.contains("day") ? Number(this.dataset?.index ?? 0) * 220 : 0;
      }
    });
    Object.defineProperty(Element.prototype, "clientWidth", { configurable: true, get: () => 1100 });
    Object.defineProperty(Element.prototype, "scrollLeft", {
      configurable: true,
      get() {
        return scrolled.get(this) ?? 0;
      },
      set(v) {
        scrolled.set(this, v);
      }
    });
    const savedScrollTo = Element.prototype.scrollTo;
    Element.prototype.scrollTo = function scrollTo(options) {
      scrolled.set(this, options.left);
    };
    try {
      // 60 days back from today, and 20 ahead: Today is mid-list.
      // A sparse record: nothing today, items a few days either side.
      const offsets = [-60, -45, -30, -20, -12, -9, -6, -5, -4, -3, -2, 1, 5, 9, 14, 20, 33, 47, 60, 80];
      const days = offsets.map((d, n) => ({
        id: `d${n}`,
        type: "web",
        category: "Digital",
        title: "Page view",
        subtitle: `Day ${d}`,
        occurredAt: new Date(Date.now() + d * 86400000).toISOString(),
        details: []
      }));
      served = { events: days, warnings: [] };
      getDays.mockClear();
      getDays.mockImplementation(() => Promise.resolve([]));
      const element = createElement("c-time-drive", { is: TimeDrive });
      element.recordId = "003000000000001AAA";
      element.layout = "Horizontal";
      element.futureYears = "0.5";
      document.body.appendChild(element);
      const load = openingLoad(getSummary.getLastConfig(), days);
      for (const call of waiting.splice(0)) call.resolve(load);
      await flush();
      await settle();
      // Every column the card then wanted was in the first answer.
      expect(getDays.mock.calls.map(([p]) => p.dayKeys)).toEqual([]);
    } finally {
      Element.prototype.scrollTo = savedScrollTo;
      for (const [owner, name, descriptor] of saved) {
        if (descriptor) Object.defineProperty(owner, name, descriptor);
        else delete owner[name];
      }
    }
  });

  it("asks for its opening request to report what it ran when told to diagnose, and says so to the log", async () => {
    getTimeline.mockClear();
    clearTraceLog();
    getTimelineDiagnosed.mockReset();
    getTimelineDiagnosed.mockResolvedValue({
      summary: {
        days: [],
        unit: "day",
        warnings: ["w"],
        problems: [{ source: "Events", kind: "denied" }],
        counted: ["Tasks"]
      },
      keys: [],
      events: [{ id: "a", grouped: true }, { id: "b" }],
      serverMs: 1800,
      cpuMs: 300,
      queryCount: 9,
      queryRows: 700,
      queries: [{ seq: 1, source: "Tasks", kind: "count", soql: "SELECT", ms: 90, rows: 3 }],
      phases: [],
      notes: [{ source: "Calls", what: "Not queried", reason: "empty" }]
    });
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Horizontal";
    element.diagnose = true;
    document.body.appendChild(element);
    await flush();
    // The diagnosed request, not the ordinary one.
    expect(getTimelineDiagnosed).toHaveBeenCalledTimes(1);
    expect(getTimeline).not.toHaveBeenCalled();
    const report = currentServerReport();
    expect(report).toMatchObject({
      serverMs: 1800,
      cpuMs: 300,
      queryCount: 9,
      queryRows: 700,
      events: 2,
      groupedRows: 1
    });
    expect(report.queries).toHaveLength(1);
    expect(report.problems).toEqual(["Events: denied"]);
    expect(report.notes[0].what).toBe("Not queried");
    clearTraceLog();
  });

  it("waits for the card's width to ask for the days, so an Auto layout opens the way it runs", async () => {
    // The host has no width when it connects; the card, once drawn, is wide.
    const saved = Element.prototype.getBoundingClientRect;
    Element.prototype.getBoundingClientRect = function getBoundingClientRect() {
      const width = this.classList?.contains("card") ? 1200 : 0;
      return { width, height: 0, top: 0, left: 0, right: width, bottom: 0, x: 0, y: 0 };
    };
    try {
      getTimeline.mockClear();
      const element = createElement("c-time-drive", { is: TimeDrive });
      element.recordId = "003000000000001AAA";
      document.body.appendChild(element);
      await flush();
      // One request, for the days around where it opens, not for a list down.
      expect(getTimeline).toHaveBeenCalledTimes(1);
      expect(getTimeline.mock.calls[0][0]).toMatchObject({ centred: true, newestFirst: false });
    } finally {
      Element.prototype.getBoundingClientRect = saved;
    }
  });

  it("reads ahead in the direction it is scrolled, so a short further scroll waits for nothing", async () => {
    // jsdom lays nothing out: columns 200px wide, 220px apart, a track 1100px
    // across, scrolled where it is told to.
    const proto = HTMLElement.prototype;
    const saved = ["offsetWidth", "offsetLeft"].map((n) => [proto, n, Object.getOwnPropertyDescriptor(proto, n)]);
    saved.push([Element.prototype, "scrollLeft", Object.getOwnPropertyDescriptor(Element.prototype, "scrollLeft")]);
    saved.push([Element.prototype, "clientWidth", Object.getOwnPropertyDescriptor(Element.prototype, "clientWidth")]);
    const scrolled = new WeakMap();
    Object.defineProperty(proto, "offsetWidth", {
      configurable: true,
      get() {
        return this.classList?.contains("day") ? 200 : 0;
      }
    });
    Object.defineProperty(proto, "offsetLeft", {
      configurable: true,
      get() {
        return this.classList?.contains("day") ? Number(this.dataset?.index ?? 0) * 220 : 0;
      }
    });
    Object.defineProperty(Element.prototype, "clientWidth", { configurable: true, get: () => 1100 });
    Object.defineProperty(Element.prototype, "scrollLeft", {
      configurable: true,
      get() {
        return scrolled.get(this) ?? 0;
      },
      set(v) {
        scrolled.set(this, v);
      }
    });
    try {
      const events = Array.from({ length: 300 }, (_, d) => ({
        id: `r${d}`,
        type: "web",
        category: "Digital",
        title: "Page view",
        subtitle: `Day ${d}`,
        occurredAt: new Date(Date.now() - d * 86400000).toISOString(),
        details: []
      }));
      getDays.mockClear();
      const element = createElement("c-time-drive", { is: TimeDrive });
      element.recordId = "003000000000001AAA";
      element.layout = "Horizontal";
      element.historyYears = "2";
      document.body.appendChild(element);
      emitEvents({ events, warnings: [] });
      await flush();
      await settle();
      const track = element.shadowRoot.querySelector(".track");
      const scrollTo = async (column) => {
        track.scrollLeft = column * 220;
        track.dispatchEvent(new CustomEvent("scroll"));
        await flush();
        await settle();
      };
      // A jump to column 100, then two short steps further the same way.
      await scrollTo(100);
      const afterJump = getDays.mock.calls.length;
      const asked = getDays.mock.calls.flatMap(([p]) => p.dayKeys);
      expect(afterJump).toBeGreaterThan(0);
      expect(new Set(asked).size).toBe(asked.length);
      // No request holds more than the window and what is read ahead.
      for (const [params] of getDays.mock.calls) expect(params.dayKeys.length).toBeLessThanOrEqual(18);
      await scrollTo(98);
      // Two columns on, the days were already here: nothing was asked for.
      expect(getDays.mock.calls.length).toBe(afterJump);
      await scrollTo(96);
      // Nearing the end of what was read, the next stretch is asked for, and only
      // days not asked for before.
      expect(getDays.mock.calls.length).toBe(afterJump + 1);
      const next = getDays.mock.calls.at(-1)[0].dayKeys;
      expect(next.some((key) => asked.includes(key))).toBe(false);
      // Days that follow one another in the summary go as runs; every day asked
      // for is in one.
      const { runs } = getDays.mock.calls.at(-1)[0];
      expect(runs.flatMap((run) => run.split(",")).sort()).toEqual([...next].sort());
      expect(runs.length).toBeLessThan(next.length);
    } finally {
      for (const [owner, name, descriptor] of saved) {
        if (descriptor) Object.defineProperty(owner, name, descriptor);
        else delete owner[name];
      }
    }
  });
});

describe("c-time-drive busy days", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });

  it("groups a day with more than 50 events into one row per type that expands to its span", async () => {
    const minute = (m) => new Date(new Date().setHours(9, 0, 0, 0) + m * 60000).toISOString();
    const busy = [
      ...Array.from({ length: 45 }, (_, i) => ({
        id: `e${i}`,
        type: "email",
        category: "Marketing",
        title: "Email opened",
        occurredAt: minute(i),
        details: []
      })),
      ...Array.from({ length: 10 }, (_, i) => ({
        id: `w${i}`,
        type: "web",
        category: "Digital",
        title: "Page view",
        occurredAt: minute(60 + i),
        details: []
      }))
    ];
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Vertical";
    document.body.appendChild(element);
    emitEvents({ events: busy, warnings: [] });
    await flush();
    const root = element.shadowRoot;
    const titles = [...root.querySelectorAll(".event-title")].map((n) => n.textContent);
    expect(titles).toEqual(["10 Page views", "45 Email items"]);
    expect([...root.querySelectorAll(".grouped-pill")].map((n) => n.textContent)).toEqual(["Grouped", "Grouped"]);
    // Grouped rows' nodes are drawn as a stack; single records' aren't.
    expect(root.querySelectorAll(".node_stack")).toHaveLength(2);
    // The busy day, whichever slot it sits in (today may be a placeholder
    // before it, depending on the hour in Salesforce's time zone).
    const metas = [...root.querySelectorAll(".day-meta")].map((m) => m.textContent);
    expect(metas).toContain("55 items");
    // Expanding a grouped row gives the count and the span it covers.
    const emails = [...root.querySelectorAll(".chevron-button")].find((b) => b.dataset.id.endsWith("-email"));
    emails.click();
    await flush();
    const ticket = emails.closest(".event");
    expect(ticket.querySelector(".group-summary").textContent).toBe("45 records grouped");
    expect([...ticket.querySelectorAll(".fact-label")].map((n) => n.textContent)).toEqual(["From", "To"]);
  });

  it("links a grouped row's title to its items, where they can be listed", async () => {
    const minute = (m) => new Date(new Date().setHours(9, 0, 0, 0) + m * 60000).toISOString();
    const busy = [
      ...Array.from({ length: 45 }, (_, i) => ({
        id: `e${i}`,
        type: "email",
        category: "Marketing",
        title: "Email opened",
        occurredAt: minute(i),
        details: []
      })),
      ...Array.from({ length: 10 }, (_, i) => ({
        id: `w${i}`,
        type: "web",
        category: "Digital",
        title: "Page view",
        occurredAt: minute(60 + i),
        details: []
      }))
    ];
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Vertical";
    document.body.appendChild(element);
    emitEvents({ events: busy, warnings: [] });
    await flush();
    const root = element.shadowRoot;
    const link = [...root.querySelectorAll("a.event-title")].find((a) => a.textContent === "45 Email items");
    expect(link).toBeTruthy();
    expect(link.getAttribute("aria-label")).toBe("View all 45 Email items");
    const url = new URL(link.getAttribute("href"), "https://example.com");
    expect(url.pathname).toBe("/lightning/cmp/c__timeDriveGroup");
    expect(url.searchParams.get("c__type")).toBe("email");
    expect(url.searchParams.get("c__count")).toBe("45");
    expect(url.searchParams.get("c__from")).toBe(minute(0));
    expect(url.searchParams.get("c__to")).toBe(minute(44));
    // Not listable (a Data 360 type): the title stays text.
    const web = [...root.querySelectorAll(".event-title")].find((n) => n.textContent === "10 Page views");
    expect(web.tagName).toBe("SPAN");

    navigated.mockClear();
    link.click();
    expect(navigated).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "standard__component",
        attributes: { componentName: "c__timeDriveGroup" },
        state: expect.objectContaining({ c__recordId: "003000000000001AAA", c__type: "email" })
      })
    );
  });
});

describe("c-time-drive configured sources", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });
  const CONFIGURED = [
    {
      id: "500A-Case_Opened",
      recordId: "500000000000001AAA",
      type: "case",
      category: "Service",
      title: "Case opened",
      subtitle: "Missing item · 00001028",
      occurredAt: new Date().toISOString(),
      details: [
        { label: "Status", value: "New" },
        { label: "Priority", value: "High" }
      ],
      icon: "standard:case",
      iconColour: "#FF538A",
      typeLabel: "Case updates",
      sourceObject: "Case",
      sourceLabel: "Salesforce · Case"
    },
    {
      id: "a05A-Loyalty",
      recordId: "a05000000000001AAA",
      type: "loyalty",
      category: "Commerce",
      title: "Points earned",
      subtitle: "120 points",
      occurredAt: new Date(Date.now() - 3600000).toISOString(),
      details: [],
      icon: "utility:trophy",
      iconColour: "#7B4FA0",
      typeLabel: "Loyalty points",
      sourceObject: "Loyalty_Transaction__c",
      sourceLabel: "Salesforce · Loyalty Transaction"
    }
  ];
  const mount = async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Vertical";
    document.body.appendChild(element);
    emitEvents({ events: CONFIGURED, warnings: [] });
    await flush();
    return element.shadowRoot;
  };

  it("uses each source's configured icon and colour", async () => {
    const root = await mount();
    const caseRow = root.querySelector('.chevron-button[data-id="500A-Case_Opened"]').closest(".event");
    expect(caseRow.querySelector("lightning-icon").iconName).toBe("standard:case");
    expect(caseRow.querySelector(".node").getAttribute("style")).toContain("#FF538A");
    expect(caseRow.getAttribute("style")).toContain("--tone: #FF538A");
  });

  it("lists configured types, custom ones included, by their configured labels", async () => {
    const root = await mount();
    root.querySelector(".filter-button").click();
    await flush();
    const options = filtersRoot(root)
      .querySelector("lightning-checkbox-group")
      .options.map((o) => o.label);
    // With each type's total from the summary.
    expect(options).toEqual(["Case updates", "Loyalty points"]);
  });

  it("opens an item on the fields the admin chose, and no others", async () => {
    const root = await mount();
    root.querySelector('.chevron-button[data-id="500A-Case_Opened"]').click();
    await flush();
    const row = root.querySelector('.chevron-button[data-id="500A-Case_Opened"]').closest(".event");
    expect([...row.querySelectorAll(".fact")].map((f) => f.textContent)).toEqual(["StatusNew", "PriorityHigh"]);
    // No record layout of its own: only what the source names.
    expect(root.querySelector("c-time-drive-record-details")).toBeNull();
    // A source with no fields chosen opens on its title, subtitle and source alone.
    root.querySelector('.chevron-button[data-id="a05A-Loyalty"]').click();
    await flush();
    const loyalty = root.querySelector('.chevron-button[data-id="a05A-Loyalty"]').closest(".event");
    expect(loyalty.querySelectorAll(".fact")).toHaveLength(0);
    expect(loyalty.querySelector(".event-source").textContent).toBe("Salesforce · Loyalty Transaction");
  });
});

describe("buildMinimap shading", () => {
  const day = (daysAgo, count) => ({ key: new Date(2026, 9, 18 - daysAgo).getTime(), label: "", count, orders: 0 });

  it("keeps quiet days apart next to one very busy day", () => {
    const levels = buildMinimap([day(0, 122), day(1, 20), day(2, 5), day(3, 1)]).cells.map((c) => c.level);
    expect(levels).toEqual([4, 3, 2, 1]);
  });

  it("gives a lone busiest day the strongest shade", () => {
    expect(buildMinimap([day(0, 1), day(1, 1)]).cells.map((c) => c.level)).toEqual([4, 4]);
  });
});

// ---- accessibility: axe (via sa11y) over each state of the card -------------

setupAccessibility();

describe("c-time-drive accessibility", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });
  const LONG = Array.from({ length: 20 }, (_, d) => ({
    id: `a${d}`,
    recordId: d % 3 === 0 ? `a0100000000000${String(d).padStart(2, "0")}AA` : undefined,
    type: d % 3 === 0 ? "purchase" : "web",
    category: d % 3 === 0 ? "Commerce" : "Digital",
    title: d % 3 === 0 ? "Order placed" : "Page view",
    subtitle: `Day ${d}`,
    occurredAt: new Date(Date.now() - d * 86400000).toISOString(),
    details: [{ label: "Order", value: `O-${d}` }]
  }));
  const mount = async (layout, events = LONG) => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = layout;
    document.body.appendChild(element);
    emitEvents({ events, warnings: [] });
    await flush();
    return element;
  };

  it("vertical, with an event expanded and the scrub tab", async () => {
    const element = await mount("Vertical");
    element.shadowRoot.querySelector(".chevron-button").click();
    await flush();
    await expect(element).toBeAccessible();
  });

  it("horizontal, with the seek bar", async () => {
    const element = await mount("Horizontal");
    await expect(element).toBeAccessible();
  });

  it("with the filters panel open", async () => {
    const element = await mount("Vertical");
    element.shadowRoot.querySelector(".filter-button").click();
    await flush();
    expect(element.shadowRoot.querySelector(".filter-button").getAttribute("aria-expanded")).toBe("true");
    await expect(element).toBeAccessible();
  });

  it("announces loading, the days moved to, and names icons only when they add something", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.layout = "Vertical";
    document.body.appendChild(element);
    await Promise.resolve();
    const status = element.shadowRoot.querySelector('.skeleton-frame[role="status"]');
    expect(status.textContent).toContain("Loading the timeline");

    emitEvents({ events: LONG, warnings: [] });
    await flush();
    const root = element.shadowRoot;
    expect(root.querySelector(".track").getAttribute("role")).toBe("region");
    // "Order placed" after an "Orders placed" icon would be noise; "Page view"
    // after "Website" isn't.
    const icons = [...root.querySelectorAll(".event lightning-icon")].map((i) => i.alternativeText);
    expect(icons).toContain("");
    expect(icons).toContain("Website");
    // A fixed name for the chevron; aria-expanded carries the state.
    const chevron = root.querySelector(".chevron-button");
    expect(chevron.getAttribute("aria-label")).toMatch(/^Details: /);

    // Days loaded by scrolling are announced.
    await scrollList(root, "bottom");
    await new Promise((resolve) => requestAnimationFrame(resolve));
    expect(root.querySelector(".announcer").textContent).toMatch(/^Added .+ to .+/);
  });

  it("empty and error states", async () => {
    const element = await mount("Vertical", []);
    await expect(element).toBeAccessible();
    jest.spyOn(console, "warn").mockImplementation(() => {});
    getSummary.error({ message: "Boom" });
    await flush();
    await expect(element).toBeAccessible();
  });
});

describe("periods on long windows", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });

  it("labels weeks and months", () => {
    // In the user's locale (en-US here).
    expect(periodLabel(new Date(2026, 9, 8).getTime(), "week")).toBe("Week of Oct 8, 2026");
    expect(periodLabel(new Date(2026, 9, 1).getTime(), "month")).toBe("October 2026");
    expect(periodLabel(new Date(2026, 9, 8).getTime(), "day")).toBe(dayLabel(new Date(2026, 9, 8).getTime()));
  });

  it("never splits the summary's unit into finer heat cells", () => {
    const weeks = [0, 7, 14].map((d) => ({ key: new Date(2026, 9, 1 + d).getTime(), label: "w", count: 3, orders: 0 }));
    expect(buildMinimap(weeks).unit).toBe("day");
    expect(buildMinimap(weeks, { minUnit: "week" }).unit).toBe("week");
    expect(buildMinimap(weeks, { minUnit: "month" }).cells).toHaveLength(1);
  });

  it("shows a week's items under the week, each with its day", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    document.body.appendChild(element);
    getDays.mockImplementation((params) =>
      Promise.resolve(
        params.dayKeys.includes("2026-10-08")
          ? [{ ...EVENTS[3], occurredAt: new Date(2026, 9, 9, 15, 30).toISOString(), dayKey: "2026-10-08" }]
          : []
      )
    );
    getSummary.emit({
      unit: "week",
      total: 1,
      unfilteredTotal: 1,
      days: [{ key: "2026-10-08", count: 1, orders: 0 }],
      types: [{ type: "case", count: 1 }],
      warnings: [],
      problems: []
    });
    await flush();
    const root = element.shadowRoot;
    // This week has nothing: its placeholder first, then the week of the 8th.
    const weeks = [...root.querySelectorAll(".day")];
    expect(weeks[0].textContent).toContain("Nothing this week");
    expect(weeks.some((w) => w.textContent.includes("Week of Oct 8, 2026"))).toBe(true);
    // The day as well as the time: a week's section doesn't say which day.
    // Its day, short ("Thu 8" or "8 Thu" by locale), then its time: no month.
    expect(root.querySelector(".event-time").textContent).toMatch(/^(\w{3} \d{1,2}|\d{1,2} \w{3}),? \d\d:\d\d/);
  });
});

describe("activity actions", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });

  it("offers the record's activity actions and opens one as Salesforce does", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    document.body.appendChild(element);
    getActivityActions.emit([
      { apiName: "Global.NewTask", label: "New Task", icon: "action:new_task", colour: "#3BA755" },
      { apiName: "Global.LogACall", label: "Log a Call", icon: "action:log_a_call", colour: "#06A59A" }
    ]);
    await Promise.resolve();
    // While the timeline first loads the header is placeholders: no buttons yet.
    expect(element.shadowRoot.querySelector(".tools_skeleton")).not.toBeNull();
    expect(element.shadowRoot.querySelector(".view-button")).toBeNull();
    expect(element.shadowRoot.querySelectorAll(".action-circle")).toHaveLength(0);
    emitEvents({ events: EVENTS, warnings: [] });
    await flush();
    expect(element.shadowRoot.querySelector(".tools_skeleton")).toBeNull();
    // Each action its own button, in its own colour's circle.
    const buttons = [...element.shadowRoot.querySelectorAll(".action-circle")];
    expect(buttons.map((b) => b.getAttribute("aria-label"))).toEqual(["New Task", "Log a Call"]);
    expect(buttons.map((b) => b.getAttribute("style"))).toEqual(["--action: #3BA755", "--action: #06A59A"]);
    expect(buttons.map((b) => b.querySelector("lightning-icon").iconName)).toEqual(["utility:task", "utility:call"]);
    buttons[1].click();
    expect(navigated).toHaveBeenLastCalledWith({
      type: "standard__quickAction",
      attributes: { apiName: "Global.LogACall" },
      state: { recordId: "003000000000001AAA" }
    });
  });

  const ACTIONS = [
    { apiName: "Global.NewTask", label: "New Task", icon: "action:new_task" },
    { apiName: "Global.NewEvent", label: "New Event", icon: "action:new_event" }
  ];
  const withActions = async (mode, layout) => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    if (mode) element.activityActionsMode = mode;
    if (layout) element.layout = layout;
    document.body.appendChild(element);
    getActivityActions.emit(ACTIONS);
    emitEvents({ events: EVENTS, warnings: [] });
    await flush();
    return element;
  };

  it("names the standard actions with its own labels, and others as Salesforce does", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    document.body.appendChild(element);
    getActivityActions.emit([
      { apiName: "Global.NewTask", label: "Create a task", icon: "action:new_task" },
      { apiName: "Global.SendEmail", label: "Send mail", icon: "action:email" },
      { apiName: "Global.NewCase", label: "Open a case", icon: "action:new_case" }
    ]);
    emitEvents({ events: EVENTS, warnings: [] });
    await flush();
    const labels = [...element.shadowRoot.querySelectorAll(".action-circle")].map((b) => b.getAttribute("aria-label"));
    expect(labels).toEqual(["New Task", "Email", "Open a case"]);
  });

  it("shows one Full action in a narrow card and puts the rest in a menu", async () => {
    let resize;
    global.ResizeObserver = class {
      constructor(callback) {
        resize = callback;
      }
      observe() {}
      disconnect() {}
    };
    try {
      const element = createElement("c-time-drive", { is: TimeDrive });
      element.recordId = "003000000000001AAA";
      element.activityActionsMode = "Full";
      element.layout = "Vertical";
      document.body.appendChild(element);
      getActivityActions.emit([
        { apiName: "Global.NewTask", label: "New Task", icon: "action:new_task" },
        { apiName: "Global.LogACall", label: "Log a Call", icon: "action:log_a_call" },
        { apiName: "Global.NewEvent", label: "New Event", icon: "action:new_event" },
        { apiName: "Global.SendEmail", label: "Email", icon: "action:email" }
      ]);
      emitEvents({ events: EVENTS, warnings: [] });
      await flush();
      resize([{ contentRect: { width: 360 } }]);
      await flush();
      const root = element.shadowRoot;
      expect(root.querySelectorAll(".actions-group lightning-button-group lightning-button")).toHaveLength(1);
      expect(root.querySelectorAll(".actions-group lightning-menu-item")).toHaveLength(3);
      // Log a Call stays on show; the rest are behind the menu.
      expect(
        [...root.querySelectorAll(".actions-group lightning-button-group lightning-button")].map((b) => b.label)
      ).toEqual(["Log a Call"]);
      expect([...root.querySelectorAll(".actions-group lightning-menu-item")].map((m) => m.label)).toEqual([
        "New Task",
        "New Event",
        "Email"
      ]);
    } finally {
      delete global.ResizeObserver;
    }
  });

  it("shows four Full actions in a wide card and puts any more in a menu", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    element.activityActionsMode = "Full";
    document.body.appendChild(element);
    getActivityActions.emit(
      ["NewTask", "LogACall", "NewEvent", "SendEmail", "NewCase", "NewNote"].map((name, i) => ({
        apiName: `Global.${name}`,
        label: `Action ${i + 1}`,
        icon: "action:new_task"
      }))
    );
    emitEvents({ events: EVENTS, warnings: [] });
    await flush();
    const root = element.shadowRoot;
    expect(root.querySelectorAll(".actions-group lightning-button-group lightning-button")).toHaveLength(4);
    expect(root.querySelectorAll(".actions-group lightning-menu-item")).toHaveLength(2);
  });

  it("shows none when App Builder says None", async () => {
    const element = await withActions("None");
    expect(element.shadowRoot.querySelector(".actions")).toBeNull();
    expect(element.shadowRoot.querySelector(".action-circle")).toBeNull();
  });

  it("folds them into one + menu for One button", async () => {
    const element = await withActions("One button");
    expect(element.shadowRoot.querySelector(".actions-menu")).not.toBeNull();
    expect(element.shadowRoot.querySelector(".action-circle")).toBeNull();
  });

  it("shows a round button each among the tools for Inline (the default)", async () => {
    const element = await withActions("Inline");
    expect(element.shadowRoot.querySelectorAll(".action-circle")).toHaveLength(2);
    const standard = await withActions(undefined);
    expect(standard.shadowRoot.querySelectorAll(".action-circle")).toHaveLength(2);
  });

  it("shows Full as a button group with the overflow menu at its end, on the view's line", async () => {
    const element = await withActions("Full", "Vertical");
    const group = element.shadowRoot.querySelector(".actions-group lightning-button-group");
    const buttons = [...group.querySelectorAll("lightning-button")];
    expect(buttons.map((b) => b.label)).toEqual(["New Task", "New Event"]);
    // Words only: icons take too much room in a group.
    expect(buttons[0].iconName).toBeUndefined();
    expect(element.shadowRoot.querySelector(".action-circle")).toBeNull();
    // On the view's line, before the tools (which wrap to the line below).
    const row = group.closest(".actions-group");
    expect(row.parentElement.classList.contains("title-row_actions")).toBe(true);
    const summary = row.parentElement.querySelector(".summary_tools");
    expect(summary.nextElementSibling.classList.contains("toolbar")).toBe(true);
    expect(element.shadowRoot.querySelectorAll(".summary")).toHaveLength(1);
    // Choosing one opens it.
    buttons[1].click();
    expect(navigated).toHaveBeenLastCalledWith({
      type: "standard__quickAction",
      attributes: { apiName: "Global.NewEvent" },
      state: { recordId: "003000000000001AAA" }
    });
  });
});

describe("display density", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });

  // The page's spacing hooks, as Lightning sets them from the user's density.
  const withHooks = (hooks) => {
    const real = window.getComputedStyle;
    const spy = jest.spyOn(window, "getComputedStyle").mockImplementation((element, ...rest) => {
      const style = real.call(window, element, ...rest);
      return new Proxy(style, {
        get(target, prop) {
          if (prop === "getPropertyValue") return (name) => hooks[name] ?? target.getPropertyValue(name);
          const value = target[prop];
          return typeof value === "function" ? value.bind(target) : value;
        }
      });
    });
    return () => spy.mockRestore();
  };

  it("reads Compact from the page's spacing", async () => {
    const restore = withHooks({ "--slds-g-spacing-var-4": "0.5rem", "--lwc-varSpacingMedium": "0.5rem" });
    try {
      const element = createElement("c-time-drive", { is: TimeDrive });
      document.body.appendChild(element);
      await flush();
      expect(element.classList.contains("density_compact")).toBe(true);
    } finally {
      restore();
    }
  });

  it("reads Comfy from SLDS 1's own spacing when the SLDS 2 hook isn't there", async () => {
    const restore = withHooks({ "--lwc-varSpacingMedium": "1rem" });
    try {
      const element = createElement("c-time-drive", { is: TimeDrive });
      document.body.appendChild(element);
      await flush();
      expect(element.classList.contains("density_comfy")).toBe(true);
    } finally {
      restore();
    }
  });

  it("defaults to Compact when the page's styles say nothing", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    document.body.appendChild(element);
    await flush();
    expect(element.classList.contains("density_compact")).toBe(true);
    expect(element.classList.contains("density_comfy")).toBe(false);
  });

  it("lets the page's Display Density override the page's styles", async () => {
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.density = "Compact";
    document.body.appendChild(element);
    await flush();
    expect(element.classList.contains("density_compact")).toBe(true);
    expect(element.classList.contains("density_comfy")).toBe(false);
  });
});
