import { createElement } from "lwc";
import TimeShift from "c/timeShift";
import getTimeline from "@salesforce/apex/TimeShiftController.getTimeline";

// A user in a right-to-left locale.
jest.mock("@salesforce/i18n/dir", () => ({ default: "rtl" }), { virtual: true });
jest.mock("@salesforce/apex/TimeShiftController.getTimeline", () => ({ default: jest.fn() }), { virtual: true });
jest.mock("@salesforce/apex/TimeShiftController.getRights", () => ({ default: jest.fn(() => Promise.resolve({ canEdit: true, canDelete: true })) }), {
  virtual: true
});
jest.mock("@salesforce/apex/TimeShiftController.getTimelineDiagnosed", () => ({ default: jest.fn() }), { virtual: true });
jest.mock("@salesforce/apex/TimeShiftController.getPageDays", () => ({ default: jest.fn(() => Promise.resolve([])) }), {
  virtual: true
});

describe("c-time-shift in a right-to-left locale", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });

  it("lays the card out right to left", async () => {
    getTimeline.mockResolvedValue({
      summary: { total: 0, unfilteredTotal: 0, days: [], types: [], warnings: [] },
      keys: [],
      events: []
    });
    const element = createElement("c-time-shift", { is: TimeShift });
    element.recordId = "003000000000001AAA";
    document.body.appendChild(element);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(element.shadowRoot.querySelector(".card").getAttribute("dir")).toBe("rtl");
  });
});
