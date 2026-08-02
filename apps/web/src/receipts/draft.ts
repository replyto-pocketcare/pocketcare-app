"use client";

/**
 * Editable-draft helpers shared by the review and split screens.
 *
 * `ReceiptDraft` is deliberately immutable (it's a parse result), so the editor
 * needs small pure updaters rather than mutating in place — that keeps undo,
 * re-render and reconciliation all honest.
 */
import {
  minorUnits,
  type Money,
} from "@sanvya/money";
import {
  reconcile,
  type ReceiptDraft,
  type ReceiptLine,
  type ReceiptLineKind,
} from "@sanvya/receipts";

/** Minor-unit digits for a currency, defaulting sanely on an unknown code. */
export function digitsFor(currency: string): number {
  try {
    return minorUnits(currency as Money["currency"]);
  } catch {
    return 2;
  }
}

/** "12.34" -> 1234. Blank/garbage becomes 0 rather than NaN. */
export function toMinor(value: string, digits: number): number {
  const n = Number.parseFloat(String(value).replace(",", "."));
  return Number.isFinite(n) ? Math.round(n * 10 ** digits) : 0;
}

/** 1234 -> "12.34", for populating an editable input. */
export function toMajorString(minor: number, digits: number): string {
  return (minor / 10 ** digits).toFixed(digits);
}

export function updateLine(
  draft: ReceiptDraft,
  lineId: string,
  patch: Partial<ReceiptLine>,
): ReceiptDraft {
  return {
    ...draft,
    lines: draft.lines.map((l) => (l.id === lineId ? { ...l, ...patch } : l)),
  };
}

export function removeLine(draft: ReceiptDraft, lineId: string): ReceiptDraft {
  return { ...draft, lines: draft.lines.filter((l) => l.id !== lineId) };
}

export function addLine(draft: ReceiptDraft, kind: ReceiptLineKind = "item"): ReceiptDraft {
  const line: ReceiptLine = {
    id: `new-${globalThis.crypto.randomUUID().slice(0, 8)}`,
    kind,
    description: "",
    quantity: null,
    unit: null,
    unitPrice: null,
    amount: 0,
    confidence: 100,
  };
  return { ...draft, lines: [...draft.lines, line] };
}

/**
 * Adopt the computed sum as the total.
 *
 * The counterpart to `balanceWithLine`: when the user has corrected the lines
 * and it's the PRINTED total we misread, this trusts the lines instead.
 */
export function adoptComputedTotal(draft: ReceiptDraft): ReceiptDraft {
  return { ...draft, total: reconcile(draft).computed };
}

/** Human-facing ordering: goods first, then charges in the order bills print them. */
const KIND_ORDER: Record<ReceiptLineKind, number> = {
  item: 0,
  discount: 1,
  service_charge: 2,
  tax: 3,
  tip: 4,
};

export function sortedLines(draft: ReceiptDraft): ReceiptLine[] {
  return [...draft.lines].sort((a, b) => KIND_ORDER[a.kind] - KIND_ORDER[b.kind]);
}
