/**
 * Nexora Markdown Preview — markdown-it plugin host.
 *
 * VS Code owns the Markdown parser, so syntax-level features must be installed
 * here instead of being guessed from the rendered DOM. In particular, recent
 * VS Code versions render YAML front matter as a table by default and core
 * markdown-it does not support footnotes.
 *
 * This plugin captures front matter before VS Code's own `front_matter` rule and
 * enables markdown-it-footnote. The resulting HTML is the same structure that
 * Nexora's desktop renderer styles.
 */
"use strict";

const markdownItFootnote = require("markdown-it-footnote");

function escapeHtml(value) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function nexoraFrontMatter(md) {
  // VS Code installs its own front_matter rule *after* contributed plugins and
  // inserts it before `fence`. Registering before `hr` therefore loses to the
  // built-in rule and produces <table class="frontmatter">. Being before
  // `fence` keeps this rule ahead even after VS Code adds its rule later.
  md.block.ruler.before("fence", "nexora_front_matter", function (
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

function normalizeFenceLanguage(value) {
  var lang = (value || "").toLowerCase();
  var aliases = {
    html: "xml", htm: "xml", svg: "xml", xhtml: "xml",
    js: "javascript", jsx: "javascript",
    ts: "typescript", tsx: "typescript",
    py: "python", ipython: "python",
    sh: "bash", zsh: "bash", ksh: "bash",
    console: "shell", shellsession: "shell",
    yml: "yaml", md: "markdown",
    h: "c", cc: "cpp", "c++": "cpp", cxx: "cpp", hpp: "cpp", hh: "cpp",
    cs: "csharp", "c#": "csharp",
    objc: "objectivec", "obj-c": "objectivec", "objective-c": "objectivec",
    golang: "go", rs: "rust", rb: "ruby", kt: "kotlin",
    pl: "perl", make: "makefile", docker: "dockerfile",
    toml: "ini", cfg: "ini", ps1: "powershell",
    bat: "dos", batch: "dos", cmd: "dos", fs: "fsharp", vb: "vbnet",
    asm: "x86asm", nasm: "x86asm", erl: "erlang", ex: "elixir", exs: "elixir",
    clj: "clojure", hs: "haskell", jl: "julia", gql: "graphql",
    proto: "protobuf", sass: "scss"
  };
  return aliases[lang] || lang || "text";
}

function nexoraFences(md) {
  // Produce Nexora's final DOM during Markdown rendering. Waiting until the
  // preview script sees a generic <pre><code> is racy: VS Code and other
  // preview contributions may have already highlighted or replaced its body.
  md.renderer.rules.fence = function (tokens, index, options, env, renderer) {
    var token = tokens[index];
    var info = (token.info || "").trim().split(/\s+/)[0];
    var language = normalizeFenceLanguage(info);

    if (language === "mermaid") {
      token.attrJoin("class", "nexora-mermaid");
      token.attrSet("data-nexora-mermaid-source", token.content);
      return (
        "<div" + renderer.renderAttrs(token) + ">" +
        '<div class="nexora-mermaid-canvas">' +
        md.utils.escapeHtml(token.content) +
        "</div>" +
        "</div>\n"
      );
    }

    token.attrJoin("class", "nexora-code-block");
    token.attrSet("data-nexora-language", language);
    var escapedLanguage = md.utils.escapeHtml(language);
    return (
      "<div" + renderer.renderAttrs(token) + ">" +
      '<span class="nexora-code-language">' + escapedLanguage + "</span>" +
      '<pre><code class="hljs language-' + escapedLanguage + '">' +
      md.utils.escapeHtml(token.content) +
      "</code></pre></div>\n"
    );
  };
}

function activate() {
  return {
    extendMarkdownIt: function (md) {
      md.use(nexoraFrontMatter);
      md.use(markdownItFootnote);
      md.use(nexoraFences);
      return md;
    },
  };
}

module.exports = { activate: activate };
