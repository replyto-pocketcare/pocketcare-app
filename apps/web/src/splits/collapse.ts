"use client";

/**
 * Split display-collapse.
 *
 * A single split expense writes up to three private ledger rows for you —
 * `own_share` (real account), `lend` (transfer to the virtual "Owed to me"
 * account when you overpaid) and `borrow` (expense on the virtual "I owe"
 * account when you underpaid). Those rows are REQUIRED for correct balances and
 * are never removed. But in transaction *lists* they read as 2–3 separate rows
 * for one real-world event, which is confusing — so we collapse every posting of
 * the same expense into ONE tile (badged "Split") and surface the breakdown in
 * the transaction detail view.
 *
 * The tile shows the **total you paid** (own_share + lend); if you paid nothing,
 * it falls back to your share so the tile isn't a meaningless ₹0.
 */
import { useQuery } from "@powersync/react";

export interface SplitInfo {
  expenseId: string;
  groupId: string | null;
  /** Amount shown on the collapsed tile — total you actually paid. */
  displayPaid: number;
  /** Your share of the expense (what it cost you). */
  yourShare: number;
  /** You overpaid and are owed this back. */
  owedToYou: number;
  /** You underpaid and owe this. */
  youOwe: number;
  currency: string;
}

interface Row { txid: string; eid: string; role: string; amount: number; currency: string; gid: string | null }

/** Map of transaction id → its split expense info (only split-posting txns present). */
export function useSplitInfo(): Map<string, SplitInfo> {
  const { data: rows = [] } = useQuery<Row>(
    `SELECT ep.transaction_id AS txid, ep.expense_id AS eid, ep.role AS role,
            t.amount AS amount, t.currency AS currency, e.group_id AS gid
     FROM expense_postings ep
     JOIN transactions t ON t.id = ep.transaction_id AND t.deleted_at IS NULL
     LEFT JOIN expenses e ON e.id = ep.expense_id
     WHERE ep.deleted_at IS NULL AND ep.expense_id IS NOT NULL`,
  );

  // Aggregate per expense.
  const byExpense = new Map<string, { own: number; lend: number; borrow: number; currency: string; gid: string | null; txids: string[] }>();
  for (const r of rows) {
    const agg = byExpense.get(r.eid) ?? { own: 0, lend: 0, borrow: 0, currency: r.currency, gid: r.gid, txids: [] };
    if (r.role === "own_share") agg.own += r.amount;
    else if (r.role === "lend") agg.lend += r.amount;
    else if (r.role === "borrow") agg.borrow += r.amount;
    agg.txids.push(r.txid);
    byExpense.set(r.eid, agg);
  }

  const infoByTx = new Map<string, SplitInfo>();
  for (const [eid, a] of byExpense) {
    const paid = a.own + a.lend;
    const info: SplitInfo = {
      expenseId: eid,
      groupId: a.gid,
      displayPaid: paid > 0 ? paid : a.borrow,
      yourShare: a.own + a.borrow,
      owedToYou: a.lend,
      youOwe: a.borrow,
      currency: a.currency,
    };
    for (const txid of a.txids) infoByTx.set(txid, info);
  }
  return infoByTx;
}

/**
 * Collapse a date-ordered row list: keep the first posting seen for each split
 * expense (annotated with its SplitInfo), drop the sibling postings.
 */
export function collapseSplitRows<T extends { id: string }>(
  rows: T[],
  infoByTx: Map<string, SplitInfo>,
): { row: T; split?: SplitInfo }[] {
  const seen = new Set<string>();
  const out: { row: T; split?: SplitInfo }[] = [];
  for (const r of rows) {
    const info = infoByTx.get(r.id);
    if (!info) { out.push({ row: r }); continue; }
    if (seen.has(info.expenseId)) continue; // hide siblings of an already-shown split
    seen.add(info.expenseId);
    out.push({ row: r, split: info });
  }
  return out;
}
