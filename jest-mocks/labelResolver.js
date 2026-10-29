/**
 * Jest's resolver: the project's custom labels (`@salesforce/label/c.Name`)
 * read as their English text from CustomLabels.labels-meta.xml, so the tests
 * assert on the words people see (the stock stub gives the label's name).
 * Everything else resolves as sfdx-lwc-jest does.
 */
const fs = require("fs");
const os = require("os");
const path = require("path");
const base = require("@salesforce/sfdx-lwc-jest/src/resolver.js");

const LABELS = path.resolve(__dirname, "../force-app/main/default/labels/CustomLabels.labels-meta.xml");
const OUT = path.join(os.tmpdir(), "time-drive-jest-labels");

const unescape = (text) =>
  text
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");

let values;
function labelValues() {
  if (!values) {
    values = {};
    const xml = fs.readFileSync(LABELS, "utf8");
    for (const [, body] of xml.matchAll(/<labels>([\s\S]*?)<\/labels>/g)) {
      const name = /<fullName>([^<]*)<\/fullName>/.exec(body)?.[1];
      const value = /<value>([\s\S]*?)<\/value>/.exec(body)?.[1];
      if (name && value !== undefined) values[name] = unescape(value);
    }
  }
  return values;
}

module.exports = function (request, options) {
  const label = /^@salesforce\/label\/c\.(.+)$/.exec(request)?.[1];
  if (label) {
    const all = labelValues();
    // A label that isn't in the file is left to the stock stub (its name), so a
    // typo shows in a test as "c.Name" instead of passing.
    if (label in all) {
      fs.mkdirSync(OUT, { recursive: true });
      const file = path.join(OUT, `${label}.js`);
      fs.writeFileSync(file, `module.exports = { __esModule: true, default: ${JSON.stringify(all[label])} };\n`);
      return file;
    }
  }
  return base(request, options);
};
