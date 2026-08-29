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
  // Added 2026-08-26 as the small-screens sweep spread these across screens
  // that had never named them. `parseHexColor` in particular had three
  // competing definitions in this module until it was promoted, so a file
  // reaching for it without an import is exactly the case worth catching.
  "parseHexColor", "ColorSwatchRow", "ConfirmDialog",
  "isoLabel", "dayMonthLabel",
  "transactionListItem", "TransactionRowCard", "merchantTitle", "avatarColor",
  "splitInfoByTransaction", "collapseSplitRowIds", "SplitInfo",
  "searchTransactions", "activeFilterCount", "categoryTree", "timeAgo", "filterHelp",
  // Added 2026-08-28 by the x100 sweep, which is exactly the case a CURATED
  // list gets wrong: the money vocabulary was half-watched. `formatMoney` and
  // `baseCurrencyNow` were on the list, `money` / `fromMajor` / `toMajor` were
  // not, and the sweep spread those three across fifteen files. The guard ran
  // clean and Android still failed CI with twenty unresolved references.
  //
  // The lesson is about the LIST, not the script, and two generalisations were
  // tried before settling on that. Watching EVERY top-level declaration in the
  // module gives 358 false positives -- a top-level `fun split` and a local
  // `val rows` are indistinguishable without real scoping, and this is
  // deliberately not a type checker. Watching every declaration in the shared
  // PACKAGES gives 111, because `fun Modifier.foo()` reads as a declaration of
  // `Modifier`, and because the `^\s*` in DECL below is load-bearing: it is what
  // lets a file declaring its OWN private `formatMoney` off the hook.
  //
  // So the list is fed by hand, and the rule is: when a symbol starts appearing
  // in files that never named it, it belongs here the same day.
  "money", "fromMajor", "toMajor", "minorUnits", "majorScale", "formatMajorPlain",
];

/**
 * Not declared in this repo, and the whole reason the check exists: it is one
 * package deeper than the wildcard everybody already has.
 */
const EXTERNAL = {
  rememberSaveable: "androidx.compose.runtime.saveable",
  // Added after the charts extraction broke the build a second time. MOVING a
  // block is the dangerous case: the file it came from had
  // `androidx.compose.foundation.layout.*`, which silently covered these, and a
  // hand-written explicit import list for the new file cannot know what a
  // wildcard was providing. If you move code out of a file with a wildcard
  // import, assume you are missing something and check.
  // These are EXTENSION functions, always written as `Modifier.fillMaxWidth()`
  // -- i.e. they look qualified but still need the import. `extension: true`
  // makes the check match the dotted form too, which is the whole point: the
  // first version of this rule missed `fillMaxHeight` for exactly that reason
  // while catching `min` on the same line.
  fillMaxHeight: { pkg: "androidx.compose.foundation.layout", extension: true },
  fillMaxWidth: { pkg: "androidx.compose.foundation.layout", extension: true },
  fillMaxSize: { pkg: "androidx.compose.foundation.layout", extension: true },
  // `weight` is deliberately ABSENT. It is a member of RowScope/ColumnScope,
  // not a top-level extension, so it arrives with Row/Column and needs no
  // import — adding it produced 17 false positives across the app, which is
  // how a guard teaches people to ignore it.
  // Added 2026-08-27, after `SanvyaCard` gained a `background: Color?` param
  // and Surfaces.kt -- the file that DECLARES the component every screen
  // uses -- shipped without the import. CI's only message was "Unresolved
  // reference 'Color'", twice, with no hint that a one-line signature change
  // three commits earlier was the cause.
  //
  // `androidx.compose.ui.graphics.*` is a wildcard some files legitimately
  // have; the resolver below already treats a matching wildcard as satisfying
  // the import, so this rule only fires on a file that names neither.
  Color: { pkg: "androidx.compose.ui.graphics", type: true },
  min: "kotlin.math",
  max: "kotlin.math",
  roundToInt: { pkg: "kotlin.math", extension: true },
  // Added 2026-08-27. kotlinx.serialization's JSON accessors are extension
  // PROPERTIES on JsonElement -- `element.jsonArray`, `.jsonObject`,
  // `.jsonPrimitive` -- and every one of them lives in
  // `kotlinx.serialization.json`, one level below the `JsonElement` /
  // `JsonObject` types that files DO remember to import. A file that imports
  // the types and forgets the accessors compiles right up until it reads one.
  jsonArray: { pkg: "kotlinx.serialization.json", property: true },
  jsonObject: { pkg: "kotlinx.serialization.json", property: true },
  jsonPrimitive: { pkg: "kotlinx.serialization.json", property: true },
  contentOrNull: { pkg: "kotlinx.serialization.json", property: true },
  booleanOrNull: { pkg: "kotlinx.serialization.json", property: true },
  doubleOrNull: { pkg: "kotlinx.serialization.json", property: true },
  intOrNull: { pkg: "kotlinx.serialization.json", property: true },
  longOrNull: { pkg: "kotlinx.serialization.json", property: true },
};

