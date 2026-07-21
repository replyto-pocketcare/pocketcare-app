/**
 * Reconcile a parsed statement against what's already recorded in the app.
 * Pure & deterministic. Matches on amount (exact magnitude + same direction),
 * a date window, and description similarity. Signed minor units throughout.
 */
import type { StatementTxn } from "./types";

/** Local copy of the merchant normaliser (kept inline so this module is
 *  self-contained for testing; mirrors analysis.normalizeMerchant). */
function normalizeMerchant(desc: string): string {
  return desc
    .toLowerCase()
    .replace(/[0-9]{4,}/g, " ")
    .replace(/\b(upi|imps|neft|rtgs|ach|nach|pos|atw|vps|mmt|inb|ref|txn|trf|payment|paytm|gpay|phonepe)\b/g, " ")
    .replace(/[^a-z ]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .split(" ").slice(0, 3).join(" ");
}

export interface RecordedTxn {
  id: string;
  amount: number;      // signed minor (− out / + in)
  date: string;        // YYYY-MM-DD
  description: string;
}

export interface Match { parsed: StatementTxn; recorded: RecordedTxn; score: number }

export interface Reconciliation {
  matched: Match[];
  /** In the statement but NOT recorded on the platform → import candidates. */
  missingOnPlatform: StatementTxn[];
  /** Recorded on the platform but not in this statement. */
  onlyOnPlatform: RecordedTxn[];
}

const tokens = (s: string) => new Set(normalizeMerchant(s).split(" ").filter(Boolean));
function jaccard(a: string, b: string): number {
  const ta = tokens(a), tb = tokens(b);
  if (ta.size === 0 || tb.size === 0) return 0;
  let inter = 0;
  for (const t of ta) if (tb.has(t)) inter++;
  return inter / (ta.size + tb.size - inter);
}
const daysApart = (a: string, b: string) =>
  Math.abs((Date.parse(a + "T00:00:00") - Date.parse(b + "T00:00:00")) / 86400000);

export function reconcile(
  parsed: StatementTxn[],
  recorded: RecordedTxn[],
  opts: { dayWindow?: number } = {},
): Reconciliation {
  const window = opts.dayWindow ?? 4;
  // Candidate pairs: same amount magnitude + direction, within the date window.
  const pairs: { pi: number; ri: number; score: number }[] = [];
  parsed.forEach((p, pi) => {
    recorded.forEach((r, ri) => {
      if (Math.round(p.amount) !== Math.round(r.amount)) return; // exact magnitude + sign
      const dd = daysApart(p.date, r.date);
      if (!Number.isFinite(dd) || dd > window) return;
      // Higher score = better: closer date + description overlap.
      const score = (1 - dd / (window + 1)) * 0.6 + jaccard(p.description, r.description) * 0.4;
      pairs.push({ pi, ri, score });
    });
  });
  pairs.sort((a, b) => b.score - a.score);

  const usedP = new Set<number>(), usedR = new Set<number>();
  const matched: Match[] = [];
  for (const { pi, ri, score } of pairs) {
    if (usedP.has(pi) || usedR.has(ri)) continue;
    usedP.add(pi); usedR.add(ri);
    matched.push({ parsed: parsed[pi]!, recorded: recorded[ri]!, score });
  }
  const missingOnPlatform = parsed.filter((_, i) => !usedP.has(i));
  const onlyOnPlatform = recorded.filter((_, i) => !usedR.has(i));
  return { matched, missingOnPlatform, onlyOnPlatform };
}
