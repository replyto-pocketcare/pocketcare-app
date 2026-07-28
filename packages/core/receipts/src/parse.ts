/**
 * Turning OCR output into a structured receipt.
 *
 * This is pure and engine-agnostic on purpose: it takes positioned tokens (from
 * tesseract) or plain lines (from a PDF text layer) and produces a
 * `ReceiptDraft`. Keeping it out of the browser means it is covered by the
 * `pnpm test:core` fixture suite, which is the only thing standing between us
 * and silent accuracy regressions.
 *
 * Guiding rule: NEVER invent a number. Anything we are unsure of is left off
 * and surfaced to the user by `reconcile()` failing, because a receipt that
 * refuses to save is recoverable and a wrong ledger entry is not.
 */
import { findDate, findNumbers, findUnit, parseMoney, detectCurrency, tidyDescription } from "./money-text.ts";
import type { ReceiptDraft, ReceiptEngine, ReceiptLine, ReceiptLineKind } from "./types.ts";
import { QTY_SCALE } from "./types.ts";

// ---------------------------------------------------------------------------
// Input shapes
// ---------------------------------------------------------------------------

export interface OcrToken {
  readonly text: string;
  readonly x0: number;
  readonly x1: number;
  readonly y0: number;
  readonly y1: number;
  readonly confidence: number;
}

export interface TextLine {
  readonly text: string;
  readonly tokens: readonly OcrToken[];
  /** Vertical centre, used only for ordering. */
  readonly y: number;
  /** Mean token confidence, 0-100. */
  readonly confidence: number;
}

/**
 * Rebuild lines from loose tokens.
 *
 * Tesseract's own line grouping gives up on the two- and three-column layouts
 * that grocery bills use, so we regroup by vertical overlap using the median
 * glyph height as the tolerance — that adapts to the image scale instead of
 * hard-coding pixels.
 */
export function groupIntoLines(tokens: readonly OcrToken[]): TextLine[] {
  if (tokens.length === 0) return [];

  const heights = tokens.map((t) => Math.max(1, t.y1 - t.y0)).sort((a, b) => a - b);
  const medianHeight = heights[Math.floor(heights.length / 2)]!;
  const tolerance = medianHeight * 0.6;

  const sorted = [...tokens].sort((a, b) => (a.y0 + a.y1) / 2 - (b.y0 + b.y1) / 2);
  const rows: OcrToken[][] = [];
  let current: OcrToken[] = [];
  let currentY = Number.NaN;

  for (const t of sorted) {
    const y = (t.y0 + t.y1) / 2;
    if (current.length === 0 || Math.abs(y - currentY) <= tolerance) {
      current.push(t);
      // Running mean keeps a slightly skewed line from drifting away.
      currentY = Number.isNaN(currentY) ? y : (currentY * (current.length - 1) + y) / current.length;
    } else {
      rows.push(current);
      current = [t];
      currentY = y;
    }
  }
  if (current.length > 0) rows.push(current);

  return rows.map((row) => {
    const ordered = [...row].sort((a, b) => a.x0 - b.x0);
    return {
      text: ordered.map((t) => t.text).join(" ").replace(/\s+/g, " ").trim(),
      tokens: ordered,
      y: ordered.reduce((s, t) => s + (t.y0 + t.y1) / 2, 0) / ordered.length,
      confidence: Math.round(ordered.reduce((s, t) => s + t.confidence, 0) / ordered.length),
    };
  });
}

/** Wrap plain text (PDF text layer, or a paste) as lines with no geometry. */
export function linesFromText(text: string, confidence = 100): TextLine[] {
  return text
    .split(/\r?\n/)
    .map((raw, i) => ({ text: raw.replace(/\s+/g, " ").trim(), tokens: [], y: i, confidence }))
    .filter((l) => l.text.length > 0);
}

// ---------------------------------------------------------------------------
// Classification
// ---------------------------------------------------------------------------

/**
 * Lines that carry numbers but are NOT part of the bill's arithmetic.
 * Getting this list wrong is the most common way to double-count: a "CASH 500 /
 * CHANGE 60" footer silently adds 560 to the bill if you let it through.
 */
