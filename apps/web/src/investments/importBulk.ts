"use client";

/**
 * BULK holdings import.
 *
 * `addHolding()` (write.ts) is the right thing for ONE holding added by hand:
 * it funds the invested pool, writes ledger entries, and can wire up a SIP.
 * Running it in a loop over an imported file would be wrong on three counts —
 * one write transaction per holding (so the CRUD queue uploads as N separate
 * requests instead of one batch), N ledger entries the user never made, and a
 * partial portfolio left behind if row 40 of 60 throws.
 *
 * So an import is its own operation: every row is validated first, then the
 * whole set is written inside a SINGLE writeTransaction. Either the import
 * lands or it doesn't. It follows `src/data/importCsv.ts`, which made the same
 * call for statement rows.
 *
 * It deliberately writes NO ledger entries. Imported holdings are a statement
 * of what you already own; inventing transfers to match would fabricate
 * history and double-count against the account that really funded them.
 */
import { fromMajor } from "@sanvya/money";
import { getDb, getUserId } from "../powersync";
import { uuid, nowIso } from "../write";
import { getBaseCurrency } from "../prefs";
import { isExampleRow, type ParsedHolding } from "./importFormats";

export interface HoldingImportResult {
  created: number;
  updated: number;
  skipped: number;
  errors: string[];
}

/** Match key for "we already track this". ISIN when we have one (it survives
 *  ticker renames), else symbol — both scoped to the destination account. */
const keyOf = (accountId: string, isin: string | null, symbol: string): string =>
  `${accountId}|${isin ? `isin:${isin.toUpperCase()}` : `sym:${symbol.trim().toUpperCase()}`}`;

export interface ImportOptions {
  /** Investment account the holdings land in. */
  accountId: string;
  /** Existing holding with the same ISIN/symbol: overwrite it, or leave it be. */
  onConflict: "update" | "skip";
  currency?: string;
}

export async function importHoldingsBulk(
  rows: ParsedHolding[],
  opts: ImportOptions,
): Promise<HoldingImportResult> {
  const db = getDb();
  const res: HoldingImportResult = { created: 0, updated: 0, skipped: 0, errors: [] };
  if (!db) { res.errors.push("Database not ready"); return res; }

  const currency = opts.currency || getBaseCurrency();
  const userId = getUserId();
  const ts = nowIso();

  // Everything that can fail is resolved BEFORE the transaction opens, so the
  // write itself is a straight run with nothing left to throw.
  const usable = rows.filter((h) => !isExampleRow(h) && h.quantity > 0);
  if (usable.length === 0) { res.errors.push("Nothing to import"); return res; }

  const existing = new Map<string, { id: string; isin: string | null; symbol: string }>();
  for (const r of await db.getAll<{ id: string; symbol: string; name: string; account_id: string }>(
    "SELECT id, symbol, name, account_id FROM holdings WHERE deleted_at IS NULL AND account_id = ?",
    [opts.accountId],
  )) {
    existing.set(keyOf(r.account_id, null, r.symbol || r.name || ""), { id: r.id, isin: null, symbol: r.symbol });
  }

  // Collapse duplicates WITHIN the file (a tradewise P&L lists one row per
  // trade, so the same scrip legitimately appears many times). Quantities add;
  // cost becomes the quantity-weighted average, which is what an average cost
  // means — averaging the per-row averages would be wrong whenever the lot
  // sizes differ.
  const merged = new Map<string, ParsedHolding & { costSum: number; costQty: number }>();
  for (const h of usable) {
    const k = keyOf(opts.accountId, h.isin, h.symbol);
    const hit = merged.get(k);
    if (!hit) {
      merged.set(k, { ...h, costSum: h.avgCost !== null ? h.avgCost * h.quantity : 0, costQty: h.avgCost !== null ? h.quantity : 0 });
      continue;
    }
    hit.quantity += h.quantity;
    if (h.avgCost !== null) { hit.costSum += h.avgCost * h.quantity; hit.costQty += h.quantity; }
    if (h.currentValue !== null) hit.currentValue = (hit.currentValue ?? 0) + h.currentValue;
  }

  const planned = [...merged.entries()].map(([k, h]) => {
    const avgCost = h.costQty > 0 ? h.costSum / h.costQty : h.avgCost;
    return {
      key: k,
      row: h,
      avgCostMinor: avgCost !== null ? fromMajor(Number(avgCost.toFixed(2)), currency).amount : null,
      currentValueMinor: h.currentValue !== null ? fromMajor(Number(h.currentValue.toFixed(2)), currency).amount : null,
    };
  });

  await db.writeTransaction(async (tx) => {
    for (const p of planned) {
      const hit = existing.get(p.key);
      const listed = p.row.assetClass === "stock" || p.row.assetClass === "mf";
      const totalInvested = p.avgCostMinor !== null ? Math.round(p.avgCostMinor * p.row.quantity) : null;

      if (hit) {
        if (opts.onConflict === "skip") { res.skipped++; continue; }
        await tx.execute(
          `UPDATE holdings SET quantity = ?, avg_cost = ?, current_value = ?, name = ?, exchange = ?,
             asset_class = ?, total_invested = ?, updated_at = ? WHERE id = ?`,
          [p.row.quantity, p.avgCostMinor, p.currentValueMinor, p.row.name, p.row.exchange,
           p.row.assetClass, totalInvested, ts, hit.id],
        );
        res.updated++;
        continue;
      }

      await tx.execute(
        `INSERT INTO holdings (id,user_id,account_id,symbol,exchange,quantity,avg_cost,currency,auto_fetch,
           instrument_type,off_list,name,asset_class,current_value,annual_rate,maturity_date,
           source_account_id,planned_id,total_invested,created_at,updated_at)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
        [
          uuid(), userId, opts.accountId, p.row.symbol, p.row.exchange, p.row.quantity, p.avgCostMinor, currency,
          listed ? 1 : 0,          // auto_fetch: only listed instruments have a price to fetch
          p.row.assetClass,
          listed ? 0 : 1,          // off_list: unlisted classes carry a user-supplied value instead
          p.row.name, p.row.assetClass, p.currentValueMinor, null, null,
          null, null, totalInvested, ts, ts,
        ],
      );
      res.created++;
    }
  });

  return res;
}
