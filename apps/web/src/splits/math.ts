// Pure split math (minor units). Keyed by user id in the multi-user model.
//
// The largest-remainder primitive now lives in @pocketcare/receipts (it is
// shared with itemized receipt splitting and is covered by that package's
// tests). Re-exported here so every existing import site keeps working and
// there is exactly ONE implementation of the money-preserving allocation.
export { splitByWeights, splitEqual } from "@pocketcare/receipts";
import { splitByWeights } from "@pocketcare/receipts";

export interface Party {
  userId: string;
  share: number; // consumption (minor)
  paid: number;  // paid (minor)
}

/**
 * Per-other-user edge (minor) that the OTHER owes YOU on one expense (negative =
 * you owe them), via pro-rata payment allocation, rounded so edges sum EXACTLY
 * to your net (self.paid − self.share). Multi-payer safe.
 */
export function pairwiseEdges(parties: Party[], selfId: string): { userId: string; amount: number }[] {
  const total = parties.reduce((s, p) => s + p.paid, 0);
  const self = parties.find((p) => p.userId === selfId) ?? { userId: selfId, share: 0, paid: 0 };
  const others = parties.filter((p) => p.userId !== selfId);
  if (!others.length) return [];
  if (total <= 0) return others.map((o) => ({ userId: o.userId, amount: 0 }));
  const selfNet = self.paid - self.share;
  const raw = others.map((o) => (o.share * self.paid - self.share * o.paid) / total);
  const rounded = raw.map((x) => Math.round(x));
  const residual = selfNet - rounded.reduce((s, x) => s + x, 0);
  if (residual !== 0) {
    let idx = 0;
    for (let i = 1; i < raw.length; i++) if (Math.abs(raw[i]!) > Math.abs(raw[idx]!)) idx = i;
    rounded[idx]! += residual;
  }
  return others.map((o, i) => ({ userId: o.userId, amount: rounded[i]! }));
}
