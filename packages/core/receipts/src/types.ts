/**
 * @sanvya/receipts — types for a parsed receipt/bill and its per-item split.
 *
 * INVARIANTS (see ARCHITECTURE.md §2 and docs/features/receipt-scanning.md):
 *  - Every money value here is an INTEGER count of minor units. Never floats.
 *  - Quantities are integers in MILLI-units (1000 = "1"), so 0.5 kg = 500 and
 *    1.25 kg = 1250. This keeps grocery bills exact without touching floats.
 *  - A discount line carries a NEGATIVE `amount`. Everything else is positive.
 *  - `Σ lines[].amount` must equal the receipt total. `reconcile()` is the gate.
 *
 * Erasable TS only (no `enum`, no namespaces) so `node --experimental-strip-types`
 * can run the tests with no build step.
 */

/** One printed line on a receipt. `item` lines are goods; the rest are charges. */
export const RECEIPT_LINE_KINDS = {
  item: "item",
  tax: "tax",
  service_charge: "service_charge",
  tip: "tip",
  discount: "discount",
} as const;
export type ReceiptLineKind = (typeof RECEIPT_LINE_KINDS)[keyof typeof RECEIPT_LINE_KINDS];

export const CHARGE_KINDS: readonly ReceiptLineKind[] = ["tax", "service_charge", "tip", "discount"];

/** True for the non-goods lines (tax / service charge / tip / discount). */
export const isCharge = (kind: ReceiptLineKind): boolean => kind !== "item";

/** Quantities are milli-units: 1000 === one unit. */
export const QTY_SCALE = 1000;
export const qtyFromMajor = (n: number): number => Math.round(n * QTY_SCALE);
export const qtyToMajor = (n: number): number => n / QTY_SCALE;

export interface ReceiptLine {
  /** Stable client-side id; survives editing so per-item shares stay attached. */
  readonly id: string;
  readonly kind: ReceiptLineKind;
  readonly description: string;
  /** Milli-units. Null when the receipt didn't print a quantity. */
  readonly quantity: number | null;
  /** Free-text unit as printed ("kg", "pcs", "L"). Null when absent. */
  readonly unit: string | null;
  /** Minor units per single unit. Null when the receipt didn't print one. */
  readonly unitPrice: number | null;
  /** Minor units. The authoritative line total. Negative for `discount`. */
  readonly amount: number;
  /** 0-100. How sure the parser is about THIS line. */
  readonly confidence: number;
}

/** Which OCR path produced a draft. */
export const RECEIPT_ENGINES = {
  tesseract: "tesseract",
  claude: "claude",
  pdf_text: "pdf_text",
  manual: "manual",
} as const;
export type ReceiptEngine = (typeof RECEIPT_ENGINES)[keyof typeof RECEIPT_ENGINES];

export interface ReceiptDraft {
  readonly merchant: string | null;
  /** ISO-8601 date (YYYY-MM-DD) as printed. Null when unreadable. */
  readonly occurredAt: string | null;
  /** ISO 4217. Falls back to the user's base currency when unreadable. */
  readonly currency: string;
  readonly lines: readonly ReceiptLine[];
  /** Minor units, as PRINTED on the receipt. Null when unreadable. */
  readonly total: number | null;
  /** 0-100 overall parse confidence. */
  readonly confidence: number;
  readonly engine: ReceiptEngine;
  /** Raw OCR text, kept for re-parsing and debugging. Never contains an image. */
  readonly rawText?: string;
}

// ---------------------------------------------------------------------------
// Split modes
// ---------------------------------------------------------------------------

/**
 * How one line is divided among its assigned participants.
 *  - `equal`        — same amount each (largest-remainder).
 *  - `quantity`     — weighted by how many units each person took.
 *  - `percent`      — weighted by percent (weights are percent x 100).
 *  - `exact`        — participant weights ARE the minor-unit amounts.
 *  - `proportional` — weighted by each person's item subtotal. Charges only.
 */
export const ITEM_SPLIT_MODES = {
  equal: "equal",
  quantity: "quantity",
  percent: "percent",
  exact: "exact",
  proportional: "proportional",
} as const;
export type ItemSplitMode = (typeof ITEM_SPLIT_MODES)[keyof typeof ITEM_SPLIT_MODES];

/** Percent weights are stored x100 so "33.33%" is the integer 3333. */
export const PERCENT_SCALE = 100;

/**
 * A participant's claim on one line. The meaning of `weight` depends on the
 * line's mode: milli-quantity, percent x100, exact minor units, or ignored
 * (`equal`). `proportional` derives its weights and ignores this field.
 */
export interface ShareInput {
  readonly userId: string;
  readonly weight?: number | undefined;
}

/** Resolved allocation: minor units this user owes for this line. */
export interface ShareResult {
  readonly userId: string;
  readonly amount: number;
}

/** One line plus who is on it and how it's divided. */
export interface LineAssignment {
  readonly lineId: string;
  readonly mode: ItemSplitMode;
  readonly shares: readonly ShareInput[];
}
