"use client";

import { toMajor, money } from "@pocketcare/money";
import { monthlyEquivalent } from "@pocketcare/finance";
import { getDb, getRepositories, getUserId } from "../powersync";
import { getBaseCurrency } from "../prefs";
import { pairwiseEdges, type Party } from "../splits/math";

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
  splits: { owed: number; owe: number; groups: number };
  /** Last 6 calendar months of income vs expense (major units) for trend charts. */
  monthlyCashflow: { ym: string; income: number; expense: number }[];
  /** Top expense categories over the last ~3 months (major units) for breakdowns. */
  topCategories: { name: string; amount: number }[];
}

const major = (minor: number) => Math.round(minor) / 100;

/** Compact, token-light JSON string of the summary (drops empty sections, caps lists). */
export function summaryForPrompt(s: FinancialSummary): string {
  const out: Record<string, unknown> = {
    baseCurrency: s.baseCurrency,
    liquidSavings: s.liquidSavings,
    avgMonthlyIncome: s.avgMonthlyIncome,
    avgMonthlyExpense: s.avgMonthlyExpense,
    monthlySurplus: s.monthlySurplus,
    fixedMonthlyObligations: s.fixedMonthlyObligations,
    accounts: s.accounts.slice(0, 12).map((a) => ({ n: a.name, t: a.type, c: a.currency, bal: a.balance })),
  };
  if (s.goals.length) out.goals = s.goals.slice(0, 12).map((g) => ({ n: g.name, target: g.target, saved: g.saved, c: g.currency }));
  if (s.upcoming.length) out.upcoming = s.upcoming.slice(0, 8).map((u) => ({ n: u.name, date: u.date, amt: u.amount }));
  if (s.splits.owed || s.splits.owe || s.splits.groups) out.splits = { friendsOweYou: s.splits.owed, youOwe: s.splits.owe, groups: s.splits.groups };
  if (s.monthlyCashflow.some((m) => m.income || m.expense)) out.monthly = s.monthlyCashflow.map((m) => ({ ym: m.ym, in: m.income, exp: m.expense }));
  if (s.topCategories.length) out.topSpendCategories = s.topCategories.map((c) => ({ n: c.name, amt: c.amount }));
  return JSON.stringify(out);
}

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

  // Last 6 calendar months of income vs expense (for trend charts).
  const sixAgo = new Date(); sixAgo.setDate(1); sixAgo.setMonth(sixAgo.getMonth() - 5);
  const byMonth = await db.getAll<{ ym: string; type: string; total: number }>(
    "SELECT strftime('%Y-%m', occurred_at) as ym, type, SUM(amount) as total FROM transactions WHERE deleted_at IS NULL AND type IN ('income','expense') AND occurred_at >= ? GROUP BY ym, type",
    [sixAgo.toISOString()],
  );
  const months: string[] = [];
  const cursor = new Date(); cursor.setDate(1);
  for (let i = 5; i >= 0; i--) { const m = new Date(cursor.getFullYear(), cursor.getMonth() - i, 1); months.push(`${m.getFullYear()}-${String(m.getMonth() + 1).padStart(2, "0")}`); }
  const mMap = new Map<string, { income: number; expense: number }>(months.map((m) => [m, { income: 0, expense: 0 }]));
  for (const r of byMonth) { const e = mMap.get(r.ym); if (e) { if (r.type === "income") e.income = major(r.total); else e.expense = major(r.total); } }
  const monthlyCashflow = months.map((ym) => ({ ym, income: mMap.get(ym)!.income, expense: mMap.get(ym)!.expense }));

  // Top expense categories over the last ~3 months (for breakdowns).
  const catRows = await db.getAll<{ name: string | null; total: number }>(
    "SELECT c.name as name, SUM(t.amount) as total FROM transactions t LEFT JOIN categories c ON c.id = t.category_id WHERE t.deleted_at IS NULL AND t.type = 'expense' AND t.occurred_at >= ? GROUP BY t.category_id ORDER BY total DESC LIMIT 8",
    [since.toISOString()],
  );
  const topCategories = catRows.map((r) => ({ name: r.name || "Uncategorized", amount: major(r.total) }));

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

  // Splits: aggregate you're-owed / you-owe across all groups (derived, like the
  // Friends page), plus a count of active groups/trips.
  const me = getUserId();
  const partRows = await db.getAll<{ expense_id: string; user_id: string; paid_amount: number; share_amount: number }>(
    "SELECT expense_id, user_id, paid_amount, share_amount FROM expense_participants WHERE deleted_at IS NULL",
  );
  const settRows = await db.getAll<{ from_user: string; to_user: string; amount: number }>(
    "SELECT from_user, to_user, amount FROM settlements WHERE deleted_at IS NULL",
  );
  const byExpense = new Map<string, Party[]>();
  for (const p of partRows) {
    const arr = byExpense.get(p.expense_id) ?? [];
    arr.push({ userId: p.user_id, share: p.share_amount, paid: p.paid_amount });
    byExpense.set(p.expense_id, arr);
  }
  const net = new Map<string, number>();
  for (const [, parties] of byExpense) for (const e of pairwiseEdges(parties, me)) net.set(e.userId, (net.get(e.userId) ?? 0) + e.amount);
  for (const st of settRows) {
    if (st.to_user === me) net.set(st.from_user, (net.get(st.from_user) ?? 0) - st.amount);
    else if (st.from_user === me) net.set(st.to_user, (net.get(st.to_user) ?? 0) + st.amount);
  }
  let owedMinor = 0, oweMinor = 0;
  for (const n of net.values()) { if (n > 0) owedMinor += n; else oweMinor += -n; }
  const groupCount = (await db.getOptional<{ c: number }>("SELECT COUNT(*) as c FROM split_groups WHERE deleted_at IS NULL AND IFNULL(is_direct,0)=0"))?.c ?? 0;

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
    splits: { owed: major(owedMinor), owe: major(oweMinor), groups: groupCount },
    monthlyCashflow,
    topCategories,
  };
}