function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    if (entry === "build" || entry === ".gradle") continue;
    const full = path.join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else if (entry.endsWith(".kt")) out.push(full);
  }
  return out;
}

/**
 * Test sources are INCLUDED, since 2026-08-27.
 *
 * They used to be filtered out, on the theory that a vector adapter is not a
 * screen. That was wrong for the reason CI then demonstrated: `:domain:test` is
 * compiled by the same build, a missing import there fails it just as hard, and
 * the *Vectors.kt adapters are precisely where kotlinx.serialization's JSON
 * accessors get used -- the one package everything below is about.
 */
const files = walk(ROOT);

/**
 * Every top-level TYPE declared in `:data` or `:domain` is watched automatically.
 *
 * Added 2026-08-29, after `GroupDetailScreen.kt` used `SplitGroup` with no
 * import and this guard said 0 hits -- the fourth time the CURATED list was the
 * thing that was wrong, and the second time in two days.
 *
 * Hand-feeding the list has now failed often enough to be the finding. But the
 * two earlier generalisations both drowned in false positives (358 and 111,
 * recorded above), and the reason is instructive: both watched FUNCTIONS.
 * A top-level `fun split` and a local `val split` are indistinguishable without
 * real scoping, and `fun Modifier.foo()` reads as a declaration of `Modifier`.
 *
 * TYPES have neither problem. A class name is capitalised, is never a local
 * binding, and -- crucially -- a type declared in another Gradle module can
 * ONLY be reached through an import. There is no wildcard on `:app` that
 * covers `com.sanvya.app.data.repository`, and no way to use `SplitGroup`
 * without naming it. So the rule is exact rather than heuristic, which is why
 * it can be automatic where the function list cannot.
 *
 * Scoped to the two shared modules on purpose: types declared inside `:app`
 * are frequently file-private UI models, and several files legitimately
 * declare their own `ExpenseUiModel`-shaped type.
 */
const SHARED_MODULE_DIRS = [
  path.join(ROOT, "data/src/main"),
  path.join(ROOT, "domain/src/main"),
];
//
// Anchored at COLUMN ZERO, no `\s*`. That is the whole difference between a
// top-level declaration and a nested one, and it matters: `AssistantCard` is a
// sealed hierarchy whose members are called `Text`, `Table` and `Result`. Those
// are reachable as `AssistantCard.Text` and need no import of their own, but as
// bare names they collide with Compose's `Text` and Kotlin's `Result` -- an
// indented match produced 47 false positives naming exactly those three.
const TYPE_DECL = /^(?:@\w+(?:\([^)]*\))?\s*)*(?:public |internal )?(?:data |sealed |value |abstract |open )?(?:class|object|interface|enum class)\s+([A-Z][A-Za-z0-9_]*)/gm;

