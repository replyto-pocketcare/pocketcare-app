#!/usr/bin/env node
/**
 * tools/parity/generate-options.mjs
 *
 * The form option lists — currencies, periods, account types, the account
 * colour palette, genders, countries — emitted for both native platforms from
 * their one source: `packages/core/catalog/src/index.ts`.
 *
 * Why generated rather than ported by hand: before this existed, the
 * nine-currency array was declared TWELVE times across the three apps, and two
 * of those twelve had quietly become three-item lists. Nothing catches that
 * kind of drift by review — the lists are in different files, in different
 * languages, and each one looks fine on its own.
 *
 * `colorForId` comes along with the palette deliberately. It is the one piece
 * of behaviour attached to this data, and a platform that had the colours but
 * re-implemented the hash would give the same account a different colour on
 * phone and web.
 *
 * Emits:
 *   apps/android/app/src/main/java/com/sanvya/app/ui/FormOptions.kt
 *   apps/ios/App/FormOptions.swift
 *
 * Usage: node tools/parity/generate-options.mjs
 */

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = process.env.SANVYA_REPO_ROOT
  ? path.resolve(process.env.SANVYA_REPO_ROOT)
  : path.resolve(__dirname, "../..");

const SRC = path.join(REPO_ROOT, "packages/core/catalog/src/index.ts");
const ANDROID_OUT = path.join(
  REPO_ROOT,
  "apps/android/app/src/main/java/com/sanvya/app/ui/FormOptions.kt",
);
const IOS_OUT = path.join(REPO_ROOT, "apps/ios/App/FormOptions.swift");

const src = readFileSync(SRC, "utf8");

// INVESTMENT_ACCOUNT_TYPES lives in packages/types, not the catalog: it is a
// behavioural rule about which accounts can move money, not a picker's option
// list. Read as a second source rather than duplicated into the catalog.
const TYPES_SRC = path.join(REPO_ROOT, "packages/types/src/index.ts");
const typesSrc = readFileSync(TYPES_SRC, "utf8");

/** Pull a `export const NAME = [ … ] as const;` string array out of the source. */
function stringArray(name) {
  const m = src.match(new RegExp(`export const ${name} = \\[([\\s\\S]*?)\\] as const;`));
  if (!m) throw new Error(`generate-options: ${name} not found in ${SRC}`);
  return [...m[1].matchAll(/"([^"]*)"/g)].map((x) => x[1]);
}

function scalar(name) {
  const m = src.match(new RegExp(`export const ${name}(?::\\s*\\w+)? = "([^"]*)"`));
  if (!m) throw new Error(`generate-options: ${name} not found in ${SRC}`);
  return m[1];
}

/** The genders table is objects, not bare strings. */
function genders() {
  const m = src.match(/export const GENDERS = \[([\s\S]*?)\] as const;/);
  if (!m) throw new Error("generate-options: GENDERS not found");
  const rows = [...m[1].matchAll(/\{ value: "([^"]*)", label: "([^"]*)" \}/g)]
    .map(([, value, label]) => ({ value, label }));
  // A silent zero here would emit an empty picker that looks intentional.
  if (rows.length === 0) throw new Error("generate-options: GENDERS parsed to 0 rows");
  return rows;
}

const CURRENCIES = stringArray("CURRENCIES");
const PERIODS = stringArray("PERIODS");
const ACCOUNT_TYPES = stringArray("ACCOUNT_TYPES");

/**
 * INVESTMENT_ACCOUNT_TYPES, resolved through the AccountType map.
 *
 * `stringArray` cannot read it: unlike every other list here it is declared as
 * `readonly AccountType[]` rather than `as const`, and its entries are
 * `AccountType.Demat`-style references rather than string literals.
 *
 * It matters enough to generate rather than retype. Accounts that only RECORD
 * investments cannot pay a bill or settle a split — money would have to be
 * sold, settled and withdrawn first — so every picker that moves real money
 * filters on this list. Three strings copied into two native codebases is three
 * strings that silently stop matching the day a fourth type is added.
 */
function investmentAccountTypes() {
  const map = typesSrc.match(/export const AccountType = \{([\s\S]*?)\} as const;/);
  if (!map) throw new Error("generate-options: AccountType map not found");
  const byName = Object.fromEntries(
    [...map[1].matchAll(/(\w+):\s*"([^"]*)"/g)].map(([, name, value]) => [name, value]),
  );

  const list = typesSrc.match(/export const INVESTMENT_ACCOUNT_TYPES[^=]*=\s*\[([\s\S]*?)\];/);
  if (!list) throw new Error("generate-options: INVESTMENT_ACCOUNT_TYPES not found");
  const values = [...list[1].matchAll(/AccountType\.(\w+)/g)].map(([, name]) => {
    const value = byName[name];
    // A silent undefined here would emit a filter that excludes nothing, i.e.
    // demat accounts quietly offered as a way to pay a credit card bill.
    if (!value) throw new Error(`generate-options: AccountType.${name} has no value`);
    return value;
  });
  if (values.length === 0) throw new Error("generate-options: INVESTMENT_ACCOUNT_TYPES parsed to 0 rows");
  return values;
}

