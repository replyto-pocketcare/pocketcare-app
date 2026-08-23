#!/usr/bin/env node
/**
 * tools/parity/generate-i18n.mjs
 *
 * Native string catalogs, generated from the one place translations live:
 * packages/core/i18n/src/locales/<namespace>/{en,hi,nl}.json.
 *
 * Why generate rather than hand-maintain: web already has 28 namespaces and
 * ~1,350 keys in three languages, and both native apps had literally none —
 * every string hardcoded English. Hand-copying them would guarantee drift the
 * first time a copy change lands on web, which is the failure this whole
 * parity effort exists to stop.
 *
 * Emits:
 *   apps/android/app/src/main/res/values/strings.xml
 *   apps/android/app/src/main/res/values-hi/strings.xml
 *   apps/android/app/src/main/res/values-nl/strings.xml
 *   apps/android/app/src/main/java/com/sanvya/app/i18n/S.kt      (typed accessors)
 *   apps/ios/App/Resources/Localizable.xcstrings
 *   apps/ios/App/Generated/S.swift                                (typed accessors)
 *
 * The typed accessor layer is the point of difference from a plain resource
 * dump: `S.transactions.item(n = 2)` will not compile if the key is renamed or
 * an argument is dropped, which a raw `getString(R.string.…)` call site would
 * happily do at runtime. Argument NAMES survive too, so a call site reads the
 * same as web's `t("item", { n })`.
 *
 * Usage: node tools/parity/generate-i18n.mjs [--check]
 */

import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = process.env.SANVYA_REPO_ROOT
  ? path.resolve(process.env.SANVYA_REPO_ROOT)
  : path.resolve(__dirname, "../..");

const LOCALES_DIR = path.join(REPO_ROOT, "packages/core/i18n/src/locales");
const ANDROID_RES = path.join(REPO_ROOT, "apps/android/app/src/main/res");
const ANDROID_I18N_DIR = path.join(REPO_ROOT, "apps/android/app/src/main/java/com/sanvya/app/i18n");
const IOS_RESOURCES = path.join(REPO_ROOT, "apps/ios/App/Resources");
const IOS_GENERATED = path.join(REPO_ROOT, "apps/ios/App/Generated");

/** Source language first — it defines the canonical key set and argument order. */
const LOCALES = ["en", "hi", "nl"];
const SOURCE_LOCALE = "en";

/** i18next plural suffixes. Only `one`/`other` are used today; the rest are
 *  accepted so a future Hindi/Dutch plural rule doesn't silently drop. */
const PLURAL_CATEGORIES = ["zero", "one", "two", "few", "many", "other"];

const CHECK_ONLY = process.argv.includes("--check");

// ---------------------------------------------------------------------------
// 1. Read + flatten
// ---------------------------------------------------------------------------

function flatten(obj, prefix = "", out = {}) {
  for (const [k, v] of Object.entries(obj)) {
    const key = prefix ? `${prefix}.${k}` : k;
    if (v && typeof v === "object" && !Array.isArray(v)) flatten(v, key, out);
    else out[key] = String(v);
  }
  return out;
}

const namespaces = readdirSync(LOCALES_DIR)
  .filter((n) => statSync(path.join(LOCALES_DIR, n)).isDirectory())
  .sort();

/** @type {Record<string, Record<string, Record<string,string>>>} ns -> locale -> key -> value */
const data = {};
const problems = [];

for (const ns of namespaces) {
  data[ns] = {};
  for (const loc of LOCALES) {
    const f = path.join(LOCALES_DIR, ns, `${loc}.json`);
    if (!existsSync(f)) {
      problems.push(`${ns}/${loc}.json is missing`);
      data[ns][loc] = {};
      continue;
    }
    data[ns][loc] = flatten(JSON.parse(readFileSync(f, "utf8")));
  }
}

// ---------------------------------------------------------------------------
// 2. Key parity — a repo rule, enforced here rather than hoped for
// ---------------------------------------------------------------------------

for (const ns of namespaces) {
  const srcKeys = Object.keys(data[ns][SOURCE_LOCALE]);
  for (const loc of LOCALES) {
    if (loc === SOURCE_LOCALE) continue;
    const missing = srcKeys.filter((k) => !(k in data[ns][loc]));
    const extra = Object.keys(data[ns][loc]).filter((k) => !(k in data[ns][SOURCE_LOCALE]));
    if (missing.length) problems.push(`${ns}/${loc}: ${missing.length} key(s) missing — ${missing.slice(0, 6).join(", ")}${missing.length > 6 ? " …" : ""}`);
    if (extra.length) problems.push(`${ns}/${loc}: ${extra.length} key(s) not in ${SOURCE_LOCALE} — ${extra.slice(0, 6).join(", ")}${extra.length > 6 ? " …" : ""}`);
  }
}

