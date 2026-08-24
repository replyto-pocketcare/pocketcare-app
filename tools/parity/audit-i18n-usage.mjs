#!/usr/bin/env node
/**
 * tools/parity/audit-i18n-usage.mjs
 *
 * Finds `t("key")` calls in apps/web that no locale file defines.
 *
 * On web a missing key is nearly invisible: `t("netMonthly", "Net monthly")`
 * falls back to the inline English default, so English looks perfect and
 * Hindi and Dutch quietly render English. On native there is no inline
 * default — a missing key means no string resource at all — so every one of
 * these has to be resolved in `packages/core/i18n` before the screen that uses
 * it can be ported.
 *
 * Report-only, deliberately. Keys can be built dynamically (`t(\`kind.${k}\`)`)
 * and a file can load more than one namespace, so this cannot be a build gate
 * without producing false failures. It tells you where to look.
 *
 * Usage: node tools/parity/audit-i18n-usage.mjs [--json]
 */

import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = process.env.SANVYA_REPO_ROOT
  ? path.resolve(process.env.SANVYA_REPO_ROOT)
  : path.resolve(__dirname, "../..");

const LOCALES_DIR = path.join(REPO_ROOT, "packages/core/i18n/src/locales");
const WEB_DIR = path.join(REPO_ROOT, "apps/web");
const PLURAL_SUFFIXES = ["zero", "one", "two", "few", "many", "other"];
const AS_JSON = process.argv.includes("--json");

function flatten(obj, prefix = "", out = {}) {
  for (const [k, v] of Object.entries(obj)) {
    const key = prefix ? `${prefix}.${k}` : k;
    if (v && typeof v === "object" && !Array.isArray(v)) flatten(v, key, out);
    else out[key] = String(v);
  }
  return out;
}

/** ns -> Set of keys, with plural bases collapsed to their stem. */
const catalog = {};
for (const ns of readdirSync(LOCALES_DIR)) {
  const dir = path.join(LOCALES_DIR, ns);
  if (!statSync(dir).isDirectory()) continue;
  const file = path.join(dir, "en.json");
  if (!existsSync(file)) continue;
  const keys = new Set();
  for (const k of Object.keys(flatten(JSON.parse(readFileSync(file, "utf8"))))) {
    keys.add(k);
    // `t("loanCount", { count })` resolves loanCount_one / loanCount_other, so
    // the stem counts as defined.
    const m = k.match(new RegExp(`^(.*)_(${PLURAL_SUFFIXES.join("|")})$`));
    if (m) keys.add(m[1]);
  }
  catalog[ns] = keys;
}

const files = [];
(function walk(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (!/node_modules|\.next|playwright-report/.test(p)) walk(p);
    } else if (/\.tsx?$/.test(entry.name)) {
      files.push(p);
    }
  }
})(WEB_DIR);

/** ns -> Map<key, Set<file>> */
const missing = {};
let seen = 0;

for (const file of files) {
  const src = readFileSync(file, "utf8");
  // A file may load several namespaces; a key is satisfied by any of them,
  // which is exactly how i18next resolves it.
  const namespaces = [...src.matchAll(/useTranslation\(\s*"([A-Za-z0-9_]+)"/g)].map((m) => m[1]);
  if (namespaces.length === 0) namespaces.push("translation");
  // `translation` is i18next's default namespace and is always in the fallback
  // chain, so it is always a legitimate home for a key.
  if (!namespaces.includes("translation")) namespaces.push("translation");

  const keys = new Set([...src.matchAll(/\bt\(\s*"([A-Za-z0-9_.]+)"/g)].map((m) => m[1]));
  if (keys.size === 0) continue;
  seen += keys.size;

  for (const key of keys) {
    const found = namespaces.some((ns) => catalog[ns]?.has(key));
    if (found) continue;
    const owner = namespaces[0];
    missing[owner] ??= new Map();
    if (!missing[owner].has(key)) missing[owner].set(key, new Set());
    missing[owner].get(key).add(path.relative(REPO_ROOT, file));
  }
}

const total = Object.values(missing).reduce((n, m) => n + m.size, 0);

if (AS_JSON) {
  console.log(
    JSON.stringify(
      Object.fromEntries(
        Object.entries(missing).map(([ns, m]) => [
          ns,
          Object.fromEntries([...m].map(([k, files]) => [k, [...files]])),
        ]),
      ),
      null,
      2,
    ),
  );
} else {
  console.log(`Scanned ${files.length} files, ${seen} t() call sites.`);
  console.log(`${total} key(s) used by the web app have no entry in packages/core/i18n.\n`);
  for (const ns of Object.keys(missing).sort()) {
    console.log(`  ${ns} (${missing[ns].size})`);
    for (const [key, where] of [...missing[ns]].sort()) {
      console.log(`    ${key}  ← ${[...where].join(", ")}`);
    }
    console.log("");
  }
  if (total > 0) {
    console.log(
      "Each of these renders its inline English default on web — including for hi and nl.\n" +
        "Native has no inline default, so they must be added to packages/core/i18n before\n" +
        "the screens that use them are ported.",
    );
  }
}
