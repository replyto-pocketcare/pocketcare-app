#!/usr/bin/env node
/**
 * tools/parity/i18n-match.mjs
 *
 * For one native source file, report which of its hardcoded English literals
 * already have a translation key — and which do not.
 *
 * Wiring i18n is ~1,370 literals across 125 files. Hand-matching each one
 * against 1,344 keys is exactly the kind of work that goes wrong quietly: it is
 * easy to pick a key whose English happens to match but whose *meaning* is a
 * different screen's, and nothing downstream would catch it. This does the
 * lookup mechanically and shows the namespace, so the judgement left to a human
 * is only "is this the right namespace", which is the part that actually needs
 * judgement.
 *
 * It suggests; it does not edit. A near match is reported as a near match,
 * because "Hide Amounts" vs "Hide amounts everywhere" is a real copy difference
 * — usually one where the native port drifted from web and adopting the key is
 * the fix, but that is a call to make deliberately rather than by regex.
 *
 * Usage:
 *   node tools/parity/i18n-match.mjs apps/android/.../SettingsScreen.kt
 *   node tools/parity/i18n-match.mjs --summary apps/ios/App           # whole tree
 */

import { readFileSync, writeFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = process.env.SANVYA_REPO_ROOT
  ? path.resolve(process.env.SANVYA_REPO_ROOT)
  : path.resolve(__dirname, "../..");
const LOCALES = path.join(REPO_ROOT, "packages/core/i18n/src/locales");

/** namespace -> { flatKey: english } */
function loadEnglish() {
  const out = {};
  for (const ns of readdirSync(LOCALES)) {
    const f = path.join(LOCALES, ns, "en.json");
    let json;
    try { json = JSON.parse(readFileSync(f, "utf8")); } catch { continue; }
    const flat = {};
    (function walk(o, p = "") {
      for (const [k, v] of Object.entries(o ?? {})) {
        if (v && typeof v === "object") walk(v, `${p}${k}.`);
        else flat[`${p}${k}`] = String(v);
      }
    })(json);
    out[ns] = flat;
  }
  return out;
}

/** `settings` + `hideAmounts` -> `S.Settings.hideAmounts` */
const pascal = (s) => s.split(/[-_]/).map((w) => w[0].toUpperCase() + w.slice(1)).join("");
/**
 * Must match `generate-i18n.mjs`'s own naming exactly, underscores included:
 * `kind.service_charge` is emitted as `kindServiceCharge`, and getting that
 * wrong produces an accessor that looks plausible and does not exist.
 */
const camel = (s) =>
  s.replace(/[._]+(.)/g, (_, c) => c.toUpperCase()).replace(/[._]/g, "");
const accessorFor = (ns, key) => `S.${pascal(ns)}.${camel(key)}`;

/** Loose enough that copy drift still matches, tight enough to stay meaningful. */
const norm = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

function literalsIn(src) {
  const stripped = src
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*(\/\/|\*|\/\*\*).*$/gm, "");
  const out = new Set();

  // Scan quote-to-quote in order rather than with a global regex. A global
  // match can start at a CLOSING quote and capture the code between two
  // strings: `Option(value: "female", label: "Female")` yields `, label: `,
  // which normalises to "label", exact-matches a real key, and gets
  // substituted into the middle of the source. That is not hypothetical — it
  // corrupted five files before this loop replaced it.
  const raw = [];
  for (let i = 0; i < stripped.length; i++) {
    if (stripped[i] !== '"') continue;
    let j = i + 1;
    while (j < stripped.length && stripped[j] !== '"' && stripped[j] !== "\n") {
      if (stripped[j] === "\\") j++;
      j++;
    }
    if (stripped[j] === '"') { raw.push(stripped.slice(i + 1, j)); i = j; }
    else i = j;
  }

  for (const v of raw) {
    if (v.length < 3) continue;
    // Skip things that are plainly not user-facing copy.
    if (/^[a-z_]+$/.test(v)) continue;                 // identifiers, routes, keys
    if (/^\$|\$\{/.test(v)) continue;                  // pure interpolation
    if (!/[A-Za-z]/.test(v)) continue;
    if (/^(https?:|mailto:|#|com\.|android\.)/.test(v)) continue;
    if (!/[A-Z]/.test(v) && v.split(" ").length < 2) continue;
    // Copy does not start with punctuation or contain a `key: value` colon —
    // those are code fragments that slipped through as strings.
    if (/^[^A-Za-z]/.test(v) || /\w:\s/.test(v)) continue;
    out.add(v);
  }
  return [...out];
}

/**
 * Which namespace a match should come from, best first.
 *
 * This is the whole reason `--apply` is safe. "Cancel", "Save" and "Delete"
 * exist in a dozen namespaces with identical English; picking whichever the
 * object happened to iterate first would scatter a screen's strings across
 * unrelated namespaces and quietly bind Settings' Cancel to the Loans one.
 * Rank by the screen the file belongs to, then the shared `translation`
 * namespace where common words actually live, and only then anything else.
 */
function namespaceRank(file) {
  const base = path.basename(file).replace(/\.(kt|swift)$/, "").toLowerCase();
  // Strip both the suffix AND the verb prefix: `AddLoanScreen` is a Loans
  // screen. Without the prefix strip it matched no namespace and fell through
  // to whatever iterated first — which bound its "Interest % p.a." to the
  // INVESTMENTS namespace, English identical, meaning wrong.
  const stem = base
    .replace(/(screen|view|viewmodel|components?|sheet|dialog)$/g, "")
    .replace(/^(add|edit|create|new|allocate|pay)/, "");
  return (ns) => {
    const n = ns.replace(/s$/, "");
    const t = stem.replace(/s$/, "");
    if (n === t) return 0;
    if (stem.includes(n) || base.includes(n)) return 1;
    if (ns === "translation") return 2;
    return 3;
  };
}

function report(file, english) {
  const src = readFileSync(path.resolve(REPO_ROOT, file), "utf8");
  const lits = literalsIn(src);
  const exact = [], near = [], none = [];
  const rank = namespaceRank(file);

  for (const lit of lits) {
    const n = norm(lit);
    let hitExact = null, hitNear = null;
    for (const [ns, keys] of Object.entries(english)) {
      for (const [k, v] of Object.entries(keys)) {
        const vn = norm(v);
        if (vn === n) {
          if (!hitExact || rank(ns) < rank(hitExact.ns)) hitExact = { ns, k, v };
        } else if ((vn.startsWith(n) || n.startsWith(vn)) && Math.min(vn.length, n.length) >= 6) {
          if (!hitNear || rank(ns) < rank(hitNear.ns)) hitNear = { ns, k, v };
        }
      }
    }
    // A key that interpolates cannot be swapped in blind — the literal has no
    // arguments to hand it. Report it, never auto-apply it.
    if (hitExact && /\{\{/.test(hitExact.v)) { none.push(lit); continue; }
    if (hitExact) exact.push([lit, hitExact]);
    else if (hitNear) near.push([lit, hitNear]);
    else none.push(lit);
  }
  return { file, lits, exact, near, none };
}

/**
 * Byte ranges of every `@Composable`-annotated function body in a Kotlin file.
 *
 * Finding the body brace is fiddlier than it looks. The first `{` after the
 * annotation is usually NOT the body — `onDismiss: () -> Unit = {}` in the
 * parameter list gets there first, and brace-matching from it yields a
 * two-character range that puts the whole real body "outside". So: walk to the
 * parameter list, match parentheses to its close, then take the first `{` after
 * that.
 *
 * An expression-bodied composable (`@Composable fun x() = when (…) {`) has no
 * body brace at paren-depth 0 before the `=`; those are matched from the `=`
 * instead, which is imprecise but errs toward including, and a false positive
 * here is caught by the compiler rather than shipped.
 */
/** Byte ranges of every `//` line comment and every block comment. */
function commentRanges(src) {
  const out = [];
  for (const m of src.matchAll(/\/\*[\s\S]*?\*\//g)) out.push([m.index, m.index + m[0].length]);
  for (const m of src.matchAll(/\/\/[^\n]*/g)) out.push([m.index, m.index + m[0].length]);
  return out;
}

function composableRanges(src) {
  const ranges = [];
  for (const m of src.matchAll(/@Composable\b/g)) {
    const funAt = src.indexOf("fun", m.index);
    if (funAt === -1) continue;
    // Bail if another declaration intervenes — the annotation was not this fun's.
    if (/\b(class|object|interface|val|var)\b/.test(src.slice(m.index, funAt))) continue;

    let i = src.indexOf("(", funAt);
    if (i === -1) continue;
    let depth = 0;
    for (; i < src.length; i++) {
      if (src[i] === "(") depth++;
      else if (src[i] === ")" && --depth === 0) { i++; break; }
    }
    // Past the parameter list: either a body `{` or an `=` expression body.
    const brace = src.indexOf("{", i);
    const eq = src.indexOf("=", i);
    const nl = src.indexOf("\n", i);
    let open;
    if (eq !== -1 && eq < brace && eq < nl + 200) open = src.indexOf("{", eq);
    else open = brace;
    if (open === -1) continue;

    depth = 0;
    let j = open;
    for (; j < src.length; j++) {
      if (src[j] === "{") depth++;
      else if (src[j] === "}" && --depth === 0) break;
    }
    ranges.push([open, j]);
  }
  return ranges;
}

function walkFiles(dir) {
  const out = [];
  for (const e of readdirSync(dir)) {
    const p = path.join(dir, e);
    if (statSync(p).isDirectory()) out.push(...walkFiles(p));
    else if (/\.(kt|swift)$/.test(e) && !/Generated|\/S\.swift$|\/S\.kt$/.test(p)) out.push(p);
  }
  return out;
}

/**
 * Rewrite the exact matches in place.
 *
 * The two platforms differ here, deliberately.
 *
 * **Swift: everything**, view models included. `S.Budgets.allSpending` is a
 * plain static — no context to thread — so localising a view model's strings
 * costs nothing and is strictly better than the hardcoded English that was
 * there.
 *
 * **Kotlin: composables only.** `sRes()` needs a composition, so a view model
 * would have to be handed a `Resources`, and that is a bolt-on worth refusing.
 * A view model that builds "You owe ₹200" is producing a sentence, which is a
 * rendering concern; injecting a string catalogue would localise the text and
 * cement the layering mistake in the same move. Those strings are tracked in
 * PARITY_AUDIT §6a as part of item 7 (DI / layering), not item 4.
 *
 * So iOS view models get translated now and Android's wait for the layering
 * fix. That is an honest asymmetry rather than an oversight, and it is recorded
 * because the file counts will look uneven until item 7 lands.
 */
function apply(file, english) {
  const abs = path.resolve(REPO_ROOT, file);
  const isSwift = file.endsWith(".swift");
  const base = path.basename(file);
  if (!isSwift && !/(Screen|Components|Dialog|Sheet)\.kt$/.test(base)) {
    return { file, skipped: "not a composable file (view models are excluded on purpose)" };
  }
  const r = report(file, english);
  if (!r.exact.length) return { file, applied: 0 };

  let src = readFileSync(abs, "utf8");
  let applied = 0;

  // `sRes()` needs a composition, so on Kotlin a literal may only be rewritten
  // if it sits inside a `@Composable` body. Three CI rounds were spent learning
  // that a "Screen.kt" file is not all composable: `periodChipLabel` is a plain
  // helper, `TYPE_LABEL` is a top-level `val` map, and a resource cannot be
  // resolved from either. Swift has no such constraint — its accessors are
  // plain statics.
  const allowed = isSwift ? null : composableRanges(src);
  // Comments are excluded from substitution on BOTH platforms. `literalsIn`
  // strips them before *finding* literals, but `apply` rewrites the raw source
  // — so a quoted phrase in a doc comment got replaced with an accessor call.
  // Harmless to the compiler and destructive to the provenance notes that make
  // this port reviewable; it corrupted nine comments before this existed.
  const comments = commentRanges(src);
  const inComment = (i) => comments.some(([a, b]) => i >= a && i < b);
  const inAllowed = (i) =>
    !inComment(i) && (allowed === null || allowed.some(([a, b]) => i >= a && i < b));

  for (const [lit, h] of r.exact) {
    const call = isSwift ? accessorFor(h.ns, h.k) : `${accessorFor(h.ns, h.k)}(sRes())`;
    // Whole-literal only: never touch a fragment of a larger string.
    const needle = `"${lit}"`;
    let out = "", cursor = 0, hit = false;
    for (let i = src.indexOf(needle); i !== -1; i = src.indexOf(needle, cursor)) {
      out += src.slice(cursor, i);
      if (inAllowed(i)) { out += call; hit = true; } else { out += needle; }
      cursor = i + needle.length;
    }
    out += src.slice(cursor);
    if (hit) { src = out; applied++; }
  }
  if (applied) {
    const imports = isSwift ? [] : ["com.sanvya.app.i18n.S", "com.sanvya.app.i18n.sRes"];
    for (const imp of imports) {
      if (!src.includes(`import ${imp}\n`)) {
        const lines = src.split("\n");
        const last = lines.reduce((acc, l, i) => (l.startsWith("import ") ? i : acc), -1);
        if (last >= 0) { lines.splice(last + 1, 0, `import ${imp}`); src = lines.join("\n"); }
      }
    }
    writeFileSync(abs, src);
  }
  return { file, applied };
}

const args = process.argv.slice(2);
const summary = args.includes("--summary");
const doApply = args.includes("--apply");
const target = args.filter((a) => !a.startsWith("--"))[0];
if (!target) {
  console.error("usage: i18n-match.mjs [--summary] <file-or-dir>");
  process.exit(2);
}
const english = loadEnglish();
const abs = path.resolve(REPO_ROOT, target);
const files = statSync(abs).isDirectory() ? walkFiles(abs) : [abs];

if (doApply) {
  let total = 0, touched = 0;
  for (const f of files) {
    const rel = path.relative(REPO_ROOT, f);
    const res = apply(rel, english);
    if (res.applied) { total += res.applied; touched++; console.log(`  ${String(res.applied).padStart(3)}  ${path.basename(rel)}`); }
  }
  console.log(`\n${total} literals wired across ${touched} files.`);
} else if (summary) {
  const rows = files
    .map((f) => report(path.relative(REPO_ROOT, f), english))
    .filter((r) => r.lits.length)
    .sort((a, b) => b.lits.length - a.lits.length);
  let tl = 0, te = 0, tn = 0, tz = 0;
  for (const r of rows) { tl += r.lits.length; te += r.exact.length; tn += r.near.length; tz += r.none.length; }
  console.log(`${rows.length} files · ${tl} literals · ${te} exact · ${tn} near · ${tz} no key\n`);
  for (const r of rows.slice(0, 25)) {
    console.log(
      `${String(r.lits.length).padStart(4)}  ${String(r.exact.length).padStart(3)}✓ ` +
      `${String(r.near.length).padStart(3)}~ ${String(r.none.length).padStart(3)}✗  ` +
      path.basename(r.file),
    );
  }
} else {
  const r = report(path.relative(REPO_ROOT, files[0]), english);
  console.log(`${r.file}\n${r.lits.length} literals: ${r.exact.length} exact, ${r.near.length} near, ${r.none.length} no key\n`);
  if (r.exact.length) {
    console.log("EXACT — safe to wire:");
    for (const [lit, h] of r.exact) console.log(`  ${JSON.stringify(lit)}\n      -> ${accessorFor(h.ns, h.k)}`);
  }
  if (r.near.length) {
    console.log("\nNEAR — copy differs; adopting the key aligns native with web:");
    for (const [lit, h] of r.near) console.log(`  ${JSON.stringify(lit)}\n      -> ${accessorFor(h.ns, h.k)}  = ${JSON.stringify(h.v)}`);
  }
  if (r.none.length) {
    console.log("\nNO KEY — needs adding to packages/core/i18n first:");
    for (const lit of r.none) console.log(`  ${JSON.stringify(lit)}`);
  }
}
