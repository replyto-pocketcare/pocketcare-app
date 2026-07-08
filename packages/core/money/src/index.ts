/**
 * @pocketcare/money — currency-aware money primitives.
 *
 * INVARIANTS (see ARCHITECTURE.md §2):
 *  - A Money value is an INTEGER count of minor units + an ISO 4217 currency.
 *    Never floats for storage/arithmetic.
 *  - Values are stored in their native currency and NEVER mutated in place;
 *    conversion produces a NEW Money in the target currency.
 *  - Arithmetic across different currencies throws unless you convert first.
 */
import type { CurrencyCode } from "@pocketcare/types";

export interface Money {
  /** Integer amount in minor units (e.g. cents, paise). */
  readonly amount: number;
  readonly currency: CurrencyCode;
}

export class CurrencyMismatchError extends Error {
  constructor(a: CurrencyCode, b: CurrencyCode) {
    super(`Currency mismatch: ${a} vs ${b}`);
    this.name = "CurrencyMismatchError";
  }
}

/** Number of minor-unit decimal places for a currency (USD=2, JPY=0, BHD=3). */
export function minorUnits(currency: CurrencyCode): number {
  try {
    const fmt = new Intl.NumberFormat("en", { style: "currency", currency });
    return fmt.resolvedOptions().maximumFractionDigits ?? 2;
  } catch {
    return 2;
  }
}

/** Round half away from zero — deterministic and symmetric for +/- amounts. */
function roundHalfAwayFromZero(n: number): number {
  return Math.sign(n) * Math.round(Math.abs(n));
}

/** Construct Money from an already-minor-unit integer. */
export function money(amount: number, currency: CurrencyCode): Money {
  if (!Number.isInteger(amount)) {
    throw new Error(`Money.amount must be an integer minor-unit value, got ${amount}`);
  }
  return { amount, currency };
}

/** Construct Money from a human/major value (e.g. 12.34 USD -> 1234). */
export function fromMajor(value: number, currency: CurrencyCode): Money {
  const factor = 10 ** minorUnits(currency);
  return money(roundHalfAwayFromZero(value * factor), currency);
}

/** Major-unit number (e.g. 1234 cents -> 12.34). For display/formatting only. */
export function toMajor(m: Money): number {
  return m.amount / 10 ** minorUnits(m.currency);
}

export const isZero = (m: Money): boolean => m.amount === 0;
export const isNegative = (m: Money): boolean => m.amount < 0;

function assertSameCurrency(a: Money, b: Money): void {
  if (a.currency !== b.currency) throw new CurrencyMismatchError(a.currency, b.currency);
}

export function add(a: Money, b: Money): Money {
  assertSameCurrency(a, b);
  return money(a.amount + b.amount, a.currency);
}

export function subtract(a: Money, b: Money): Money {
  assertSameCurrency(a, b);
  return money(a.amount - b.amount, a.currency);
}

export function negate(m: Money): Money {
  return money(-m.amount, m.currency);
}

/** Multiply by a scalar (e.g. a rate or quantity); rounds to whole minor units. */
export function scale(m: Money, factor: number): Money {
  return money(roundHalfAwayFromZero(m.amount * factor), m.currency);
}

/** Sum a list; empty list requires an explicit currency. */
export function sum(items: readonly Money[], currency?: CurrencyCode): Money {
  if (items.length === 0) {
    if (!currency) throw new Error("sum() of empty list needs a currency");
    return money(0, currency);
  }
  return items.reduce((acc, m) => add(acc, m));
}

/**
 * Convert to another currency using an explicit rate (target per 1 source major).
 * Returns Money in the target currency; the source is unchanged.
 * Rounds to the target currency's minor units.
 */
export function convert(m: Money, to: CurrencyCode, rate: number): Money {
  if (m.currency === to) return m;
  if (!(rate > 0)) throw new Error(`convert() needs a positive rate, got ${rate}`);
  const sourceMajor = toMajor(m);
  const targetMinorFactor = 10 ** minorUnits(to);
  return money(roundHalfAwayFromZero(sourceMajor * rate * targetMinorFactor), to);
}

/**
 * Split a total into `parts` amounts that sum EXACTLY to the total
 * (largest-remainder distribution). Powers the transaction breakdown /
 * "+" sub-item builder so items always reconcile to the total.
 */
export function split(total: Money, parts: number): Money[] {
  if (!Number.isInteger(parts) || parts <= 0) {
    throw new Error(`split() needs a positive integer count, got ${parts}`);
  }
  const base = Math.trunc(total.amount / parts);
  let remainder = total.amount - base * parts;
  const step = Math.sign(remainder) || 1;
  remainder = Math.abs(remainder);
  const out: Money[] = [];
  for (let i = 0; i < parts; i++) {
    const extra = i < remainder ? step : 0;
    out.push(money(base + extra, total.currency));
  }
  return out;
}

/** True when breakdown items sum exactly to the transaction total (invariant #5). */
export function itemsReconcile(total: Money, items: readonly Money[]): boolean {
  if (items.length === 0) return total.amount === 0;
  // Any item in a different currency can never reconcile.
  if (items.some((m) => m.currency !== total.currency)) return false;
  return sum(items, total.currency).amount === total.amount;
}

