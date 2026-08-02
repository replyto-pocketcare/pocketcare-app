/**
 * Parsing money and quantities out of OCR text.
 *
 * Deliberately separate from `@sanvya/money`: that package deals in
 * already-trusted values, this one deals in whatever a thermal printer and an
 * OCR engine conspired to produce. Everything here returns `null` rather than
 * guessing, because a wrong amount is far worse than an unread one.
 */

/** Currency symbols/codes we strip before parsing, and map for detection. */
export const CURRENCY_SYMBOLS: ReadonlyArray<readonly [RegExp, string]> = [
  [/₹|\brs\.?\b|\binr\b/i, "INR"],
  [/\$|\busd\b/i, "USD"],
  [/€|\beur\b/i, "EUR"],
  [/£|\bgbp\b/i, "GBP"],
  [/¥|\bjpy\b/i, "JPY"],
  [/\baed\b|\bdhs?\b/i, "AED"],
];

/** First currency mentioned anywhere in the text, or null. */
export function detectCurrency(text: string): string | null {
  for (const [re, code] of CURRENCY_SYMBOLS) if (re.test(text)) return code;
  return null;
}

/**
 * Parse a money-ish string to integer minor units.
 *
 * Handles both separator conventions by looking at what comes AFTER the last
 * separator rather than assuming a locale: `1,234.56` and `1.234,56` both give
 * 123456, and Indian lakh grouping (`1,23,456`) falls out for free.
 */
export function parseMoney(raw: string, minorDigits = 2): number | null {
  let s = raw.trim();
  if (!s) return null;

  let negative = false;
  if (/^\(.*\)$/.test(s)) { negative = true; s = s.slice(1, -1); }     // (12.34)
  if (/-\s*$/.test(s)) negative = true;                                 // 12.34-

  s = s.replace(/[^\d.,-]/g, "");
  if (s.startsWith("-")) negative = true;
  s = s.replace(/-/g, "");
  if (!/\d/.test(s)) return null;

  // More than 12 digits is a phone number, GSTIN or invoice reference.
  if ((s.match(/\d/g) ?? []).length > 12) return null;

  const lastDot = s.lastIndexOf(".");
  const lastComma = s.lastIndexOf(",");
  const lastSep = Math.max(lastDot, lastComma);
  let decIdx = -1;
  if (lastSep >= 0) {
    const after = s.length - lastSep - 1;
    const bothPresent = lastDot >= 0 && lastComma >= 0;
    // Both separators present: the last one must be the decimal point.
    // Only one: it is a decimal point when it isn't grouping three digits.
    if (bothPresent) decIdx = lastSep;
    else if (after === minorDigits || after === 1) decIdx = lastSep;
  }

  const intPart = (decIdx >= 0 ? s.slice(0, decIdx) : s).replace(/[.,]/g, "");
  let fracPart = (decIdx >= 0 ? s.slice(decIdx + 1) : "").replace(/[.,]/g, "");
  if (!intPart && !fracPart) return null;
  fracPart = (fracPart + "0".repeat(minorDigits)).slice(0, minorDigits);

  const value = Number(intPart || "0") * 10 ** minorDigits + Number(fracPart || "0");
  if (!Number.isFinite(value)) return null;
  return negative ? -value : value;
}

/** A numeric run found in a line, with where it sat. */
export interface NumberMatch {
  readonly raw: string;
  readonly start: number;
  readonly end: number;
  readonly value: number;
}

const NUMBER_RE = /-?\d[\d.,]*\d|-?\d/g;

/** Every parseable number in a line, left to right. */
export function findNumbers(line: string, minorDigits = 2): NumberMatch[] {
  const out: NumberMatch[] = [];
  NUMBER_RE.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = NUMBER_RE.exec(line)) !== null) {
    const value = parseMoney(m[0], minorDigits);
    if (value === null) continue;
    out.push({ raw: m[0], start: m.index, end: m.index + m[0].length, value });
  }
  return out;
}

// ---------------------------------------------------------------------------
// Dates
// ---------------------------------------------------------------------------

