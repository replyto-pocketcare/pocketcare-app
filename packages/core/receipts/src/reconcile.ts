/**
 * Reconciliation — does what we read add up to what the receipt says?
 *
 * This is the quality gate for the whole feature. OCR is confident and wrong
 * far more often than it is unsure, so we do NOT trust the confidence score
 * alone: a draft only passes when the arithmetic closes.
 */
import type { ReceiptDraft, ReceiptLine } from "./types.ts";

export interface Subtotals {
  /** Σ of `item` lines. */
  readonly items: number;
  readonly tax: number;
  readonly serviceCharge: number;
  readonly tip: number;
  /** Negative (discounts reduce the bill). */
  readonly discount: number;
  /** items + tax + serviceCharge + tip + discount. */
  readonly computed: number;
}

export function subtotals(lines: readonly ReceiptLine[]): Subtotals {
  let items = 0, tax = 0, serviceCharge = 0, tip = 0, discount = 0;
  for (const l of lines) {
    if (l.kind === "item") items += l.amount;
    else if (l.kind === "tax") tax += l.amount;
    else if (l.kind === "service_charge") serviceCharge += l.amount;
    else if (l.kind === "tip") tip += l.amount;
    else discount += l.amount;
  }
  return { items, tax, serviceCharge, tip, discount, computed: items + tax + serviceCharge + tip + discount };
}

export const RECONCILE_REASONS = {
  balanced: "balanced",
  no_lines: "no_lines",
  missing_total: "missing_total",
  mismatch: "mismatch",
} as const;
export type ReconcileReason = (typeof RECONCILE_REASONS)[keyof typeof RECONCILE_REASONS];

export interface ReconcileResult {
  readonly ok: boolean;
  readonly reason: ReconcileReason;
  /** Σ of the parsed lines. */
  readonly computed: number;
  /** The total as printed on the receipt, if we could read one. */
  readonly stated: number | null;
  /** stated − computed. Positive = we're missing lines worth this much. */
  readonly delta: number;
  readonly subtotals: Subtotals;
}

/**
 * Compare Σ lines against the printed total.
 *
 * Exact-match only: a receipt that is off by even one minor unit means we
 * misread something, and quietly absorbing it would corrupt the ledger.
 */
export function reconcile(draft: ReceiptDraft): ReconcileResult {
  const s = subtotals(draft.lines);
  if (draft.lines.length === 0) {
    return { ok: false, reason: "no_lines", computed: 0, stated: draft.total, delta: draft.total ?? 0, subtotals: s };
  }
  if (draft.total === null) {
    return { ok: false, reason: "missing_total", computed: s.computed, stated: null, delta: 0, subtotals: s };
  }
  const delta = draft.total - s.computed;
  return {
    ok: delta === 0,
    reason: delta === 0 ? "balanced" : "mismatch",
    computed: s.computed,
    stated: draft.total,
    delta,
    subtotals: s,
  };
}

/** Confidence below this is treated as "we probably misread this". */
export const LOW_CONFIDENCE = 70;

/**
 * Should we offer the AI fallback? True when the arithmetic doesn't close, we
 * found no total, or the OCR itself was shaky. The caller still asks the user —
 * the image never leaves the device without an explicit tap.
 */
export function shouldEscalate(draft: ReceiptDraft): boolean {
  if (draft.engine === "claude") return false;
  if (draft.confidence < LOW_CONFIDENCE) return true;
  return !reconcile(draft).ok;
}

/**
 * One-tap fix for a mismatch: append a single line absorbing the difference so
 * the draft balances and can be saved. Used by the review screen's "add the
 * missing ₹x as an unlabelled line" action.
 */
export function balanceWithLine(
  draft: ReceiptDraft,
  id: string,
  description: string,
): ReceiptDraft {
  const r = reconcile(draft);
  if (r.ok || r.stated === null) return draft;
  const line: ReceiptLine = {
    id,
    kind: r.delta < 0 ? "discount" : "item",
    description,
    quantity: null,
    unit: null,
    unitPrice: null,
    amount: r.delta,
    confidence: 0,
  };
  return { ...draft, lines: [...draft.lines, line] };
}
