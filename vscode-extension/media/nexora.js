/**
 * Nexora Markdown Preview — enhancement script for VS Code's built-in markdown preview.
 *
 * Ported from Nexora `lib/widgets/markdown_dom_preview.dart` (`_bridgeScript`).
 * Runs after highlight.js and mermaid (declared earlier in previewScripts), so
 * `window.hljs` / `window.mermaid` are available. Read-only preview: editor /
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

  function enhanceAlerts() {
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
      var capsule = document.createElement("div");
      capsule.className =
        "nexora-alert-text-container nexora-alert-text-" + item.type;
      capsule.innerHTML =
        '<span class="nexora-alert-icon">' +
        item.icon +
        "</span>" +
        item.title;
      bq.insertBefore(capsule, bq.firstChild);
      bq.classList.add("nexora-alert", "nexora-alert-" + item.type);
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
    var m = (el.className || "").match(/(?:^|\s)language-([\w-]+)/);
    return m ? m[1] : "";
  }

  // Splits fenced blocks into either a Mac-style code wrapper or a Mermaid
  // render container. Strips VS Code/Shiki inline styling so Nexora CSS wins.
  function processBlocks() {
    var pres = document.querySelectorAll("pre");
    forEach(pres, function (pre) {
      if (pre.closest(".nexora-code-block") || pre.closest(".nexora-mermaid"))
        return;
      var code = pre.querySelector("code");
      var lang = extractLang(code || pre);
      var text = (code ? code.textContent : pre.textContent) || "";

      if (lang === "mermaid") {
        var box = document.createElement("div");
        box.className = "nexora-mermaid";
        box.setAttribute("data-nexora-mermaid-source", text);
        var inner = document.createElement("div");
        inner.className = "mermaid";
        inner.textContent = text;
        box.appendChild(inner);
        pre.parentNode.replaceChild(box, pre);
        return;
      }

      var wrapper = document.createElement("div");
      wrapper.className = "nexora-code-block";
      if (lang) wrapper.setAttribute("data-nexora-language", lang);
      pre.removeAttribute("style");
      if (code) code.removeAttribute("style");
      pre.parentNode.insertBefore(wrapper, pre);
      wrapper.appendChild(pre);
      if (lang && lang !== "text") {
        var label = document.createElement("span");
        label.className = "nexora-code-language";
        label.textContent = lang;
        wrapper.appendChild(label);
      }
      if (code && !code.classList.contains("hljs")) code.classList.add("hljs");
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
          code.innerHTML = window.hljs.highlightAuto(text).value;
        }
        code.classList.add("hljs");
        code.setAttribute("data-nexora-highlighted", "1");
      } catch (e) {
        if (window.console) console.error("nexora hljs:", e);
      }
    });
  }

  function renderMermaid() {
    if (!window.mermaid) return;
    var containers = document.querySelectorAll(".nexora-mermaid");
    if (!containers.length) return;
    try {
      window.mermaid.initialize({
        startOnLoad: false,
        theme: isDark() ? "dark" : "default",
        securityLevel: "loose",
        fontFamily: "inherit",
      });
    } catch (e) {
      if (window.console) console.error("nexora mermaid init:", e);
    }
    forEach(containers, function (box) {
      var source = box.getAttribute("data-nexora-mermaid-source") || "";
      var target = box.querySelector(".mermaid");
      if (!target) {
        target = document.createElement("div");
        target.className = "mermaid";
        box.appendChild(target);
      }
      target.removeAttribute("data-processed");
      target.innerHTML = source;
    });
    try {
      window.mermaid.run({
        nodes: document.querySelectorAll(".nexora-mermaid .mermaid"),
      });
    } catch (e) {
      if (window.console) console.error("nexora mermaid run:", e);
    }
  }

  function enhanceAll() {
    try {
      enhanceAlerts();
      buildToc();
      wrapImages();
      processBlocks();
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

  // Re-render Mermaid only when light/dark actually flips.
  var lastDark = null;
  var themeObserver = new MutationObserver(function () {
    var d = isDark();
    if (d === lastDark) return;
    lastDark = d;
    if (enhanceTimer) clearTimeout(enhanceTimer);
    enhanceTimer = setTimeout(renderMermaid, 120);
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