// ---------------------------------------------------------------------------
// 3. Group plural variants, collect arguments
// ---------------------------------------------------------------------------

/**
 * @typedef {{ ns: string, key: string, args: string[], plural: boolean,
 *             values: Record<string, string|Record<string,string>> }} Entry
 */

const PLACEHOLDER = /\{\{\s*([A-Za-z0-9_]+)\s*\}\}/g;

function argsOf(s) {
  const out = [];
  let m;
  PLACEHOLDER.lastIndex = 0;
  while ((m = PLACEHOLDER.exec(s))) if (!out.includes(m[1])) out.push(m[1]);
  return out;
}

/**
 * The argument list for a key is the UNION across locales, not just English's.
 *
 * This is not defensive coding — it is how the source is actually written.
 * `loans:nthEmi` is `"{{ord}} EMI"` in English but `"ईएमआई {{n}}"` in Hindi,
 * because English wants an ordinal ("3rd") where Hindi and Dutch want the bare
 * number; the call site passes both (`t("nthEmi", { ord: ordinal(m), n: m })`).
 * Deriving arguments from English alone would silently drop `n` and leave a
 * literal `{{n}}` on screen in two of the three shipped languages.
 *
 * Order is English-first-appearance, then any locale-only argument appended in
 * a stable alphabetical order — so every locale agrees on which positional
 * specifier means what, which is the entire point of `%1$s` over `%s`.
 */
function unionArgs(srcValue, otherValues) {
  const args = argsOf(srcValue);
  const extra = new Set();
  for (const v of otherValues) for (const a of argsOf(v)) if (!args.includes(a)) extra.add(a);
  return [...args, ...[...extra].sort()];
}

/** @type {Entry[]} */
const entries = [];

for (const ns of namespaces) {
  const srcKeys = Object.keys(data[ns][SOURCE_LOCALE]);
  /** base key -> { category -> true } */
  const pluralBases = new Map();
  for (const k of srcKeys) {
    const m = k.match(new RegExp(`^(.*)_(${PLURAL_CATEGORIES.join("|")})$`));
    if (!m) continue;
    if (!pluralBases.has(m[1])) pluralBases.set(m[1], new Set());
    pluralBases.get(m[1]).add(m[2]);
  }

  const consumed = new Set();
  for (const [base, cats] of pluralBases) {
    // A plural group needs at least `other`; anything else is a key that merely
    // happens to end in "_one" and is treated as a normal string.
    if (!cats.has("other")) continue;
    /** @type {Record<string, Record<string,string>>} */
    const values = {};
    for (const loc of LOCALES) {
      values[loc] = {};
      for (const c of cats) {
        const v = data[ns][loc][`${base}_${c}`];
        if (v != null) values[loc][c] = v;
      }
    }
    // i18next always passes `count` for a plural; make sure it is an argument
    // even when the source string does not interpolate it (e.g. "one member").
    const args = unionArgs(
      values[SOURCE_LOCALE].other ?? "",
      LOCALES.filter((l) => l !== SOURCE_LOCALE).flatMap((l) => Object.values(values[l] ?? {})),
    );
    if (!args.includes("count")) args.unshift("count");
    entries.push({ ns, key: base, args, plural: true, values });
    for (const c of cats) consumed.add(`${base}_${c}`);
  }

  for (const k of srcKeys) {
    if (consumed.has(k)) continue;
    /** @type {Record<string,string>} */
    const values = {};
    for (const loc of LOCALES) values[loc] = data[ns][loc][k] ?? data[ns][SOURCE_LOCALE][k];
    const args = unionArgs(
      values[SOURCE_LOCALE],
      LOCALES.filter((l) => l !== SOURCE_LOCALE).map((l) => values[l]),
    );
    entries.push({ ns, key: k, args, plural: false, values });
  }
}

entries.sort((a, b) => (a.ns === b.ns ? a.key.localeCompare(b.key) : a.ns.localeCompare(b.ns)));

