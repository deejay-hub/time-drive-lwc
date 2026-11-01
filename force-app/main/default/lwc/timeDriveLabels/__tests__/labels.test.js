import fs from "fs";
import path from "path";
import { LABELS, format } from "../timeDriveLabels";

const MAIN = path.resolve(__dirname, "../../..");
const read = (file) => fs.readFileSync(path.join(MAIN, file), "utf8");
const unescape = (t) =>
  t
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");

// name -> English
const english = {};
for (const [, body] of read("labels/CustomLabels.labels-meta.xml").matchAll(/<labels>([\s\S]*?)<\/labels>/g)) {
  english[/<fullName>([^<]*)</.exec(body)[1]] = unescape(/<value>([\s\S]*?)<\/value>/.exec(body)[1]);
}
const translations = (lang) => {
  const out = {};
  for (const [, label, name] of read(`translations/${lang}.translation-meta.xml`).matchAll(
    /<customLabels>\s*<label>([\s\S]*?)<\/label>\s*<name>([^<]*)<\/name>/g
  )) {
    out[name] = unescape(label);
  }
  return out;
};
const places = (text) => [...text.matchAll(/\{\d+\}/g)].map((m) => m[0]).sort();

describe("the timeline's custom labels", () => {
  const es = translations("es");
  const ar = translations("ar");
  const names = Object.keys(english);

  it("has a Spanish and an Arabic translation for every label", () => {
    expect(names.filter((n) => !es[n])).toEqual([]);
    expect(names.filter((n) => !ar[n])).toEqual([]);
  });

  it("keeps each placeholder in every language", () => {
    const wrong = names.filter(
      (n) => places(es[n]).join() !== places(english[n]).join() || places(ar[n]).join() !== places(english[n]).join()
    );
    expect(wrong).toEqual([]);
  });

  it("writes the Arabic in Arabic letters", () => {
    // (A label that is only placeholders and punctuation has no words to translate.)
    const words = (n) => /[A-Za-z]/.test(english[n].replace(/\{\d+\}/g, ""));
    const notArabic = names.filter((n) => words(n) && !/[؀-ۿ]/.test(ar[n]));
    expect(notArabic).toEqual([]);
  });

  it("stays inside Salesforce's limits", () => {
    expect(names.filter((n) => n.length > 40)).toEqual([]);
    expect(names.filter((n) => english[n].length > 1000)).toEqual([]);
  });

  it("reaches the components through the shared module", () => {
    const source = read("lwc/timeDriveLabels/timeDriveLabels.js");
    const imported = [...source.matchAll(/c\.(Time_Drive_\w+)"/g)].map((m) => m[1]);
    // (Server_* labels are Apex's, Label.Time_Drive_Server_...; the rest are
    // named by sources and lenses as $Label.Time_Drive_...)
    const mine = names.filter((n) => !/^Time_Drive_(Example_Legend|View_\w+|Server_\w+|Legend_\w+)$/.test(n));
    expect(imported.sort()).toEqual(mine.sort());
    // And each reads as its English text in the tests.
    expect(LABELS.buttonToday).toBe("Today");
    expect(LABELS.itemsMany).toBe("{0} items");
  });
});

describe("format", () => {
  it("fills in {0}, {1} ... and leaves unknown ones", () => {
    expect(format("{0} of {1} types", 2, 5)).toBe("2 of 5 types");
    expect(format("Back to {0}", "Ada")).toBe("Back to Ada");
    expect(format("{0} and {2}", "a")).toBe("a and {2}");
  });
});
