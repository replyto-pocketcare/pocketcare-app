#!/usr/bin/env node
/**
 * Guard: no hardcoded ×100 / ÷100 on a money amount.
 *
 * WHY THIS EXISTS. `100` is the minor-unit scale for the rupee, the dollar and
 * the euro, and it is WRONG for the yen (0 decimals) and the dinar (3). The
 * codebase had 47 sites that assumed it. Three of them were not cosmetic:
 *
 *   - the split editor's `toMinor` made an exact-mode JPY split impossible to
 *     save at all (audit defect #15);
 *   - the AI receipt reader returned a ¥3000 bill as ¥300000 (#19);
 *   - a credit card's entered balance was read a hundred times too small.
 *
 * The fix is always the same: `fromMajor(major, currency)` /
 * `toMajor(money(minor, currency))` for exact amounts, `majorScale(currency)`
 * for a Double already in flight (a chart average, a running total).
 *
 * WHAT IT DOES NOT FLAG. A `100` that is a PERCENTAGE is not a money scale, so
 * lines that name one (`pct`, `percent`, `progress`, `ratio`, `%`) are skipped.
 * Everything else needs an entry in ALLOWED below, with a reason — the point is
 * that a new ÷100 has to be argued for in writing, not that it can never exist.
 */

import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const ROOTS = [
  "apps/android/app/src/main",
  "apps/android/data/src/main",
  "apps/android/domain/src/main",
  "apps/ios/App",
  "apps/ios/Data/Sources",
  "apps/ios/Domain/Sources",
];

/**
 * Sites where 100 is correct, with the reason. Keyed by file path; a file may
 * legitimately have more than one.
 *
 * Every entry here is INR-scoped or a deliberate web-parity mirror. None of
 * them is "we'll get to it".
 */
const ALLOWED = new Map([
  // The NPCI UPI URI spec defines `am` as INR with two decimals. UPI carries no
  // other currency, and both sheets are gated on the group being in INR.
  ["apps/android/app/src/main/java/com/sanvya/app/ui/splits/PayViaUpiDialog.kt", "UPI URI is INR-by-spec"],
  ["apps/ios/App/PayViaUpiSheet.swift", "UPI URI is INR-by-spec"],
  ["apps/android/domain/src/main/kotlin/com/sanvya/app/domain/upi/Upi.kt", "UPI amounts are INR-by-spec"],
  ["apps/ios/Domain/Sources/Domain/Upi.swift", "UPI amounts are INR-by-spec"],
  // The assistant's prompt summary mirrors web's own `major()` exactly, and the
  // vectors pin it. Changing it here would diverge from the corpus, not fix it.
  ["apps/android/data/src/main/kotlin/com/sanvya/app/data/repository/AssistantRepository.kt", "mirrors web's major(), vector-pinned"],
  ["apps/ios/Data/Sources/Data/AssistantRepository.swift", "mirrors web's major(), vector-pinned"],
  // The helpers that DEFINE the conversion.
  ["apps/android/app/src/main/java/com/sanvya/app/ui/MoneyFormat.kt", "defines majorScale"],
  ["apps/ios/App/Components/MoneyFormat.swift", "defines majorScale"],
]);

/** A `100` that is plainly a percentage, not a minor-unit scale. */
const PERCENT = /pct|Pct|percent|Percent|PERCENT|progress|ratio|%|share|Share|threshold|Threshold|confidence|Confidence/;

/** Date arithmetic: the Gregorian century rule, not money. */
const CALENDAR = /yoe|doe|doy|year|Year|leap|Leap/;

const SUSPECT = [
  // `(?![\d_])` matters twice: QTY_SCALE is 1000 and milli-quantities are not
  // money, and `100_000` is the lakh breakpoint, not a minor-unit scale.
  /\/\s*100(\.0)?[fF]?(?![\d_])/,
  /\*\s*100(\.0)?[fF]?(?![\d_])\s*\)/,
  /\*\s*100(\.0)?[fF]?(?![\d_])\s*$/,
  /round\([^)]*\*\s*100(?![\d_])/,
];

/**
 * `(a / b) * 100` is "what fraction of", not a minor-unit scale.
 *
 * The shape is unambiguous -- a division and a multiplication by 100 in one
 * expression is a percentage every time -- and it saves five real percentage
 * formulas from needing an allowlist entry that would then also excuse the
 * money code in the same file.
 */
const PERCENTAGE_OF = /\/[^*]*\*\s*100(?!\d)/;

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (name.endsWith(".kt") || name.endsWith(".swift")) out.push(p);
  }
  return out;
}

const hits = [];
let scanned = 0;
let skippedPercent = 0;
let allowed = 0;

for (const root of ROOTS) {
  for (const file of walk(root)) {
    scanned++;
    const lines = readFileSync(file, "utf8").split("\n");
    let inBlockComment = false;
    lines.forEach((line, i) => {
      const t = line.trim();
      // Comments are prose about the rule, not the rule.
      if (inBlockComment) {
        if (t.includes("*/")) inBlockComment = false;
        return;
      }
      if (t.startsWith("/*")) { if (!t.includes("*/")) inBlockComment = true; return; }
      if (t.startsWith("//") || t.startsWith("*") || t.startsWith("///")) return;
      if (!SUSPECT.some((r) => r.test(line))) return;
      if (PERCENT.test(line) || PERCENTAGE_OF.test(line)) { skippedPercent++; return; }
      if (CALENDAR.test(line)) { skippedPercent++; return; }
      if (ALLOWED.has(file)) { allowed++; return; }
      hits.push(`${file}:${i + 1}: ${t.slice(0, 110)}`);
    });
  }
}

console.log(
  `money-scale: ${scanned} files, ${skippedPercent} percentage/calendar line(s) skipped, ` +
    `${allowed} allowed site(s), ${hits.length} hit(s)`,
);
for (const h of hits) console.log(`  ${h}`);
if (hits.length > 0) {
  console.log(
    "\nUse fromMajor(major, currency) / toMajor(money(minor, currency)) for an exact amount,\n" +
      "or majorScale(currency) for a Double already in flight. If the 100 is genuinely correct,\n" +
      "add the file to ALLOWED in this script WITH A REASON.",
  );
}
process.exit(hits.length === 0 ? 0 : 1);
