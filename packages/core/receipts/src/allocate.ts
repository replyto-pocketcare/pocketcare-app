/**
 * Allocation math for itemized receipt splitting.
 *
 * Every function here is pure and works in integer minor units. The single
 * money-preserving primitive is `splitByWeights` (largest remainder): the
 * returned parts ALWAYS sum exactly back to the input total, so no rupee is
 * ever created or lost no matter how the weights fall.
 */
import type {
  ItemSplitMode,
  LineAssignment,
  ReceiptLine,
  ShareInput,
  ShareResult,
} from "./types.ts";
import { isCharge } from "./types.ts";

/**
 * Distribute `total` minor units across `weights` via largest-remainder.
 * Sums exactly to `total` for positive AND negative totals (discount lines).
 * Weights are clamped at 0; an all-zero weight vector yields all zeros.
 */
export function splitByWeights(total: number, weights: readonly number[]): number[] {
  const W = weights.reduce((s, w) => s + Math.max(0, w), 0);
  if (W <= 0) return weights.map(() => 0);
  const raw = weights.map((w) => (total * Math.max(0, w)) / W);
  const out = raw.map((x) => Math.floor(x));
  const rem = total - out.reduce((s, x) => s + x, 0);
  const order = raw
    .map((x, i) => ({ i, frac: x - Math.floor(x) }))
    .sort((a, b) => b.frac - a.frac || a.i - b.i);
  for (let k = 0; k < rem && k < order.length; k++) out[order[k]!.i]! += 1;
  return out;
}

export const splitEqual = (total: number, n: number): number[] =>
  splitByWeights(total, Array.from({ length: n }, () => 1));

export class AllocationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AllocationError";
  }
}

/**
 * Allocate ONE line across its participants.
 *
 * `proportional` is not handled here — it needs the item subtotals, so it is
 * resolved by `allocateReceipt`. Calling this with `proportional` throws.
 */
export function allocateItem(
  amount: number,
  shares: readonly ShareInput[],
  mode: ItemSplitMode,
): ShareResult[] {
  if (shares.length === 0) return [];
  if (mode === "proportional") {
    throw new AllocationError("proportional lines must be allocated via allocateReceipt()");
  }

  if (mode === "exact") {
    // Weights ARE the amounts. We do not rebalance: an exact split that does
    // not add up is a user error the UI must surface before saving.
    const parts = shares.map((s) => Math.round(s.weight ?? 0));
    const sum = parts.reduce((a, b) => a + b, 0);
    if (sum !== amount) {
      throw new AllocationError(`Exact shares sum to ${sum}, expected ${amount}`);
    }
    return shares.map((s, i) => ({ userId: s.userId, amount: parts[i]! }));
  }

  const weights =
    mode === "equal" ? shares.map(() => 1) : shares.map((s) => Math.max(0, s.weight ?? 0));

  // A quantity/percent split where nobody was given a weight is almost always
  // "the user hasn't filled it in yet" — fall back to equal rather than
  // silently assigning the whole line to nobody.
  const totalWeight = weights.reduce((a, b) => a + b, 0);
  const effective = totalWeight > 0 ? weights : shares.map(() => 1);

  const parts = splitByWeights(amount, effective);
  return shares.map((s, i) => ({ userId: s.userId, amount: parts[i]! }));
}

/**
 * Allocate a charge (tax / service / tip / discount) pro-rata to each person's
 * item subtotal. Participants with a zero subtotal get nothing — unless NOBODY
 * has a subtotal, in which case it falls back to an equal split.
 */
export function allocateProportional(
  amount: number,
  participants: readonly string[],
  subtotalByUser: ReadonlyMap<string, number>,
): ShareResult[] {
  if (participants.length === 0) return [];
  const weights = participants.map((u) => Math.max(0, subtotalByUser.get(u) ?? 0));
  const total = weights.reduce((a, b) => a + b, 0);
  const parts = splitByWeights(amount, total > 0 ? weights : participants.map(() => 1));
  return participants.map((userId, i) => ({ userId, amount: parts[i]! }));
}

/** Sum per-line allocations into one total per user. */
export function rollUp(perLine: ReadonlyMap<string, readonly ShareResult[]>): Map<string, number> {
  const out = new Map<string, number>();
  for (const results of perLine.values()) {
    for (const r of results) out.set(r.userId, (out.get(r.userId) ?? 0) + r.amount);
  }
  return out;
}

export interface AllocationResult {
  /** lineId -> per-user amounts. */
  readonly perLine: Map<string, ShareResult[]>;
  /** userId -> total owed across every line. Sums exactly to `total`. */
  readonly byUser: Map<string, number>;
  /** Σ of every line amount (what the expense row will carry). */
  readonly total: number;
  /** userId -> subtotal from `item` lines only (what proportional charges use). */
  readonly itemSubtotalByUser: Map<string, number>;
}

/**
 * Allocate a whole receipt: item lines first, then charge lines (which may be
 * proportional to the item subtotals just computed), then roll up per user.
 *
 * Guarantees `Σ byUser === Σ lines[].amount`, which is exactly the invariant
 * `expense_participants` needs so the existing balance logic keeps working.
 */
export function allocateReceipt(
  lines: readonly ReceiptLine[],
  assignments: readonly LineAssignment[],
): AllocationResult {
  const byLineId = new Map(assignments.map((a) => [a.lineId, a]));
  const perLine = new Map<string, ShareResult[]>();

  // Pass 1 — item lines. These define each person's subtotal.
  for (const line of lines) {
    if (isCharge(line.kind)) continue;
    const a = byLineId.get(line.id);
    if (!a || a.shares.length === 0) continue;
    if (a.mode === "proportional") {
      throw new AllocationError(`Line ${line.id} is an item; 'proportional' applies to charges only`);
    }
    perLine.set(line.id, allocateItem(line.amount, a.shares, a.mode));
  }
  const itemSubtotalByUser = rollUp(perLine);

  // Pass 2 — charges, which may lean on the subtotals from pass 1.
  for (const line of lines) {
    if (!isCharge(line.kind)) continue;
    const a = byLineId.get(line.id);
    if (!a || a.shares.length === 0) continue;
    perLine.set(
      line.id,
      a.mode === "proportional"
        ? allocateProportional(line.amount, a.shares.map((s) => s.userId), itemSubtotalByUser)
        : allocateItem(line.amount, a.shares, a.mode),
    );
  }

  const byUser = rollUp(perLine);
  const total = lines.reduce((s, l) => s + l.amount, 0);

  // Defensive: an unassigned line would silently vanish from the roll-up and
  // leave the expense unbalanced. Fail loudly instead of writing bad data.
  const allocated = [...byUser.values()].reduce((a, b) => a + b, 0);
  if (allocated !== total) {
    throw new AllocationError(
      `Allocated ${allocated} but lines total ${total} — every line must be assigned to at least one person`,
    );
  }

  return { perLine, byUser, total, itemSubtotalByUser };
}
