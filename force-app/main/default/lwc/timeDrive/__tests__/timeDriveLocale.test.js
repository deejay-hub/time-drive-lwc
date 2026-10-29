import { FORMATS, dayLabel, dayWord, windowRange as range } from "../timeDriveModel";

// A Salesforce user with the German (Germany) locale, in Berlin.
jest.mock("@salesforce/i18n/locale", () => ({ default: "de-DE" }), { virtual: true });
jest.mock("@salesforce/i18n/timeZone", () => ({ default: "Europe/Berlin" }), { virtual: true });
jest.mock("@salesforce/i18n/lang", () => ({ default: "de" }), { virtual: true });
jest.mock("@salesforce/i18n/dateTime.shortTimeFormat", () => ({ default: "HH:mm" }), { virtual: true });

describe("dates in the user's Salesforce locale", () => {
  it("names nearby days in the locale", () => {
    expect(dayWord(0)).toBe("Heute");
    expect(dayWord(-1)).toBe("Gestern");
    expect(dayWord(1)).toBe("Morgen");
    const now = Date.now();
    const today = new Date(new Date(now).toLocaleString("en-US", { timeZone: "Europe/Berlin" }));
    expect(dayLabel(new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime(), now)).toBe("Heute");
  });

  it("formats days and times the German way, in the Salesforce time zone", () => {
    const date = new Date(Date.UTC(2026, 2, 3, 14, 5));
    // 15:05 in Berlin (UTC+1 in March), 24-hour clock.
    expect(FORMATS.time.format(date)).toBe("15:05");
    expect(FORMATS.monthYear.format(new Date(2026, 2, 3))).toBe("März 2026");
    expect(dayLabel(new Date(2025, 2, 3).getTime(), Date.UTC(2026, 9, 18))).toMatch(/^Mo\.?, 3\. März 2025$/);
  });

  it("dates the History and Future window as the server does, the German way", () => {
    // 31 Aug in Berlin: six months back is the last day of February.
    const now = Date.UTC(2026, 7, 31, 12);
    // Ranges space their dash with thin spaces.
    const windowRange = (...args) => range(...args).replace(/\s/g, " ");
    expect(windowRange("0.5", "None", { now })).toBe("28. Feb. – 31. Aug. 2026");
    expect(windowRange("0.5", "0.25", { now })).toBe("28. Feb. – 30. Nov. 2026");
    expect(windowRange("10", "10", { now })).toBe("31. Aug. 2016 – 31. Aug. 2036");
    expect(windowRange("10", "10", { now, short: true })).toBe("Aug. 2016 – Aug. 2036");
  });
});
