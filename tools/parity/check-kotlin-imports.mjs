#!/usr/bin/env node
/**
 * tools/parity/check-kotlin-imports.mjs
 *
 * Catches a Kotlin symbol that a file uses but never imports.
 *
 * WHY THIS EXISTS. `DashboardScreen.kt` shipped to CI missing four imports.
 * The interesting part is not that it happened, it is what the compiler said:
 *
 *     Cannot access 'fun WideNavigationRailValue.not()': it is internal
 *
 * ...because `editing` had no type, so Kotlin resolved `!editing` against a
 * Material3 extension. The error named a class the file does not use, in a
 * library the feature has nothing to do with. The four real causes were three
 * screens up the log.
 *
 * `rememberSaveable` is the specific trap. It lives in
 * `androidx.compose.runtime.saveable`, NOT `androidx.compose.runtime` — so a
 * file with `import androidx.compose.runtime.*`, which most screens here have,
 * still does not get it, and nothing about the wildcard suggests that.
 *
 * WHAT IT IS NOT. Not a type checker. It resolves a short, curated list of
 * symbols this codebase actually uses everywhere, against the packages they are
 * really declared in — read from the source, so a moved file cannot make the
 * rule stale. Everything else is the compiler's job.
 *
 * Usage: node tools/parity/check-kotlin-imports.mjs
 */

import { readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = process.env.SANVYA_REPO_ROOT
  ? path.resolve(process.env.SANVYA_REPO_ROOT)
  : path.resolve(__dirname, "../..");
const ROOT = path.join(REPO_ROOT, "apps/android");

/** Symbols worth resolving: the shared vocabulary every screen reaches for. */
const WATCHED = [
  "SanvyaText", "SanvyaButton", "SanvyaCard", "SanvyaChip", "SanvyaInput",
  "SanvyaModal", "SanvyaPage", "SanvyaIcon", "Eyebrow",
  "SanvyaType", "LocalSanvyaColors", "SanvyaIcons", "SanvyaRadius", "SanvyaShape",
  "S", "sRes",
  "formatMoney", "formatMoneyAware", "formatMoneyUnmasked", "baseCurrencyNow",
  "Prefs", "colorForId", "accountColor",
];

/**
 * Not declared in this repo, and the whole reason the check exists: it is one
 * package deeper than the wildcard everybody already has.
 */
const EXTERNAL = { rememberSaveable: "androidx.compose.runtime.saveable" };

function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    if (entry === "build" || entry === ".gradle") continue;
    const full = path.join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else if (entry.endsWith(".kt")) out.push(full);
  }
  return out;
}

const files = walk(ROOT).filter((f) => !f.includes("/src/test/"));

/** symbol -> the package(s) it is declared in, read from the source. */
const declaredIn = new Map();
const packageOf = new Map();
const DECL = /^\s*(?:@\w+(?:\([^)]*\))?\s*)*(?:public |internal |private )?(?:const )?(?:fun|val|var|class|object|interface|enum class|data class|sealed class|sealed interface)\s+(?:<[^>]*>\s+)?([A-Za-z_][A-Za-z0-9_]*)/gm;

for (const file of files) {
  const src = readFileSync(file, "utf8");
  const pkg = src.match(/^package\s+([\w.]+)/m)?.[1];
  if (!pkg) continue;
  packageOf.set(file, pkg);
  for (const m of src.matchAll(DECL)) {
    const name = m[1];
    if (!WATCHED.includes(name)) continue;
    if (!declaredIn.has(name)) declaredIn.set(name, new Set());
    declaredIn.get(name).add(pkg);
  }
}

let hits = 0;
for (const file of files) {
  const src = readFileSync(file, "utf8");
  const pkg = packageOf.get(file);
  if (!pkg) continue;

  const imports = src.split("\n").filter((l) => l.startsWith("import "))
    .map((l) => l.slice("import ".length).trim());
  const explicit = new Set(imports.filter((i) => !i.endsWith("*")).map((i) => i.split(" as ")[0]));
  const wildcards = new Set(imports.filter((i) => i.endsWith("*")).map((i) => i.slice(0, -2)));

  // Strip comments and strings so a symbol named in prose is not a use.
  const body = src
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .filter((l) => !l.startsWith("import ") && !l.trim().startsWith("//") && !l.trim().startsWith("*"))
    .join("\n")
    .replace(/"(?:[^"\\]|\\.)*"/g, '""');

  const check = (name, candidatePkgs) => {
    // A qualified use (`com.sanvya.app.ui.formatMoney(...)` or `Foo.name`)
    // needs no import, so only bare uses count.
    const used = new RegExp(`(?<![.\\w])${name}\\s*[\\(\\.\\{]`).test(body)
      || new RegExp(`(?<![.\\w])${name}::`).test(body);
    if (!used) return;
    if (candidatePkgs.includes(pkg)) return;
    for (const p of candidatePkgs) {
      if (explicit.has(`${p}.${name}`) || wildcards.has(p)) return;
    }
    hits++;
    console.log(
      `${path.relative(REPO_ROOT, file)}: uses \`${name}\` with no import.\n` +
      `    → add: import ${candidatePkgs[0]}.${name}`,
    );
  };

  for (const [name, pkgs] of declaredIn) check(name, [...pkgs]);
  for (const [name, pkg2] of Object.entries(EXTERNAL)) check(name, [pkg2]);
}

console.log(`kotlin-imports: ${files.length} files, ${WATCHED.length + Object.keys(EXTERNAL).length} symbols, ${hits} hit(s)`);
if (hits > 0) {
  console.log("::error::Kotlin symbols used without an import. Kotlin's own error for this names an unrelated class -- see the header of this script.");
  process.exit(1);
}
