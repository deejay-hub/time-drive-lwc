import LOCALE from "@salesforce/i18n/locale";
import LANG from "@salesforce/i18n/lang";
import SHORT_TIME_FORMAT from "@salesforce/i18n/dateTime.shortTimeFormat";
import TIME_ZONE from "@salesforce/i18n/timeZone";
import { LABELS, format } from "c/timeDriveLabels";
import VIEW_ALL from "@salesforce/label/c.Time_Drive_View_All";
import VIEW_MARKETING from "@salesforce/label/c.Time_Drive_View_Marketing";
import VIEW_COMMERCE from "@salesforce/label/c.Time_Drive_View_Commerce";
import VIEW_DIGITAL from "@salesforce/label/c.Time_Drive_View_Digital";
import VIEW_SERVICE from "@salesforce/label/c.Time_Drive_View_Service";
import VIEW_SALES from "@salesforce/label/c.Time_Drive_View_Sales";

/**
 * Event types, timeline views and date ranges for Time Drive, and the pure
 * helpers that filter and group events. Kept free of
 * the component so the Jest tests can drive it directly.
 */

// The icon and tone (the node colour, see .node_* in the CSS) of the event
// types the shipped sources use, for an item whose source sets neither. Its
// name always comes from its source (the legend name); "Other" is a last resort.
export const EVENT_TYPES = {
  purchase: { icon: "utility:clock", tone: "commerce" },
  delivered: { icon: "utility:check", tone: "commerce" },
  canceled: { icon: "utility:close", tone: "alert" },
  cart: { icon: "utility:cart", tone: "commerce" },
  email: { icon: "utility:email", tone: "marketing" },
  message: { icon: "utility:notification", tone: "marketing" },
  web: { icon: "utility:world", tone: "digital" },
  search: { icon: "utility:search", tone: "digital" },
  app: { icon: "utility:phone_portrait", tone: "digital" },
  case: { icon: "utility:case", tone: "service" },
  review: { icon: "utility:favorite", tone: "feedback" },
  // Tasks by their Task Subtype (see the shipped Calls and Emails sources).
  call: { icon: "standard:log_a_call", tone: "sales" },
  sales_email: { icon: "standard:email", tone: "sales" },
  opportunity: { icon: "utility:opportunity", tone: "sales" },
  opportunity_won: { icon: "utility:check", tone: "sales" },
  opportunity_lost: { icon: "utility:close", tone: "alert" }
};

const FALLBACK_TYPE = { label: LABELS.typeOther, icon: "utility:record", tone: "digital", many: LABELS.manyOther };

export function typeInfo(type) {
  return { ...FALLBACK_TYPE, ...EVENT_TYPES[type] };
}

// The timeline views in the header picker: each shows some event categories.
export const VIEWS = [
  { value: "All", label: VIEW_ALL, categories: ["All"] },
  { value: "Marketing", label: VIEW_MARKETING, categories: ["Marketing"] },
  { value: "Commerce", label: VIEW_COMMERCE, categories: ["Commerce"] },
  { value: "Digital", label: VIEW_DIGITAL, categories: ["Digital"] },
  { value: "Service", label: VIEW_SERVICE, categories: ["Service"] },
  { value: "Sales", label: VIEW_SALES, categories: ["Sales"] }
];

export function viewFor(value) {
  return VIEWS.find((v) => v.value === value) ?? VIEWS[0];
}

// ---- dates in the user's Salesforce locale and time zone ---------------------

// The Salesforce time zone, if the browser knows it.
const ZONE = (() => {
  try {
    return new Intl.DateTimeFormat(LOCALE, { timeZone: TIME_ZONE }).resolvedOptions().timeZone;
  } catch {
    return undefined;
  }
})();

// Calendar days (day keys are already the user's days, at local midnight):
// the user's locale. Instants (event times): its locale and time zone.
// Always the Gregorian calendar and the user's own clock: some locales' Intl
// default (Thai, Arabic (Saudi Arabia), Persian) is another calendar, while
// Salesforce's dates, and the day keys the server sends, are Gregorian; and
// the clock is the 12 or 24 hours the user's Salesforce locale shows
// (its short time format has an "a" for AM/PM, or doesn't).
const HOUR12 = /a/.test(String(SHORT_TIME_FORMAT ?? ""));
const hasClock = (o) => o.hour !== undefined || o.timeStyle !== undefined;
const calendar = (options) => new Intl.DateTimeFormat(LOCALE, { calendar: "gregory", ...options });
const instant = (options) =>
  new Intl.DateTimeFormat(LOCALE, {
    calendar: "gregory",
    timeZone: ZONE,
    ...(hasClock(options) ? { hour12: HOUR12 } : {}),
    ...options
  });

