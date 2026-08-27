#!/usr/bin/env node
/**
 * tools/parity/check-trailing-lambda.mjs
 *
 * Catches a trailing lambda handed to a composable whose LAST parameter is not
 * a lambda.
 *
 * WHY THIS EXISTS. `SanvyaChip(label, active) { onClick() }` reads like every
 * other Compose call and is wrong, because the signature is
 * `(label, active, onClick, modifier = Modifier)` — `modifier` is last, so the
 * trailing lambda binds to IT. Six call sites on one screen went to CI and came
 * back with twelve errors, none of which say "trailing lambda":
 *
 *     No value passed for parameter 'onClick'.
 *     Argument type mismatch: actual type is '() -> Unit', but 'Modifier' was expected.
 *
 * WHAT IT IS NOT. Not a type checker, and it invents no list. It READS every
 * `@Composable fun Sanvya*` declaration in the component layer, works out
 * whether the last parameter is a function type, and only then looks for
 * trailing-lambda call sites of the ones where it is not. Reordering a
 * signature updates the rule automatically; that is the point.
 *
 * Usage: node tools/parity/check-trailing-lambda.mjs
 */

import { readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = process.env.SANVYA_REPO_ROOT
  ? path.resolve(process.env.SANVYA_REPO_ROOT)
  : path.resolve(__dirname, "../..");
const ROOT = path.join(REPO_ROOT, "apps/android");
const COMPONENTS = path.join(ROOT, "app/src/main/java/com/sanvya/app/ui/components");

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const full = path.join(dir, name);
    if (statSync(full).isDirectory()) walk(full, out);
    else if (name.endsWith(".kt")) out.push(full);
  }
  return out;
}

/** Split a parameter list on top-level commas — a function-typed default has its own. */
function splitParams(text) {
  const out = [];
  let depth = 0;
  let start = 0;
  // `->` first: its `>` is not a closing generic bracket, and counting it as
  // one sends depth negative, after which no comma is top-level any more and
  // the whole list collapses into one "parameter". That is exactly the bug this
  // file exists to catch, in the file that catches it.
  const scan = text.replace(/->/g, "=$");
  for (let i = 0; i < scan.length; i++) {
    const c = scan[i];
    if (c === "(" || c === "<") depth++;
    else if (c === ")" || c === ">") depth--;
    else if (c === "," && depth === 0) {
      out.push(text.slice(start, i));
      start = i + 1;
    }
  }
  out.push(text.slice(start));
  return out.map((p) => p.trim()).filter(Boolean);
}

/** Read the whole parenthesised parameter list starting at `open`. */
function readParams(body, open) {
  let depth = 0;
  for (let i = open; i < body.length; i++) {
    if (body[i] === "(") depth++;
    else if (body[i] === ")") {
      depth--;
      if (depth === 0) return body.slice(open + 1, i);
    }
  }
  return null;
}

const lambdaLast = new Set();
const notLambdaLast = new Map(); // name -> last param name

for (const file of walk(COMPONENTS)) {
  const body = readFileSync(file, "utf8");
  const decl = /fun\s+(Sanvya[A-Za-z0-9_]*)\s*\(/g;
  let m;
  while ((m = decl.exec(body))) {
    const name = m[1];
    const params = readParams(body, decl.lastIndex - 1);
    if (params == null) continue;
    const parts = splitParams(params);
    if (parts.length === 0) continue;
    const last = parts[parts.length - 1];
    // A function-typed parameter: `x: () -> Unit`, `x: (@Composable) () -> Unit`,
    // `x: @Composable () -> Unit`, or a nullable one.
    const isLambda = /->/.test(last.split(":").slice(1).join(":"));
    if (isLambda) lambdaLast.add(name);
    else notLambdaLast.set(name, last.split(":")[0].trim());
  }
}

// A name declared BOTH ways somewhere (an overload) is not decidable here, so
// it is left alone rather than reported on a guess.
for (const name of lambdaLast) notLambdaLast.delete(name);

const hits = [];
const callSites = walk(path.join(ROOT, "app/src/main/java/com/sanvya/app"));
for (const file of callSites) {
  if (file.startsWith(COMPONENTS)) continue;
  const lines = readFileSync(file, "utf8").split("\n");
  for (const [name, lastParam] of notLambdaLast) {
    for (let i = 0; i < lines.length; i++) {
      const idx = lines[i].indexOf(`${name}(`);
      if (idx < 0) continue;
      // Find this call's closing paren, which may be lines below.
      let depth = 0;
      let li = i;
      let ci = idx + name.length;
      let closed = null;
      scan: for (; li < lines.length && li < i + 60; li++) {
        for (; ci < lines[li].length; ci++) {
          const c = lines[li][ci];
          if (c === "(") depth++;
          else if (c === ")") {
            depth--;
            if (depth === 0) { closed = { li, ci }; break scan; }
          }
        }
        ci = 0;
      }
      if (!closed) continue;
      const after = lines[closed.li].slice(closed.ci + 1).trim();
      if (after.startsWith("{")) {
        hits.push(
          `${path.relative(REPO_ROOT, file)}:${i + 1} ${name}(...) { ... } — ` +
          `trailing lambda binds to '${lastParam}', not a callback. Pass it by name.`,
        );
      }
    }
  }
}

const checked = notLambdaLast.size;
console.log(
  `trailing-lambda: ${callSites.length} files, ${checked} component(s) whose last parameter is not a lambda, ${hits.length} hit(s)`,
);
if (hits.length) {
  for (const h of hits) console.log(`  ${h}`);
  process.exit(1);
}