// Every placeholder in every locale must have landed in the argument list —
// one that did not would be emitted as a literal `{{name}}` on screen, which
// is precisely the class of bug this generator exists to make impossible.
for (const e of entries) {
  for (const loc of LOCALES) {
    const vals = e.plural ? Object.values(e.values[loc] ?? {}) : [e.values[loc]];
    for (const v of vals) {
      if (v == null) continue;
      for (const a of argsOf(v)) {
        if (!e.args.includes(a)) {
          problems.push(`${e.ns}:${e.key} (${loc}) interpolates {{${a}}}, which is not in the derived argument list`);
        }
      }
    }
  }
}

if (problems.length) {
  console.error(`i18n source problems (${problems.length}):\n` + problems.map((p) => "  " + p).join("\n"));
  process.exit(1);
}
console.log(`i18n: ${namespaces.length} namespaces, ${entries.length} entries (${entries.filter((e) => e.plural).length} plural), ${LOCALES.length} locales — key sets aligned.`);
if (CHECK_ONLY) process.exit(0);

// ---------------------------------------------------------------------------
// 4. Android resource ids
// ---------------------------------------------------------------------------

/** `transactions` + `filter.all` -> `transactions_filter_all`; camelCase splits. */
function androidId(ns, key) {
  const raw = `${ns}_${key}`;
  return raw
    .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
    .replace(/[^A-Za-z0-9]+/g, "_")
    .toLowerCase()
    .replace(/_+/g, "_")
    .replace(/^_|_$/g, "");
}

const idMap = new Map();
for (const e of entries) {
  const id = androidId(e.ns, e.key);
  if (idMap.has(id)) {
    console.error(
      `Android resource id collision: \`${id}\` produced by both ${idMap.get(id)} and ${e.ns}:${e.key}. ` +
        `Rename one of the source keys in packages/core/i18n.`,
    );
    process.exit(1);
  }
  idMap.set(id, `${e.ns}:${e.key}`);
  e.androidId = id;
}

// ---------------------------------------------------------------------------
// 5. Placeholder conversion
// ---------------------------------------------------------------------------

/**
 * `{{name}}` -> `%1$s` (Android) / `%1$@` (iOS), numbered by the ORDER THE
 * ARGUMENT LIST DEFINES, not the order it appears in this particular
 * translation — a Hindi sentence may well use them in a different order, and
 * positional specifiers are exactly the mechanism for that.
 *
 * A literal `%` in a string that also carries arguments must be doubled, or
 * Android's formatter reads it as a specifier and throws.
 */
function toPlatformFormat(s, args, kind, isPlural) {
  let out = args.length ? s.replace(/%/g, "%%") : s;
  out = out.replace(PLACEHOLDER, (_, name) => {
    const i = args.indexOf(name);
    if (i < 0) return `%%{{${name}}}`; // unreachable: validated above
    // The integer specifier belongs to PLURALS, not to the name "count".
    //
    // In a plural, `count` is what Android's getQuantityString and iOS's plural
    // variations select the grammatical form from, so it is genuinely an Int and
    // the accessor types it that way. Elsewhere `count` is just an argument name
    // — `accounts:showArchived` is "Show archived ({{count}})", an ordinary
    // string — and emitting %d for it while typing the parameter as Any is a
    // type mismatch. Android lint catches exactly that:
    //   "Wrong argument type for formatting argument '#1' in
    //    accounts_show_archived: conversion is 'd', received Object"
    const isCount = isPlural && name === "count";
    const spec = isCount ? (kind === "ios" ? "lld" : "d") : kind === "ios" ? "@" : "s";
    return `%${i + 1}$${spec}`;
  });
  return out;
}

// ---------------------------------------------------------------------------
// 6. Android strings.xml
// ---------------------------------------------------------------------------

function xmlEscape(s) {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "\\\"")
    .replace(/'/g, "\\'")
    .replace(/\n/g, "\\n");
}