/** The formats the component shows dates in. */
export const FORMATS = {
  time: instant({ hour: "2-digit", minute: "2-digit" }),
  // An item's time in a week or month (its section doesn't say the day).
  // A row in a week's or month's group: its day, as "Tue 13", and its time.
  dayShort: instant({ weekday: "short", day: "numeric" }),
  dayShortTime: instant({ weekday: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }),
  dayTime: instant({ weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }),
  dateTime: instant({ dateStyle: "medium", timeStyle: "short" }),
  weekday: calendar({ weekday: "short" }),
  month: calendar({ month: "short" }),
  monthYear: calendar({ month: "short", year: "numeric" })
};

const DAY_FORMAT = calendar({ weekday: "short", day: "numeric", month: "short" });
const DAY_FORMAT_YEAR = calendar({ weekday: "short", day: "numeric", month: "short", year: "numeric" });
// Words ("today", "3 days ago") follow the language, like the labels beside
// them; dates follow the locale.
const RELATIVE = new Intl.RelativeTimeFormat(LANG, { numeric: "auto" });
// Reads an instant's date in the Salesforce time zone (Latin digits, to parse).
const DAY_PARTS = new Intl.DateTimeFormat("en-US-u-nu-latn", {
  timeZone: ZONE,
  year: "numeric",
  month: "numeric",
  day: "numeric"
});

// Midnight (local) of the user's day an instant falls on in Salesforce's time
// zone, as day keys are.
function dayKey(date) {
  const parts = {};
  for (const p of DAY_PARTS.formatToParts(date)) parts[p.type] = Number(p.value);
  return new Date(parts.year, parts.month - 1, parts.day).getTime();
}

/** Today's day key (local midnight of today in Salesforce's time zone). */
export function todayKey(now = Date.now()) {
  return dayKey(new Date(now));
}

/**
 * The current period's key (yyyy-MM-dd) as the server keys them: today, its
 * week (counted from 1 January, as SOQL's WEEK_IN_YEAR) or its month.
 */
export function currentPeriodKey(unit, now = Date.now()) {
  return periodKeyOf(todayKey(now), unit);
}

// The key of the period (day, week from 1 January, month) a day falls in.
function periodKeyOf(day, unit) {
  const date = new Date(day);
  let start = date;
  if (unit === "week") {
    const jan1 = new Date(date.getFullYear(), 0, 1);
    const dayOfYear = Math.round((date - jan1) / 86400000);
    start = new Date(date.getFullYear(), 0, 1 + Math.floor(dayOfYear / 7) * 7);
  } else if (unit === "month") {
    start = new Date(date.getFullYear(), date.getMonth(), 1);
  }
  const pad = (n) => String(n).padStart(2, "0");
  return `${start.getFullYear()}-${pad(start.getMonth() + 1)}-${pad(start.getDate())}`;
}

/** -1, 0 or 1 for yesterday, today or tomorrow (in Salesforce's time zone); else null. */
export function relativeDay(key, now = Date.now()) {
  const offset = Math.round((key - dayKey(new Date(now))) / 86400000);
  return Math.abs(offset) <= 1 ? offset : null;
}

/** The locale's word for a nearby day, capitalised: "Today", "Heute", "اليوم". */
export function dayWord(offset) {
  const word = RELATIVE.format(offset, "day");
  return word.charAt(0).toLocaleUpperCase(LOCALE) + word.slice(1);
}

/** "Today", "Yesterday", "Tomorrow", "Tue 13 Oct" (in the user's locale), with the year when it isn't this year. */
export function dayLabel(key, now = Date.now()) {
  const near = relativeDay(key, now);
  if (near !== null) return dayWord(near);
  const date = new Date(key);
  return date.getFullYear() === new Date(now).getFullYear() ? DAY_FORMAT.format(date) : DAY_FORMAT_YEAR.format(date);
}