const IGNORE_PATTERNS: readonly RegExp[] = [
  /\b(cash|change|tendered|tender|card|visa|master(card)?|maestro|rupay|amex|upi|paytm|gpay|phonepe|wallet|pin|contactless)\b/i,
  /\b(balance|due|payable\s*by|received|payment\s*mode|mode\s*of\s*payment)\b.*\b(card|cash|upi)\b/i,
  /\b(gstin|gst\s*no|tin|pan|fssai|cin|vat\s*no|btw[\s-]*nr|tax\s*invoice|invoice\s*(no|#)|bill\s*(no|#)|order\s*(no|#)|receipt\s*(no|#)|token)\b/i,
  /\b(thank\s*you|visit\s*again|welcome|customer\s*copy|merchant\s*copy|bedankt|dhanyavaad|have\s*a\s*(nice|great))\b/i,
  /\b(table|server|waiter|cashier|counter|terminal|till|operator|staff)\b/i,
  // NOTE: no trailing \b after "ph\s*[:.]" — a word boundary cannot follow a
  // colon, which silently disabled this whole alternation.
  /\bphone\b|\btel\b|\bmob(ile)?\b|\bcontact\b|\bph\b\s*[:.]|www\.|https?:|@\w+\.(com|in|co|nl)/i,
  /\b(total\s*(qty|items?|quantity|nos?\.?)|no\.?\s*of\s*items?|item\s*count|aantal)\b/i,
  /\b(points?|loyalty|reward|membership|member\s*since|valid\s*(till|until))\b/i,
  /\b(date|time|dated|datum|tijd|dinank)\b/i,
  /\b(qty|quantity|aantal)\b\s*(x|rate|price|amount|amt)\b/i, // column header row
  /^\s*[-=*_.~]{3,}\s*$/,                                     // separator rule
];

/**
 * Header-zone-only ignores. An address line is full of numbers ("12 MG Road,
 * Bengaluru 560001") and reads exactly like an expensive item, but these words
 * are also plausible product names, so we only suppress them near the top where
 * the shop's own details are printed.
 */
const HEADER_NOISE_RE =
  /\b(road|rd|street|st|marg|nagar|sector|shop\s*no|shop|floor|plot|opp|near|layout|colony|cross|avenue|lane|block|straat|weg|pin\s*code)\b/i;
const HEADER_ZONE_LINES = 5;

/** A line that is essentially just a date, with no label and nothing else. */
function isBareDate(text: string): boolean {
  if (findDate(text, "9999-12-31") === null) return false;
  // Strip everything date-shaped and see whether any real content remains.
  const rest = text
    .replace(/\b\d{1,4}[/\-.]\d{1,2}[/\-.]\d{2,4}\b/g, " ")
    .replace(/\b\d{1,2}[\s\-][A-Za-z]{3,9}[\s\-,]+\d{2,4}\b/g, " ")
    .replace(/\b[A-Za-z]{3,9}[\s\-]\d{1,2}[\s\-,]+\d{2,4}\b/g, " ")
    .replace(/[^A-Za-z]/g, "");
  return rest.length < 3;
}

/**
 * Running subtotals: recorded for cross-checking, never stored as a line.
 * Includes Dutch, since the app ships nl alongside en/hi.
 */
const SUBTOTAL_RE =
  /\b(sub\s*-?\s*total|subtotal|subtotaal|tussentotaal|net\s*amount|taxable\s*(value|amount)|gross\s*amount|item\s*total)\b/i;

/** The bill total. Checked AFTER subtotal so "sub total" can't win. */
const TOTAL_RE =
  /\b(grand\s*total|net\s*payable|amount\s*payable|total\s*payable|bill\s*(amount|total)|invoice\s*total|total\s*amount|te\s*betalen|totaal|total)\b/i;

const KIND_PATTERNS: ReadonlyArray<readonly [RegExp, ReceiptLineKind]> = [
  // Service charge before tax: "service charge" and "service tax" are different
  // things and only the second is a tax.
  [/\b(service\s*(charge|chg|fee)|svc\s*(charge|chg)|delivery\s*(charge|fee)|packaging\s*(charge|fee)|packing\s*(charge|fee)|convenience\s*fee|handling\s*(charge|fee)|servicekosten|bedieningsgeld)\b/i, "service_charge"],
  [/\b(tip|gratuity|fooi)\b/i, "tip"],
  [/\b(c?gst|sgst|igst|ugst|vat|btw|service\s*tax|sales\s*tax|cess|tax|belasting)\b/i, "tax"],
  [/\b(discount|disc\b|savings?|coupon|promo|offer|less\b|off\b|redeem(ed)?|korting)\b/i, "discount"],
];

const ROUND_OFF_RE = /\bround(ed)?\s*(off|ing)?\b/i;

function classify(text: string, isHeaderZone: boolean): ReceiptLineKind | "total" | "subtotal" | "ignore" {
  for (const re of IGNORE_PATTERNS) if (re.test(text)) return "ignore";
  if (isBareDate(text)) return "ignore";
  if (isHeaderZone && HEADER_NOISE_RE.test(text)) return "ignore";
  if (SUBTOTAL_RE.test(text)) return "subtotal";
  // Round-off is a real adjustment to the total, so it must stay in the maths,
  // but it is not a "total" line even though some printers label it as one.
  if (ROUND_OFF_RE.test(text) && !/total/i.test(text)) return "item";
  if (TOTAL_RE.test(text)) return "total";
  for (const [re, kind] of KIND_PATTERNS) if (re.test(text)) return kind;
  return "item";
}

// ---------------------------------------------------------------------------
// Quantity / unit price extraction
// ---------------------------------------------------------------------------

interface QtyInfo {
  quantity: number | null;
  unit: string | null;
  unitPrice: number | null;
  description: string;
}

const QTY_PREFIX_RE = /^(\d+(?:[.,]\d+)?)\s*(?:x|\*|@)\s*(.+)$/i;
const QTY_SUFFIX_RE = /^(.+?)\s*(?:x|\*)\s*(\d+(?:[.,]\d+)?)$/i;

const toQty = (s: string): number => Math.round(Number(s.replace(",", ".")) * QTY_SCALE);

/**
 * Work out quantity and unit price for an item line.
 *
 * The reliable signal is ARITHMETIC, not layout: if a line ends with three
 * numbers and the first two multiply to the third, they are unambiguously
 * qty x rate = amount. Grocery bills print exactly that, and checking the
 * product is what stops us reading an item code as a quantity.
 */
function extractQty(description: string, amount: number, minorDigits: number): QtyInfo {
  const base: QtyInfo = { quantity: null, unit: null, unitPrice: null, description: description.trim() };
  const scale = 10 ** minorDigits;
  const nums = findNumbers(description, minorDigits);

  // --- qty x rate = amount, verified by multiplication -------------------
  if (nums.length >= 2) {
    const rate = nums[nums.length - 1]!;
    const qty = nums[nums.length - 2]!;
    const qtyMajor = qty.value / scale;
    if (qtyMajor > 0 && qtyMajor <= 1000) {
      const product = Math.round(qtyMajor * rate.value);
      // One minor unit of slack: printers round the extension, not the rate.
      if (Math.abs(product - amount) <= 1) {
        return {
          quantity: Math.round(qtyMajor * QTY_SCALE),
          unit: findUnit(description),
          unitPrice: rate.value,
          description: description.slice(0, qty.start).trim().replace(/[-–:|]+$/, "").trim() || base.description,
        };
      }
    }
  }

  // --- explicit "2 x Latte" / "Latte x 2" --------------------------------
  let m = description.match(QTY_PREFIX_RE);
  if (m) {
    const quantity = toQty(m[1]!);
    const rest = m[2]!.trim();
    // "2 x 60.00" is qty x rate, not a description.
    const asMoney = parseMoney(rest, minorDigits);
    if (asMoney !== null && /^[\d.,\s]+$/.test(rest)) {
      return { quantity, unit: findUnit(description), unitPrice: asMoney, description: base.description };
    }
    return {
      quantity,
      unit: findUnit(description),
      unitPrice: quantity > 0 ? Math.round((amount * QTY_SCALE) / quantity) : null,
      description: rest,
    };
  }
  m = description.match(QTY_SUFFIX_RE);
  if (m) {
    const quantity = toQty(m[2]!);
    return {
      quantity,
      unit: findUnit(description),
      unitPrice: quantity > 0 ? Math.round((amount * QTY_SCALE) / quantity) : null,
      description: m[1]!.trim(),
    };
  }

  // --- "1.5 kg Basmati Rice" ---------------------------------------------
  const unit = findUnit(description);
  if (unit) {
    const um = description.match(new RegExp(`(\\d+(?:[.,]\\d+)?)\\s*${unit}\\b`, "i"));
    if (um) {
      const quantity = toQty(um[1]!);
      return {
        quantity,
        unit,
        unitPrice: quantity > 0 ? Math.round((amount * QTY_SCALE) / quantity) : null,
        description: description.replace(um[0]!, " ").replace(/\s+/g, " ").trim() || base.description,
      };
    }
  }

  // --- trailing bare integer, e.g. "Paneer Tikka  1" ----------------------
  // Common when the printer puts a Qty column between the name and the amount.
  const trail = description.match(/^(.*[A-Za-z])\s+(\d{1,3})$/);
  if (trail) {
    const quantity = toQty(trail[2]!);
    if (quantity > 0) {
      return {
        quantity,
        unit: findUnit(description),
        unitPrice: Math.round((amount * QTY_SCALE) / quantity),
        description: trail[1]!.trim(),
      };
    }
  }

  // --- leading small integer, e.g. "2 Masala Dosa" -----------------------
  // Only when what follows is clearly a name; an item CODE would leave digits.
  const lead = description.match(/^(\d{1,2})\s+([A-Za-z][^\d]{2,})$/);
  if (lead) {
    const quantity = toQty(lead[1]!);
    return {
      quantity,
      unit: null,
      unitPrice: quantity > 0 ? Math.round((amount * QTY_SCALE) / quantity) : null,
      description: lead[2]!.trim(),
    };
  }

  return base;
}

// ---------------------------------------------------------------------------
// Merchant
// ---------------------------------------------------------------------------

function findMerchant(lines: readonly TextLine[]): string | null {
  // Merchants print their name big, at the top. Look only at the first few
  // lines and prefer the most name-like: mostly letters, few digits.
  const head = lines.slice(0, 6);
  let best: { text: string; score: number } | null = null;
  for (const line of head) {
    const t = line.text.trim();
    if (t.length < 3 || t.length > 60) continue;
    if (IGNORE_PATTERNS.some((re) => re.test(t))) continue;
    const letters = (t.match(/[A-Za-z]/g) ?? []).length;
    const digits = (t.match(/\d/g) ?? []).length;
    if (letters < 3 || digits > letters) continue;
    const score = letters / t.length - digits / t.length;
    if (!best || score > best.score) best = { text: t, score };
  }
  return best ? best.text.replace(/[*_|]+/g, "").trim() : null;
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

export interface ParseOptions {
  /** Fallback when the receipt doesn't print a currency. */
  readonly currency: string;
  readonly minorDigits?: number;
  /** ISO date; dates after this are rejected as misreads. Defaults to today. */
  readonly today?: string;
  /** Prefix for the generated stable line ids. */
  readonly idPrefix?: string;
  readonly engine?: ReceiptEngine;
}

export function parseReceipt(lines: readonly TextLine[], opts: ParseOptions): ReceiptDraft {
  const minorDigits = opts.minorDigits ?? 2;
  const prefix = opts.idPrefix ?? "l";
  const fullText = lines.map((l) => l.text).join("\n");

  const out: ReceiptLine[] = [];
  let total: number | null = null;
  let subtotal: number | null = null;
  let seq = 0;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]!;
    const text = line.text;
    if (!text) continue;

    const kind = classify(text, i < HEADER_ZONE_LINES);
    if (kind === "ignore") continue;

    const nums = findNumbers(text, minorDigits);
    if (nums.length === 0) continue;

    // The rightmost number on a line is the amount. Percentages, rates and
    // quantities all sit to its left on every receipt layout we've seen.
    const last = nums[nums.length - 1]!;
    const amount = last.value;

    // Identifier guard: printed prices carry decimals. A long run of digits
    // with no decimal separator is a PIN code, phone number or invoice
    // reference, not ₹5,60,001 of biryani. Dropping it makes reconciliation
    // fail loudly, which is the outcome we want over a silent corruption.
    if (kind === "item" && !/[.,]\d{1,2}$/.test(last.raw) && (last.raw.match(/\d/g) ?? []).length >= 5) {
      continue;
    }
    if (kind === "total") {
      // Prefer the LAST total-ish line: printers put "Total" then "Grand Total".
      total = amount;
      continue;
    }
    if (kind === "subtotal") {
      subtotal = amount;
      continue;
    }

    const description = tidyDescription(text.slice(0, last.start));
    // A bare number with no label is noise (page numbers, stray marks).
    if (!description && kind === "item") continue;

    if (kind === "item") {
      const q = extractQty(description, amount, minorDigits);
      out.push({
        id: `${prefix}${seq++}`,
        kind: "item",
        description: q.description || description,
        quantity: q.quantity,
        unit: q.unit,
        unitPrice: q.unitPrice,
        amount,
        confidence: line.confidence,
      });
    } else {
      // Charges: discounts are stored negative regardless of how they print.
      out.push({
        id: `${prefix}${seq++}`,
        kind,
        description: description || kind.replace("_", " "),
        quantity: null,
        unit: null,
        unitPrice: null,
        amount: kind === "discount" ? -Math.abs(amount) : amount,
        confidence: line.confidence,
      });
    }
  }

  // A round-off line printed as a bare negative shows up as an item; that is
  // fine — it keeps the arithmetic exact, which is all reconciliation cares about.

  // If no total was printed but a subtotal was, and the lines agree with the
  // subtotal, we can trust the arithmetic and derive the total ourselves.
  const computed = out.reduce((s, l) => s + l.amount, 0);
  if (total === null && subtotal !== null) {
    const itemsOnly = out.filter((l) => l.kind === "item").reduce((s, l) => s + l.amount, 0);
    if (itemsOnly === subtotal) total = computed;
  }

  const meanConfidence =
    lines.length > 0 ? Math.round(lines.reduce((s, l) => s + l.confidence, 0) / lines.length) : 0;

  return {
    merchant: findMerchant(lines),
    occurredAt: findDate(fullText, opts.today),
    currency: detectCurrency(fullText) ?? opts.currency,
    lines: out,
    total,
    confidence: scoreConfidence(meanConfidence, out.length, total, computed),
    engine: opts.engine ?? "tesseract",
    rawText: fullText,
  };
}

/** Convenience wrapper for a PDF text layer or pasted text. */
export function parseReceiptText(text: string, opts: ParseOptions): ReceiptDraft {
  return parseReceipt(linesFromText(text), { ...opts, engine: opts.engine ?? "pdf_text" });
}

/**
 * Blend raw OCR confidence with structural evidence.
 *
 * OCR confidence alone is a poor predictor — engines are cheerfully confident
 * about nonsense. Whether the numbers ADD UP is a much stronger signal, so it
 * dominates the score.
 */
function scoreConfidence(
  ocrConfidence: number,
  lineCount: number,
  total: number | null,
  computed: number,
): number {
  if (lineCount === 0) return 0;
  let score = ocrConfidence * 0.5;
  if (total !== null) {
    score += 20;
    if (total === computed) score += 30;
    else {
      // Near-misses are more recoverable than wild ones.
      const drift = Math.abs(total - computed) / Math.max(1, Math.abs(total));
      score += drift < 0.05 ? 12 : drift < 0.2 ? 5 : 0;
    }
  }
  if (lineCount >= 3) score += 5;
  return Math.max(0, Math.min(100, Math.round(score)));
}
