/**
 * Nexora Markdown Preview — markdown-it plugin host.
 *
 * VS Code's markdown preview strips YAML front matter at the source level before
 * it ever reaches the DOM (controlled by `markdown.preview.frontMatter`, which
 * defaults to "hide"). A previewScripts/previewStyles approach therefore can't
 * see the front matter text to restyle it.
 *
 * Through the `markdown.markdownItPlugins` contribution point we register a
 * block rule that, when the user opts in via `markdown.preview.frontMatter: "show"`,
 * captures the leading `--- ... ---` block and emits Nexora's
 * `<pre class="nexora-front-matter">` structure so the existing CSS applies.
 */
"use strict";

function escapeHtml(value) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function nexoraFrontMatter(md) {
  md.block.ruler.before("hr", "nexora_front_matter", function (
    state,
    startLine,
    endLine,
    silent
  ) {
    // Front matter must be the very first block in the document.
    if (startLine !== 0) return false;

    var begin = state.bMarks[startLine] + state.tShift[startLine];
    var end = state.eMarks[startLine];
    if (state.src.slice(begin, end).trim() !== "---") return false;

    var closeLine = -1;
    for (var next = startLine + 1; next < endLine; next++) {
      var lb = state.bMarks[next] + state.tShift[next];
      var le = state.eMarks[next];
      if (state.src.slice(lb, le).trim() === "---") {
        closeLine = next;
        break;
      }
    }
    if (closeLine === -1) return false;

    if (silent) return true;

    var yaml = state.src
      .slice(state.bMarks[startLine + 1], state.eMarks[closeLine - 1])
      .replace(/^\n+|\n+$/g, "");

    var token = state.push("html_block", "", 0);
    token.content =
      '<pre class="nexora-front-matter"><code>' +
      escapeHtml(yaml) +
      "</code></pre>";
    token.map = [startLine, closeLine + 1];
    token.children = [];

    state.line = closeLine + 1;
    return true;
  });
}

function activate() {
  return {
    extendMarkdownIt: function (md) {
      md.use(nexoraFrontMatter);
      return md;
    },
  };
}

module.exports = { activate: activate };
