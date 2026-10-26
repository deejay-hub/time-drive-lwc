// The Salesforce mobile app on a phone: the form factor is Small.
import { createElement } from "lwc";
import TIME_ZONE from "@salesforce/i18n/timeZone";
import TimeShift from "c/timeShift";
import getTimeline from "@salesforce/apex/TimeShiftController.getTimeline";
import getDays from "@salesforce/apex/TimeShiftController.getPageDays";

jest.mock("@salesforce/client/formFactor", () => ({ __esModule: true, default: "Small" }), { virtual: true });
jest.mock("@salesforce/apex/TimeShiftController.getTimeline", () => ({ default: jest.fn() }), { virtual: true });
jest.mock("@salesforce/apex/TimeShiftController.getRights", () => ({ default: jest.fn(() => Promise.resolve({ canEdit: true, canDelete: true })) }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeShiftController.getTimelineDiagnosed", () => ({ default: jest.fn() }), { virtual: true });
jest.mock("@salesforce/apex/TimeShiftController.getPageDays", () => ({ default: jest.fn() }), { virtual: true });
jest.mock(
  "@salesforce/apex/TimeShiftController.getActivityActions",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const today = new Intl.DateTimeFormat("en-CA", {
  timeZone: TIME_ZONE,
  year: "numeric",
  month: "2-digit",
  day: "2-digit"
}).format(new Date());

const settle = async () => {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop, @lwc/lwc/no-async-operation
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
};

describe("c-time-shift on a phone", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });

  const mount = async (props = {}) => {
    window.localStorage.removeItem("timeShift.itemDetail");
    getDays.mockResolvedValue([
      {
        id: "t1",
        type: "task",
        category: "Sales",
        title: "Call back",
        subtitle: "Open",
        occurredAt: new Date().toISOString(),
        dayKey: today,
        details: [],
        sourceObject: "Task",
        sourceLabel: "Tasks"
      }
    ]);
    getTimeline.mockResolvedValue({
      summary: {
        total: 1,
        unfilteredTotal: 1,
        days: [{ key: today, count: 1, orders: 0 }],
        types: [{ type: "task", count: 1 }],
        warnings: [],
        problems: []
      },
      keys: [],
      events: []
    });
    const element = createElement("c-time-shift", { is: TimeShift });
    element.recordId = "003000000000001AAA";
    Object.assign(element, props);
    document.body.appendChild(element);
    await settle();
    return element;
  };

  it("is always the vertical list and starts in Lite", async () => {
    // The Layout property is ignored on a phone.
    const element = await mount({ layout: "Horizontal" });
    const root = element.shadowRoot;
    const card = root.querySelector(".card");
    expect(card.classList.contains("card_phone")).toBe(true);
    expect(card.classList.contains("card_horizontal")).toBe(false);
    // Titles only until the person asks for times and dates.
    expect(root.querySelector(".event-title")).not.toBeNull();
    expect(root.querySelectorAll(".event-time")).toHaveLength(0);
  });

  it("has a one-line header: Today and Filters, with the rest behind a menu, and no activity buttons", async () => {
    const element = await mount({ activityActionsMode: "Full" });
    const root = element.shadowRoot;
    expect(root.querySelector(".lite-button")).toBeNull();
    expect(root.querySelector(".expand-button")).toBeNull();
    expect(root.querySelector('lightning-button-icon[title="Refresh"]')).toBeNull();
    expect(root.querySelector(".actions-group")).toBeNull();
    expect(root.querySelector(".actions-menu")).toBeNull();
    root.querySelector(".header-menu-button").click();
    await settle();
    const items = [...root.querySelectorAll(".row-popover-item")];
    expect(items.map((i) => i.textContent.trim())).toEqual(["Refresh", "Expand all", "Show times and dates"]);
    // Choosing the Lite switch brings the times back.
    items[2].click();
    await settle();
    expect(root.querySelector(".row-popover")).toBeNull();
    expect(root.querySelectorAll(".event-time").length).toBeGreaterThan(0);
  });

  it("fits the list to the screen, or to the pixels an admin sets", async () => {
    const auto = await mount();
    const style = auto.shadowRoot.querySelector(".track")?.getAttribute("style") ?? "";
    // The window's height (jsdom's 768), less the header, never below 240.
    expect(style).toMatch(/max-height: \d+px/);
    const px = Number(/max-height: (\d+)px/.exec(style)[1]);
    expect(px).toBeGreaterThanOrEqual(240);
    expect(px).toBeLessThanOrEqual(768);
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    const fixed = await mount({ phoneHeight: 400 });
    expect(fixed.shadowRoot.querySelector(".track").getAttribute("style")).toContain("max-height: 400px");
  });
});
