// Pure split math (minor units). Separate so it's trivially testable and reused
// across equal / exact / percent modes.

/** Distribute `total` minor units across `weights` using largest-remainder,
 *  so the parts sum to `total` exactly. Used for equal and percentage splits. */
export function splitByWeights(total: number, weights: number[]): number[] {
  const W = weights.reduce((s, w) => s + Math.max(0, w), 0);
  if (W <= 0) return weights.map(() => 0);
  const raw = weights.map((w) => (total * Math.max(0, w)) / W);
  const out = raw.map((x) => Math.floor(x));
  let rem = total - out.reduce((s, x) => s + x, 0);
  const order = raw.map((x, i) => ({ i, frac: x - Math.floor(x) })).sort((a, b) => b.frac - a.frac || a.i - b.i);
  for (let k = 0; k < rem && k < order.length; k++) out[order[k]!.i]! += 1;
  return out;
}

/** Equal split of `total` into `n` parts. */
export const splitEqual = (total: number, n: number): number[] => splitByWeights(total, Array.from({ length: n }, () => 1));

export interface PartyAgg {
  id: string | null; // null = self
  share: number;     // consumption (minor)
  paid: number;      // paid (minor)
}

/**
 * Per-contact edge amount (minor) that the CONTACT owes YOU on one expense —
 * negative means you owe them. Uses pro-rata payment allocation:
 *   edge_c = (share_c · self_paid − self_share · paid_c) / total_paid
 * rounded so the edges sum EXACTLY to your net (self_paid − self_share).
 */
export function contactEdges(parties: PartyAgg[]): { id: string; amount: number }[] {
  const total = parties.reduce((s, p) => s + p.paid, 0);
  const self = parties.find((p) => p.id === null) ?? { id: null as string | null, share: 0, paid: 0 };
  const others = parties.filter((p) => p.id !== null).map((p) => ({ id: p.id as string, share: p.share, paid: p.paid }));
  if (!others.length) return [];
  if (total <= 0) return others.map((o) => ({ id: o.id, amount: 0 }));
  const selfNet = self.paid - self.share;
  const raw = others.map((o) => (o.share * self.paid - self.share * o.paid) / total);
  const rounded = raw.map((x) => Math.round(x));
  const residual = selfNet - rounded.reduce((s, x) => s + x, 0);
  if (residual !== 0) {
    let idx = 0;
    for (let i = 1; i < raw.length; i++) if (Math.abs(raw[i]!) > Math.abs(raw[idx]!)) idx = i;
    rounded[idx]! += residual;
  }
  return others.map((o, i) => ({ id: o.id, amount: rounded[i]! }));
}
