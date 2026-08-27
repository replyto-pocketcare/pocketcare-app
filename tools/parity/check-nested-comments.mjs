#!/usr/bin/env node
/**
 * tools/parity/check-nested-comments.mjs
 *
 * Finds `/*` INSIDE a block comment, in Kotlin and Swift.
 *
 * Both languages NEST block comments — unlike Java, C and JavaScript, where an
 * inner `/*` is just two characters. So a doc comment that mentions a path
 * pattern in prose:
 *
 *     /**
 *      * Refused: `/admin/[*]`, `/auth/[*]`, `/join/[*]`.
 *      *\/
 *
 * silently opens a second comment at the first of those, and the `*\/` that was
 * meant to end the doc comment ends the INNER one instead. Everything after it
 * — the whole rest of the file — is swallowed, and the compiler reports
 * "Unclosed comment" at the last line, which is nowhere near the cause.
 *
 * That is a full CI round trip (nine minutes on Android, longer on iOS) for a
 * defect that is two characters wide and invisible on review, which is exactly
 * the trade these guards exist to make. Found the hard way in run 33100717697.
 *
 * Usage: node tools/parity/check-nested-comments.mjs
 * Exit 1 on any hit.
 */

import { readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = process.env.SANVYA_REPO_ROOT
  ? path.resolve(process.env.SANVYA_REPO_ROOT)
  : path.resolve(__dirname, "../..");

const ROOTS = [
  path.join(REPO_ROOT, "apps/android"),
  path.join(REPO_ROOT, "apps/ios"),
];
const SKIP_DIRS = new Set(["build", ".build", ".git", "node_modules", "DerivedData", "Pods"]);
const EXTENSIONS = new Set([".kt", ".kts", ".swift"]);

function walk(dir, out = []) {
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return out;
  }
  for (const name of entries) {
    if (SKIP_DIRS.has(name)) continue;
    const full = path.join(dir, name);
    if (statSync(full).isDirectory()) walk(full, out);
    else if (EXTENSIONS.has(path.extname(name))) out.push(full);
  }
  return out;
}

/**
 * One pass, tracking comment depth.
 *
 * Line comments and string literals are skipped so a `/*` inside either is not
 * reported — `"https://x/*"` in a SQL string is legal and common. The string
 * skip is deliberately crude (it stops at a newline) because a raw string that
 * spans lines cannot contain an unbalanced comment opener that matters here:
 * the compiler is not in a comment inside one either.
 */
function nestedOpeners(source) {
  const hits = [];
  let depth = 0;
  let line = 1;
  for (let i = 0; i < source.length - 1; ) {
    if (source[i] === "\n") line++;
    const two = source.slice(i, i + 2);
    if (depth === 0) {
      if (two === "//") {
        const end = source.indexOf("\n", i);
        if (end < 0) break;
        line++;
        i = end + 1;
        continue;
      }
      if (two === "/*") {
        depth = 1;
        i += 2;
        continue;
      }
      if (source[i] === '"') {
        let j = i + 1;
        while (j < source.length && source[j] !== '"' && source[j] !== "\n") {
          if (source[j] === "\\") j++;
          j++;
        }
        i = j + 1;
        continue;
      }
      i++;
      continue;
    }
    if (two === "/*") {
      hits.push(line);
      depth++;
      i += 2;
      continue;
    }
    if (two === "*/") {
      depth--;
      i += 2;
      continue;
    }
    i++;
  }
  return hits;
}

const files = ROOTS.flatMap((root) => walk(root));
const problems = [];
for (const file of files) {
  const source = readFileSync(file, "utf8");
  if (!source.includes("/*")) continue;
  const seen = new Set();
  for (const line of nestedOpeners(source)) {
    // One report per line: a depth that never returns to zero re-reports every
    // subsequent opener in the file, and only the first is the cause.
    if (seen.has(line)) continue;
    seen.add(line);
    problems.push(`${path.relative(REPO_ROOT, file)}:${line}: \`/*\` inside a block comment — Kotlin and Swift NEST these, so this opens a comment the closing \`*/\` then ends early`);
  }
}

console.log(`nested-comments: ${files.length} files, ${problems.length} hit(s)`);
if (problems.length) {
  console.error(problems.map((p) => "  " + p).join("\n"));
  console.error("\nReword the prose (write `/admin` rather than `/admin/*`), or move it to `//` line comments.");
  process.exit(1);
}
