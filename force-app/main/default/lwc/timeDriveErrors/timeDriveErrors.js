/**
 * Errors, said plainly, for Time Drive and the record
 * details it expands: a plain title and message, never the raw
 * message (which can carry query text, field names and stack traces).
 */
import { LABELS, format } from "c/timeDriveLabels";

// What can go wrong, matched on codes, status and wording, in order: a
// missing record says "does not exist" too, so it's checked before setup.
const ERROR_KINDS = [
  {
    kind: "offline",
    test: (e) => e.status === 0 || /failed to fetch|network ?error|disconnected|offline/.test(e.text),
    message: LABELS.errOffline
  },
  {
    kind: "access",
    test: (e) =>
      e.status === 403 ||
      /insufficient_access|insufficient access|inaccessible|not accessible|isn't accessible|no access|permission|_filter'|not in '\w+_filter/.test(
        e.text
      ),
    message: LABELS.errAccess
  },
  {
    kind: "notFound",
    test: (e) =>
      e.status === 404 ||
      /entity_is_deleted|invalid_id|invalid cross reference|not_found|record not found/.test(e.text),
    message: LABELS.errNotFound
  },
  {
    kind: "setup",
    test: (e) =>
      /invalid_type|invalid type|invalid_field|no such column|does not exist|isn't supported|not supported/.test(
        e.text
      ),
    message: LABELS.errSetup
  },
  {
    kind: "busy",
    test: (e) =>
      e.status === 503 || e.status === 504 || /limit|timed out|timeout|too many|cpu time|unable to lock/.test(e.text),
    message: LABELS.errBusy
  }
];
const UNKNOWN_ERROR = {
  kind: "unknown",
  message: LABELS.errUnknown
};

// Every message and code an error carries (Apex, Lightning Data, GraphQL or
// a plain Error), for matching only.
function errorParts(error) {
  const out = [];
  const add = (item) => {
    if (!item) return;
    if (typeof item === "string") out.push(item);
    else if (Array.isArray(item)) item.forEach(add);
    else if (typeof item === "object") {
      for (const key of ["message", "errorCode", "statusCode", "exceptionType", "errorType"]) add(item[key]);
      add(item.body);
      add(item.errors);
      add(item.pageErrors);
      add(item.fieldErrors && Object.values(item.fieldErrors));
    }
  };
  add(error);
  return out;
}

/**
 * A safe, plain description of an error: { kind, message, detail }.
 * `detail` is the technical summary for the console (codes and messages, no
 * stack trace); the rest is for the user.
 */
export function describeError(error) {
  const parts = errorParts(error);
  const status = typeof error?.status === "number" ? error.status : undefined;
  const offline = typeof navigator !== "undefined" && navigator.onLine === false;
  const facts = { status: offline ? 0 : status, text: parts.join(" ").toLowerCase() };
  // The timeline's own server says the kind outright ("timedrive:access").
  const coded = /timedrive:(\w+)/.exec(facts.text)?.[1];
  const found =
    ERROR_KINDS.find((k) => k.kind.toLowerCase() === coded) ?? ERROR_KINDS.find((k) => k.test(facts)) ?? UNKNOWN_ERROR;
  return {
    kind: found.kind,
    message: found.message,
    detail: [status, ...parts]
      .filter((p) => p !== undefined && p !== "")
      .join(" · ")
      .slice(0, 500)
  };
}

/**
 * One notice for the sources that couldn't be read ({ source, kind } from
 * the server): which, by the most common kind.
 */
export function describeProblems(problems, listFormat) {
  if (!problems?.length) return null;
  const count = new Map();
  for (const p of problems) count.set(p.kind, (count.get(p.kind) ?? 0) + 1);
  const kind = [...count.entries()].sort((a, b) => b[1] - a[1])[0][0];
  const names = problems.map((p) => p.source);
  const list = listFormat ? listFormat.format(names) : names.join(", ");
  return {
    kind,
    sources: list,
    message: format(LABELS.probMessage, list)
  };
}

