/**
 * What the timeline card did and when, kept for the Diagnostics page in Time
 * Trail Setup: the card writes a line for each request and draw, and the page
 * reads them. Modules are shared on a page, so both see the same list.
 */
const MAX_LINES = 400;
const lines = [];
const listeners = new Set();
// What the server reported for the card's opening request, when the card was
// asked to diagnose it (see timeShift's `diagnose`).
let serverReport;

/** Adds a line: `at` is the page's clock in ms (performance.now). */
export function note(at, text) {
  lines.push({ at, text });
  if (lines.length > MAX_LINES) lines.shift();
  listeners.forEach((listener) => listener());
}

/** The lines so far, oldest first. */
export function recent() {
  return lines.slice();
}

/** Calls `listener` whenever a line is added or the list is cleared; returns how to stop. */
export function subscribe(listener) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function clear() {
  lines.length = 0;
  serverReport = undefined;
  listeners.forEach((listener) => listener());
}

/** Keeps what the server said about the card's own request. */
export function setServerReport(report) {
  serverReport = report;
  listeners.forEach((listener) => listener());
}

export function currentServerReport() {
  return serverReport;
}
