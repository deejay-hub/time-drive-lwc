import { parseInline, parseMarkdown, sectionize } from "../markdown";

describe("markdown", () => {
  it("reads headings, paragraphs, lists, notes, code, images and rules", () => {
    const blocks = parseMarkdown(
      [
        "# Title",
        "",
        "One line",
        "and the next.",
        "",
        "- a",
        "- b",
        "  carried on",
        "",
        "1. first",
        "2. second",
        "",
        "> [!NOTE]",
        "> Careful.",
        "",
        "```js",
        "const x = 1;",
        "```",
        "",
        "![Shot](img/shot.png)",
        "",
        "---"
      ].join("\n")
    );
    expect(blocks.map((b) => b.type)).toEqual(["heading", "p", "ul", "ol", "note", "code", "image", "rule"]);
    expect(blocks[1].text).toBe("One line and the next.");
    expect(blocks[2].items).toEqual(["a", "b carried on"]);
    expect(blocks[4].text).toBe("Careful.");
    expect(blocks[5].text).toBe("const x = 1;");
    expect(blocks[6]).toMatchObject({ alt: "Shot", src: "img/shot.png" });
  });

  it("reads bold, italic, code and links inline", () => {
    const parts = parseInline("Use **this**, *that* and `code`, or [read](a.md).", (href) => ({ href, doc: "a" }));
    expect(parts).toEqual([
      { text: "Use " },
      { text: "this", bold: true },
      { text: ", " },
      { text: "that", italic: true },
      { text: " and " },
      { text: "code", code: true },
      { text: ", or " },
      { text: "read", link: { href: "a.md", doc: "a" } },
      { text: "." }
    ]);
  });

  it("splits a doc into sections at each ##", () => {
    const sections = sectionize(parseMarkdown("# T\n\nIntro\n\n## First one\n\nA\n\n## Second\n\nB"));
    expect(sections.map((s) => [s.id, s.title])).toEqual([
      ["intro", ""],
      ["first-one", "First one"],
      ["second", "Second"]
    ]);
  });
});