const WEEK_OF_FORMAT = calendar({ day: "numeric", month: "short", year: "numeric" });
const PERIOD_MONTH_FORMAT = calendar({ month: "long", year: "numeric" });

/**
 * A summary period's label: the day ("Today", "Tue 13 Oct"), "Week of 8 Oct
 * 2026" (weeks run from 1 January: the 1st-7th, 8th-14th ...) or "October
 * 2026". Long windows count by week or month (the summary's unit).
 */
export function periodLabel(key, unit, now = Date.now()) {
  if (unit === "week") return format(LABELS.weekOf, WEEK_OF_FORMAT.format(new Date(key)));
  if (unit === "month") return PERIOD_MONTH_FORMAT.format(new Date(key));
  return dayLabel(key, now);
}

const RANGE_FORMAT = calendar({ day: "numeric", month: "short", year: "numeric" });
const RANGE_FORMAT_SHORT = calendar({ month: "short", year: "numeric" });

// A day months away, on the same day of the month or the month's last (as
// Apex's Date.addMonths).
function addMonths(key, months) {
  const date = new Date(key);
  const last = new Date(date.getFullYear(), date.getMonth() + months + 1, 0).getDate();
  return new Date(date.getFullYear(), date.getMonth() + months, Math.min(date.getDate(), last)).getTime();
}

// History or Future in months: years (0.25 to 10), "1m" for a month, or
// "0" (History only: from today); null for none or anything else.
function monthsIn(value) {
  const text = String(value ?? "").trim();
  if (text === "1m") return 1;
  if (text === "0") return 0;
  const years = Number(text);
  return text && Number.isFinite(years) && years > 0 ? Math.round(years * 12) : null;
}

// The window's first and last days (day keys), from History and Future.
function windowDays(historyYears, futureYears, now) {
  const today = dayKey(new Date(now));
  return {
    from: addMonths(today, -pageMonths(historyYears, "back")),
    to: addMonths(today, pageMonths(futureYears, "ahead"))
  };
}

/**
 * How far back or ahead a user can narrow the timeline to (the Filters
 * panel's Back and Ahead), in months, each up to the page's own History or
 * Future and relative to today. 0 is none: Back starts today, Ahead ends it.
 */
const LENGTHS = [0, 1, 3, 6, 12, 24, 36, 48, 60, 72, 84, 96, 108, 120];
const LENGTH_NUMBER = new Intl.NumberFormat(LOCALE);

/** A length in words: "None", "1 month", "3 months", "1 year", "2 years". */
export function lengthText(months) {
  if (!months) return LABELS.rangeNone;
  if (months < 12) return months === 1 ? LABELS.rangeMonth : format(LABELS.rangeMonths, LENGTH_NUMBER.format(months));
  return months === 12 ? LABELS.rangeYear : format(LABELS.rangeYears, LENGTH_NUMBER.format(months / 12));
}

/** History or Future as the server takes it, for a length in months. */
export function lengthValue(months, side) {
  if (!months) return side === "back" ? "0" : "None";
  if (months === 1) return "1m";
  return String(months / 12);
}

/** The page's History or Future in months (History unset: a year). */
export function pageMonths(value, side) {
  return monthsIn(value) ?? (side === "back" ? 12 : 0);
}

/** The lengths a side offers: up to the page's own, as { value, label }. */
export function lengthOptions(pageValue, side) {
  const most = pageMonths(pageValue, side);
  return LENGTHS.filter((m) => m <= most).map((m) => ({ value: String(m), label: lengthText(m) }));
}

/**
 * The dates the timeline covers, as the server works them out: History years
 * back to Future years ahead (today, with none). "19 Apr – 19 Oct 2026" in the
 * user's locale; short, "Apr – Oct 2026".
 */
export function windowRange(historyYears, futureYears, { short = false, now = Date.now() } = {}) {
  const { from, to } = windowDays(historyYears, futureYears, now);
  const range = short ? RANGE_FORMAT_SHORT : RANGE_FORMAT;
  return range.formatRange ? range.formatRange(from, to) : `${range.format(from)} – ${range.format(to)}`;
}

