"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const MarkdownIt = require("markdown-it");
const extension = require("../extension");

function createMarkdownIt() {
  return extension.activate().extendMarkdownIt(new MarkdownIt({ html: true }));
}

// Emulates the front matter rule VS Code installs after contributed plugins.
function installVscodeFrontMatterRule(md) {
  md.block.ruler.before("fence", "front_matter", function (
    state,
    startLine,
    endLine,
    silent
  ) {
    if (startLine !== 0) return false;
    const start = state.bMarks[startLine] + state.tShift[startLine];
    const end = state.eMarks[startLine];
    if (state.src.slice(start, end).trim() !== "---") return false;

    let closeLine = startLine + 1;
    while (closeLine < endLine) {
      const lineStart = state.bMarks[closeLine] + state.tShift[closeLine];
      const lineEnd = state.eMarks[closeLine];
      if (state.src.slice(lineStart, lineEnd).trim() === "---") break;
      closeLine += 1;
    }
    if (closeLine >= endLine) return false;
    if (silent) return true;

    const token = state.push("html_block", "", 0);
    token.content = '<table class="frontmatter"><tr><td>VS Code</td></tr></table>';
    state.line = closeLine + 1;
    return true;
  });
}

test("Nexora front matter wins over VS Code's table renderer", () => {
  const md = createMarkdownIt();
  installVscodeFrontMatterRule(md);

  const html = md.render("---\ntitle: Demo\ntags: [one, two]\n---\n\n# Body\n");

  assert.match(html, /<pre class="nexora-front-matter">/);
  assert.match(html, /title: Demo/);
  assert.doesNotMatch(html, /<table class="frontmatter">/);
});

test("footnotes render during Markdown parsing", () => {
  const md = createMarkdownIt();
  const html = md.render(
    "A reference[^note] and another reference[^note].\n\n" +
      "[^note]: Footnote with **formatting**.\n"
  );

  assert.match(html, /<sup class="footnote-ref">/);
  assert.match(html, /<section class="footnotes">/);
  assert.match(html, /Footnote with <strong>formatting<\/strong>/);
  assert.match(html, /class="footnote-backref"/);
  assert.doesNotMatch(html, /\[\^note\]/);
});

test("an unclosed front matter delimiter remains ordinary Markdown", () => {
  const md = createMarkdownIt();
  const html = md.render("---\ntitle: Demo\n");

  assert.doesNotMatch(html, /nexora-front-matter/);
  assert.match(html, /title: Demo/);
});

test("Mermaid fences bypass the generic code-block DOM", () => {
  const md = createMarkdownIt();
  const source = "flowchart LR\n  A[Markdown] --> B[Nexora]\n";
  const html = md.render("```mermaid\n" + source + "```\n");

  assert.match(html, /class="nexora-mermaid"/);
  assert.match(html, /data-nexora-mermaid-source=/);
  assert.match(html, /<div class="nexora-mermaid-canvas">flowchart LR/);
  assert.doesNotMatch(html, /class="mermaid"/);
  assert.doesNotMatch(html, /nexora-code-block/);
  assert.doesNotMatch(html, /<pre>/);
});

test("code fences render directly with Nexora language normalization", () => {
  const md = createMarkdownIt();
  const html = md.render("```c++\nint main() { return 0; }\n```\n");

  assert.match(html, /class="nexora-code-block"/);
  assert.match(html, /data-nexora-language="cpp"/);
  assert.match(html, /<span class="nexora-code-language">cpp<\/span>/);
  assert.match(html, /<code class="hljs language-cpp">/);
});