/**
 * States: "setup" (something an admin hasn't set up or granted), "error"
 * (it failed as it ran), "noresults" (set up, just nothing found) and
 * "filtered" (the filters hid everything).
 */
const ILLUSTRATIONS = {
  setup: "access:request",
  error: "error:recoverable",
  // Set up, but no record matches: a search that found nothing.
  noresults: "noresults:search",
  // Filters took everything away.
  filtered: "noresults:filter"
};

/**
 * The SLDS illustration (for lightning-illustration) for a state. The
 * component picks SLDS 1's or SLDS 2's drawing, and light or dark, itself.
 */
export function illustrationName(state) {
  return ILLUSTRATIONS[state] ?? ILLUSTRATIONS.error;
}

/** The illustration state for an error kind: setup for what an admin can fix, else error. */
export function illustrationState(kind) {
  return kind === "setup" || kind === "access" ? "setup" : "error";
}

/**
 * Whether the page draws SLDS 2. Its buttons are rounded far more than SLDS
 * 1's (0.25rem), so a hidden SLDS button's corners say which, whatever
 * styling hooks the page also defines (SLDS 1 pages can define SLDS 2's).
 * Read once per page. Where nothing can be measured (no SLDS styles, as in
 * tests), SLDS 2's surface hook decides.
 */
let measuredSlds2;
export function isSlds2(element) {
  if (measuredSlds2 !== undefined) return measuredSlds2;
  if (!element || typeof getComputedStyle !== "function") return false;
  const radius = buttonRadius();
  if (Number.isFinite(radius)) {
    measuredSlds2 = radius > 6;
    return measuredSlds2;
  }
  return getComputedStyle(element).getPropertyValue("--slds-g-color-surface-1").trim() !== "";
}

// A neutral SLDS button's corner radius in px, or NaN when it has none.
function buttonRadius() {
  try {
    const probe = document.createElement("button");
    probe.className = "slds-button slds-button_neutral";
    probe.setAttribute("aria-hidden", "true");
    probe.tabIndex = -1;
    probe.style.cssText = "position: absolute; visibility: hidden; pointer-events: none";
    probe.textContent = "x";
    document.body.appendChild(probe);
    const value = getComputedStyle(probe).borderTopLeftRadius;
    probe.remove();
    // No SLDS on the page: nothing to go by.
    return value && value !== "0px" ? parseFloat(value) : NaN;
  } catch {
    return NaN;
  }
}

// The slots a drawing sits in (a fixed size, so the words under it start in the
// same place whichever drawing it is).
const SLOTS = ".illustration, .issue-illustration, .error-illustration, .problem-art";
const watched = new WeakSet();

// A drawing's file has empty margin around the artwork, so it may be this much
// taller than its slot before the artwork itself could reach the words.
const OVERHANG = 1.6;

/**
 * Keeps each drawing from reaching the words. lightning-illustration sizes
 * itself to the slot's width, and the slot is only as tall as the artwork, so a
 * drawing is allowed to be taller (its empty margin spills above, unseen). One
 * far taller than that is scaled down to fit, standing on the slot's floor.
 * Call it after rendering; each drawing is watched once, and again whenever
 * it changes size.
 */
export function fitIllustrations(root) {
  if (typeof ResizeObserver === "undefined") return;
  for (const slot of root.querySelectorAll(SLOTS)) {
    const art = slot.querySelector("lightning-illustration");
    if (!art || watched.has(art)) continue;
    watched.add(art);
    new ResizeObserver(() => {
      const room = slot.clientHeight;
      const height = art.offsetHeight;
      const limit = room * OVERHANG;
      const scale = room && height > limit ? limit / height : 1;
      art.style.transform = scale < 1 ? `scale(${scale})` : "";
      art.style.transformOrigin = "center bottom";
    }).observe(art);
  }
}
