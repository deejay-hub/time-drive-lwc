import { FORMATS } from "../timeDriveModel";

// An English (United States) user whose Salesforce locale shows 24-hour time.
jest.mock("@salesforce/i18n/locale", () => ({ default: "en-US" }), { virtual: true });
jest.mock("@salesforce/i18n/lang", () => ({ default: "en-US" }), { virtual: true });
jest.mock("@salesforce/i18n/timeZone", () => ({ default: "America/New_York" }), { virtual: true });
jest.mock("@salesforce/i18n/dateTime.shortTimeFormat", () => ({ default: "HH:mm" }), { virtual: true });

describe("a 24-hour clock in a locale that is usually 12-hour", () => {
  it("shows the hour as the user's Salesforce locale does", () => {
    // 10:05 in New York (UTC-4 on 25 October).
    expect(FORMATS.time.format(new Date(Date.UTC(2026, 9, 25, 14, 5)))).toBe("10:05");
    expect(FORMATS.time.format(new Date(Date.UTC(2026, 9, 25, 22, 5)))).toBe("18:05");
  });
});