/** The window's first and last dates, each in the user's locale: { from: "22 Oct 2024", to: "22 Oct 2027" }. */
export function windowDates(historyYears, futureYears, { now = Date.now() } = {}) {
  const { from, to } = windowDays(historyYears, futureYears, now);
  return { from: RANGE_FORMAT.format(from), to: RANGE_FORMAT.format(to) };
}

/** A period's date in words: "18 Dec 2026", "the week of 17 Dec 2026", "December 2026". */
export function periodDate(key, unit) {
  const date = new Date(key);
  if (unit === "week") return format(LABELS.theWeekOf, RANGE_FORMAT.format(date));
  if (unit === "month") return PERIOD_MONTH_FORMAT.format(date);
  return RANGE_FORMAT.format(date);
}

/**
 * The window's ends as period keys, with their dates in words: where History
 * starts, and where Future ends (null with no Future: the window ends today).
 */
export function windowEnds(historyYears, futureYears, unit, now = Date.now()) {
  const { from, to } = windowDays(historyYears, futureYears, now);
  return {
    start: { key: periodKeyOf(from, unit), date: RANGE_FORMAT.format(from) },
    end: monthsIn(futureYears) > 0 ? { key: periodKeyOf(to, unit), date: RANGE_FORMAT.format(to) } : null
  };
}

const time = (e) => new Date(e.occurredAt).getTime();

// ---- day summaries and recency -------------------------------------------------

// Counts in the user's locale: 1,008 (or 1.008, 1 008 ...).
const NUMBER = new Intl.NumberFormat(LOCALE);
export function formatCount(n) {
  return NUMBER.format(n ?? 0);
}

/** "5 minutes ago", "2 hours ago", "yesterday", "3 weeks ago". */
export function ago(iso, now = Date.now()) {
  const minutes = Math.round((time({ occurredAt: iso }) - now) / 60000);
  if (Math.abs(minutes) < 1) return "just now";
  if (Math.abs(minutes) < 60) return RELATIVE.format(minutes, "minute");
  const hours = Math.round(minutes / 60);
  if (Math.abs(hours) < 24) return RELATIVE.format(hours, "hour");
  const days = Math.round(hours / 24);
  if (Math.abs(days) < 14) return RELATIVE.format(days, "day");
  if (Math.abs(days) < 60) return RELATIVE.format(Math.round(days / 7), "week");
  return RELATIVE.format(Math.round(days / 30), "month");
}

// ---- minimap (horizontal layout) and scrubber (vertical) ---------------------

const MONTH_FORMAT = calendar({ month: "short" });
const LONG_GAP_DAYS = 7;
const DAY_MS = 86400000;

// Units a heat cell can stand for, finest first.
// Half a year sits between a quarter and a year, for histories too long for
// quarters and too short to be told only by years.
const UNITS = ["day", "week", "month", "quarter", "half", "year"];

// The start of the unit an instant falls in (weeks start on Monday).
function unitStart(at, unit) {
  const d = new Date(at);
  if (unit === "day") return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  if (unit === "week") return new Date(d.getFullYear(), d.getMonth(), d.getDate() - ((d.getDay() + 6) % 7)).getTime();
  if (unit === "month") return new Date(d.getFullYear(), d.getMonth(), 1).getTime();
  if (unit === "quarter") return new Date(d.getFullYear(), Math.floor(d.getMonth() / 3) * 3, 1).getTime();
  if (unit === "half") return new Date(d.getFullYear(), Math.floor(d.getMonth() / 6) * 6, 1).getTime();
  return new Date(d.getFullYear(), 0, 1).getTime();
}

// A unit's position on a running count, so two units' distance is a number
// of days, weeks, months, quarters or years.
function unitOrdinal(start, unit) {
  const d = new Date(start);
  if (unit === "day") return Math.round(start / DAY_MS);
  if (unit === "week") return Math.round(start / (7 * DAY_MS));
  if (unit === "month") return d.getFullYear() * 12 + d.getMonth();
  if (unit === "quarter") return d.getFullYear() * 4 + Math.floor(d.getMonth() / 3);
  if (unit === "half") return d.getFullYear() * 2 + Math.floor(d.getMonth() / 6);
  return d.getFullYear();
}

