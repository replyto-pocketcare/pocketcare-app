#!/usr/bin/env node
/**
 * Guard: every S.* call site matches the generated accessor's signature.
 *
 * WHY THIS EXISTS. CI is the compiler of record for this port -- there is no
 * Gradle or Xcode locally -- so a mistake this mechanical costs a full
 * round trip to discover. It has now cost three:
 *
 *   - `%@` given an Int, because the generator typed non-plural args CVarArg
 *     (15 sites, silent at runtime rather than at compile time);
 *   - seven `missing argument label` errors in one new file;
 *   - and the same shape is one typo away on Kotlin, where the arguments are
 *     positional and `res` is easy to forget.
 *
 * It is a text check, not a parse. It reads the two GENERATED files as the
 * source of truth for arity and labels, then checks every call site against
 * them. Anything it cannot parse confidently it skips and counts, so the
 * report says how much it actually looked at.
 *
 * Swift: labels must match exactly, in order. Kotlin: argument COUNT must
 * match (the language has no labels to check, and a wrong count is the whole
 * failure mode there).
 */

import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const IOS_S = "apps/ios/App/Generated/S.swift";
const ANDROID_S = "apps/android/app/src/main/java/com/sanvya/app/i18n/S.kt";
const IOS_ROOT = "apps/ios/App";
const ANDROID_ROOT = "apps/android/app/src/main/java";

function walk(dir, ext, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, ext, out);
    else if (name.endsWith(ext)) out.push(p);
  }
  return out;
}

/**
 * Split a call's argument list on top-level commas.
 *
 * Nested calls, string literals and interpolations all contain commas that are
 * not argument separators; counting them naively is the bug this guard exists
 * to catch, so it must not commit it itself. Returns null when the parens do
 * not close inside `src` -- the caller then skips rather than guesses.
 */
function argsOf(src, openParenIndex) {
  let depth = 0;
  let inString = false;
  let escaped = false;
  const parts = [];
  let current = "";
  for (let i = openParenIndex; i < src.length; i++) {
    const c = src[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (c === "\\") escaped = true;
      else if (c === '"') inString = false;
      current += c;
      continue;
    }
    if (c === '"') { inString = true; current += c; continue; }
    if (c === "(" || c === "[" || c === "{") {
      depth++;
      if (depth === 1) continue; // the opening paren itself
      current += c;
      continue;
    }
    if (c === ")" || c === "]" || c === "}") {
      depth--;
      if (depth === 0) {
        if (current.trim()) parts.push(current.trim());
        return parts;
      }
      current += c;
      continue;
    }
    if (c === "," && depth === 1) { parts.push(current.trim()); current = ""; continue; }
    current += c;
  }
  return null; // unbalanced within the slice we were given
}

// ---- signatures, read off the generated files ----

/** "Namespace.member" -> array of labels ([] for a zero-arg `var`). */
function swiftSignatures() {
  const src = readFileSync(IOS_S, "utf8");
  const sigs = new Map();
  let ns = null;
  for (const line of src.split("\n")) {
    const nsMatch = line.match(/^\s*public enum (\w+)\s*\{/);
    if (nsMatch) { ns = nsMatch[1]; continue; }
    if (!ns) continue;
    const varMatch = line.match(/^\s*public static var (\w+):/);
    if (varMatch) { sigs.set(`${ns}.${varMatch[1]}`, []); continue; }
    const funcMatch = line.match(/^\s*public static func (\w+)\(([^)]*)\)/);
    if (funcMatch) {
      const labels = funcMatch[2]
        .split(",")
        .map((p) => p.trim())
        .filter(Boolean)
        .map((p) => p.split(":")[0].trim().split(/\s+/)[0]);
      sigs.set(`${ns}.${funcMatch[1]}`, labels);
    }
  }
  return sigs;
}

/** "Namespace.member" -> argument COUNT (`res` included). */
function kotlinSignatures() {
  const src = readFileSync(ANDROID_S, "utf8");
  const sigs = new Map();
  let ns = null;
  for (const line of src.split("\n")) {
    const nsMatch = line.match(/^\s*object (\w+)\s*\{/);
    if (nsMatch) { ns = nsMatch[1]; continue; }
    if (!ns) continue;
    const funcMatch = line.match(/^\s*fun (\w+)\(([^)]*)\)/);
    if (funcMatch) {
      const count = funcMatch[2].split(",").map((p) => p.trim()).filter(Boolean).length;
      sigs.set(`${ns}.${funcMatch[1]}`, count);
    }
  }
  return sigs;
}

// ---- call sites ----

const hits = [];
let checked = 0;
let skipped = 0;

function scanSwift(sigs) {
  const files = walk(IOS_ROOT, ".swift").filter((f) => !f.endsWith("Generated/S.swift"));
  for (const file of files) {
    const src = readFileSync(file, "utf8");
    const re = /\bS\.(\w+)\.(\w+)\(/g;
    let m;
    while ((m = re.exec(src)) !== null) {
      const key = `${m[1]}.${m[2]}`;
      const expected = sigs.get(key);
      if (expected === undefined) continue; // not an S accessor we generated
      const open = re.lastIndex - 1;
      const args = argsOf(src, open);
      if (args === null) { skipped++; continue; }
      checked++;
      const actual = args.map((a) => {
        const label = a.match(/^(\w+)\s*:/);
        return label ? label[1] : "_";
      });
      if (actual.join(",") !== expected.join(",")) {
        const line = src.slice(0, open).split("\n").length;
        hits.push(
          `${file}:${line} S.${key} takes (${expected.join(", ") || "no args"}) ` +
            `but is called with (${actual.join(", ") || "no args"})`,
        );
      }
    }
  }
  return files.length;
}

function scanKotlin(sigs) {
  const files = walk(ANDROID_ROOT, ".kt").filter((f) => !f.endsWith("i18n/S.kt"));
  for (const file of files) {
    const src = readFileSync(file, "utf8");
    const re = /\bS\.(\w+)\.(\w+)\(/g;
    let m;
    while ((m = re.exec(src)) !== null) {
      const key = `${m[1]}.${m[2]}`;
      const expected = sigs.get(key);
      if (expected === undefined) continue;
      const open = re.lastIndex - 1;
      const args = argsOf(src, open);
      if (args === null) { skipped++; continue; }
      checked++;
      if (args.length !== expected) {
        const line = src.slice(0, open).split("\n").length;
        hits.push(
          `${file}:${line} S.${key} takes ${expected} argument(s) but is called with ${args.length}`,
        );
      }
    }
  }
  return files.length;
}

const swiftSigs = swiftSignatures();
const kotlinSigs = kotlinSignatures();
const swiftFiles = scanSwift(swiftSigs);
const kotlinFiles = scanKotlin(kotlinSigs);

console.log(
  `i18n-args: ${swiftFiles} swift + ${kotlinFiles} kotlin files, ` +
    `${swiftSigs.size} swift + ${kotlinSigs.size} kotlin accessors, ` +
    `${checked} call site(s) checked, ${skipped} skipped, ${hits.length} hit(s)`,
);
for (const h of hits) console.log(`  ${h}`);
process.exit(hits.length === 0 ? 0 : 1);
