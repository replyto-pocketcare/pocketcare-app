"use client";

import { toMajor, money } from "@pocketcare/money";
import { monthlyEquivalent } from "@pocketcare/finance";
import { getDb, getRepositories } from "../powersync";
import { getBaseCurrency } from "../prefs";

/**
 * An AGGREGATED financial snapshot computed entirely on-device. This is the ONLY
 * financial data sent to the model — never raw transactions. All amounts are in
 * major units (e.g. rupees, not paise) for the model's convenience.
 */
export interface FinancialSummary {
  baseCurrency: string;
  today: string;
  accounts: { name: string; type: string; currency: string; balance: number }[];
  liquidSavings: number;
  avgMonthlyIncome: number;
  avgMonthlyExpense: number;
  monthlySurplus: number;
  fixedMonthlyObligations: number;
  goals: { name: string; target: number; saved: number; currency: string }[];
  upcoming: { name: string; date: string; amount: number; currency: string }[];
}

const major = (minor: number) => Math.round(minor) / 100;

export async function buildFinancialSummary(): Promise<FinancialSummary> {
  const db = getDb();
  if (!db) throw new Error("Database not ready");
  const base = getBaseCurrency();
  const repos = getRepositories();

  const accountRows = await db.getAll<{ id: string; name: string; type: string; currency: string }>(
    "SELECT id, name, type, currency FROM accounts WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0 ORDER BY created_at",
  );
  const accounts: FinancialSummary["accounts"] = [];
  let liquidSavings = 0;
  for (const a of accountRows) {
    const bal = await repos.balances.accountBalance(a.id);
    const balMajor = toMajor(bal);
    accounts.push({ name: a.name, type: a.type, currency: a.currency, balance: balMajor });
    if (["savings", "current", "cash"].includes(a.type) && a.currency === base) liquidSavings += balMajor;
  }

  // Cashflow: 3-month average income / expense.
  const since = new Date();
  since.setMonth(since.getMonth() - 3);
  const flow = await db.getAll<{ type: string; total: number }>(
    "SELECT type, SUM(amount) as total FROM transactions WHERE deleted_at IS NULL AND type IN ('income','expense') AND occurred_at >= ? GROUP BY type",
    [since.toISOString()],
  );
  const inc = flow.find((f) => f.type === "income")?.total ?? 0;
  const exp = flow.find((f) => f.type === "expense")?.total ?? 0;
  const avgMonthlyIncome = major(inc / 3);
  const avgMonthlyExpense = major(exp / 3);

  // Fixed monthly obligations = subscriptions + loan EMIs + recurring commitments.
  const subs = await db.getAll<{ amount: number; billing_cycle: string }>(
    "SELECT amount, billing_cycle FROM subscriptions WHERE is_active = 1 AND deleted_at IS NULL",
  );
  const loans = await db.getAll<{ emi_amount: number | null }>(
    "SELECT emi_amount FROM loans WHERE deleted_at IS NULL AND emi_amount IS NOT NULL",
  );
  const commitments = await db.getAll<{ amount: number; frequency: string }>(
    "SELECT amount, frequency FROM recurring_commitments WHERE deleted_at IS NULL",
  );
  let obligationsMinor = 0;
  for (const s of subs) obligationsMinor += monthlyEquivalent(s.amount, s.billing_cycle as never);
  for (const l of loans) obligationsMinor += l.emi_amount ?? 0;
  for (const c of commitments) obligationsMinor += monthlyEquivalent(c.amount, c.frequency as never);
  const fixedMonthlyObligations = major(obligationsMinor);

  // Goals + progress.
  const goalRows = await db.getAll<{ id: string; name: string; target_amount: number; currency: string }>(
    "SELECT id, name, target_amount, currency FROM goals WHERE deleted_at IS NULL",
  );
  const allocRows = await db.getAll<{ goal_id: string; saved: number }>(
    "SELECT goal_id, SUM(amount_blocked) as saved FROM goal_allocations WHERE deleted_at IS NULL GROUP BY goal_id",
  );
  const goals = goalRows.map((g) => ({
    name: g.name,
    target: major(g.target_amount),
    saved: major(allocRows.find((a) => a.goal_id === g.id)?.saved ?? 0),
    currency: g.currency,
  }));

  // Upcoming obligations in the next 60 days (subscription renewals).
  const soon = new Date();
  soon.setDate(soon.getDate() + 60);
  const renew = await db.getAll<{ name: string; next_renewal: string; amount: number; currency: string }>(
    "SELECT name, next_renewal, amount, currency FROM subscriptions WHERE is_active = 1 AND deleted_at IS NULL AND next_renewal IS NOT NULL",
  );
  const upcoming = renew
    .filter((r) => { const d = new Date(r.next_renewal); return d >= new Date() && d <= soon; })
    .map((r) => ({ name: r.name, date: r.next_renewal, amount: major(r.amount), currency: r.currency }))
    .sort((a, b) => a.date.localeCompare(b.date));

  return {
    baseCurrency: base,
    today: new Date().toISOString().slice(0, 10),
    accounts,
    liquidSavings,
    avgMonthlyIncome,
    avgMonthlyExpense,
    monthlySurplus: +(avgMonthlyIncome - avgMonthlyExpense).toFixed(2),
    fixedMonthlyObligations,
    goals,
    upcoming,
  };
}
