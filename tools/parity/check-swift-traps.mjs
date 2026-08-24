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

console.log(`swift-traps: ${swiftFiles.length} files, ${RULES.length} rules, ${failures.length} hit(s)`);
if (failures.length) {
  console.error("\n" + failures.join("\n\n"));
  console.error(`\n::error::${failures.length} known Swift trap(s). Each of these has broken CI before.`);
  process.exit(1);
}
