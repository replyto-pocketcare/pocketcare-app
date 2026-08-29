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
    name: "a `??` fallback closure that is not `@Sendable`",
    // Every function-typed alias in Domain is `@Sendable` (`RateLookup` says so
    // in its own doc comment), and a bare closure literal is not. Swift 6
    // rejects the conversion with "converting non-Sendable function value to
    // '@Sendable ...' may introduce data races" -- a message that names the
    // TYPE and not the two characters that are missing.
    //
    // It has bitten three view models now, always in the same shape:
    // `(try? await repo.rates()) ?? { _, _ in 1.0 }`. Two of the three were
    // written after the first one was fixed AND documented, which is what
    // makes it a rule rather than a note.
    //
    // Zero false positives on the current tree: every `??` fallback in the app
    // that is a closure literal is a function-typed one, and all of them want
    // `@Sendable`.
    test: (line) => /\?\?\s*\{/.test(line) && !line.includes("@Sendable"),
    fix: "Spell it: `?? { @Sendable _, _ in ... }`.",
  },
  {
    name: "`.frame()` mixing a fixed dimension with a flexible one",
    // SwiftUI has TWO frame modifiers and no overload spanning them: the fixed
    // `frame(width:height:alignment:)` and the flexible
    // `frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)`.
    // `frame(width: 112, minHeight: 58)` reads perfectly and does not exist.
    //
    // Worth a rule because of what the compiler says: "extra argument
    // 'minHeight' in call", which sounds like one argument too many rather
    // than "you have combined two different modifiers", so the obvious fix --
    // deleting the argument -- silently drops the constraint you wanted.
    //
    // The fix is two chained calls. They compose: the inner one sizes, the
    // outer one constrains.
    test: (line) => {
      const call = line.match(/\.frame\(([^)]*)\)/);
      if (!call) return false;
      const args = call[1];
      return /(^|[\s,])(width|height):/.test(args)
        && /(^|[\s,])(minWidth|idealWidth|maxWidth|minHeight|idealHeight|maxHeight):/.test(args);
    },
    fix: "Split it: `.frame(width: 112).frame(minHeight: 58)`.",
  },
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
    name: "a UNUserNotificationCenterDelegate method that is not `nonisolated`",
    // UIApplicationDelegate is @MainActor, so an AppDelegate that also adopts
    // UNUserNotificationCenterDelegate inherits that isolation -- and
    // UNUserNotificationCenter / UNNotification are not Sendable, so an
    // implementation the compiler has to hop onto the main actor cannot receive
    // them. Swift 6's message names the two types and the protocol requirement
    // and reads like a library problem; the fix is one keyword.
    test: (line) => /\bfunc\s+userNotificationCenter\s*\(/.test(line) && !/\bnonisolated\b/.test(line),
    fix: "Mark it `nonisolated` and take the completion-handler form, not `async`.",
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
 * `@Bindable var vm = viewModel` passed to a `Bindable<T>` parameter.
 *
 * `@Bindable var vm` makes `vm` a plain `T` and `$vm` the `Bindable<T>` —
 * the wrapper is the PROJECTED value, not the variable. A helper written as
 * `func card(vm: Bindable<DataViewModel>)` therefore has to be called with
 * `card(vm: $vm)`, and `card(vm: vm)` fails with "cannot convert value of
 * type 'DataViewModel' to expected argument type 'Bindable<DataViewModel>'".
 *
 * That error names both types and still reads like the view model is wrong,
 * which is why `DataView.swift` shipped it and `WalkthroughView.swift` was
 * written the same way an hour later. It is cross-line — the declaration and
 * the call site are far apart — so it cannot be a per-line rule.
 * ------------------------------------------------------------------ */
for (const file of swiftFiles) {
  const src = readFileSync(file, "utf8");
  const declared = new Set(
    [...src.matchAll(/@Bindable\s+var\s+(\w+)\s*=/g)].map((m) => m[1]),
  );
  if (declared.size === 0) continue;
  const bindableParams = new Set(
    [...src.matchAll(/(\w+)\s*:\s*Bindable</g)].map((m) => m[1]),
  );
  if (bindableParams.size === 0) continue;

  src.split("\n").forEach((line, i) => {
    if (/^\s*(\/\/|\*|\/\*)/.test(line)) return;
    // The declaration itself is `x: Bindable<T>` — not a call site.
    if (/:\s*Bindable</.test(line)) return;
    for (const label of bindableParams) {
      for (const name of declared) {
        if (new RegExp(`\\b${label}\\s*:\\s*${name}\\b`).test(line)) {
          failures.push(
            `${path.relative(repoRoot, file)}:${i + 1}  @Bindable variable passed where Bindable<T> is expected\n` +
            `    ${line.trim()}\n` +
            `    → pass the projected value: \`${label}: $${name}\``,
          );
        }
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

/* ------------------------------------------------------------------ *
 * A non-`@escaping` @ViewBuilder closure handed to a component that STORES it.
 *
 * `SanvyaCard`, `SanvyaButton` and friends keep their content closure in a
 * property, so their initialisers declare `@ViewBuilder content: @escaping`.
 * A local helper written the obvious way —
 *
 *     private func chartCard(_ t: String, @ViewBuilder content: () -> some View) -> some View {
 *         SanvyaCard { ... content() ... }
 *     }
 *
 * — gets "escaping closure captures non-escaping parameter 'content'", which
 * points at the CARD, names the parameter, and says nothing about the helper's
 * own signature being the fixable end. StatementAnalyzeView.swift shipped it.
 *
 * Which components need it is read from their own initialisers, not listed
 * here, so a component that stops storing its content stops being flagged.
 * ------------------------------------------------------------------ */
const escapingContentComponents = new Set();
for (const file of swiftFiles) {
  const src = readFileSync(file, "utf8");
  for (const m of src.matchAll(/struct\s+(\w+)\s*<[^>]*>\s*:\s*View\b/g)) {
    const name = m[1];
    const after = src.slice(m.index, m.index + 4000);
    if (/@ViewBuilder\s+\w+\s*:\s*@escaping/.test(after)) escapingContentComponents.add(name);
  }
}

if (escapingContentComponents.size) {
  for (const file of swiftFiles) {
    const src = readFileSync(file, "utf8");
    // `func name(... @ViewBuilder label: () -> X ...) ` with no @escaping.
    for (const m of src.matchAll(/func\s+\w+[^\n]*?@ViewBuilder\s+(\w+)\s*:\s*(?!@escaping)\(\s*\)\s*->/g)) {
      const param = m[1];
      // Take the helper's body by brace matching from its opening `{`.
      const open = src.indexOf("{", m.index);
      if (open < 0) continue;
      let depth = 0;
      let end = open;
      for (; end < src.length; end++) {
        if (src[end] === "{") depth++;
        else if (src[end] === "}") { depth--; if (depth === 0) break; }
      }
      const body = src.slice(open, end);
      const stored = [...escapingContentComponents].filter((c) =>
        new RegExp(`\\b${c}\\s*[({]`).test(body) && new RegExp(`\\b${param}\\s*\\(`).test(body),
      );
      if (stored.length) {
        const lineNo = src.slice(0, m.index).split("\n").length;
        failures.push(
          `${path.relative(repoRoot, file)}:${lineNo}  non-@escaping @ViewBuilder '${param}' handed to ${stored[0]}, which stores it\n` +
          `    → make it \`@ViewBuilder ${param}: @escaping () -> C\` with an explicit \`<C: View>\`; \`some View\` cannot carry @escaping cleanly.`,
        );
      }
    }
  }
}

/* ------------------------------------------------------------------ *
 * A test-target helper whose name shadows a PUBLIC Domain function.
 *
 * The test target declares its own symbols and `@testable import Domain`
 * brings in Domain's. On a name clash the TARGET'S OWN declaration wins,
 * with no ambiguity error and no warning.
 *
 * `FinanceVectors.swift` had a `jsonNumber(Double) -> Any` helper long before
 * Domain gained a public `jsonNumber(Double) -> String`. Every call in
 * AssistantVectors silently got the test one: 41 vectors compared a number
 * against a string, and the log said the ported function was wrong when the
 * ported function was never called.
 *
 * This is the ONE guard here that has not shipped to CI twice, and the reason
 * is the failure mode: every other trap in this file is a COMPILE error, loud
 * and attributable. This one produces a wrong value and blames the wrong code.
 * ------------------------------------------------------------------ */
const domainPublicFns = new Set();
for (const file of swiftFiles) {
  if (!file.includes("/Domain/Sources/Domain/")) continue;
  for (const m of readFileSync(file, "utf8").matchAll(/^public func (\w+)\s*[(<]/gm)) {
    domainPublicFns.add(m[1]);
  }
}
for (const file of swiftFiles) {
  if (!file.includes("/Domain/Tests/")) continue;
  const src = readFileSync(file, "utf8");
  for (const m of src.matchAll(/^(?:private |internal )?func (\w+)\s*[(<]/gm)) {
    if (!domainPublicFns.has(m[1])) continue;
    // `private` is file-scoped and cannot shadow across the target.
    if (/^private /.test(m[0])) continue;
    const lineNo = src.slice(0, m.index).split("\n").length;
    failures.push(
      `${path.relative(repoRoot, file)}:${lineNo}  test helper '${m[1]}' shadows a public Domain function\n` +
      `    → the test target's own declaration wins silently. Rename the helper, or call \`Domain.${m[1]}(…)\`.`,
    );
  }
}

/* ------------------------------------------------------------------
 * A `static let` holding a non-Sendable Foundation class.
 *
 * `static let plainDay = ISO8601DateFormatter()` reads like the obvious way to
 * avoid rebuilding a formatter. Under Swift 6 strict concurrency it is a build
 * ERROR — "static property is not concurrency-safe because non-'Sendable' type
 * ... may have shared mutable state" — because every one of these is a mutable
 * class with settable properties, and a static is reachable from any isolation
 * domain at once.
 *
 * The error is clear when you read it. It is also invisible to anyone writing
 * the line, costs a full macOS build to discover, and this codebase has now hit
 * it twice. The house answer is a fresh instance per call, which is what
 * `Domain/Entitlements.swift` and `App/DateLabels.swift` both already do and
 * both already explain.
 * ------------------------------------------------------------------ */
const NON_SENDABLE_FOUNDATION = [
  "ISO8601DateFormatter",
  "DateFormatter",
  "NumberFormatter",
  "DateComponentsFormatter",
  "DateIntervalFormatter",
  "ByteCountFormatter",
  "MeasurementFormatter",
  "PersonNameComponentsFormatter",
  "RelativeDateTimeFormatter",
  "JSONDecoder",
  "JSONEncoder",
  "NSMutableArray",
  "NSMutableDictionary",
  "NSMutableString",
];
const staticNonSendable = new RegExp(
  String.raw`^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+)?static\s+(?:let|var)\s+(\w+)\s*[:=][^\n]*\b(${NON_SENDABLE_FOUNDATION.join("|")})\b`,
  "gm",
);
for (const file of swiftFiles) {
  const src = readFileSync(file, "utf8");
  for (const m of src.matchAll(staticNonSendable)) {
    const lineNo = src.slice(0, m.index).split("\n").length;
    failures.push(
      `${path.relative(repoRoot, file)}:${lineNo}  static '${m[1]}' holds a non-Sendable ${m[2]}\n` +
      `    → Swift 6 rejects this outright. Build a fresh one per call, as Domain/Entitlements.swift does.`,
    );
  }
}

/* ------------------------------------------------------------------
 * A lock taken inside an `async` function.
 *
 * `NSLock.lock()` / `.unlock()`, `NSCondition.wait()` and
 * `DispatchSemaphore.wait()` are all `@available(*, noasync)` under Swift 6:
 * a task can suspend while holding the lock and resume on a different thread,
 * which is how you deadlock a cooperative pool.
 *
 * This is a CROSS-LINE rule, which is why it is a scan rather than a line
 * rule. The lock call reads perfectly on its own; what makes it illegal is the
 * `async` on a `func` line that may be forty lines above it. And the way it
 * arrives is worse than writing it by hand: `SecurityRepository.swift` had
 * twelve legal `lock()` calls until a review asked for Keychain I/O to move
 * off the main thread. Making four functions `async` turned sixteen of those
 * calls into errors at once, in code nobody had touched.
 *
 * The fix is never to remove the lock. Pull the critical section into a
 * private SYNCHRONOUS method and call that from the async one — a sync
 * function that locks internally is legal from anywhere, and it turns a span
 * between two lines into a named thing.
 *
 * Brace counting is deliberately naive: it tracks depth from each `func` line
 * and only attributes a lock call to the nearest enclosing one. Nested types
 * and closures inside a function body stay attributed to that function, which
 * is the conservative direction — a closure inside an async func is exactly
 * where this bites too.
 * ------------------------------------------------------------------ */
// Matches the METHOD call -- `lock.lock()`, `sem.wait()`. The leading dot is
// required: an earlier version used a negative lookbehind for `.`, which
// excluded every real call site and made the whole scan silently find nothing.
const LOCK_CALLS = /\.(?:lock|unlock|wait)\s*\(\s*\)/;
const FUNC_LINE = /^\s*(?:@\w+(?:\([^)]*\))?\s*)*(?:(?:public|internal|private|fileprivate|open)\s+)?(?:static\s+|class\s+|final\s+|override\s+|nonisolated\s+|mutating\s+)*func\s+\w+/;

for (const file of swiftFiles) {
  const lines = readFileSync(file, "utf8").split("\n");
  // Stack of { isAsync, depth } for functions we are currently inside.
  let depth = 0;
  const funcs = [];
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    const line = raw.replace(/\/\/.*$/, "").replace(/"(?:[^"\\]|\\.)*"/g, '""');

    if (FUNC_LINE.test(line)) {
      // The signature can wrap; look ahead until the opening brace.
      let sig = line;
      for (let j = i + 1; j < Math.min(i + 8, lines.length) && !sig.includes("{"); j++) {
        sig += " " + lines[j].replace(/\/\/.*$/, "");
      }
      funcs.push({ isAsync: /\basync\b/.test(sig), depth, line: i + 1 });
    }

    if (LOCK_CALLS.test(line) && !/\bfunc\b/.test(line)) {
      const enclosing = funcs[funcs.length - 1];
      if (enclosing?.isAsync) {
        failures.push(
          `${path.relative(repoRoot, file)}:${i + 1}  lock taken inside an \`async\` function (declared line ${enclosing.line})\n` +
          `    ${raw.trim()}\n` +
          `    → Pull the critical section into a private SYNCHRONOUS method and call that. Never drop the lock.`,
        );
      }
    }

    for (const ch of line) {
      if (ch === "{") depth++;
      else if (ch === "}") {
        depth--;
        while (funcs.length && funcs[funcs.length - 1].depth >= depth) funcs.pop();
      }
    }
  }
}

console.log(`swift-traps: ${swiftFiles.length} files, ${RULES.length} line rules + bindable + escaping-content + shadowed-symbol + missing-import + static-non-Sendable + async-lock scans, ${failures.length} hit(s)`);
if (failures.length) {
  console.error("\n" + failures.join("\n\n"));
  console.error(`\n::error::${failures.length} known Swift trap(s). Each of these has broken CI before.`);
  process.exit(1);
}
