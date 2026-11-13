#!/usr/bin/env python3
"""
Writes, from catalogue.py:
  - force-app/main/default/labels/CustomLabels.labels-meta.xml (the catalogue's
    labels; any others already in the file are kept as they are)
  - force-app/main/default/translations/<lang>.translation-meta.xml: es and ar from
    the catalogue; da, de, fi, fr, ja, ko, sv, zh_CN and zh_TW from their own files (fr.py ...)
  - force-app/main/default/lwc/timeDriveLabels/timeDriveLabels.js (one import
    per label, and format() to fill in {0}, {1} ...)

Run it again after changing the catalogue:  python3 -I scripts/labels/generate.py
"""
import os
import re
import sys
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import catalogue  # noqa: E402

MAIN = os.path.join(ROOT, "force-app", "main", "default")
LABELS_FILE = os.path.join(MAIN, "labels", "CustomLabels.labels-meta.xml")
PREFIX = "Time_Drive_"


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def camel(key):
    first, *rest = key.split("_")
    return first.lower() + "".join(p[:1].upper() + p[1:].lower() for p in rest)


entries = catalogue.LABELS
names = {PREFIX + k for k, *_ in entries}
# A description is the label's Short Description in Setup: where it shows and why, in 80 characters.
too_long = [k for k, what, *_ in entries if len(what) > 80]
assert not too_long, f"descriptions over 80 characters: {too_long}"
# Server_* labels are for Apex (Label.Time_Drive_Server_...): not in the components'
# module, but for those the card also words itself. Apex only translates a label once
# its language is Active in Translation Language Settings, the card's labels whatever,
# so the card shows its own copy of the source names ($Label.Time_Drive_Legend_...)
# and email subtitles the server sends (see labelNamed).
CLIENT_TOO = {"Server_Sent_To", "Server_Sent_To_One_Other", "Server_Sent_To_Others"}
js_entries = [e for e in entries if not e[0].startswith("Server_") or e[0] in CLIENT_TOO]
js_names = [camel(k) for k, *_ in js_entries]
assert len(set(js_names)) == len(js_names), "two keys give the same JS name"

# ---- custom labels
xml = read(LABELS_FILE)
blocks = re.findall(r"    <labels>.*?</labels>\n", xml, flags=re.S)
# Labels from before the catalogue stay as they are; any other not in it any
# longer (a string that was taken out) goes.
kept = [b for b in blocks if re.search(r"<fullName>([^<]*)</fullName>", b).group(1) in catalogue.EXISTING_AR]
generated = "".join(
    "    <labels>\n"
    f"        <fullName>{PREFIX}{key}</fullName>\n"
    "        <categories>Time Drive</categories>\n"
    "        <language>en_US</language>\n"
    "        <protected>false</protected>\n"
    f"        <shortDescription>{escape(what)}</shortDescription>\n"
    f"        <value>{escape(en)}</value>\n"
    "    </labels>\n"
    for key, what, en, es, ar in entries
)
head = xml[: xml.index("    <labels>")]
write(LABELS_FILE, head + "".join(kept) + generated + "</CustomLabels>\n")

# ---- translations
def existing_translations(lang):
    path = os.path.join(MAIN, "translations", f"{lang}.translation-meta.xml")
    out = {}
    if os.path.exists(path):
        for label, name in re.findall(
            r"<customLabels>\s*<label>(.*?)</label>\s*<name>(.*?)</name>\s*</customLabels>", read(path), flags=re.S
        ):
            out[name] = label
    return out


def translations(lang, column):
    values = {n: v for n, v in existing_translations(lang).items() if n in catalogue.EXISTING_AR}
    if lang == "ar":
        values.update(catalogue.EXISTING_AR)
    for entry in entries:
        values[PREFIX + entry[0]] = entry[column]
    body = "".join(
        f"    <customLabels>\n        <label>{label if label.startswith('&') else escape(label) if '&' not in label else label}</label>\n"
        f"        <name>{name}</name>\n    </customLabels>\n"
        for name, label in sorted(values.items())
    )
    write(
        os.path.join(MAIN, "translations", f"{lang}.translation-meta.xml"),
        '<?xml version="1.0" encoding="UTF-8"?>\n<Translations xmlns="http://soap.sforce.com/2006/04/metadata">\n'
        + body
        + "</Translations>\n",
    )


