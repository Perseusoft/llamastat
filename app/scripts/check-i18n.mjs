#!/usr/bin/env node
// Every locale must translate exactly the keys the UI uses, with the same {n} placeholders.
// Keys are collected from t("...") calls plus the string tables in Settings.svelte that go through t().
import { readdirSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "src");
const localesDir = join(root, "lib", "locales");

function walk(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(join(dir, e.name)) : /\.(svelte|ts)$/.test(e.name) ? [join(dir, e.name)] : []);
}

const used = new Set();
for (const file of walk(root)) {
  const src = readFileSync(file, "utf8");
  for (const m of src.matchAll(/\bt\(\s*"((?:[^"\\]|\\.)*)"/g)) used.add(m[1]);
  // Settings.svelte: string tables like `const sections: Record<Section, string> = { a: "Gauges", ... }`
  // whose values are shown through t().
  if (file.endsWith("Settings.svelte")) {
    for (const m of src.matchAll(/const \w+: Record<\w+, string> = \{([^}]*)\}/g))
      for (const s of m[1].matchAll(/"([^"]+)"/g)) used.add(s[1]);
  }
}
used.add("System"); // languages[].name shown through t()

const placeholders = (s) => [...s.matchAll(/\{(\d+)\}/g)].map((m) => m[1]).sort().join(",");
let failed = false;
const report = (msg) => { failed = true; console.error("i18n: " + msg); };

for (const file of readdirSync(localesDir).filter((f) => f.endsWith(".json")).sort()) {
  const dict = JSON.parse(readFileSync(join(localesDir, file), "utf8"));
  const keys = new Set(Object.keys(dict));
  for (const k of used) if (!keys.has(k)) report(`${file}: missing "${k}"`);
  for (const k of keys) {
    if (!used.has(k)) report(`${file}: unused key "${k}"`);
    else if (placeholders(k) !== placeholders(dict[k])) report(`${file}: placeholders differ in "${k}"`);
    else if (!dict[k].trim()) report(`${file}: empty translation for "${k}"`);
  }
  console.log(`${file}: ${keys.size} keys${failed ? "" : " ok"}`);
}
console.log(`${used.size} keys used by the UI`);
process.exit(failed ? 1 : 0);
