#!/usr/bin/env node
/**
 * tools/parity/check-hardcoded-strings.mjs
 *
 * Finds user-facing text typed straight into a screen instead of coming from
 * the i18n catalogue.
 *
 * WHY THIS EXISTS. This app ships English, Hindi and Dutch, and it has a
 * generator that turns one set of JSON files into 1,746 typed accessors on both
 * platforms. None of that helps a string that was never put in the catalogue.
 * A hardcoded label does not fail, does not warn, and does not look wrong in
 * review -- it renders in English to a Hindi user and nowhere else does
 * anything happen. It is the one defect class in this port with no natural
 * detector, which is why it accumulated in the screens written under time
 * pressure while the other guards caught everything else.
 *
 * WHAT IT IS NOT. Not a translator and not a linter. It answers one question:
 * does this literal contain prose? Everything below exists to make that
 * question answerable without drowning in false positives.
 *
 * THE BASELINE. This guard arrives late, against roughly 250 existing sites.
 * Failing the build on all of them would mean either a 250-site diff nobody can
 * review or a guard everybody disables -- both worse than the debt. So it
 * carries a baseline of the sites that existed the day it was written, and
 * fails only on NEW ones. The count prints on every run and can only go down:
 * removing a site from the code and from the baseline is one edit; adding one
 * back fails. That makes the debt visible and monotonic instead of invisible
 * and growing.
 *
 * Usage:
 *   node tools/parity/check-hardcoded-strings.mjs            # fail on new
 *   node tools/parity/check-hardcoded-strings.mjs --list     # print every site
 *   node tools/parity/check-hardcoded-strings.mjs --bless    # rewrite baseline
 */

import { readFileSync, writeFileSync, readdirSync, statSync, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = process.env.SANVYA_REPO_ROOT
  ? path.resolve(process.env.SANVYA_REPO_ROOT)
  : path.resolve(__dirname, "../..");

const BASELINE = path.join(__dirname, "hardcoded-strings.baseline.json");
const LIST = process.argv.includes("--list");
const BLESS = process.argv.includes("--bless");

/**
 * Composable / view parameters whose value a person reads.
 *
 * Deliberately a list of SITES rather than "any string literal": this codebase
 * is full of literals that are not user-facing -- SQL, route names, column
 * names, analytics scopes, SF Symbol ids, test tags. Naming the places text
 * comes OUT is far more precise than trying to name all the places it does not.
 */
const SITES = [
  { re: /\bText\(\s*"((?:[^"\\]|\\.)*)"/g, what: "Text(...)" },
  { re: /\bplaceholder\s*=\s*\{\s*Text\(\s*"((?:[^"\\]|\\.)*)"/g, what: "placeholder" },
  { re: /\blabel\s*=\s*\{\s*Text\(\s*"((?:[^"\\]|\\.)*)"/g, what: "label" },
  { re: /\bcontentDescription\s*=\s*"((?:[^"\\]|\\.)*)"/g, what: "contentDescription" },
  { re: /\.navigationTitle\(\s*"((?:[^"\\]|\\.)*)"/g, what: "navigationTitle" },
  { re: /\bTextField\(\s*"((?:[^"\\]|\\.)*)"/g, what: "TextField placeholder" },
  { re: /\bButton\(\s*"((?:[^"\\]|\\.)*)"/g, what: "Button title" },
  { re: /\.accessibilityLabel\(\s*"((?:[^"\\]|\\.)*)"/g, what: "accessibilityLabel" },
  { re: /\bLabel\(\s*"((?:[^"\\]|\\.)*)"\s*,/g, what: "Label" },
  { re: /\bToggle\(\s*"((?:[^"\\]|\\.)*)"/g, what: "Toggle title" },
  { re: /\bSection\(\s*header:\s*Text\(\s*"((?:[^"\\]|\\.)*)"/g, what: "Section header" },
];
/**
 * A literal is PROSE if, once every interpolation is removed, two ASCII letters
 * remain in a row.
 *
 * Stripping interpolation FIRST is what makes this usable. A string like
 * "NAME · BALANCE" spelled with two interpolations is a composition of values
 * that are already localised, and flagging it would teach people to ignore the
 * guard. "Owes you AMOUNT" still has "Owes" in it and is caught. That one rule
 * removes almost every false positive without a single per-file exception.
 */
