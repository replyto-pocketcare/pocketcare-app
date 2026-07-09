// Pure split math (minor units). Keyed by user id in the multi-user model.

/** Distribute `total` minor units across `weights` via largest-remainder. */
export function splitByWeights(total: number, weights: number[]): number[] {
  const W = weights.reduce((s, w) => s + Math.max(0, w), 0);
  if (W <= 0) return weights.map(() => 0);
  const raw = weights.map((w) => (total * Math.max(0, w)) / W);
  const out = raw.map((x) => Math.floor(x));
  const rem = total - out.reduce((s, x) => s + x, 0);
  const order = raw.map((x, i) => ({ i, frac: x - Math.floor(x) })).sort((a, b) => b.frac - a.frac || a.i - b.i);
  for (let k = 0; k < rem && k < order.length; k++) out[order[k]!.i]! += 1;
  return out;
}

export const splitEqual = (total: number, n: number): number[] => splitByWeights(total, Array.from({ length: n }, () => 1));

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
