"use strict";

const path = require("node:path");
const esbuild = require("esbuild");

const projectRoot = path.resolve(__dirname, "..");
const output = path.join(projectRoot, "media/vendor/highlight.min.js");

esbuild.buildSync({
  stdin: {
    contents: [
      'import hljs from "highlight.js";',
      "globalThis.hljs = hljs;",
    ].join("\n"),
    resolveDir: projectRoot,
    sourcefile: "nexora-highlight-browser-entry.js",
  },
  bundle: true,
  format: "iife",
  platform: "browser",
  target: ["chrome100"],
  minify: true,
  legalComments: "none",
  outfile: output,
});

const languageCount = require("highlight.js").listLanguages().length;
console.log(`Built highlight.js with ${languageCount} languages: ${output}`);
