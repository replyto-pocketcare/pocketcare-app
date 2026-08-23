#!/usr/bin/env node
/**
 * tools/parity/generate-money-format.mjs
 *
 * The currency→locale table that money formatting depends on, emitted for both
 * native platforms from its one source: `CURRENCY_LOCALES` in
 * `packages/core/money/src/index.ts`.
 *
 * Why this is generated rather than ported by hand: it is 161 entries, and
 * `format()` is the one part of `@sanvya/money` with NO golden vectors — it
 * delegates to `Intl.NumberFormat`, which has no cross-platform equivalent to
 * assert against. So nothing would have caught it drifting. The table is
 * mechanical; the drift risk is not.
 *
 * The formatter itself is small enough to live alongside the table, and is
 * emitted here too so the two stay together: web picks the currency's NATIVE
 * locale (so INR groups as 1,00,000 — lakh/crore — rather than 100,000) unless
 * the caller passes a specific non-English locale, and native does the same.
 *
 * Emits:
 *   apps/ios/Domain/Sources/Domain/MoneyFormat.swift
 *   apps/android/domain/src/main/kotlin/com/sanvya/app/domain/money/MoneyFormat.kt
 *
 * Usage: node tools/parity/generate-money-format.mjs
 */

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = process.env.SANVYA_REPO_ROOT
  ? path.resolve(process.env.SANVYA_REPO_ROOT)
  : path.resolve(__dirname, "../..");

const SRC = path.join(REPO_ROOT, "packages/core/money/src/index.ts");
const IOS_OUT = path.join(REPO_ROOT, "apps/ios/Domain/Sources/Domain/MoneyFormat.swift");
const ANDROID_OUT = path.join(
  REPO_ROOT,
  "apps/android/domain/src/main/kotlin/com/sanvya/app/domain/money/MoneyFormat.kt",
);

const src = readFileSync(SRC, "utf8");
const start = src.indexOf("const CURRENCY_LOCALES");
if (start < 0) {
  console.error("CURRENCY_LOCALES not found in packages/core/money/src/index.ts — the source shape changed. Fix this script rather than emitting an empty table.");
  process.exit(1);
}
const block = src.slice(start, src.indexOf("};", start));
const entries = [...block.matchAll(/^\s+([A-Z]{3}):\s*"([A-Za-z-]+)"/gm)].map((m) => [m[1], m[2]]);
if (entries.length === 0) {
  console.error("Parsed 0 currency locales — refusing to emit an empty table.");
  process.exit(1);
}
console.log(`money-format: ${entries.length} currency locales parsed`);

const BANNER = [
  "GENERATED FILE — do not hand-edit.",
  "Source: packages/core/money/src/index.ts (CURRENCY_LOCALES, format)",
  "Regenerate with: node tools/parity/generate-money-format.mjs",
].join("\n");

// Foundation and java.util.Locale both want an underscore, not a hyphen.
const nativeLocale = (tag) => tag.replace("-", "_");

const swift = `import Foundation

// ${BANNER.split("\n").join("\n// ")}

/**
 The locale whose conventions each currency is normally written in.

 Grouping is the reason this exists: INR written in \`en_US\` is 100,000 but in
 \`en_IN\` it is 1,00,000, and every South-Asian currency behaves the same way.
 Mirrors \`CURRENCY_LOCALES\` in packages/core/money.
 */
public let currencyLocales: [String: String] = [
${entries.map(([code, tag]) => `    "${code}": "${nativeLocale(tag)}",`).join("\n")}
]

/**
 Format a \`Money\` for display.

 Mirrors \`format(m, locale)\` in packages/core/money, including its quirk: an
 explicit "en" or "en-US" is IGNORED in favour of the currency's own locale,
 because those two are the defaults callers pass without meaning to choose,
 and honouring them would silently break INR grouping everywhere.

 Fraction digits come from \`minorUnits(currency)\` — never a hardcoded 2. JPY
 has none and BHD has three.
 */
public func format(_ m: Money, locale: String? = nil) -> String {
    let tag: String
    if let locale, locale != "en", locale != "en-US", locale != "en_US" {
        tag = locale.replacingOccurrences(of: "-", with: "_")
    } else {
        tag = currencyLocales[m.currency] ?? "en_US"
    }

    let digits = minorUnits(m.currency)
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = m.currency
    formatter.locale = Locale(identifier: tag)
    formatter.minimumFractionDigits = digits
    formatter.maximumFractionDigits = digits

    let major = NSDecimalNumber(value: m.amount)
        .multiplying(byPowerOf10: Int16(-digits))
    return formatter.string(from: major) ?? "\\(m.currency) \\(major)"
}
`;

const kotlin = `package com.sanvya.app.domain.money

import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

// ${BANNER.split("\n").join("\n// ")}

/**
 * The locale whose conventions each currency is normally written in.
 *
 * Grouping is the reason this exists: INR written in \`en_US\` is 100,000 but in
 * \`en_IN\` it is 1,00,000, and every South-Asian currency behaves the same way.
 * Mirrors \`CURRENCY_LOCALES\` in packages/core/money.
 */
val CURRENCY_LOCALES: Map<String, String> = mapOf(
${entries.map(([code, tag]) => `    "${code}" to "${nativeLocale(tag)}",`).join("\n")}
)

private fun localeOf(tag: String): Locale {
    val parts = tag.split("_")
    return if (parts.size >= 2) Locale(parts[0], parts[1]) else Locale(parts[0])
}

/**
 * Format a [Money] for display.
 *
 * Mirrors \`format(m, locale)\` in packages/core/money, including its quirk: an
 * explicit "en" or "en-US" is IGNORED in favour of the currency's own locale,
 * because those two are the defaults callers pass without meaning to choose,
 * and honouring them would silently break INR grouping everywhere.
 *
 * Fraction digits come from [minorUnits] — never a hardcoded 2. JPY has none
 * and BHD has three.
 */
fun format(m: Money, locale: String? = null): String {
    val tag = if (locale != null && locale != "en" && locale != "en-US" && locale != "en_US") {
        locale.replace("-", "_")
    } else {
        CURRENCY_LOCALES[m.currency] ?: "en_US"
    }

    val digits = minorUnits(m.currency)
    val formatter = NumberFormat.getCurrencyInstance(localeOf(tag)).apply {
        try {
            currency = Currency.getInstance(m.currency)
        } catch (_: IllegalArgumentException) {
            // Not a JDK-known ISO code — the locale's own currency symbol is a
            // better fallback than throwing in the middle of rendering a list.
        }
        minimumFractionDigits = digits
        maximumFractionDigits = digits
    }
    return formatter.format(BigDecimal.valueOf(m.amount).movePointLeft(digits))
}
`;

mkdirSync(path.dirname(IOS_OUT), { recursive: true });
mkdirSync(path.dirname(ANDROID_OUT), { recursive: true });
writeFileSync(IOS_OUT, swift);
writeFileSync(ANDROID_OUT, kotlin);

console.log("Wrote:");
console.log(" -", path.relative(REPO_ROOT, IOS_OUT));
console.log(" -", path.relative(REPO_ROOT, ANDROID_OUT));
