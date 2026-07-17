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
  /** When present, sets up a recurring SIP transfer (debit account → this investment
   *  account) that posts on `firstDue` and each period — shows under Recurring / Planned Cashflow. */
  sip?: { amount: number; frequency: Period; firstDue: string; sourceAccountId: string } | null;
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

  // 2) SIP → a recurring transfer rule (debit account → this investment account)
  //    that auto-posts on the SIP date. Surfaces under Recurring / Planned Cashflow.
  let plannedId: string | null = null;
  if (inp.sip && inp.sip.amount > 0 && inp.sip.sourceAccountId) {
    const templateId = await insertRow("transaction_templates", {
      name: inp.name || inp.symbol || "SIP",
      type: "transfer",
      amount: inp.sip.amount,
      currency: inp.currency,
      account_id: inp.sip.sourceAccountId,
      to_account_id: inp.investmentAccountId,
      category_id: null, description: "SIP", note: null, payment_method: null,
      labels: null, split_group_id: null, split_mode: "equal", sort: 0,
    });
    plannedId = await insertRow("recurring_rules", {
      template_id: templateId, frequency: inp.sip.frequency, interval_count: 1,
      next_due: inp.sip.firstDue, last_generated: null, auto_post: 1, active: 1,
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
