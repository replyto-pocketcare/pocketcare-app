/**
 * Pure statement analytics (no I/O, no formatting). Amounts are signed minor
 * units (− debit / + credit). Everything here is deterministic and unit-tested.
 */
import type { StatementTxn } from "./types";

export interface Summary {
  count: number;
  credits: number;   // total money in (minor, positive)
  debits: number;    // total money out (minor, positive)
  net: number;       // credits − debits
  from: string | null;
  to: string | null;
}

export function summarize(txns: StatementTxn[]): Summary {
  let credits = 0, debits = 0;
  let from: string | null = null, to: string | null = null;
  for (const t of txns) {
    if (t.amount >= 0) credits += t.amount; else debits += -t.amount;
    if (t.date) { if (!from || t.date < from) from = t.date; if (!to || t.date > to) to = t.date; }
  }
  return { count: txns.length, credits, debits, net: credits - debits, from, to };
}

/** Spend (debits) grouped by category label; sorted desc. Uncategorised → "Uncategorised". */
export function byCategory(txns: StatementTxn[]): { name: string; total: number; count: number }[] {
  const m = new Map<string, { total: number; count: number }>();
  for (const t of txns) {
    if (t.amount >= 0) continue; // only spends
    const key = (t.category && t.category.trim()) || "Uncategorised";
    const e = m.get(key) ?? { total: 0, count: 0 };
    e.total += -t.amount; e.count += 1;
    m.set(key, e);
  }
  return [...m.entries()].map(([name, v]) => ({ name, ...v })).sort((a, b) => b.total - a.total);
}

/** Debits bucketed by calendar month (YYYY-MM), chronological. */
export function byMonth(txns: StatementTxn[]): { ym: string; debit: number; credit: number }[] {
  const m = new Map<string, { debit: number; credit: number }>();
  for (const t of txns) {
    if (!t.date) continue;
    const ym = t.date.slice(0, 7);
    const e = m.get(ym) ?? { debit: 0, credit: 0 };
    if (t.amount >= 0) e.credit += t.amount; else e.debit += -t.amount;
    m.set(ym, e);
  }
  return [...m.entries()].map(([ym, v]) => ({ ym, ...v })).sort((a, b) => a.ym.localeCompare(b.ym));
}

/** Daily spend series over the statement window (chronological). */
export function byDay(txns: StatementTxn[]): { date: string; debit: number }[] {
  const m = new Map<string, number>();
  for (const t of txns) { if (t.amount < 0 && t.date) m.set(t.date, (m.get(t.date) ?? 0) + -t.amount); }
  return [...m.entries()].map(([date, debit]) => ({ date, debit })).sort((a, b) => a.date.localeCompare(b.date));
}

export interface Outlier { txn: StatementTxn; amount: number; reason: string }

/**
 * Flag unusually large spends using the IQR fence (> Q3 + 1.5·IQR) over the
 * debit magnitudes. Falls back to "> 3× median" for very small samples.
 */
export function outliers(txns: StatementTxn[]): Outlier[] {
  const debits = txns.filter((t) => t.amount < 0);
  const mags = debits.map((t) => -t.amount).sort((a, b) => a - b);
  if (mags.length < 4) {
    if (mags.length === 0) return [];
    const median = mags[Math.floor(mags.length / 2)]!;
    const thr = median * 3;
    return debits.filter((t) => -t.amount > thr && -t.amount > 0)
      .map((t) => ({ txn: t, amount: -t.amount, reason: `Much larger than your typical spend (~3× the median)` }));
  }
  const q = (p: number) => {
    const idx = (mags.length - 1) * p;
    const lo = Math.floor(idx), hi = Math.ceil(idx);
    return mags[lo]! + (mags[hi]! - mags[lo]!) * (idx - lo);
  };
  const q1 = q(0.25), q3 = q(0.75);
  const fence = q3 + 1.5 * (q3 - q1);
  return debits.filter((t) => -t.amount > fence)
    .map((t) => ({ txn: t, amount: -t.amount, reason: `Unusually large — above the normal range for this statement` }))
    .sort((a, b) => b.amount - a.amount);
}

/** Normalise a merchant/narration for grouping: drop refs, digits, banking noise. */
export function normalizeMerchant(desc: string): string {
  return desc
    .toLowerCase()
    .replace(/[0-9]{4,}/g, " ")       // long numbers (refs, card tails) — strip first
    .replace(/\b(upi|imps|neft|rtgs|ach|nach|pos|atw|vps|mmt|inb|ref|txn|trf|payment|paytm|gpay|phonepe)\b/g, " ")
    .replace(/[^a-z ]+/g, " ")         // punctuation/symbols
    .replace(/\s+/g, " ")
    .trim()
    .split(" ").slice(0, 3).join(" "); // first few tokens = the merchant
}

export interface RecurringCandidate {
  label: string;       // representative description
  key: string;         // normalized merchant
  amount: number;      // typical debit magnitude (minor)
  count: number;
  cadence: "weekly" | "monthly" | "yearly" | "irregular";
  sample: StatementTxn[];
}

/**
 * Detect likely recurring debits: same merchant, similar amount (±12%), seen
 * ≥2 times with a regular gap. Powers "add as a recurring payment".
 */
export function recurringCandidates(txns: StatementTxn[]): RecurringCandidate[] {
  const groups = new Map<string, StatementTxn[]>();
  for (const t of txns) {
    if (t.amount >= 0) continue;
    const key = normalizeMerchant(t.description);
    if (!key) continue;
    (groups.get(key) ?? groups.set(key, []).get(key)!).push(t);
  }
  const out: RecurringCandidate[] = [];
  for (const [key, list] of groups) {
    if (list.length < 2) continue;
    const sorted = [...list].sort((a, b) => (a.date || "").localeCompare(b.date || ""));
    const mags = sorted.map((t) => -t.amount);
    const median = [...mags].sort((a, b) => a - b)[Math.floor(mags.length / 2)]!;
    // amounts must cluster (each within ±12% of the median)
    if (!mags.every((m) => Math.abs(m - median) <= median * 0.12)) continue;
    // gaps in days between consecutive occurrences
    const gaps: number[] = [];
    for (let i = 1; i < sorted.length; i++) {
      const d0 = Date.parse(sorted[i - 1]!.date + "T00:00:00");
      const d1 = Date.parse(sorted[i]!.date + "T00:00:00");
      if (Number.isFinite(d0) && Number.isFinite(d1)) gaps.push((d1 - d0) / 86400000);
    }
    const avgGap = gaps.length ? gaps.reduce((a, b) => a + b, 0) / gaps.length : 0;
    const cadence: RecurringCandidate["cadence"] =
      avgGap >= 5 && avgGap <= 10 ? "weekly"
      : avgGap >= 25 && avgGap <= 35 ? "monthly"
      : avgGap >= 350 && avgGap <= 380 ? "yearly"
      : "irregular";
    out.push({ label: sorted[sorted.length - 1]!.description, key, amount: Math.round(median), count: sorted.length, cadence, sample: sorted });
  }
  // Prefer regular cadences and more occurrences.
  return out.sort((a, b) => (a.cadence === "irregular" ? 1 : 0) - (b.cadence === "irregular" ? 1 : 0) || b.count - a.count);
}
