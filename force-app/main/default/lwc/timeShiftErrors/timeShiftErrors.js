/**
 * Errors, said plainly, for Time Trail and the record
 * details it expands: what went wrong and a likely cause, never the raw
 * message (which can carry query text, field names and stack traces).
 */
import { LABELS, format } from "c/timeShiftLabels";

// What can go wrong, matched on codes, status and wording, in order: a
// missing record says "does not exist" too, so it's checked before setup.
const ERROR_KINDS = [
  {
    kind: "offline",
    test: (e) => e.status === 0 || /failed to fetch|network ?error|disconnected|offline/.test(e.text),
    message: LABELS.errOffline,
    cause: LABELS.errOfflineCause
  },
  {
    kind: "access",
    test: (e) =>
      e.status === 403 ||
      /insufficient_access|insufficient access|inaccessible|not accessible|isn't accessible|no access|permission|_filter'|not in '\w+_filter/.test(
        e.text
      ),
    message: LABELS.errAccess,
    cause: LABELS.errAccessCause
  },
  {
    kind: "notFound",
    test: (e) =>
      e.status === 404 ||
      /entity_is_deleted|invalid_id|invalid cross reference|not_found|record not found/.test(e.text),
    message: LABELS.errNotFound,
    cause: LABELS.errNotFoundCause
  },
  {
    kind: "setup",
    test: (e) =>
      /invalid_type|invalid type|invalid_field|no such column|does not exist|isn't supported|not supported/.test(
        e.text
      ),
    message: LABELS.errSetup,
    cause: LABELS.errSetupCause
  },
  {
    kind: "busy",
    test: (e) =>
      e.status === 503 || e.status === 504 || /limit|timed out|timeout|too many|cpu time|unable to lock/.test(e.text),
    message: LABELS.errBusy,
    cause: LABELS.errBusyCause
  }
];
const UNKNOWN_ERROR = {
  kind: "unknown",
  message: LABELS.errUnknown,
  cause: LABELS.errUnknownCause
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
 * A safe, plain description of an error: { kind, message, cause, detail }.
 * `detail` is the technical summary for the console (codes and messages, no
 * stack trace); the rest is for the user.
 */
export function describeError(error) {
  const parts = errorParts(error);
  const status = typeof error?.status === "number" ? error.status : undefined;
  const offline = typeof navigator !== "undefined" && navigator.onLine === false;
  const facts = { status: offline ? 0 : status, text: parts.join(" ").toLowerCase() };
  // The timeline's own server says the kind outright ("timeshift:access").
  const coded = /timeshift:(\w+)/.exec(facts.text)?.[1];
  const found =
    ERROR_KINDS.find((k) => k.kind.toLowerCase() === coded) ?? ERROR_KINDS.find((k) => k.test(facts)) ?? UNKNOWN_ERROR;
  return {
    kind: found.kind,
    message: found.message,
    cause: found.cause,
    detail: [status, ...parts]
      .filter((p) => p !== undefined && p !== "")
      .join(" · ")
      .slice(0, 500)
  };
}

// Sources that couldn't be read while others could: why, and what to do.
const PROBLEM_TEXT = {
  access: {
    cause: LABELS.probAccessCause,
    fix: LABELS.probAccessFix
  },
  busy: {
    cause: LABELS.probBusyCause,
    fix: LABELS.probBusyFix
  },
  unknown: {
    cause: LABELS.probUnknownCause,
    fix: LABELS.probUnknownFix
  }
};

/**
 * One notice for the sources that couldn't be read ({ source, kind } from
 * the server): which, why and what to do, by the most common kind.
 */
export function describeProblems(problems, listFormat) {
  if (!problems?.length) return null;
  const count = new Map();
  for (const p of problems) count.set(p.kind, (count.get(p.kind) ?? 0) + 1);
  const kind = [...count.entries()].sort((a, b) => b[1] - a[1])[0][0];
  const text = PROBLEM_TEXT[kind] ?? PROBLEM_TEXT.unknown;
  const names = problems.map((p) => p.source);
  const list = listFormat ? listFormat.format(names) : names.join(", ");
  return {
    kind,
    sources: list,
    message: format(LABELS.probMessage, list),
    cause: text.cause,
    fix: text.fix
  };
}

/**
 * The illustration for a state, in the page's SLDS: SLDS 2's where its
 * global styling hooks are on the page, else SLDS 1's (as Time Warp uses).
 * States: "setup" (something an admin hasn't set up or granted), "error"
 * (it failed as it ran) and "noresults" (set up, just nothing found).
 */
export function illustrationUrl(assets, state, element) {
  return `${assets}/illustrations/${isSlds2(element) ? "slds2" : "slds1"}/${state}.svg`;
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
