/**
 * Nexora Markdown Preview — enhancement script for VS Code's built-in markdown preview.
 *
 * Ported from Nexora `lib/widgets/markdown_dom_preview.dart` (`_bridgeScript`).
 * Runs after highlight.js and Mermaid (declared earlier in previewScripts), so
 * `window.hljs` / `window.__nexoraMermaid` are available. Read-only preview:
 * editor /
 * find / scroll-sync from the original were intentionally dropped.
 *
 *   - GitHub callouts (`> [!NOTE] / [!TIP] / ...`)            → enhanceAlerts
 *   - `[TOC]` placeholder → generated table of contents        → buildToc
 *   - Images → <figure> + <figcaption>                          → wrapImages
 *   - Fenced code → `.nexora-code-block` (mac dots + label)     → processBlocks
 *   - Code tokens re-highlighted with highlight.js              → highlightCode
 *   - ```mermaid blocks rendered via mermaid                     → renderMermaid
 *
 * Re-runs via a debounced MutationObserver so it survives VS Code swapping the
 * preview content, and re-renders Mermaid when light/dark actually flips.
 */
(function () {
  "use strict";

  function forEach(list, fn) {
    Array.prototype.forEach.call(list, fn);
  }

  function isDark() {
    var c = document.body.classList;
    return c.contains("vscode-dark") || c.contains("vscode-high-contrast");
  }

  var ALERT_MAP = {
    NOTE: { type: "note", title: "Note", icon: "📝" },
    TIP: { type: "tip", title: "Tip", icon: "💡" },
    WARNING: { type: "warning", title: "Warning", icon: "⚠️" },
    IMPORTANT: { type: "important", title: "Important", icon: "📌" },
    CAUTION: { type: "caution", title: "Caution", icon: "🔥" },
  };

  function promoteAlert(el, type) {
    if (el.classList.contains("nexora-alert")) return;
    var item = ALERT_MAP[type.toUpperCase()];
    if (!item) return;
    // VS Code's own alert ships a <p class="markdown-alert-title"> (icon + word)
    // and may set inline styles on the container. Drop both so Nexora CSS wins.
    var title = el.querySelector(".markdown-alert-title");
    if (title) title.remove();
    el.removeAttribute("style");
    var capsule = document.createElement("div");
    capsule.className =
      "nexora-alert-text-container nexora-alert-text-" + type;
    capsule.innerHTML =
      '<span class="nexora-alert-icon">' + item.icon + "</span>" + item.title;
    el.insertBefore(capsule, el.firstChild);
    el.classList.remove("markdown-alert", "markdown-alert-" + type);
    el.classList.add("nexora-alert", "nexora-alert-" + type);
  }

  function enhanceAlerts() {
    // VS Code renders GitHub alerts as <div class="markdown-alert markdown-alert-X">.
    document.querySelectorAll(".markdown-alert").forEach(function (el) {
      var m = (el.className || "").match(
        /markdown-alert-(note|tip|warning|important|caution)\b/i
      );
      if (m) promoteAlert(el, m[1].toLowerCase());
    });
    // Fallback for renderers that keep the literal "[!NOTE]" inside a blockquote.
    var blockquotes = document.querySelectorAll("blockquote");
    forEach(blockquotes, function (bq) {
      if (bq.classList.contains("nexora-alert")) return;
      var target = bq.querySelector("p") || bq;
      var html = target.innerHTML || "";
      var match = html.match(
        /^\s*\[!(NOTE|TIP|WARNING|IMPORTANT|CAUTION)\]\s*(?:<br\s*\/?>|\n)?/i
      );
      if (!match) return;
      var item = ALERT_MAP[match[1].toUpperCase()];
      if (!item) return;
      target.innerHTML = html.slice(match[0].length);
      promoteAlert(bq, item.type);
    });
  }

  function buildToc() {
    var placeholders = document.querySelectorAll("p");
    forEach(placeholders, function (p) {
      if ((p.textContent || "").trim() !== "[TOC]") return;
      if (p.closest(".nexora-toc")) return;
      var headings = document.querySelectorAll("h1, h2, h3, h4, h5, h6");
      var nav = document.createElement("nav");
      nav.className = "nexora-toc";
      forEach(headings, function (h) {
        var level = parseInt(h.tagName.substring(1), 10);
        var a = document.createElement("a");
        a.className = "nexora-toc-item nexora-toc-level-" + level;
        a.href = "#" + (h.id || "");
        a.textContent = (h.textContent || "").replace(/\s+/g, " ").trim();
        nav.appendChild(a);
      });
      p.replaceWith(nav);
    });
  }

  function wrapImages() {
    var imgs = document.querySelectorAll("img");
    forEach(imgs, function (img) {
      if (img.closest("figure")) return;
      if (img.closest("a")) return;
      var alt = (img.getAttribute("alt") || "").trim();
      var title = (img.getAttribute("title") || "").trim();
      var caption = alt || title;
      if (!caption) return;
      var parent = img.parentNode;
      var target = img;
      if (parent && parent.tagName === "P") {
        var onlyChild = true;
        for (var i = 0; i < parent.childNodes.length; i++) {
          var n = parent.childNodes[i];
          if (n === img) continue;
          if (n.nodeType === Node.TEXT_NODE && ((n.nodeValue || "").trim() === ""))
            continue;
          onlyChild = false;
          break;
        }
        if (onlyChild) target = parent;
      }
      var figure = document.createElement("figure");
      target.parentNode.replaceChild(figure, target);
      figure.appendChild(img);
      var figcaption = document.createElement("figcaption");
      figcaption.textContent = caption;
      figure.appendChild(figcaption);
    });
  }

  function extractLang(el) {
    var m = (el.className || "").match(/(?:^|\s)language-([^\s]+)/);
    return m ? normalizeLang(m[1]) : "";
  }

  // Keep aliases in sync with Nexora's MarkdownCodeHighlighter. Besides making
  // badges consistent, this avoids cases such as `c++` being truncated to `c`.
  function normalizeLang(value) {
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
    return aliases[lang] || lang;
  }

  // Splits fenced blocks into either a Mac-style code wrapper or a Mermaid
  // render container. Strips VS Code/Shiki inline styling so Nexora CSS wins.
  function processBlocks() {
    var pres = document.querySelectorAll("pre");
    forEach(pres, function (pre) {
      if (pre.closest(".nexora-code-block") || pre.closest(".nexora-mermaid"))
        return;
      // VS Code renders YAML front matter (when markdown.preview.frontMatter is
      // "show") as <pre class="frontmatter hljs">; adopt it as Nexora's card.
      if (pre.classList.contains("nexora-front-matter")) return;
      if (pre.classList.contains("frontmatter")) {
        if (!pre.classList.contains("nexora-front-matter")) {
          pre.classList.add("nexora-front-matter");
          var fcode = pre.querySelector("code");
          if (fcode) {
            fcode.textContent = fcode.textContent;
            fcode.className = "";
          }
        }
        return;
      }
      var code = pre.querySelector("code");
      var lang = extractLang(code || pre);

      if (lang === "mermaid") {
        var mBox = document.createElement("div");
        mBox.className = "nexora-mermaid";
        var source = (code ? code.textContent : pre.textContent) || "";
        mBox.setAttribute("data-nexora-mermaid-source", source);
        var mInner = document.createElement("div");
        // Do not use the generic `.mermaid` class. VS Code 1.131+ ships its own
        // Mermaid preview module, which unconditionally clears every `.mermaid`
        // element before rendering it with a second runtime.
        mInner.className = "nexora-mermaid-canvas";
        mInner.textContent = source;
        mBox.appendChild(mInner);
        pre.parentNode.replaceChild(mBox, pre);
        return;
      }

      var wrapper = document.createElement("div");
      wrapper.className = "nexora-code-block";
      var displayLang = lang || "text";
      wrapper.setAttribute("data-nexora-language", displayLang);
      pre.removeAttribute("style");
      pre.classList.remove("hljs");
      if (code) {
        // Discard VS Code's first highlight pass. Nexora owns both the token
        // markup and palette, otherwise the two highlighters leave different
        // spans/classes depending on the active VS Code version.
        var sourceText = code.textContent || "";
        code.textContent = sourceText;
        code.removeAttribute("style");
        code.className = "hljs language-" + displayLang;
      }
      pre.parentNode.insertBefore(wrapper, pre);
      wrapper.appendChild(pre);
      var label = document.createElement("span");
      label.className = "nexora-code-language";
      label.textContent = displayLang;
      wrapper.insertBefore(label, wrapper.firstChild);
    });
  }

  function highlightCode() {
    if (!window.hljs) return;
    var codes = document.querySelectorAll(".nexora-code-block pre code");
    forEach(codes, function (code) {
      if (code.getAttribute("data-nexora-highlighted")) return;
      var wrapper = code.closest(".nexora-code-block");
      var lang = wrapper ? wrapper.getAttribute("data-nexora-language") : "";
      var text = code.textContent || "";
      try {
        if (lang && window.hljs.getLanguage(lang)) {
          code.innerHTML = window.hljs.highlight(text, { language: lang }).value;
        } else {
          // Nexora leaves missing/unknown languages unhighlighted. Auto detect
          // is deliberately avoided because it made identical code render
          // differently in the desktop app and VS Code.
          code.textContent = text;
        }
        code.classList.add("hljs");
        code.setAttribute("data-nexora-highlighted", "1");
      } catch (e) {
        if (window.console) console.error("nexora hljs:", e);
      }
    });
  }

  // VS Code's markdown preview does NOT render footnotes — `[^1]` stays literal.
  // Collect `[^id]: text` definitions, turn `[^id]` refs into superscript links,
  // and append a Nexora-styled footnotes section.
  function processFootnotes() {
    var root = document.querySelector("body.vscode-body") || document.body;
    if (!root || root.querySelector("section.footnotes")) return;

    var defs = [];
    var seen = {};
    forEach(root.querySelectorAll("p"), function (p) {
      var m = (p.textContent || "").match(/^\s*\[\^([^\]]+)\]:\s*([\s\S]+?)\s*$/);
      if (m && !seen[m[1]]) {
        seen[m[1]] = true;
        defs.push({
          id: m[1],
          html: (p.innerHTML || "").replace(/^\s*\[\^[^\]]+\]:\s*/, ""),
        });
        p.setAttribute("data-nexora-fn-def", m[1]);
      }
    });
    if (!defs.length) return;
    forEach(root.querySelectorAll("[data-nexora-fn-def]"), function (p) {
      p.remove();
    });

    var num = {};
    defs.forEach(function (d, i) {
      num[d.id] = i + 1;
    });

    // Replace literal [^id] refs in text with superscript links.
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        var parent = n.parentElement;
        if (!parent) return NodeFilter.FILTER_REJECT;
        if (parent.closest("pre, code, script, style, .nexora-code-block"))
          return NodeFilter.FILTER_REJECT;
        return /\[\^[^\]]+\]/.test(n.nodeValue)
          ? NodeFilter.FILTER_ACCEPT
          : NodeFilter.FILTER_REJECT;
      },
    });
    var nodes = [];
    var node;
    while ((node = walker.nextNode())) nodes.push(node);
    forEach(nodes, function (textNode) {
      var text = textNode.nodeValue;
      var frag = document.createDocumentFragment();
      var last = 0;
      var re = /\[\^([^\]]+)\]/g;
      var m;
      while ((m = re.exec(text))) {
        if (m.index > last)
          frag.appendChild(document.createTextNode(text.slice(last, m.index)));
        if (num[m[1]]) {
          var sup = document.createElement("sup");
          sup.className = "footnote-ref";
          var a = document.createElement("a");
          a.href = "#fn-" + m[1];
          a.id = "fnref-" + m[1];
          a.textContent = num[m[1]];
          sup.appendChild(a);
          frag.appendChild(sup);
        } else {
          frag.appendChild(document.createTextNode(m[0]));
        }
        last = m.index + m[0].length;
      }
      if (last < text.length)
        frag.appendChild(document.createTextNode(text.slice(last)));
      textNode.parentNode.replaceChild(frag, textNode);
    });

    var sec = document.createElement("section");
    sec.className = "footnotes";
    var ol = document.createElement("ol");
    defs.forEach(function (d) {
      var li = document.createElement("li");
      li.id = "fn-" + d.id;
      li.innerHTML =
        d.html +
        ' <a class="footnote-backref" href="#fnref-' +
        d.id +
        '">↩</a>';
      ol.appendChild(li);
    });
    sec.appendChild(ol);
    root.appendChild(sec);
  }

  var mermaidTheme = "";
  var mermaidGeneration = 0;
  var mermaidRenderId = 0;
  var mermaidRenderQueue = Promise.resolve();

  function renderMermaidBox(box, source, generation) {
    var target = box.querySelector(".nexora-mermaid-canvas");
    if (!target) {
      target = document.createElement("div");
      target.className = "nexora-mermaid-canvas";
      box.appendChild(target);
    }
    box.classList.remove("nexora-mermaid-failed");
    box.setAttribute("data-nexora-mermaid-rendering", "1");
    box.removeAttribute("data-nexora-mermaid-rendered");

    var renderId = "nexora-mermaid-" + generation + "-" + (++mermaidRenderId);
    var job = mermaidRenderQueue.then(function () {
      if (generation !== mermaidGeneration) return null;
      // render() accepts the original source string and returns SVG. This is
      // deterministic inside VS Code's WebView and avoids run() scanning and
      // mutating live preview DOM while our MutationObserver is active.
      return window.__nexoraMermaid.render(renderId, source);
    });
    // Keep subsequent diagrams moving even if this one has invalid syntax.
    mermaidRenderQueue = job.catch(function () {});

    return job.then(function (result) {
      if (!result || generation !== mermaidGeneration) return;
      var svg = typeof result === "string" ? result : result.svg;
      box.setAttribute("data-nexora-mermaid-rendered", String(generation));
      box.removeAttribute("data-nexora-mermaid-rendering");
      target.innerHTML = svg;
      if (result.bindFunctions) result.bindFunctions(target);
    }).catch(function (e) {
      if (generation !== mermaidGeneration) return;
      if (window.console) console.error("nexora mermaid render:", e);
      box.removeAttribute("data-nexora-mermaid-rendering");
      box.classList.add("nexora-mermaid-failed");
      box.setAttribute("data-nexora-mermaid-rendered", String(generation));
      target.textContent =
        "Mermaid 渲染失败：" + (e && e.message ? e.message : String(e));
    });
  }

  function renderMermaid(force) {
    if (!window.__nexoraMermaid) return Promise.resolve();
    var containers = document.querySelectorAll(".nexora-mermaid");
    if (!containers.length) return Promise.resolve();
    var theme = isDark() ? "dark" : "default";
    if (force || theme !== mermaidTheme) {
      mermaidTheme = theme;
      mermaidGeneration += 1;
      try {
        window.__nexoraMermaid.initialize({
          startOnLoad: false,
          theme: theme,
          securityLevel: "loose",
          fontFamily: "inherit",
          // Mermaid 11 defaults to 50,000 characters and silently replaces a
          // larger diagram with "Maximum text size...". Large architecture and
          // generated diagrams are common in Markdown, so allow up to 1 MiB.
          maxTextSize: 1024 * 1024,
        });
      } catch (e) {
        if (window.console) console.error("nexora mermaid init:", e);
      }
    }
    var generation = mermaidGeneration;
    var jobs = [];
    forEach(containers, function (box) {
      if (!force &&
          (box.getAttribute("data-nexora-mermaid-rendering") === "1" ||
           box.getAttribute("data-nexora-mermaid-rendered") === String(generation))) {
        return;
      }
      var target = box.querySelector(".nexora-mermaid-canvas");
      var attrSource = box.getAttribute("data-nexora-mermaid-source");
      var source = attrSource !== null
        ? attrSource
        : ((target && target.textContent) || "");
      jobs.push(renderMermaidBox(box, source, generation));
    });
    return Promise.all(jobs);
  }

  function enhanceAll() {
    try {
      enhanceAlerts();
      buildToc();
      wrapImages();
      processBlocks();
      processFootnotes();
      highlightCode();
      renderMermaid();
    } catch (e) {
      if (window.console) console.error("nexora enhance:", e);
    }
  }

  function ready(fn) {
    if (document.readyState !== "loading") fn();
    else document.addEventListener("DOMContentLoaded", fn);
  }

  var enhanceTimer = null;
  function debouncedEnhance() {
    if (enhanceTimer) clearTimeout(enhanceTimer);
    enhanceTimer = setTimeout(enhanceAll, 80);
  }

  ready(enhanceAll);

  // Re-run on DOM changes (document switches / live edit).
  var domObserver = new MutationObserver(debouncedEnhance);
  ready(function () {
    domObserver.observe(document.body, { childList: true, subtree: true });
  });

  // Re-render Mermaid when light/dark flips.
  var lastDark = null;
  var themeObserver = new MutationObserver(function () {
    var d = isDark();
    if (d === lastDark) return;
    lastDark = d;
    if (enhanceTimer) clearTimeout(enhanceTimer);
    enhanceTimer = setTimeout(function () {
      renderMermaid(true);
    }, 120);
  });
  ready(function () {
    lastDark = isDark();
    themeObserver.observe(document.body, {
      attributes: true,
      attributeFilter: ["class"],
    });
  });

  // Safety net: if a vendor bundle was still parsing on first pass, retry.
  ready(function () {
    setTimeout(function () {
      highlightCode();
      renderMermaid();
    }, 350);
  });
})();