// Consecutive days in the same unit, in the order given: their day index
// range and totals.
function bucketsOf(days, unit, countOf) {
  const buckets = [];
  days.forEach((day, i) => {
    const start = unitStart(day.key, unit);
    let bucket = buckets[buckets.length - 1];
    if (!bucket || bucket.start !== start) {
      bucket = { start, from: i, to: i, count: 0, label: day.label };
      buckets.push(bucket);
    }
    bucket.to = i;
    bucket.count += countOf(day);
  });
  return buckets;
}

/**
 * The heat strip beside the timeline: one cell per active day, in the same
 * order as the days, so cells and days line up. Quiet stretches between
 * cells are compressed on a log scale (a day apart: touching; a quiet week:
 * a sliver; a quiet quarter: a bit more), so the rhythm shows without empty
 * gaps. Positions are percentages along the strip.
 *
 * Options, for long histories on a small strip:
 *   maxCells     the most cells that stay readable. More active days than
 *                that and each cell stands for a week, month, quarter or
 *                year instead (the finest unit that fits); cells keep the
 *                day indexes they cover in `from` and `to`.
 *   minLabelGap  the least distance between labels, in percent; closer
 *                labels are dropped (a year's first label wins).
 *   minUnit      the finest unit cells may be: the summary's ("week" when
 *                the server counted by week, so a cell never splits one).
 */
export function buildMinimap(days, { maxCells = Infinity, minLabelGap = 0, minUnit = "day", now = Date.now() } = {}) {
  if (!days?.length) return { cells: [], gaps: [], months: [], years: [], now: null };
  // Days carry counts (from the server's summary) or their events.
  const countOf = (d) => d.count ?? d.events.length;

  const allowed = UNITS.slice(Math.max(0, UNITS.indexOf(minUnit)));
  let unit = allowed[0];
  let buckets = bucketsOf(days, unit, countOf);
  for (const next of allowed.slice(1)) {
    if (buckets.length <= maxCells) break;
    unit = next;
    buckets = bucketsOf(days, unit, countOf);
  }

  const max = Math.max(...buckets.map((b) => b.count));
  const units = [];
  let x = 0;
  buckets.forEach((bucket, i) => {
    if (i > 0) {
      const apart = Math.abs(unitOrdinal(bucket.start, unit) - unitOrdinal(buckets[i - 1].start, unit));
      const space = 0.12 + Math.log1p(Math.max(0, apart - 1)) * 0.35;
      units.push({ gapFrom: x, gapWidth: space, apart });
      x += space;
    }
    units.push({ bucket, i, left: x });
    x += 1;
  });
  const total = x;
  const pct = (v) => (v / total) * 100;

  // Today: its cell when it has items, else a point between the cells
  // either side of it (or at the end it lies beyond), in either order.
  const today = unitOrdinal(unitStart(todayKey(now), unit), unit);
  const placed = units.filter((u) => u.bucket).map((u) => ({ ...u, at: unitOrdinal(u.bucket.start, unit) }));
  let nowAt = null;
  const own = placed.find((u) => u.at === today);
  if (own) nowAt = own.left + 0.5;
  else if (placed.length) {
    for (let i = 1; i < placed.length && nowAt === null; i++) {
      const [a, b] = [placed[i - 1], placed[i]];
      if ((a.at < today && today < b.at) || (a.at > today && today > b.at)) nowAt = (a.left + 1 + b.left) / 2;
    }
    if (nowAt === null) {
      const first = placed[0];
      const last = placed.at(-1);
      const rising = last.at >= first.at;
      // Beyond the latest, or before the earliest.
      const pastEnd = rising ? today > last.at : today < last.at;
      nowAt = pastEnd ? total : 0;
    }
  }
  // Long histories label years; shorter ones label months.
  const yearLabels = unit === "month" || unit === "quarter" || unit === "half" || unit === "year";

  const cells = [];
  const gaps = [];
  const months = [];
  // Where one year meets the next: a divider midway between the two cells,
  // and the year on the label that follows it.
  const years = [];
  let lastMonth = null;
  let lastYear = null;
  let lastEnd = 0;
  for (const u of units) {
    if (u.bucket) {
      const { bucket, i } = u;
      const { count } = bucket;
      // Log scale: each doubling of activity moves about as far up the four
      // shades, so one very busy day doesn't flatten every other day.
      const level =
        count === 0 ? 0 : max <= 1 ? 4 : Math.min(4, 1 + Math.floor((Math.log1p(count) / Math.log1p(max)) * 3.999));
      cells.push({
        index: i,
        key: bucket.start,
        from: bucket.from,
        to: bucket.to,
        left: pct(u.left),
        width: pct(1),
        level,
        current: own?.i === i
      });
      const date = new Date(bucket.start);
      const year = date.getFullYear();
      const newYear = lastYear !== null && year !== lastYear;
      if (newYear) {
        years.push({ key: `y-${bucket.start}`, left: pct((lastEnd + u.left) / 2), year });
      }
      if (yearLabels) {
        if (year !== lastYear) {
          months.push({ key: `m-${bucket.start}`, left: pct(u.left), label: String(year), year: null, newYear: true });
        }
      } else if (date.getMonth() !== lastMonth || newYear) {
        months.push({
          key: `m-${bucket.start}`,
          left: pct(u.left),
          label: MONTH_FORMAT.format(date),
          year: newYear ? String(year) : null,
          newYear
        });
        lastMonth = date.getMonth();
      }
      lastYear = year;
      lastEnd = u.left + 1;
    } else if (unit === "day" ? u.apart > LONG_GAP_DAYS : u.apart > 1) {
      const quiet = u.apart - 1;
      gaps.push({
        key: `g-${u.gapFrom}`,
        left: pct(u.gapFrom),
        width: pct(u.gapWidth),
        days: quiet
      });
    }
  }
  return {
    cells,
    gaps,
    months: spaced(months, minLabelGap),
    years,
    unit,
    // Where today is, and whether it's a cell (it has items) or between.
    now: nowAt === null ? null : { at: pct(nowAt), onCell: Boolean(own) }
  };
}