const CURRENCY_LOCALES: Record<string, string> = {
  AED: "ar-AE",
  AFN: "fa-AF",
  ALL: "sq-AL",
  AMD: "hy-AM",
  ANG: "nl-CW",
  AOA: "pt-AO",
  ARS: "es-AR",
  AUD: "en-AU",
  AWG: "nl-AW",
  AZN: "az-AZ",
  BAM: "bs-BA",
  BBD: "en-BB",
  BDT: "bn-BD",
  BGN: "bg-BG",
  BHD: "ar-BH",
  BIF: "fr-BI",
  BMD: "en-BM",
  BND: "ms-BN",
  BOB: "es-BO",
  BRL: "pt-BR",
  BSD: "en-BS",
  BTN: "dz-BT",
  BWP: "en-BW",
  BYN: "be-BY",
  BZD: "en-BZ",
  CAD: "en-CA",
  CDF: "fr-CD",
  CHF: "de-CH",
  CLP: "es-CL",
  CNY: "zh-CN",
  COP: "es-CO",
  CRC: "es-CR",
  CUP: "es-CU",
  CVE: "pt-CV",
  CZK: "cs-CZ",
  DJF: "fr-DJ",
  DKK: "da-DK",
  DOP: "es-DO",
  DZD: "ar-DZ",
  EGP: "ar-EG",
  ERN: "ti-ER",
  ETB: "am-ET",
  EUR: "de-DE",
  FJD: "en-FJ",
  FKP: "en-FK",
  FOK: "en-FO",
  GBP: "en-GB",
  GEL: "ka-GE",
  GGP: "en-GG",
  GHS: "en-GH",
  GIP: "en-GI",
  GMD: "en-GM",
  GNF: "fr-GN",
  GTQ: "es-GT",
  GYD: "en-GY",
  HKD: "zh-HK",
  HNL: "es-HN",
  HRK: "hr-HR",
  HTG: "fr-HT",
  HUF: "hu-HU",
  IDR: "id-ID",
  ILS: "he-IL",
  IMP: "en-IM",
  INR: "en-IN",
  IQD: "ar-IQ",
  IRR: "fa-IR",
  ISK: "is-IS",
  JEP: "en-JE",
  JMD: "en-JM",
  JOD: "ar-JO",
  JPY: "ja-JP",
  KES: "en-KE",
  KGS: "ky-KG",
  KHR: "km-KH",
  KID: "en-KI",
  KMF: "fr-KM",
  KRW: "ko-KR",
  KWD: "ar-KW",
  KYD: "en-KY",
  KZT: "kk-KZ",
  LAK: "lo-LA",
  LBP: "ar-LB",
  LKR: "si-LK",
  LRD: "en-LR",
  LSL: "st-LS",
  LYD: "ar-LY",
  MAD: "ar-MA",
  MDL: "ro-MD",
  MGA: "mg-MG",
  MKD: "mk-MK",
  MMK: "my-MM",
  MNT: "mn-MN",
  MOP: "zh-MO",
  MRU: "ar-MR",
  MUR: "en-MU",
  MVR: "dv-MV",
  MWK: "en-MW",
  MXN: "es-MX",
  MYR: "ms-MY",
  MZN: "pt-MZ",
  NAD: "en-NA",
  NGN: "en-NG",
  NIO: "es-NI",
  NOK: "no-NO",
  NPR: "ne-NP",
  NZD: "en-NZ",
  OMR: "ar-OM",
  PAB: "es-PA",
  PEN: "es-PE",
  PGK: "en-PG",
  PHP: "en-PH",
  PKR: "ur-PK",
  PLN: "pl-PL",
  PYG: "es-PY",
  QAR: "ar-QA",
  RON: "ro-RO",
  RSD: "sr-RS",
  RUB: "ru-RU",
  RWF: "rw-RW",
  SAR: "ar-SA",
  SBD: "en-SB",
  SCR: "en-SC",
  SDG: "ar-SD",
  SEK: "sv-SE",
  SGD: "en-SG",
  SHP: "en-SH",
  SLE: "en-SL",
  SLL: "en-SL",
  SOS: "so-SO",
  SRD: "nl-SR",
  SSP: "en-SS",
  STN: "pt-ST",
  SYP: "ar-SY",
  SZL: "en-SZ",
  THB: "th-TH",
  TJS: "tg-TJ",
  TMT: "tk-TM",
  TND: "ar-TND",
  TOP: "to-TO",
  TRY: "tr-TR",
  TTD: "en-TT",
  TVD: "en-TV",
  TWD: "zh-TW",
  TZS: "sw-TZ",
  UAH: "uk-UA",
  UGX: "en-UG",
  USD: "en-US",
  UYU: "es-UY",
  UZS: "uz-UZ",
  VES: "es-VE",
  VND: "vi-VN",
  VUV: "en-VU",
  WST: "sm-WS",
  XAF: "fr-CM",
  XCD: "en-AG",
  XOF: "fr-SN",
  XPF: "fr-PF",
  YER: "ar-YE",
  ZAR: "en-ZA",
  ZMW: "en-ZM",
  ZWL: "en-ZW",
};

/** Locale-aware currency string, e.g. format(money(123456,"INR"),"en-IN") -> "₹1,234.56". */
export function format(m: Money, locale?: string): string {
  // Ignore "en" or "en-US" to prioritize the currency's native locale for correct grouping (e.g. INR)
  const finalLocale = (locale && locale !== "en" && locale !== "en-US") 
    ? locale 
    : (CURRENCY_LOCALES[m.currency] || "en-US");

  return new Intl.NumberFormat(finalLocale, {
    style: "currency",
    currency: m.currency,
  }).format(toMajor(m));
}