function isProse(raw) {
  const stripped = raw
    .replace(/\$\{[^}]*\}/g, "")
    .replace(/\\\([^)]*\)/g, "")
    .replace(/\$\w+/g, "")
    .replace(/%[\d.\-+]*[a-zA-Z@]/g, "");
  if (!/[A-Za-z]{2}/.test(stripped)) return false;
  // A lone identifier-shaped token is a key or a symbol name, not a sentence.
  if (/^[a-z][a-zA-Z0-9_]*$/.test(stripped.trim())) return false;
  return true;
}

/**
 * Files that legitimately hold English literals.
 *
 * The generated catalogue is the SOURCE of the strings, not a consumer.
 * Previews are developer scaffolding. Vector adapters are test fixtures whose
 * literals are function names and JSON keys.
 */
const SKIP_PATH = [
  "/Generated/", "/i18n/S.kt", "/build/", "/.build/",
  "Vectors.kt", "Vectors.swift", "VectorRunner",
  "SupportedLanguages",
];

function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const entry of readdirSync(dir)) {
    if (entry === "build" || entry === ".build" || entry === ".gradle") continue;
    const full = path.join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else if (entry.endsWith(".kt") || entry.endsWith(".swift")) out.push(full);
  }
  return out;
}

const files = [
  ...walk(path.join(REPO_ROOT, "apps/android/app/src/main/java")),
  ...walk(path.join(REPO_ROOT, "apps/ios/App")),
].filter((f) => !SKIP_PATH.some((s) => f.includes(s)));

const hits = [];
for (const file of files) {
  const src = readFileSync(file, "utf8");
  const rel = path.relative(REPO_ROOT, file);
  // Blank out block comments so prose ABOUT a string is not mistaken for one,
  // keeping newlines so line numbers stay honest.
  const body = src.replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, " "));
  const lines = body.split("\n");

  for (const { re, what } of SITES) {
    for (const m of body.matchAll(re)) {
      const text = m[1];
      if (!isProse(text)) continue;
      const lineNo = body.slice(0, m.index).split("\n").length;
      if (lines[lineNo - 1].trim().startsWith("//")) continue;
      hits.push({ file: rel, line: lineNo, what, text: text.slice(0, 90) });
    }
  }
}

// A site's identity is file + text, NOT the line number: moving code must not
// look like a new offence, and the same literal twice in one file is one thing
// to fix.
const key = (h) => `${h.file} :: ${h.text}`;
const found = new Set(hits.map(key));

if (BLESS) {
  const sites = [...found].sort();
  writeFileSync(
    BASELINE,
    JSON.stringify(
      {
        note: "Hardcoded user-facing strings that existed when the guard was written. Only ever REMOVE entries -- adding one means the debt grew.",
        sites,
      },
      null,
      2,
    ) + "\n",
  );
  console.log(`hardcoded-strings: baseline written with ${sites.length} site(s).`);
  process.exit(0);
}

const baseline = existsSync(BASELINE)
  ? new Set(JSON.parse(readFileSync(BASELINE, "utf8")).sites)
  : new Set();

const added = hits.filter((h) => !baseline.has(key(h)));
const fixed = [...baseline].filter((k) => !found.has(k));

if (LIST) {
  for (const h of hits.sort((a, b) => a.file.localeCompare(b.file) || a.line - b.line)) {
    const mark = baseline.has(key(h)) ? "" : "   <-- NEW";
    console.log(`${h.file}:${h.line}  ${h.what}  "${h.text}"${mark}`);
  }
}

console.log(
  `hardcoded-strings: ${files.length} files, ${found.size} site(s) — ` +
  `${baseline.size} baselined, ${added.length} new, ${fixed.length} since fixed.`,
);

if (fixed.length && !added.length) {
  console.log(`    ${fixed.length} baselined site(s) are gone. Run with --bless to bank the progress.`);
}

if (added.length) {
  console.error("");
  for (const h of added) {
    console.error(
      `${h.file}:${h.line}  ${h.what} has hardcoded text\n` +
      `    "${h.text}"\n` +
      `    → add a key under packages/core/i18n and use S.<Ns>.<key>`,
    );
  }
  console.error(
    `\n::error::${added.length} new hardcoded user-facing string(s). ` +
    `This app ships en/hi/nl; a literal renders English to everyone.`,
  );
  process.exit(1);
}
