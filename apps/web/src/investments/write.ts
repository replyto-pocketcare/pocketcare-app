"use client";

/**
 * Write helpers for the Investments page. A holding always sits in an
 * "investment account" (demat / stocks / mutual_funds). Adding one either:
 *   - tracks an EXISTING investment → we raise the account's invested pool with
 *     an `adjustment` entry (money was already in the market, nothing leaves a
 *     savings account); or
 *   - funds a NEW investment → we `transfer` the amount from a chosen savings
 *     account into the investment account (money moves, net worth preserved).
 * In both cases the holding's cost is "deployed" from the pool, so the
 * account's available-to-invest figure stays coherent.
 */
import type { Period } from "@pocketcare/types";
import { insertRow, uuid, nowIso } from "../write";
import { getDb, getUserId } from "../powersync";
import type { AssetClass } from "./model";

async function insertLedger(row: Record<string, unknown>): Promise<void> {
  const db = getDb();
  if (!db) throw new Error("DB not ready");
  const id = uuid();
  const ts = nowIso();
  const full: Record<string, unknown> = { id, user_id: getUserId(), created_at: ts, updated_at: ts, occurred_at: ts, ...row };
  const keys = Object.keys(full);
  await db.execute(`INSERT INTO transactions (${keys.join(",")}) VALUES (${keys.map(() => "?").join(",")})`, keys.map((k) => full[k] as never));
}

export interface AddHoldingInput {
  investmentAccountId: string;
  assetClass: AssetClass;
  symbol: string;
  exchange: string | null;
  name: string;
  quantity: number;
  avgCost: number | null;      // minor units per unit (cost / NAV)
  currency: string;
  currentValue: number | null; // minor units (for unpriced assets)
  annualRate: number | null;   // FD / scheme % p.a.
  maturityDate: string | null;
  offList: boolean;
  autoFetch: boolean;
  funding: { mode: "existing" } | { mode: "new"; sourceAccountId: string };
  /** When present, also records a recurring saving in Planned Cashflow (SIP). */
  sip?: { amount: number; frequency: Period; expectedReturnPct: number | null } | null;
}

export async function addHolding(inp: AddHoldingInput): Promise<string> {
  const costTotal = Math.round((inp.avgCost ?? 0) * inp.quantity);

  // 1) Fund the invested pool.
  if (costTotal > 0) {
    if (inp.funding.mode === "new") {
      await insertLedger({
        account_id: inp.funding.sourceAccountId,
        type: "transfer",
        amount: costTotal,
        currency: inp.currency,
        to_account_id: inp.investmentAccountId,
        to_amount: costTotal,
        description: `Invested in ${inp.name || inp.symbol || "investment"}`,
      });
    } else {
      await insertLedger({
        account_id: inp.investmentAccountId,
        type: "adjustment",
        amount: costTotal,
        currency: inp.currency,
        description: `Existing investment: ${inp.name || inp.symbol || "holding"}`,
      });
    }
  }

  // 2) Optional linked SIP saving in Planned Cashflow.
  let plannedId: string | null = null;
  if (inp.sip && inp.sip.amount > 0) {
    plannedId = await insertRow("planned_cashflow", {
      name: inp.name || inp.symbol || "SIP",
      direction: "saving",
      bucket: "sip",
      amount: inp.sip.amount,
      currency: inp.currency,
      frequency: inp.sip.frequency,
      timeframe: inp.sip.frequency === "yearly" ? "yearly" : "monthly",
      next_due: null,
      expected_return: inp.sip.expectedReturnPct != null ? Math.round(inp.sip.expectedReturnPct * 100) : null,
      is_active: 1,
    });
  }

  // 3) The holding itself.
  return insertRow("holdings", {
    account_id: inp.investmentAccountId,
    symbol: inp.symbol,
    exchange: inp.exchange,
    name: inp.name || null,
    quantity: inp.quantity,
    avg_cost: inp.avgCost,
    currency: inp.currency,
    asset_class: inp.assetClass,
    instrument_type: inp.assetClass === "mf" ? "mf" : inp.assetClass === "stock" ? "stock" : null,
    current_value: inp.currentValue,
    annual_rate: inp.annualRate,
    maturity_date: inp.maturityDate,
    source_account_id: inp.funding.mode === "new" ? inp.funding.sourceAccountId : null,
    planned_id: plannedId,
    off_list: inp.offList ? 1 : 0,
    auto_fetch: inp.autoFetch ? 1 : 0,
  });
}
