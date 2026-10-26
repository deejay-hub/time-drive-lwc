import { ageText } from "../timeShiftModel";

const NOW = new Date(2026, 9, 23, 12, 0, 0).getTime();
const DAY = 86400000;

describe("ageText", () => {
  it("counts minutes and hours within a day", () => {
    expect(ageText(NOW - 5 * 60000, { now: NOW })).toBe("5 minutes ago");
    expect(ageText(NOW - 3 * 3600000, { now: NOW })).toBe("3 hours ago");
    expect(ageText(NOW + 2 * 3600000, { now: NOW })).toBe("in 2 hours");
  });

  it("counts calendar days, months and years beyond a day", () => {
    expect(ageText(NOW - DAY, { now: NOW })).toBe("yesterday");
    expect(ageText(NOW - 3 * DAY, { now: NOW })).toBe("3 days ago");
    expect(ageText(NOW + 2 * DAY, { now: NOW })).toBe("in 2 days");
    expect(ageText(NOW - 90 * DAY, { now: NOW })).toBe("3 months ago");
    expect(ageText(NOW - 800 * DAY, { now: NOW })).toBe("2 years ago");
  });

  it("counts an all-day item in days, never hours", () => {
    const midnight = new Date(2026, 9, 23, 0, 0, 0).getTime();
    expect(ageText(midnight, { allDay: true, now: NOW })).toBe("today");
  });

  it("is empty without a date", () => {
    expect(ageText(NaN, { now: NOW })).toBe("");
  });
});
