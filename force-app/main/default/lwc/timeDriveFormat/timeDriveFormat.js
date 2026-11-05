/**
 * Detail values in the user's locale. The server sends each number's amount
 * (and, for money, its currency) beside its text, so the browser can write it
 * the way the user reads numbers: grouping, decimal mark and currency symbol.
 * Anything else keeps the server's text.
 */
import LOCALE from "@salesforce/i18n/locale";
import { LABELS, format, labelNamed } from "c/timeDriveLabels";

const formats = new Map();

function formatter(currencyCode) {
  const key = currencyCode || "";
  if (!formats.has(key)) {
    formats.set(
      key,
      new Intl.NumberFormat(
        LOCALE,
        currencyCode ? { style: "currency", currency: currencyCode } : { maximumFractionDigits: 6 }
      )
    );
  }
  return formats.get(key);
}

/**
 * A detail's text, numbers and money in the user's locale.
 *
 * @param {{value: string, amount?: number, currencyCode?: string}} detail a detail from the server
 * @returns {string} the text to show
 */
export function detailText(detail) {
  if (detail?.amount == null) {
    return detail?.value;
  }
  try {
    return formatter(detail.currencyCode).format(detail.amount);
  } catch {
    // A currency code the browser doesn't know: the server's own text.
    return detail.value;
  }
}

/**
 * The details, each with its value in the user's locale.
 *
 * @param {Array} details the server's details
 * @returns {Array} the same details, values formatted
 */
export function localDetails(details) {
  return details?.map((d) => (d.amount == null ? d : { ...d, value: detailText(d) }));
}

/**
 * "Sent to: Sam Lee and 2 others", in the card's own words, from who and how
 * many others the server sent (null without them). Apex words it too (the
 * subtitle), but only in a language that is Active in Translation Language
 * Settings; the card's labels are translated whatever.
 *
 * @param {{sentTo?: string, sentToOthers?: number}} e an event from the server
 * @returns {string|null} the subtitle, or null
 */
export function sentToText(e) {
  if (!e?.sentTo) return null;
  const others = Number(e.sentToOthers ?? 0);
  if (!(others > 0)) return format(LABELS.serverSentTo, e.sentTo);
  return others === 1
    ? format(LABELS.serverSentToOneOther, e.sentTo)
    : format(LABELS.serverSentToOthers, e.sentTo, others);
}

/**
 * An event from the server with the card's own copy of the Time Drive labels
 * in it: its type's name (when the server says which label it comes from)
 * and an email's "Sent to: ..." subtitle. The same event when nothing changes.
 *
 * @param {object} e an event from the server
 * @returns {object} the event to show
 */
export function ownWords(e) {
  const typeLabel = labelNamed(e?.typeLabelName, e?.typeLabel);
  const subtitle = sentToText(e) ?? e?.subtitle;
  return typeLabel === e?.typeLabel && subtitle === e?.subtitle ? e : { ...e, typeLabel, subtitle };
}
