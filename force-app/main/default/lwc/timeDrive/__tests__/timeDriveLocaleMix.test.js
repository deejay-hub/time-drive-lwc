import { FORMATS, dayWord } from "../timeDriveModel";

// A Thai-locale user whose language is English, in Bangkok, on Salesforce's
// 12-hour clock: words follow the language, dates the locale, and dates stay
// Gregorian (the Thai locale's Intl default is the Buddhist calendar, year 2569).
jest.mock("@salesforce/i18n/locale", () => ({ default: "th-TH" }), { virtual: true });
jest.mock("@salesforce/i18n/lang", () => ({ default: "en-US" }), { virtual: true });
jest.mock("@salesforce/i18n/timeZone", () => ({ default: "Asia/Bangkok" }), { virtual: true });
jest.mock("@salesforce/i18n/dateTime.shortTimeFormat", () => ({ default: "h:mm a" }), { virtual: true });

describe("a user whose language and locale differ", () => {
  it("says today, yesterday and tomorrow in the language", () => {
    expect(dayWord(0)).toBe("Today");
    expect(dayWord(-1)).toBe("Yesterday");
    expect(dayWord(1)).toBe("Tomorrow");
  });

  it("keeps the Gregorian calendar, whatever the locale's own default", () => {
    expect(FORMATS.monthYear.format(new Date(2026, 9, 25))).toContain("2026");
    expect(FORMATS.monthYear.format(new Date(2026, 9, 25))).not.toContain("2569");
  });

  it("shows the clock Salesforce's locale shows, in the Salesforce time zone", () => {
    // 21:05 in Bangkok (UTC+7), on a 12-hour clock: not "21:05".
    const date = new Date(Date.UTC(2026, 9, 25, 14, 5));
    expect(FORMATS.time.format(date)).not.toContain("21:05");
    expect(FORMATS.time.format(date)).toMatch(/9[:.]05/);
  });
});