/** symbol -> the package(s) it is declared in, read from the source. */
const declaredIn = new Map();
/** The subset of the above that must be matched in TYPE position, not as a call. */
const typeOnly = new Set();
const packageOf = new Map();
/** file -> the names that file declares itself, which it never needs to import. */
const declaresLocally = new Map();
const DECL = /^\s*(?:@\w+(?:\([^)]*\))?\s*)*(?:public |internal |private )?(?:const )?(?:fun|val|var|class|object|interface|enum class|data class|sealed class|sealed interface)\s+(?:<[^>]*>\s+)?([A-Za-z_][A-Za-z0-9_]*)/gm;

for (const file of files) {
  const src = readFileSync(file, "utf8");
  const pkg = src.match(/^package\s+([\w.]+)/m)?.[1];
  if (!pkg) continue;
  packageOf.set(file, pkg);
  const local = new Set();
  for (const m of src.matchAll(DECL)) local.add(m[1]);
  declaresLocally.set(file, local);

  for (const m of src.matchAll(DECL)) {
    const name = m[1];
    if (!WATCHED.includes(name)) continue;
    if (!declaredIn.has(name)) declaredIn.set(name, new Set());
    declaredIn.get(name).add(pkg);
  }

  if (SHARED_MODULE_DIRS.some((d) => file.startsWith(d + path.sep))) {
    for (const m of src.matchAll(TYPE_DECL)) {
      const name = m[1];
      if (!declaredIn.has(name)) declaredIn.set(name, new Set());
      declaredIn.get(name).add(pkg);
      typeOnly.add(name);
    }
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

  const check = (name, candidatePkgs, isExtension = false, matchTypePosition = false, isProperty = false) => {
    // A qualified use (`com.sanvya.app.ui.formatMoney(...)` or `Foo.name`)
    // needs no import, so only bare uses count -- EXCEPT for extension
    // functions, which are always written dotted and still need one.
    //
    // `matchTypePosition` widens the match to a bare word, for symbols that
    // appear as TYPES rather than calls (`background: Color? = null`). The
    // narrow form requires a following `(`, `.` or `{`, which a type
    // annotation never has -- that is exactly how Surfaces.kt shipped without
    // its `Color` import while this check said 0 hits.
    //
    // `isProperty` is the same idea for an extension PROPERTY: `.jsonArray` is
    // written dotted like an extension function but has no argument list, so
    // neither of the two rules above sees it. AssistantVectors.kt shipped
    // without that import while this check said 0 hits, for the third time in
    // three different disguises.
    const used = new RegExp(`(?<![.\\w])${name}\\s*[\\(\\.\\{]`).test(body)
      || new RegExp(`(?<![.\\w])${name}::`).test(body)
      || (matchTypePosition && new RegExp(`(?<![.\\w])${name}\\b`).test(body))
      || (isExtension && new RegExp(`\\.${name}\\s*\\(`).test(body))
      || (isProperty && new RegExp(`\\.${name}\\b`).test(body));
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

  const localNames = declaresLocally.get(file) ?? new Set();
  for (const [name, pkgs] of declaredIn) {
    // A file that declares the name itself never needs to import it, whatever
    // else in the repo happens to share the name.
    if (localNames.has(name)) continue;
    check(name, [...pkgs], false, typeOnly.has(name));
  }
  for (const [name, spec] of Object.entries(EXTERNAL)) {
    const pkg2 = typeof spec === "string" ? spec : spec.pkg;
    const isExtension = typeof spec === "object" && spec.extension === true;
    const isType = typeof spec === "object" && spec.type === true;
    const isProperty = typeof spec === "object" && spec.property === true;
    check(name, [pkg2], isExtension, isType, isProperty);
  }
}

console.log(`kotlin-imports: ${files.length} files, ${WATCHED.length + Object.keys(EXTERNAL).length} curated + ${typeOnly.size} shared-module types, ${hits} hit(s)`);
if (hits > 0) {
  console.log("::error::Kotlin symbols used without an import. Kotlin's own error for this names an unrelated class -- see the header of this script.");
  process.exit(1);
}
