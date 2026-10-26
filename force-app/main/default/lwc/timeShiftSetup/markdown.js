// A small markdown reader for the Docs, which come from a public GitHub
// repo. It turns markdown into plain blocks that templates draw, so nothing
// from the repo becomes HTML on the page and there's nothing to sanitize.
//
// It reads what the docs use: # headings, paragraphs, - and 1. lists,
// > notes, ``` code, ![images](), ---, and inline **bold**, *italic*,
// `code` and [links]().

const SLUG_STRIP = /[^a-z0-9]+/g;

export function slugify(text) {
  return text.toLowerCase().replace(SLUG_STRIP, "-").replace(/^-|-$/g, "");
}

// Inline text: bold, italic, code and links, in reading order.
const INLINE = /(\*\*([^*]+)\*\*)|(`([^`]+)`)|(\[([^\]]+)\]\(([^)\s]+)\))|(\*([^*]+)\*)|(_([^_]+)_)/g;

export function parseInline(text, resolve) {
  const parts = [];
  let last = 0;
  for (const m of text.matchAll(INLINE)) {
    if (m.index > last) parts.push({ text: text.slice(last, m.index) });
    if (m[1]) parts.push({ text: m[2], bold: true });
    else if (m[3]) parts.push({ text: m[4], code: true });
    else if (m[5]) parts.push({ text: m[6], link: resolve ? resolve(m[7]) : { href: m[7] } });
    else parts.push({ text: m[9] ?? m[11], italic: true });
    last = m.index + m[0].length;
  }
  if (last < text.length) parts.push({ text: text.slice(last) });
  return parts;
}

const HEADING = /^(#{1,4})\s+(.*)$/;
const BULLET = /^\s*[-*+]\s+(.*)$/;
const NUMBERED = /^\s*\d+[.)]\s+(.*)$/;
const IMAGE = /^!\[([^\]]*)\]\(([^)\s]+)\)\s*$/;
const RULE = /^(-{3,}|\*{3,}|_{3,})\s*$/;

// Blocks: { type: "heading", level, text }, { type: "p", text },
// { type: "ul" | "ol", items: [text] }, { type: "note", text },
// { type: "code", text }, { type: "image", alt, src }, { type: "rule" }.
// Text stays markdown here; parseInline reads it when drawn.
export function parseMarkdown(source) {
  const lines = String(source ?? "")
    .replace(/\r\n?/g, "\n")
    .split("\n");
  const blocks = [];
  let para = [];
  const flush = () => {
    if (para.length) blocks.push({ type: "p", text: para.join(" ") });
    para = [];
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();

    if (trimmed.startsWith("```")) {
      flush();
      const code = [];
      for (i++; i < lines.length && !lines[i].trim().startsWith("```"); i++) code.push(lines[i]);
      blocks.push({ type: "code", text: code.join("\n") });
      continue;
    }
    if (!trimmed) {
      flush();
      continue;
    }
    const heading = trimmed.match(HEADING);
    if (heading) {
      flush();
      blocks.push({ type: "heading", level: heading[1].length, text: heading[2].trim() });
      continue;
    }
    if (RULE.test(trimmed)) {
      flush();
      blocks.push({ type: "rule" });
      continue;
    }
    const image = trimmed.match(IMAGE);
    if (image) {
      flush();
      blocks.push({ type: "image", alt: image[1], src: image[2] });
      continue;
    }
    if (trimmed.startsWith(">")) {
      flush();
      const note = [];
      for (; i < lines.length && lines[i].trim().startsWith(">"); i++) {
        note.push(lines[i].trim().replace(/^>\s?/, ""));
      }
      i--;
      // GitHub's alert marker ([!NOTE], [!TIP]…) reads as a plain note.
      const text = note
        .join(" ")
        .replace(/^\[!\w+\]\s*/, "")
        .trim();
      blocks.push({ type: "note", text });
      continue;
    }
    const listType = BULLET.test(line) ? "ul" : NUMBERED.test(line) ? "ol" : null;
    if (listType) {
      flush();
      const pattern = listType === "ul" ? BULLET : NUMBERED;
      const items = [];
      for (; i < lines.length; i++) {
        const item = lines[i].match(pattern);
        if (item) items.push(item[1].trim());
        else if (lines[i].trim() && /^\s{2,}/.test(lines[i]) && items.length) {
          // An indented line carries on the item above.
          items[items.length - 1] += ` ${lines[i].trim()}`;
        } else break;
      }
      i--;
      blocks.push({ type: listType, items });
      continue;
    }
    para.push(trimmed);
  }
  flush();
  return blocks;
}

// A doc in sections: each ## starts one; anything before the first is the
// intro. The # title is left to the page's own heading.
export function sectionize(blocks) {
  const sections = [];
  let current = { id: "intro", title: "", blocks: [] };
  for (const block of blocks) {
    if (block.type === "heading" && block.level === 1) continue;
    if (block.type === "heading" && block.level === 2) {
      if (current.blocks.length || current.title) sections.push(current);
      current = { id: slugify(block.text), title: block.text, blocks: [] };
    } else {
      current.blocks.push(block);
    }
  }
  if (current.blocks.length || current.title) sections.push(current);
  return sections;
}

// Blocks ready to draw: keyed, flagged by type, inline text read, and links
// and images resolved by `resolve(href)` → { href, doc?, anchor?, external? }
// and `image(src)` → src.
export function present(blocks, { prefix = "b", resolve, image } = {}) {
  const parts = (text, key) =>
    parseInline(text, resolve).map((part, i) => {
      const link = part.link;
      return {
        ...part,
        key: `${key}-${i}`,
        isLink: Boolean(link),
        href: link?.href,
        doc: link?.doc,
        anchor: link?.anchor,
        target: link?.external ? "_blank" : null,
        rel: link?.external ? "noopener" : null
      };
    });
  return blocks.map((block, i) => {
    const key = `${prefix}-${i}`;
    return {
      ...block,
      key,
      isHeading: block.type === "heading",
      isP: block.type === "p",
      isUl: block.type === "ul",
      isOl: block.type === "ol",
      isNote: block.type === "note",
      isCode: block.type === "code",
      isImage: block.type === "image",
      isRule: block.type === "rule",
      src: block.type === "image" && image ? image(block.src) : block.src,
      parts: block.text !== undefined && block.type !== "code" ? parts(block.text, key) : [],
      items: (block.items ?? []).map((text, j) => ({ key: `${key}-${j}`, parts: parts(text, `${key}-${j}`) }))
    };
  });
}