// Labels at least `gap` percent apart; a year's first label replaces the one
// it collides with.
function spaced(labels, gap) {
  const plain = ({ key, left, label, year }) => ({ key, left, label, year });
  if (!gap) return labels.map(plain);
  const kept = [];
  for (const label of labels) {
    const last = kept[kept.length - 1];
    if (!last || label.left - last.left >= gap) kept.push(label);
    else if (label.newYear && !last.newYear) kept[kept.length - 1] = label;
  }
  return kept.map(plain);
}

/** The day (fractional) at a point along the strip, in percent. */
export function dayAtPercent(cells, at) {
  if (!cells?.length) return 0;
  let best = cells[0];
  let bestDistance = Infinity;
  for (const cell of cells) {
    if (at >= cell.left && at <= cell.left + cell.width) {
      const span = cell.to - cell.from + 1;
      return cell.from + Math.min(span - 0.001, ((at - cell.left) / cell.width) * span);
    }
    const distance = Math.min(Math.abs(at - cell.left), Math.abs(at - cell.left - cell.width));
    if (distance < bestDistance) {
      best = cell;
      bestDistance = distance;
    }
  }
  return at < best.left ? best.from : best.to + 0.999;
}

/** Where a (fractional) day sits along the strip, in percent. */
export function percentAtDay(cells, day) {
  if (!cells?.length) return 0;
  const i = Math.floor(day);
  const cell = cells.find((c) => i >= c.from && i <= c.to);
  if (!cell) return i < cells[0].from ? cells[0].left : cells[cells.length - 1].left + cells[cells.length - 1].width;
  const span = cell.to - cell.from + 1;
  return cell.left + Math.min(1, (day - cell.from) / span) * cell.width;
}

// A file (a ContentDocument, key prefix 069) opens Salesforce's file preview,
// not a record page, as it does anywhere else in Lightning.
export function isFileId(id) {
  return typeof id === "string" && id.startsWith("069");
}

/** Where an item's link goes in a new tab or a copied link: its page, or for a file its document. */
export function recordHref(id) {
  return isFileId(id) ? `/lightning/r/ContentDocument/${id}/view` : `/lightning/r/${id}/view`;
}

/** The file preview page reference (the document's Id as the selected record). */
export function filePreviewRef(id) {
  return {
    type: "standard__namedPage",
    attributes: { pageName: "filePreview" },
    state: { selectedRecordId: id }
  };
}