const INVESTMENT_ACCOUNT_TYPES = investmentAccountTypes();
const ACCOUNT_COLORS = stringArray("ACCOUNT_COLORS");

/**
 * The two CHART palettes, which are not the account palette and not each other.
 *
 * Web keeps them in two files and they have drifted: INSIGHT_PALETTE's own
 * comment says it "matches the Insights page PIE", and it does not -- the last
 * two entries differ. Native had copied one of them by hand into a `private`
 * val inside InsightsScreen, so there were four copies across the repo and no
 * way to notice the fifth being wrong.
 *
 * Ported verbatim, drift included. PIE's `#4f46e5` is an indigo in a palette
 * that is otherwise entirely earth-toned, and it is REACHED -- the spending
 * tile charts seven categories, so it colours the seventh bar. That looks like
 * a stray Tailwind default rather than a decision, but it is web's decision to
 * unmake, not this port's. Flagged in PARITY_AUDIT.md §"Web bugs found while
 * porting".
 */
const INSIGHTS_SRC = path.join(REPO_ROOT, "apps/web/src/insights/types.ts");
const TILES_SRC = path.join(REPO_ROOT, "apps/web/src/dashboard/tiles.tsx");
const hexArray = (src, decl, what) => {
  const m = src.match(new RegExp(`${decl}[^\\[]*\\[([^\\]]*)\\]`));
  if (!m) throw new Error(`generate-options: ${what} not found`);
  const out = [...m[1].matchAll(/"(#[0-9a-fA-F]{6})"/g)].map((x) => x[1]);
  if (!out.length) throw new Error(`generate-options: ${what} parsed to an empty list`);
  return out;
};
const CHART_PALETTE = hexArray(readFileSync(INSIGHTS_SRC, "utf8"), "export const INSIGHT_PALETTE", "INSIGHT_PALETTE");
const DASHBOARD_PALETTE = hexArray(readFileSync(TILES_SRC, "utf8"), "const PIE", "the dashboard PIE palette");
const COUNTRIES = stringArray("COUNTRIES");
const GENDERS = genders();
const DEFAULT_CURRENCY = scalar("DEFAULT_CURRENCY");
const FALLBACK_ACCOUNT_COLOR = scalar("FALLBACK_ACCOUNT_COLOR");

const banner = (comment) => `${comment} GENERATED FILE — do not hand-edit.
${comment} Source: packages/core/catalog/src/index.ts
${comment} Regenerate with: node tools/parity/generate-options.mjs`;

const ktList = (xs) => xs.map((x) => `"${x}"`).join(", ");
const swiftList = (xs) => xs.map((x) => `"${x}"`).join(", ");

// ---------------------------------------------------------------- Android

const androidKt = `package com.sanvya.app.ui

${banner("//")}

/**
 * The option lists every form offers.
 *
 * These are *offered* options, not the currencies the app can handle: the
 * money layer knows the minor units of every ISO 4217 code, and an account
 * synced in a currency absent from this list still formats correctly. This is
 * only what a picker shows.
 */
object FormOptions {
    val currencies = listOf(${ktList(CURRENCIES)})

    /**
     * The fallback when nothing else is known — a fresh install, or a row whose
     * currency column is null. The ONLY place a currency literal belongs;
     * everywhere else reads the user's base-currency setting.
     */
    const val DEFAULT_CURRENCY = "${DEFAULT_CURRENCY}"

    val periods = listOf(${ktList(PERIODS)})

    val accountTypes = listOf(${ktList(ACCOUNT_TYPES)})

    /**
     * Accounts that only RECORD investments — they hold holdings, not spendable
     * money. Every picker that moves real money filters these out.
     */
    val investmentAccountTypes = listOf(${ktList(INVESTMENT_ACCOUNT_TYPES)})

    /** True when the type is an investment account. Mirrors web isInvestmentAccount. */
    fun isInvestmentAccount(type: String?): Boolean = !type.isNullOrEmpty() && type in investmentAccountTypes

    /**
     * Hex, not \`Color\`: this is what gets written to \`accounts.color\`, so all
     * three apps must agree on the string. Converted at the point of use.
     */
    val accountColors = listOf(${ktList(ACCOUNT_COLORS)})

    val defaultAccountColor = accountColors.first()

    /** Insights' multi-series palette -- web's INSIGHT_PALETTE. */
    val chartColors = listOf(${ktList(CHART_PALETTE)})

    /** The dashboard tiles' palette -- web's PIE. NOT the same list. */
    val dashboardChartColors = listOf(${ktList(DASHBOARD_PALETTE)})

    const val FALLBACK_ACCOUNT_COLOR = "${FALLBACK_ACCOUNT_COLOR}"

    /**
     * \`value\` is what is stored. \`label\` is English and NOT yet translated —
     * there are no \`gender.*\` keys in the i18n on any platform. See the note
     * in packages/core/catalog.
     */
    data class Option(val value: String, val label: String)

    val genders = listOf(
${GENDERS.map((g) => `        Option("${g.value}", "${g.label}"),`).join("\n")}
    )

    val countries = listOf(${ktList(COUNTRIES)})

    /**
     * A stable colour for an id, when none was chosen.
     *
     * Deterministic so the same account is the same colour on every device and
     * in every session. Ported with the palette rather than re-implemented,
     * because a platform that re-derived the hash would disagree with web about
     * a colour the user has already seen.
     */
    fun colorForId(id: String?, fallback: String = FALLBACK_ACCOUNT_COLOR): String {
        if (id.isNullOrEmpty()) return fallback
        var h = 0u
        for (c in id) h = (h * 31u + c.code.toUInt())
        return accountColors[(h % accountColors.size.toUInt()).toInt()]
    }
}
`;