const MONTHS: Record<string, number> = {
  jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6,
  jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12,
};

const iso = (y: number, m: number, d: number): string =>
  `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;

const valid = (y: number, m: number, d: number): boolean =>
  m >= 1 && m <= 12 && d >= 1 && d <= 31 && y >= 2000 && y <= 2100;

/**
 * Find a date in receipt text. Day-first (India is the primary market), but an
 * unambiguous day > 12 flips the interpretation. Future dates are rejected —
 * a receipt cannot be from tomorrow, so a "future" read means we misparsed.
 */
export function findDate(text: string, today?: string): string | null {
  const cutoff = today ?? new Date().toISOString().slice(0, 10);
  const candidates: string[] = [];

  // ISO: 2026-07-25
  for (const m of text.matchAll(/\b(\d{4})-(\d{1,2})-(\d{1,2})\b/g)) {
    const y = +m[1]!, mo = +m[2]!, d = +m[3]!;
    if (valid(y, mo, d)) candidates.push(iso(y, mo, d));
  }

  // Numeric: 25/07/2026, 25-07-26, 25.07.2026
  for (const m of text.matchAll(/\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b/g)) {
    let a = +m[1]!, b = +m[2]!;
    const y = m[3]!.length === 2 ? 2000 + +m[3]! : +m[3]!;
    // Day-first unless the second field can only be a day.
    if (b > 12 && a <= 12) { const t = a; a = b; b = t; }
    if (valid(y, b, a)) candidates.push(iso(y, b, a));
  }

  // Textual: 25 Jul 2026 / Jul 25, 2026
  for (const m of text.matchAll(/\b(\d{1,2})[\s\-]([A-Za-z]{3,9})[\s\-,]+(\d{2,4})\b/g)) {
    const d = +m[1]!;
    const mo = MONTHS[m[2]!.slice(0, 3).toLowerCase()];
    const y = m[3]!.length === 2 ? 2000 + +m[3]! : +m[3]!;
    if (mo && valid(y, mo, d)) candidates.push(iso(y, mo, d));
  }
  for (const m of text.matchAll(/\b([A-Za-z]{3,9})[\s\-](\d{1,2})[\s\-,]+(\d{2,4})\b/g)) {
    const mo = MONTHS[m[1]!.slice(0, 3).toLowerCase()];
    const d = +m[2]!;
    const y = m[3]!.length === 2 ? 2000 + +m[3]! : +m[3]!;
    if (mo && valid(y, mo, d)) candidates.push(iso(y, mo, d));
  }

  const usable = candidates.filter((c) => c <= cutoff);
  if (usable.length === 0) return null;
  // The latest plausible date: receipts print the transaction date alongside
  // older things like "member since" or a validity date.
  return usable.sort()[usable.length - 1]!;
}

// ---------------------------------------------------------------------------
// Quantities
// ---------------------------------------------------------------------------

export const UNIT_WORDS =
  "kg|kgs|g|gm|gms|gram|grams|l|ltr|ltrs|litre|litres|ml|pcs|pc|piece|pieces|nos|no|unit|units|dozen|dz|pkt|pack|packs|box|btl|bottle|bottles";

// A unit only counts when it directly follows a number. Without that anchor,
// the single-letter units match inside ordinary words — "Parle-G" reads as
// grams, "Model L" as litres.
const UNIT_RE = new RegExp(`\\d\\s*(${UNIT_WORDS})\\b`, "i");

/** Canonical-ish unit label, or null. Keeps whatever the receipt printed. */
export function findUnit(text: string): string | null {
  const m = text.match(UNIT_RE);
  return m ? m[1]!.toLowerCase() : null;
}

/** Trailing currency symbols and separators left behind after slicing an amount off. */
export function tidyDescription(text: string): string {
  return text
    .replace(/[₹$€£¥]|\b(rs|inr|usd|eur|gbp)\b\.?/gi, " ")
    .replace(/[\s\-–:|@.,*]+$/, "")
    .replace(/^[\s\-–:|@.,*]+/, "")
    .replace(/\s+/g, " ")
    .trim();
}
