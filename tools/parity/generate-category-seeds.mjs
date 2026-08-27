#!/usr/bin/env node
/**
 * tools/parity/generate-category-seeds.mjs
 *
 * The auto-categoriser's cold-start keyword table, generated from the single
 * place it is written: `SEED_RULES` in apps/web/src/categorize/seeds.ts.
 *
 * It is ~150 keyword → category-name pairs and it is DATA, not logic. Hand-
 * copying it into two native files would guarantee exactly the drift this job
 * exists to prevent: nobody re-reads a keyword list to check "zepto" is still
 * Groceries on all three clients, and a missing entry does not fail anything —
 * it quietly drops a merchant into "Uncategorised" on one platform.
 *
 * Also emits the STOP_WORDS and NOISE_TOKENS sets from `normalize.ts`, for the
 * same reason and with more force: those two decide which tokens survive at
 * all, so one platform missing a bank code silently changes what every
 * statement row categorises as.
 *
 * Emits:
 *   apps/android/domain/src/main/kotlin/com/sanvya/app/domain/categorize/CategorySeeds.kt
 *   apps/ios/Domain/Sources/Domain/CategorySeeds.swift
 *
 * Usage: node tools/parity/generate-category-seeds.mjs
 */

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = process.env.SANVYA_REPO_ROOT
  ? path.resolve(process.env.SANVYA_REPO_ROOT)
  : path.resolve(__dirname, "../..");

const SEEDS_SRC = path.join(REPO_ROOT, "apps/web/src/categorize/seeds.ts");
const NORMALIZE_SRC = path.join(REPO_ROOT, "apps/web/src/categorize/normalize.ts");
const ANDROID_OUT = path.join(
  REPO_ROOT,
  "apps/android/domain/src/main/kotlin/com/sanvya/app/domain/categorize/CategorySeeds.kt",
);
const IOS_OUT = path.join(REPO_ROOT, "apps/ios/Domain/Sources/Domain/CategorySeeds.swift");

/** Balanced-delimiter slice starting at the first `open` after `from`. */
function block(src, from, open, close, what) {
  const start = src.indexOf(open, from);
  if (start === -1) {
    console.error(`generate-category-seeds: could not find ${what}. Fix this script rather than committing stale content.`);
    process.exit(1);
  }
  let depth = 0;
  let inString = null;
  for (let i = start; i < src.length; i++) {
    const ch = src[i];
    if (inString) {
      if (ch === "\\") { i++; continue; }
      if (ch === inString) inString = null;
      continue;
    }
    if (ch === '"' || ch === "'" || ch === "`") { inString = ch; continue; }
    if (ch === open) depth++;
    else if (ch === close) {
      depth--;
      if (depth === 0) return src.slice(start, i + 1);
    }
  }
  console.error(`generate-category-seeds: ${what} is unterminated. Fix this script.`);
  process.exit(1);
}

const seedsSrc = readFileSync(SEEDS_SRC, "utf8");
const seedsMarker = seedsSrc.indexOf("export const SEED_RULES");
if (seedsMarker === -1) {
  console.error("generate-category-seeds: no `export const SEED_RULES` in seeds.ts — the source shape changed.");
  process.exit(1);
}
// The `{` after the `=`, not after the marker: the type annotation
// `Record<string, string>` has no brace, but a future one might.
// eslint-disable-next-line no-new-func
const SEED_RULES = new Function(
  `return ${block(seedsSrc, seedsSrc.indexOf("=", seedsMarker), "{", "}", "SEED_RULES")};`,
)();

const normalizeSrc = readFileSync(NORMALIZE_SRC, "utf8");
const readSet = (name) => {
  const marker = normalizeSrc.indexOf(`const ${name} = new Set(`);
  if (marker === -1) {
    console.error(`generate-category-seeds: no \`const ${name} = new Set(\` in normalize.ts.`);
    process.exit(1);
  }
  // eslint-disable-next-line no-new-func
  return new Function(`return ${block(normalizeSrc, marker, "[", "]", name)};`)();
};
const STOP_WORDS = readSet("STOP_WORDS");
const NOISE_TOKENS = readSet("NOISE_TOKENS");

