#!/usr/bin/env node
/**
 * Guard: the golden-vector corpus is actually wired to both runners.
 *
 * WHY THIS EXISTS. The vectors are the law of this port, and there are three
 * ways to think they are running when they are not. All three are silent:
 *
 *   1. **A registration file in the wrong source set.** `FunctionRegistry` and
 *      kotlinx.serialization are TEST-only on Android, so a `*Vectors.kt` that
 *      lands in `src/main` does not merely fail to run -- it fails the whole
 *      module build, 20 minutes into CI, with 30 unresolved references. That
 *      is how this guard was paid for.
 *   2. **A domain the runner never asks for.** A `vectors/<name>.json` with no
 *      `runDomain("<name>")` is a file nobody reads. It looks like coverage.
 *   3. **A domain the runner asks for that does not exist.** `runDomain` on a
 *      missing corpus is a typo that reads as a passing test.
 *
 * The runners themselves already SKIP an unregistered function rather than
 * fail -- deliberately, so a half-ported domain can land -- which is exactly
 * why the wiring above it has to be checked from outside.
 */

import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join } from "node:path";

const VECTORS = "tools/golden-vectors/vectors";
const KT_RUNNER = "apps/android/domain/src/test/kotlin/com/sanvya/app/domain/vectors/VectorRunnerTest.kt";
const SWIFT_RUNNER = "apps/ios/Domain/Tests/DomainTests/VectorRunnerTests.swift";
const KT_MAIN = "apps/android/domain/src/main";
const SWIFT_MAIN = "apps/ios/Domain/Sources";

function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

const hits = [];

// 1. registration files must live in a TEST source set on both platforms.
for (const [root, ext, label] of [[KT_MAIN, "Vectors.kt", "Android"], [SWIFT_MAIN, "Vectors.swift", "iOS"]]) {
  for (const f of walk(root)) {
    if (f.endsWith(ext)) {
      hits.push(`${f}: ${label} vector registrations belong in the TEST source set, not in ${root}`);
    }
  }
}

// 2/3. every corpus file has a runDomain on both platforms, and vice versa.
/**
 * Files in `vectors/` that are NOT a function corpus.
 *
 * `mobile-schema.json` is the exported PowerSync schema, and it lives here
 * because it is generated from web the same way and versioned the same way --
 * but it is consumed by `gen-mobile-schema.mjs`, which renders it into
 * PocketCareSchema.kt/.swift, not by a runner. Listing it is better than
 * moving it: the corpus directory is where "generated from web, checked in"
 * lives, and one named exception is cheaper than a second directory.
 */
const NOT_A_CORPUS = new Set(["mobile-schema"]);

const corpus = new Set(
  readdirSync(VECTORS)
    .filter((f) => f.endsWith(".json"))
    .map((f) => f.slice(0, -5))
    .filter((d) => !NOT_A_CORPUS.has(d)),
);

function runDomains(path) {
  const src = readFileSync(path, "utf8");
  return new Set([...src.matchAll(/runDomain\("([^"]+)"\)/g)].map((m) => m[1]));
}

const kt = runDomains(KT_RUNNER);
const swift = runDomains(SWIFT_RUNNER);

for (const domain of corpus) {
  if (!kt.has(domain)) hits.push(`${VECTORS}/${domain}.json: no runDomain("${domain}") in the Android runner`);
  if (!swift.has(domain)) hits.push(`${VECTORS}/${domain}.json: no runDomain("${domain}") in the iOS runner`);
}
for (const [set, path] of [[kt, KT_RUNNER], [swift, SWIFT_RUNNER]]) {
  for (const domain of set) {
    if (!corpus.has(domain)) hits.push(`${path}: runDomain("${domain}") has no ${VECTORS}/${domain}.json`);
  }
}

console.log(
  `vector-registration: ${corpus.size} domain(s), ` +
    `${kt.size} wired on Android, ${swift.size} on iOS, ${hits.length} hit(s)`,
);
for (const h of hits) console.log(`  ${h}`);
process.exit(hits.length === 0 ? 0 : 1);
