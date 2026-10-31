/**
 * Detail values in the user's locale. The server sends each number's amount
 * (and, for money, its currency) beside its text, so the browser can write it
 * the way the user reads numbers: grouping, decimal mark and currency symbol.
 * Anything else keeps the server's text.
 */
import LOCALE from "@salesforce/i18n/locale";

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
