import { createElement } from "lwc";
import TimeDrive from "c/timeDrive";
import getTimeline from "@salesforce/apex/TimeDriveController.getTimeline";

// A user in a right-to-left locale.
jest.mock("@salesforce/i18n/dir", () => ({ default: "rtl" }), { virtual: true });
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
jest.mock("@salesforce/apex/TimeDriveController.getPageDays", () => ({ default: jest.fn(() => Promise.resolve([])) }), {
  virtual: true
});

describe("c-time-drive in a right-to-left locale", () => {
  afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
  });

  it("lays the card out right to left", async () => {
    getTimeline.mockResolvedValue({
      summary: { total: 0, unfilteredTotal: 0, days: [], types: [], warnings: [] },
      keys: [],
      events: []
    });
    const element = createElement("c-time-drive", { is: TimeDrive });
    element.recordId = "003000000000001AAA";
    document.body.appendChild(element);
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(element.shadowRoot.querySelector(".card").getAttribute("dir")).toBe("rtl");
  });
});