translations("es", 3)
translations("ar", 4)

# ---- the languages kept in their own files (fr.py, zh_CN.py ...): every
# catalogue key, with the same {0}, {1} ... as its English.
import importlib  # noqa: E402

MORE_LANGUAGES = ["da", "de", "fi", "fr", "ja", "ko", "sv", "zh_CN", "zh_TW"]
english = {k: en for k, _what, en, *_ in entries}
for lang in MORE_LANGUAGES:
    module = importlib.import_module(lang)
    missing = set(english) - set(module.LABELS)
    extra = set(module.LABELS) - set(english)
    assert not missing and not extra, f"{lang}: missing {sorted(missing)}, not in the catalogue {sorted(extra)}"
    for key, text in module.LABELS.items():
        want = sorted(re.findall(r"\{\d+\}", english[key]))
        got = sorted(re.findall(r"\{\d+\}", text))
        assert want == got, f"{lang} {key}: placeholders {got}, English has {want}"
        if key.startswith("Server_"):
            assert "'" not in text, f"{lang} {key}: a straight apostrophe (String.format reads it as a quote)"
    values = dict(module.EXISTING)
    values.update({PREFIX + k: v for k, v in module.LABELS.items()})
    body = "".join(
        f"    <customLabels>\n        <label>{escape(label)}</label>\n"
        f"        <name>{name}</name>\n    </customLabels>\n"
        for name, label in sorted(values.items())
    )
    write(
        os.path.join(MAIN, "translations", f"{lang}.translation-meta.xml"),
        '<?xml version="1.0" encoding="UTF-8"?>\n<Translations xmlns="http://soap.sforce.com/2006/04/metadata">\n'
        + body
        + "</Translations>\n",
    )

# ---- the shared module
imports = "".join(
    f'import {js} from "@salesforce/label/c.{PREFIX}{key}";\n' for js, (key, *_rest) in zip(js_names, js_entries)
)
listing = "".join(f"  {js},\n" for js in js_names)
write(
    os.path.join(MAIN, "lwc", "timeDriveLabels", "timeDriveLabels.js"),
    "// Generated by scripts/labels/generate.py from scripts/labels/catalogue.py: do not edit.\n"
    "// Every end-user string of the timeline components, as a custom label (in\n"
    "// the viewer's language, where it is translated).\n"
    + imports
    + "\nexport const LABELS = Object.freeze({\n"
    + listing
    + "});\n\n"
    "// The same labels by their API names, for a name the server sends (a lens's or a\n"
    "// source's): the card shows its own copy, translated even before Apex's is.\n"
    "const BY_NAME = Object.freeze({\n"
    + "".join(f'  {PREFIX}{key}: {js},\n' for js, (key, *_rest) in zip(js_names, js_entries))
    + "});\n\n"
    "/** A Time Drive label by its API name (Time_Drive_Legend_Emails), else the fallback. */\n"
    "export function labelNamed(name, fallback) {\n"
    "  return (name && BY_NAME[name]) || fallback;\n"
    "}\n\n"
    "/** Fills a label's {0}, {1} ... with the values given: format(LABELS.itemsMany, 12). */\n"
    "export function format(text, ...values) {\n"
    "  return String(text).replace(/\\{(\\d+)\\}/g, (match, i) => (values[i] === undefined ? match : String(values[i])));\n"
    "}\n",
)
write(
    os.path.join(MAIN, "lwc", "timeDriveLabels", "timeDriveLabels.js-meta.xml"),
    '<?xml version="1.0" encoding="UTF-8" ?>\n'
    '<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">\n'
    "    <apiVersion>67.0</apiVersion>\n"
    "    <isExposed>false</isExposed>\n"
    "    <description>The timeline components' custom labels, in one place (generated from scripts/labels).</description>\n"
    "</LightningComponentBundle>\n",
)
print(f"{len(entries)} labels, {len(kept)} kept, es + ar + " + " + ".join(MORE_LANGUAGES) + " written")
