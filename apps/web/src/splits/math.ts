// Pure split math (minor units). Kept separate so it's trivially testable and
// reused by the exact/percent modes in later phases.

/**
 * Split `total` minor units into `n` integer parts using the largest-remainder
 * method: everyone gets floor(total/n), and the leftover minor units (0..n-1)
 * go one each to the first participants. Guarantees the parts sum to `total`
 * exactly — no penny created or lost.
 */
export function splitEqual(total: number, n: number): number[] {
  if (n <= 0) return [];
  const base = Math.floor(total / n);
  const rem = total - base * n; // 0..n-1
  return Array.from({ length: n }, (_, i) => base + (i < rem ? 1 : 0));
}