const entries = Object.entries(SEED_RULES);
if (entries.length === 0 || STOP_WORDS.length === 0 || NOISE_TOKENS.length === 0) {
  console.error("generate-category-seeds: parsed an empty table. Fix this script rather than committing one.");
  process.exit(1);
}

// A keyword mapped to two different categories would be a silent coin flip
// (JS object literals keep the LAST duplicate, so web would already have
// quietly dropped one). Fail here where it is visible.
const seen = new Map();
for (const [k, v] of entries) {
  if (seen.has(k) && seen.get(k) !== v) {
    console.error(`generate-category-seeds: "${k}" maps to both "${seen.get(k)}" and "${v}".`);
    process.exit(1);
  }
  seen.set(k, v);
}

const categories = [...new Set(entries.map(([, v]) => v))].sort();
console.log(
  `category-seeds: ${entries.length} keywords over ${categories.length} categories, ` +
  `${STOP_WORDS.length} stop words, ${NOISE_TOKENS.length} noise tokens`,
);

const q = (s) => `"${String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;

const BANNER = [
  "// GENERATED FILE - do not hand-edit.",
  "// Source: apps/web/src/categorize/seeds.ts (SEED_RULES)",
  "//         apps/web/src/categorize/normalize.ts (STOP_WORDS, NOISE_TOKENS)",
  "// Regenerate with: node tools/parity/generate-category-seeds.mjs",
].join("\n");

const DOC = [
  "The auto-categoriser's cold-start tables, exactly as web writes them.",
  "",
  "SEED_RULES maps a keyword to a category NAME, not an id -- the ids are the",
  "user's own and are resolved at runtime by buildSeedMap(). NOISE_TOKENS and",
  "STOP_WORDS decide which tokens survive normalisation at all, which is why",
  "they are generated too: one platform missing a bank code silently changes",
  "what every statement row categorises as.",
];

const kt = `package com.sanvya.app.domain.categorize

${BANNER}

/**
 * ${DOC.join("\n * ")}
 */
object CategorySeeds {
    /** keyword -> category NAME. Insertion order is web's, and buildSeedList depends on it for tie-breaks. */
    val SEED_RULES: Map<String, String> = linkedMapOf(
${entries.map(([k, v]) => `        ${q(k)} to ${q(v)},`).join("\n")}
    )

    val STOP_WORDS: Set<String> = setOf(
${STOP_WORDS.map((w) => `        ${q(w)},`).join("\n")}
    )

    val NOISE_TOKENS: Set<String> = setOf(
${NOISE_TOKENS.map((w) => `        ${q(w)},`).join("\n")}
    )
}
`;

const swift = `import Foundation

${BANNER}

/// ${DOC.join("\n/// ")}
public enum CategorySeeds {
    /// keyword -> category NAME, in web's own order. Kept as an ARRAY of pairs,
    /// not a Dictionary: Swift dictionaries have no defined iteration order at
    /// all, and buildSeedList's tie-break depends on this one.
    public static let seedRules: [(keyword: String, category: String)] = [
${entries.map(([k, v]) => `        (${q(k)}, ${q(v)}),`).join("\n")}
    ]

    public static let stopWords: Set<String> = [
${STOP_WORDS.map((w) => `        ${q(w)},`).join("\n")}
    ]

    public static let noiseTokens: Set<String> = [
${NOISE_TOKENS.map((w) => `        ${q(w)},`).join("\n")}
    ]
}
`;

mkdirSync(path.dirname(ANDROID_OUT), { recursive: true });
mkdirSync(path.dirname(IOS_OUT), { recursive: true });
writeFileSync(ANDROID_OUT, kt);
writeFileSync(IOS_OUT, swift);
console.log(` - ${path.relative(REPO_ROOT, ANDROID_OUT)}`);
console.log(` - ${path.relative(REPO_ROOT, IOS_OUT)}`);
