#!/usr/bin/env node
/**
 * Cheap greps for Swift mistakes this codebase has made more than once.
 *
 * Every rule here earned its place by shipping to CI at least twice. They are
 * text checks, not a type-checker — the point is that they run in under a
 * second in the `parity` job, where the real answer costs a ~10-minute macOS
 * build and a round trip through a human to push again.
 *
 * Comment lines are skipped: the traps below are all *documented* in comments,
 * which is exactly why a naive grep would be useless.
 *
 * Run: node tools/parity/check-swift-traps.mjs
 */
import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const roots = [
  "apps/ios/App",
  "apps/ios/Data/Sources",
  "apps/ios/Domain/Sources",
  "apps/ios/Domain/Tests",
];

const RULES = [
  {
    name: "await inside ??",
    // `??`'s right-hand side is an @autoclosure, which is not async. The
    // compiler blames the `??`, not the `await`, so the message reads
    // "'async' call in a function that does not support concurrency" and
    // points at a line with no visible problem.
    test: (line) => /\?\?\s*\(?\s*(try\?\s*)?await\b/.test(line),
    fix: "Spell it out: `if let x = sync { return x }; return try? await asyncCall()`.",
  },
  {
    name: "UUID().uuidString on a persisted id",
    // Swift's uuidString is UPPERCASE; web and Android write lowercase, and
    // SQLite compares TEXT case-sensitively. See Data/Ids.swift.
    test: (line) => /UUID\(\)\.uuidString/.test(line) && !/DraftItem|Identifiable key/.test(line),
    fix: "Use `UUID().canonicalString` (Data/Ids.swift) for anything persisted or compared.",
  },
];

const swiftFiles = [];
const walk = (dir) => {
  let entries;
  try { entries = readdirSync(dir); } catch { return; }
  for (const entry of entries) {
    const full = path.join(dir, entry);
    if (entry === ".build" || entry === "Generated") continue;
    if (statSync(full).isDirectory()) walk(full);
    else if (entry.endsWith(".swift")) swiftFiles.push(full);
  }
};
for (const r of roots) walk(path.join(repoRoot, r));

const failures = [];
for (const file of swiftFiles) {
  const lines = readFileSync(file, "utf8").split("\n");
  lines.forEach((line, i) => {
    // Skip comments — every one of these traps is documented in prose
    // somewhere, and flagging the warning would be worse than useless.
    if (/^\s*(\/\/|\*|\/\*)/.test(line)) return;
    for (const rule of RULES) {
      if (rule.test(line)) {
        failures.push(`${path.relative(repoRoot, file)}:${i + 1}  ${rule.name}\n    ${line.trim()}\n    → ${rule.fix}`);
      }
    }
  });
}

/* ------------------------------------------------------------------ *
 * A file that NAMES a type from Data or Domain but never imports it.
 *
 * Swift's error for this is "cannot find type 'LabelRow' in scope", which
 * reads like a typo rather than a missing import, and a view file that got
 * the type by inference compiles right up until someone writes the name.
 * `SearchView.swift` and `TaxonomyViews.swift` both shipped this way; the
 * view model beside each of them had the import, so nothing looked wrong.
 *
 * Names declared in the App module itself are excluded, or every shared name
 * would be a false positive.
 * ------------------------------------------------------------------ */
// Zero indentation on purpose: a NESTED type (`RecurringRepository.Item`)
// cannot be named bare from another module, so matching indented declarations
// would flag every file that happens to contain the word "Item".
const DECL = /^public\s+(?:final\s+)?(?:struct|class|enum|actor|protocol|typealias)\s+([A-Z]\w*)/gm;

/**
 * Names Apple's own frameworks also define. A file using SwiftUI's `GridItem`
 * is not evidence that it wants Domain's, and no import would fix it.
 */
const APPLE_NAMES = new Set(["GridItem", "Label", "Section", "Item", "Path", "Group", "Transaction"]);

const declaredIn = (dir) => {
  const names = new Set();
  const files = [];
  const collect = (d) => {
    let entries;
    try { entries = readdirSync(d); } catch { return; }
    for (const entry of entries) {
      const full = path.join(d, entry);
      if (entry === ".build") continue;
      if (statSync(full).isDirectory()) collect(full);
      else if (entry.endsWith(".swift")) files.push(full);
    }
  };
  collect(path.join(repoRoot, dir));
  for (const f of files) {
    const src = readFileSync(f, "utf8");
    for (const m of src.matchAll(DECL)) {
      // Only PUBLIC declarations can be named from another module anyway.
      names.add(m[1]);
    }
  }
  return names;
};

const MODULE_TYPES = {
  Data: declaredIn("apps/ios/Data/Sources/Data"),
  Domain: declaredIn("apps/ios/Domain/Sources/Domain"),
};
for (const n of APPLE_NAMES) {
  MODULE_TYPES.Data.delete(n);
  MODULE_TYPES.Domain.delete(n);
}
const appTypes = declaredIn("apps/ios/App");
// A name the App module also declares is ambiguous evidence; skip it.
for (const names of Object.values(MODULE_TYPES)) {
  for (const n of appTypes) names.delete(n);
}
// Both modules declaring it means the import is whichever one, not both.
for (const n of [...MODULE_TYPES.Data]) {
  if (MODULE_TYPES.Domain.has(n)) {
    MODULE_TYPES.Data.delete(n);
    MODULE_TYPES.Domain.delete(n);
  }
}

/** Strip comments and string literals so prose cannot trip the check. */
const code = (src) =>
  src
    .replace(/\/\*[\s\S]*?\*\//g, " ")
    .replace(/\/\/[^\n]*/g, " ")
    .replace(/"(?:[^"\\\n]|\\.)*"/g, '""');

for (const file of swiftFiles) {
  if (!file.includes(`${path.sep}apps${path.sep}ios${path.sep}App${path.sep}`)) continue;
  const src = readFileSync(file, "utf8");
  const body = code(src);
  for (const [module, names] of Object.entries(MODULE_TYPES)) {
    if (new RegExp(`^\\s*import\\s+${module}\\s*$`, "m").test(src)) continue;
    const used = [...names].filter((n) => new RegExp(`\\b${n}\\b`).test(body));
    if (used.length) {
      failures.push(
        `${path.relative(repoRoot, file)}  names ${module} type(s) without importing the module\n    ${used.slice(0, 4).join(", ")}${used.length > 4 ? ` (+${used.length - 4} more)` : ""}\n    → add \`import ${module}\` at the top of the file.`,
      );
    }
  }
}

console.log(`swift-traps: ${swiftFiles.length} files, ${RULES.length} rules + missing-import scan, ${failures.length} hit(s)`);
if (failures.length) {
  console.error("\n" + failures.join("\n\n"));
  console.error(`\n::error::${failures.length} known Swift trap(s). Each of these has broken CI before.`);
  process.exit(1);
}
