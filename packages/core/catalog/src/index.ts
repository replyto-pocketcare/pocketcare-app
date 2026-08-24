/**
 * The option lists every form in the app offers.
 *
 * One declaration each, here, because the alternative is what this package
 * replaced: the nine-currency list existed **twelve** times across the three
 * apps (four in `apps/web`, four in Kotlin, four in Swift), plus two divergent
 * three-item variants in the Splits pickers that nobody had noticed were
 * different. Adding a currency meant finding all twelve.
 *
 * Native does not import this file — `tools/parity/generate-options.mjs`
 * emits `FormOptions.kt` and `FormOptions.swift` from it, the same way tokens
 * and strings are generated. So the list is edited in exactly one place and
 * three apps move together, and CI fails if a generated file drifts from it.
 *
 * These are *offered* options, not the set of currencies the app can handle:
 * `@sanvya/money` knows the minor units of every ISO 4217 code, and an account
 * synced from elsewhere in a currency absent from this list still formats
 * correctly. This list is only what a picker shows.
 */

/** Currencies offered in every picker. */
export const CURRENCIES = [
  "INR", "USD", "EUR", "GBP", "JPY", "AUD", "CAD", "SGD", "AED",
] as const;

/**
 * The fallback when nothing else is known — a new install before Settings has
 * been opened, or a row whose currency column is null.
 *
 * **This is the only place `"INR"` should appear as a default in any of the
 * three apps.** Everywhere else reads the user's base-currency setting.
 */
export const DEFAULT_CURRENCY = "INR";

/** Budget/recurring periods. Mirrors `Period` in `@sanvya/types`. */
export const PERIODS = ["daily", "weekly", "monthly", "yearly"] as const;

/** The account types a user can create. */
export const ACCOUNT_TYPES = [
  "savings", "current", "credit_card", "cash", "mutual_funds", "stocks", "demat",
] as const;

/**
 * Account/card palette — earthy base with a few jewel tones.
 *
 * Hex, not a platform colour type: this is what gets persisted to the
 * `accounts.color` column, so all three apps must agree on the string. Each
 * platform converts at its single point of use.
 */
export const ACCOUNT_COLORS = [
  "#3e4a38", // forest
  "#5f6647", // olive
  "#6b7a4f", // moss
  "#9cae8e", // sage
  "#b06a4f", // terracotta
  "#c98a72", // clay
  "#a8503a", // rust
  "#7c4a3a", // sienna
  "#5f4636", // coffee
  "#c9b79c", // sand
  "#c08a3e", // gold
  "#4f46e5", // indigo
  "#6d5acf", // violet
  "#3f5a8a", // denim
  "#2f6f6a", // teal
  "#7a4a6b", // plum
  "#4b5563", // slate
  "#2b2723", // ink
] as const;

export const DEFAULT_ACCOUNT_COLOR: string = ACCOUNT_COLORS[0];

/** Used when an account has no colour set. */
export const FALLBACK_ACCOUNT_COLOR = "#7c7264";

/**
 * A stable colour for an id, when none was chosen.
 *
 * Deterministic so the same account is the same colour on every device and in
 * every session — a random pick would make the app look different on a phone
 * and a tablet showing the same data.
 */
export function colorForId(
  id: string | null | undefined,
  fallback: string = FALLBACK_ACCOUNT_COLOR,
): string {
  if (!id) return fallback;
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) >>> 0;
  return ACCOUNT_COLORS[h % ACCOUNT_COLORS.length] ?? fallback;
}

/** Profile options. Value is what is stored; the label is translated at render. */
export const GENDERS = [
  { value: "", tkey: "gender.unspecified", label: "Not specified" },
  { value: "female", tkey: "gender.female", label: "Female" },
  { value: "male", tkey: "gender.male", label: "Male" },
  { value: "non-binary", tkey: "gender.nonBinary", label: "Non-binary" },
  { value: "prefer not to say", tkey: "gender.preferNotToSay", label: "Prefer not to say" },
] as const;

/** ISO 3166-1 alpha-2, plus "" for unset and "Other". */
export const COUNTRIES = [
  "", "IN", "US", "GB", "CA", "AU", "SG", "AE", "DE", "FR", "NL", "JP", "BR", "ZA", "NG", "KE", "Other",
] as const;