function androidStringsXml(locale) {
  const lines = [
    '<?xml version="1.0" encoding="utf-8"?>',
    "<!--",
    "  GENERATED FILE — do not hand-edit.",
    "  Source: packages/core/i18n/src/locales/<namespace>/" + locale + ".json",
    "  Regenerate with: node tools/parity/generate-i18n.mjs",
    "-->",
    "<resources>",
  ];
  let ns = null;
  for (const e of entries) {
    if (e.ns !== ns) {
      ns = e.ns;
      lines.push("", `    <!-- ${ns} -->`);
    }
    if (e.plural) {
      lines.push(`    <plurals name="${e.androidId}">`);
      for (const c of PLURAL_CATEGORIES) {
        const v = e.values[locale]?.[c];
        if (v == null) continue;
        lines.push(`        <item quantity="${c}">${xmlEscape(toPlatformFormat(v, e.args, "android", true))}</item>`);
      }
      lines.push("    </plurals>");
    } else {
      lines.push(`    <string name="${e.androidId}">${xmlEscape(toPlatformFormat(e.values[locale], e.args, "android", false))}</string>`);
    }
  }
  lines.push("</resources>", "");
  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// 7. Android typed accessors
// ---------------------------------------------------------------------------

const nsOf = (list) => {
  const m = new Map();
  for (const e of list) {
    if (!m.has(e.ns)) m.set(e.ns, []);
    m.get(e.ns).push(e);
  }
  return m;
};

/** PascalCase for the namespace objects/enums — Kotlin and Swift both expect
 *  a type-like name there, and web's namespaces are lowerCamel. */
function pascal(s) {
  const c = s.replace(/[^A-Za-z0-9]+(.)?/g, (_, ch) => (ch ? ch.toUpperCase() : ""));
  return c.charAt(0).toUpperCase() + c.slice(1);
}

function ktIdent(s) {
  const c = s.replace(/[^A-Za-z0-9]+(.)?/g, (_, ch) => (ch ? ch.toUpperCase() : ""));
  const safe = /^[0-9]/.test(c) ? `_${c}` : c;
  // Kotlin hard keywords that can still appear as an i18n key.
  const KEYWORDS = new Set(["as", "break", "class", "continue", "do", "else", "false", "for", "fun", "if", "in", "interface", "is", "null", "object", "package", "return", "super", "this", "throw", "true", "try", "typealias", "typeof", "val", "var", "when", "while"]);
  return KEYWORDS.has(safe) ? `\`${safe}\`` : safe;
}

function androidAccessorsKt() {
  const byNs = nsOf(entries);
  const blocks = [];
  for (const [ns, list] of byNs) {
    const fns = list.map((e) => {
      const objName = ktIdent(e.key);
      if (e.plural) {
        const params = e.args.map((a) => (a === "count" ? "count: Int" : `${ktIdent(a)}: Any`)).join(", "); // plural only
        const fmtArgs = e.args.map((a) => (a === "count" ? "count" : ktIdent(a))).join(", ");
        return `        fun ${objName}(res: Resources, ${params}): String =\n            res.getQuantityString(R.plurals.${e.androidId}, count, ${fmtArgs})`;
      }
      if (e.args.length === 0) {
        return `        fun ${objName}(res: Resources): String = res.getString(R.string.${e.androidId})`;
      }
      const params = e.args.map((a) => `${ktIdent(a)}: Any`).join(", ");
      const fmtArgs = e.args.map((a) => ktIdent(a)).join(", ");
      return `        fun ${objName}(res: Resources, ${params}): String =\n            res.getString(R.string.${e.androidId}, ${fmtArgs})`;
    });
    blocks.push(`    object ${pascal(ns)} {\n${fns.join("\n")}\n    }`);
  }

  return `package com.sanvya.app.i18n

import android.content.res.Resources
import com.sanvya.app.R

// GENERATED FILE — do not hand-edit.
// Source: packages/core/i18n/src/locales/**
// Regenerate with: node tools/parity/generate-i18n.mjs

/**
 * Typed access to every translated string, grouped by the same namespace web
 * uses. \`S.Transactions.item(res, n = 2)\` is the native equivalent of web's
 * \`useTranslation("transactions")\` + \`t("item", { n: 2 })\`, and unlike a raw
 * \`R.string\` lookup it stops compiling the moment a key is renamed or an
 * interpolation argument is added.
 *
 * Prefer the \`stringResource\`-style helpers in I18n.kt inside composables;
 * these take a Resources so they also work in ViewModels and services.
 */
object S {
${blocks.join("\n\n")}
}
`;
}

// ---------------------------------------------------------------------------
// 8. iOS .xcstrings + typed accessors
// ---------------------------------------------------------------------------

function xcstrings() {
  /** @type {Record<string, any>} */
  const strings = {};
  for (const e of entries) {
    const id = `${e.ns}:${e.key}`;
    /** @type {Record<string, any>} */
    const localizations = {};
    for (const loc of LOCALES) {
      if (e.plural) {
        const variations = {};
        for (const c of PLURAL_CATEGORIES) {
          const v = e.values[loc]?.[c];
          if (v == null) continue;
          variations[c] = { stringUnit: { state: "translated", value: toPlatformFormat(v, e.args, "ios", true) } };
        }
        localizations[loc] = { variations: { plural: variations } };
      } else {
        localizations[loc] = {
          stringUnit: { state: "translated", value: toPlatformFormat(e.values[loc], e.args, "ios", false) },
        };
      }
    }
    strings[id] = { extractionState: "manual", localizations };
  }
  return JSON.stringify({ sourceLanguage: SOURCE_LOCALE, strings, version: "1.0" }, null, 2) + "\n";
}

function swiftIdent(s) {
  const c = s.replace(/[^A-Za-z0-9]+(.)?/g, (_, ch) => (ch ? ch.toUpperCase() : ""));
  const safe = /^[0-9]/.test(c) ? `_${c}` : c;
  const KEYWORDS = new Set(["associatedtype", "class", "deinit", "enum", "extension", "func", "import", "init", "inout", "internal", "let", "operator", "private", "protocol", "public", "static", "struct", "subscript", "typealias", "var", "break", "case", "continue", "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while", "as", "catch", "false", "is", "nil", "rethrows", "super", "self", "throw", "throws", "true", "try", "Type", "Any"]);
  return KEYWORDS.has(safe) ? `\`${safe}\`` : safe;
}

function iosAccessorsSwift() {
  const byNs = nsOf(entries);
  const blocks = [];
  for (const [ns, list] of byNs) {
    const fns = list.map((e) => {
      const name = swiftIdent(e.key);
      const id = `${e.ns}:${e.key}`;
      if (e.plural) {
        const params = e.args.map((a) => (a === "count" ? "count: Int" : `${swiftIdent(a)}: CVarArg`)).join(", "); // plural only
        const fmtArgs = e.args.map((a) => (a === "count" ? "count" : swiftIdent(a))).join(", ");
        return `        public static func ${name}(${params}) -> String {\n            String(format: String(localized: "${id}", defaultValue: "", table: "Localizable"), ${fmtArgs})\n        }`;
      }
      if (e.args.length === 0) {
        return `        public static var ${name}: String { String(localized: "${id}", table: "Localizable") }`;
      }
      const params = e.args.map((a) => `${swiftIdent(a)}: CVarArg`).join(", ");
      const fmtArgs = e.args.map((a) => swiftIdent(a)).join(", ");
      return `        public static func ${name}(${params}) -> String {\n            String(format: String(localized: "${id}", table: "Localizable"), ${fmtArgs})\n        }`;
    });
    blocks.push(`    public enum ${pascal(ns)} {\n${fns.join("\n")}\n    }`);
  }

  return `import Foundation

// GENERATED FILE — do not hand-edit.
// Source: packages/core/i18n/src/locales/**
// Regenerate with: node tools/parity/generate-i18n.mjs

/**
 Typed access to every translated string, grouped by the same namespace web
 uses. \`S.Transactions.item(n: 2)\` is the native equivalent of web's
 \`useTranslation("transactions")\` + \`t("item", { n: 2 })\`, and unlike a bare
 \`String(localized:)\` it stops compiling the moment a key is renamed or an
 interpolation argument is added.
 */
public enum S {
${blocks.join("\n\n")}
}
`;
}

// ---------------------------------------------------------------------------
// 9. Write
// ---------------------------------------------------------------------------

const written = [];
function emit(file, body) {
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, body);
  written.push(path.relative(REPO_ROOT, file));
}

emit(path.join(ANDROID_RES, "values", "strings.xml"), androidStringsXml("en"));
emit(path.join(ANDROID_RES, "values-hi", "strings.xml"), androidStringsXml("hi"));
emit(path.join(ANDROID_RES, "values-nl", "strings.xml"), androidStringsXml("nl"));
emit(path.join(ANDROID_I18N_DIR, "S.kt"), androidAccessorsKt());
emit(path.join(IOS_RESOURCES, "Localizable.xcstrings"), xcstrings());
emit(path.join(IOS_GENERATED, "S.swift"), iosAccessorsSwift());

console.log("Wrote:");
for (const f of written) console.log(" -", f);