// -------------------------------------------------------------------- iOS

const iosSwift = `import Foundation

${banner("//")}

/**
 The option lists every form offers.

 These are *offered* options, not the currencies the app can handle: the money
 layer knows the minor units of every ISO 4217 code, and an account synced in a
 currency absent from this list still formats correctly. This is only what a
 picker shows.
 */
public enum FormOptions {
    public static let currencies = [${swiftList(CURRENCIES)}]

    /**
     The fallback when nothing else is known — a fresh install, or a row whose
     currency column is null. The ONLY place a currency literal belongs;
     everywhere else reads the user's base-currency setting.
     */
    public static let defaultCurrency = "${DEFAULT_CURRENCY}"

    public static let periods = [${swiftList(PERIODS)}]

    public static let accountTypes = [${swiftList(ACCOUNT_TYPES)}]

    /// Accounts that only RECORD investments — they hold holdings, not
    /// spendable money. Every picker that moves real money filters these out.
    public static let investmentAccountTypes = [${swiftList(INVESTMENT_ACCOUNT_TYPES)}]

    /// True when the type is an investment account. Mirrors web isInvestmentAccount.
    public static func isInvestmentAccount(_ type: String?) -> Bool {
        guard let type, !type.isEmpty else { return false }
        return investmentAccountTypes.contains(type)
    }

    /**
     Hex, not \`Color\`: this is what gets written to \`accounts.color\`, so all
     three apps must agree on the string. Converted at the point of use.
     */
    public static let accountColors = [${swiftList(ACCOUNT_COLORS)}]

    public static let defaultAccountColor = accountColors[0]

    /// Insights' multi-series palette — web's INSIGHT_PALETTE.
    public static let chartColors = [${swiftList(CHART_PALETTE)}]

    /// The dashboard tiles' palette — web's PIE. NOT the same list.
    public static let dashboardChartColors = [${swiftList(DASHBOARD_PALETTE)}]

    public static let fallbackAccountColor = "${FALLBACK_ACCOUNT_COLOR}"

    /// \`value\` is what is stored. \`label\` is English and NOT yet translated —
    /// there are no \`gender.*\` keys in the i18n on any platform. See the note
    /// in packages/core/catalog.
    public struct Option: Identifiable, Sendable {
        public let value: String
        public let label: String
        public var id: String { value }
    }

    public static let genders: [Option] = [
${GENDERS.map((g) => `        Option(value: "${g.value}", label: "${g.label}"),`).join("\n")}
    ]

    public static let countries = [${swiftList(COUNTRIES)}]

    /**
     A stable colour for an id, when none was chosen.

     Deterministic so the same account is the same colour on every device and in
     every session. Ported with the palette rather than re-implemented, because
     a platform that re-derived the hash would disagree with web about a colour
     the user has already seen.
     */
    public static func colorForId(_ id: String?, fallback: String = fallbackAccountColor) -> String {
        guard let id, !id.isEmpty else { return fallback }
        // \`utf16\`, not \`unicodeScalars\`: the source is JavaScript's
        // \`charCodeAt\`, which yields UTF-16 code UNITS. Scalars would agree on
        // everything in the BMP and silently diverge on an emoji — and account
        // ids are user-supplied often enough for that to matter one day.
        var h: UInt32 = 0
        for unit in id.utf16 {
            h = h &* 31 &+ UInt32(unit)
        }
        return accountColors[Int(h % UInt32(accountColors.count))]
    }
}
`;

for (const [out, body] of [[ANDROID_OUT, androidKt], [IOS_OUT, iosSwift]]) {
  mkdirSync(path.dirname(out), { recursive: true });
  writeFileSync(out, body);
}

console.log(
  `catalog: ${CURRENCIES.length} currencies, ${PERIODS.length} periods, ` +
    `${ACCOUNT_TYPES.length} account types (${INVESTMENT_ACCOUNT_TYPES.length} investment), ${ACCOUNT_COLORS.length} colours, ` +
    `${CHART_PALETTE.length}+${DASHBOARD_PALETTE.length} chart colours, ` +
    `${GENDERS.length} genders, ${COUNTRIES.length} countries.`,
);
console.log("Wrote:");
console.log(` - ${path.relative(REPO_ROOT, ANDROID_OUT)}`);
console.log(` - ${path.relative(REPO_ROOT, IOS_OUT)}`);
