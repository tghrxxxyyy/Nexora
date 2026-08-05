"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

test("browser highlight bundle includes the full language set", function () {
  const bundle = fs.readFileSync(
    path.join(__dirname, "../media/vendor/highlight.min.js"),
    "utf8"
  );
  const sandbox = { console: console };
  sandbox.globalThis = sandbox;
  vm.runInNewContext(bundle, sandbox);

  const languages = sandbox.hljs.listLanguages();
  assert.ok(languages.length >= 190, `only ${languages.length} languages bundled`);
  for (const language of [
    "dart",
    "dockerfile",
    "elixir",
    "fsharp",
    "gradle",
    "groovy",
    "haskell",
    "latex",
    "matlab",
    "nginx",
    "powershell",
    "protobuf",
    "scala",
    "verilog",
    "x86asm",
  ]) {
    assert.ok(sandbox.hljs.getLanguage(language), `missing ${language}`);
  }
});
