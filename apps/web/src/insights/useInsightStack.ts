"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@powersync/react";
import { useBaseCurrency } from "../prefs";
import { composeStack, type GenContext, type DayAgg, type MonthAgg, type CatAgg, type BudgetAgg, type TopExpense, type SubAgg, type GoalAgg } from "./generators";
import type { InsightCard, SeriesPoint } from "./types";

const iso = (d: Date) => d.toISOString().slice(0, 10);
const ymOf = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;

interface TypeRow { key: string; type: string; total: number }

/**
 * Builds today's insight stack from the local (PowerSync) ledger. All heavy
 * lifting is SQL aggregates + pure generators, so it recomputes reactively as
 * data syncs and stays fully offline-first.
 */
export function useInsightStack() {
  const currency = useBaseCurrency();
  const now = useMemo(() => new Date(), []);
  const thisM = ymOf(now);

  const { data: dayRows = [] } = useQuery<TypeRow>(
    "SELECT date(occurred_at) as key, type, SUM(amount) as total FROM transactions WHERE deleted_at IS NULL AND type IN ('income','expense') AND occurred_at >= date('now','-14 days') GROUP BY key, type",
  );
  const { data: monthRows = [] } = useQuery<TypeRow>(
    "SELECT strftime('%Y-%m', occurred_at) as key, type, SUM(amount) as total FROM transactions WHERE deleted_at IS NULL AND type IN ('income','expense') GROUP BY key, type",
  );
  const { data: catRows = [] } = useQuery<{ name: string | null; cid: string | null; total: number }>(
    "SELECT c.name as name, t.category_id as cid, SUM(t.amount) as total FROM transactions t LEFT JOIN categories c ON c.id = t.category_id WHERE t.deleted_at IS NULL AND t.type='expense' AND strftime('%Y-%m', t.occurred_at)=? GROUP BY t.category_id ORDER BY total DESC",
    [thisM],
  );
  const { data: labelRows = [] } = useQuery<{ name: string; total: number }>(
    "SELECT l.name as name, SUM(t.amount) as total FROM transaction_labels tl JOIN labels l ON l.id = tl.label_id JOIN transactions t ON t.id = tl.transaction_id WHERE t.deleted_at IS NULL AND t.type='expense' AND strftime('%Y-%m', t.occurred_at)=? GROUP BY l.id ORDER BY total DESC LIMIT 8",
    [thisM],
  );
  const { data: budgetRows = [] } = useQuery<{ id: string; name: string | null; limit_amount: number; period: string | null }>(
    "SELECT id, name, limit_amount, period FROM budgets WHERE deleted_at IS NULL",
  );
  const { data: budgetCatRows = [] } = useQuery<{ budget_id: string; category_id: string }>(
    "SELECT budget_id, category_id FROM budget_categories",
  );
  const { data: activeDayRows = [] } = useQuery<{ day: string; c: number }>(
    "SELECT date(occurred_at) as day, COUNT(*) as c FROM transactions WHERE deleted_at IS NULL AND occurred_at >= date('now','-30 days') GROUP BY day ORDER BY day",
  );
  const { data: expDayRows = [] } = useQuery<{ day: string; total: number }>(
    "SELECT date(occurred_at) as day, SUM(amount) as total FROM transactions WHERE deleted_at IS NULL AND type='expense' AND occurred_at >= date('now','-70 days') GROUP BY day ORDER BY day",
  );
  const { data: topExpRows = [] } = useQuery<{ description: string | null; note: string | null; amount: number }>(
    "SELECT description, note, amount FROM transactions WHERE deleted_at IS NULL AND type='expense' AND strftime('%Y-%m', occurred_at)=? ORDER BY amount DESC LIMIT 6",
    [thisM],
  );
  const { data: subRows = [] } = useQuery<{ name: string | null; amount: number; billing_cycle: string | null }>(
    "SELECT name, amount, billing_cycle FROM subscriptions WHERE deleted_at IS NULL AND is_active = 1",
  );
  const { data: goalRows = [] } = useQuery<{ name: string | null; target: number; saved: number; emergency: number }>(
    "SELECT g.name as name, g.target_amount as target, g.is_emergency_fund as emergency, COALESCE((SELECT SUM(a.amount_blocked) FROM goal_allocations a WHERE a.goal_id = g.id AND a.deleted_at IS NULL), 0) as saved FROM goals g WHERE g.deleted_at IS NULL",
  );
  const { data: catMonthRows = [] } = useQuery<{ name: string | null; cid: string | null; ym: string; total: number }>(
    "SELECT c.name as name, t.category_id as cid, strftime('%Y-%m', t.occurred_at) as ym, SUM(t.amount) as total FROM transactions t LEFT JOIN categories c ON c.id = t.category_id WHERE t.deleted_at IS NULL AND t.type='expense' AND t.occurred_at >= date('now','-4 months') GROUP BY t.category_id, ym",
  );

  const cards: InsightCard[] = useMemo(() => {
    // ---- continuous 14-day series ----
    const dayMap = new Map<string, { income: number; expense: number }>();
    for (const r of dayRows) {
      const e = dayMap.get(r.key) ?? { income: 0, expense: 0 };
      if (r.type === "income") e.income = r.total; else e.expense = r.total;
      dayMap.set(r.key, e);
    }
    const days: DayAgg[] = [];
    for (let i = 13; i >= 0; i--) {
      const d = new Date(now); d.setDate(d.getDate() - i);
      const k = iso(d); const e = dayMap.get(k) ?? { income: 0, expense: 0 };
      days.push({ day: k, income: e.income, expense: e.expense });
    }

    // ---- continuous 8-month series ----
    const monthMap = new Map<string, { income: number; expense: number }>();
    for (const r of monthRows) {
      const e = monthMap.get(r.key) ?? { income: 0, expense: 0 };
      if (r.type === "income") e.income = r.total; else e.expense = r.total;
      monthMap.set(r.key, e);
    }
    const months: MonthAgg[] = [];
    for (let i = 7; i >= 0; i--) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
      const k = ymOf(d); const e = monthMap.get(k) ?? { income: 0, expense: 0 };
      months.push({ ym: k, income: e.income, expense: e.expense });
    }

    // ---- categories + labels this month ----
    const cats: CatAgg[] = catRows.map((r) => ({ name: r.name ?? "Uncategorised", expense: r.total }));
    const labels: CatAgg[] = labelRows.map((r) => ({ name: r.name, expense: r.total }));
    const catExpense = new Map<string, number>();
    for (const r of catRows) if (r.cid) catExpense.set(r.cid, r.total);
    const totalMonthExpense = catRows.reduce((s, r) => s + r.total, 0);

    // ---- budgets (simplified monthly spend vs limit) ----
    const budgetCats = new Map<string, string[]>();
    for (const r of budgetCatRows) { const a = budgetCats.get(r.budget_id) ?? []; a.push(r.category_id); budgetCats.set(r.budget_id, a); }
    const budgets: BudgetAgg[] = budgetRows
      .filter((b) => !b.period || b.period === "monthly")
      .map((b) => {
        const scoped = budgetCats.get(b.id) ?? [];
        const spent = scoped.length ? scoped.reduce((s, cid) => s + (catExpense.get(cid) ?? 0), 0) : totalMonthExpense;
        return { name: b.name?.trim() || "Budget", limit: b.limit_amount, spent };
      });

    // ---- streak + last-7-day counts ----
    const daySet = new Set(activeDayRows.map((r) => r.day));
    const countByDay = new Map(activeDayRows.map((r) => [r.day, r.c] as const));
    let streak = 0;
    const cur = new Date(now);
    if (!daySet.has(iso(cur))) cur.setDate(cur.getDate() - 1);
    while (daySet.has(iso(cur))) { streak++; cur.setDate(cur.getDate() - 1); }
    const txnDays7: { day: string; count: number }[] = [];
    for (let i = 6; i >= 0; i--) { const d = new Date(now); d.setDate(d.getDate() - i); const k = iso(d); txnDays7.push({ day: k, count: countByDay.get(k) ?? 0 }); }

    // ---- expense-by-day map (70d) for weekday / pace / no-spend / avg ----
    const expDay = new Map(expDayRows.map((r) => [r.day, r.total] as const));

    // weekday averages, last 60 days
    const wdSum = new Array(7).fill(0), wdCnt = new Array(7).fill(0);
    for (let i = 0; i < 60; i++) {
      const d = new Date(now); d.setDate(d.getDate() - i);
      const wd = d.getDay(); wdSum[wd] += expDay.get(iso(d)) ?? 0; wdCnt[wd] += 1;
    }
    const WD = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    const weekday: SeriesPoint[] = WD.map((label, i) => ({ label, value: wdCnt[i] ? Math.round(wdSum[i] / wdCnt[i]) / 100 : 0 }));
    const weekdayTop = weekday.reduce((a, b) => (b.value > a.value ? b : a), weekday[0]!).label;

    // month pace / no-spend / avg
    const dayOfMonth = now.getDate();
    const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    const lastMonthDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    const lastYm = ymOf(lastMonthDate);
    const daysInLastMonth = new Date(now.getFullYear(), now.getMonth(), 0).getDate();
    let thisSoFar = 0, spendDays = 0; const cumulative: SeriesPoint[] = [];
    for (let dd = 1; dd <= dayOfMonth; dd++) {
      const k = `${thisM}-${String(dd).padStart(2, "0")}`;
      const v = expDay.get(k) ?? 0; thisSoFar += v; if (v > 0) spendDays++;
      cumulative.push({ label: String(dd), value: Math.round(thisSoFar) / 100 });
    }
    let lastSameSoFar = 0, lastFull = 0;
    for (let dd = 1; dd <= daysInLastMonth; dd++) {
      const k = `${lastYm}-${String(dd).padStart(2, "0")}`;
      const v = expDay.get(k) ?? 0; lastFull += v; if (dd <= dayOfMonth) lastSameSoFar += v;
    }
    const pace = { thisSoFar, lastSameSoFar, lastFull, dayOfMonth, daysInMonth, cumulative };
    const noSpend = { noSpendDays: Math.max(0, dayOfMonth - spendDays), daysElapsed: dayOfMonth, spendDays };
    const avgDaily = { thisAvg: dayOfMonth ? thisSoFar / dayOfMonth : 0, lastAvg: daysInLastMonth ? lastFull / daysInLastMonth : 0 };

    // top expenses
    const topExpenses: TopExpense[] = topExpRows.map((r) => ({ label: (r.description || r.note || "Expense").trim(), amount: r.amount }));

    // subscriptions (monthly-normalised)
    const norm = (amt: number, cycle: string | null) =>
      cycle === "yearly" ? amt / 12 : cycle === "weekly" ? (amt * 52) / 12 : cycle === "quarterly" ? amt / 3 : amt;
    const subs: SubAgg[] = subRows.map((r) => ({ name: r.name?.trim() || "Subscription", monthly: norm(r.amount, r.billing_cycle) }));
    const subsTotal = subs.reduce((s, x) => s + x.monthly, 0);

    // goals
    const goals: GoalAgg[] = goalRows.map((r) => ({ name: r.name?.trim() || "Goal", target: r.target, saved: r.saved, emergency: Boolean(r.emergency) }));

    // category spike (this month vs prior-months average, per category)
    const byCat = new Map<string, { this: number; prior: number[] }>();
    for (const r of catMonthRows) {
      const key = r.name ?? "Uncategorised";
      const e = byCat.get(key) ?? { this: 0, prior: [] };
      if (r.ym === thisM) e.this = r.total; else e.prior.push(r.total);
      byCat.set(key, e);
    }
    let catSpike: { name: string; thisMonth: number; avgPrior: number } | null = null;
    for (const [name, v] of byCat) {
      if (v.this <= 0 || !v.prior.length) continue;
      const avgPrior = v.prior.reduce((s, x) => s + x, 0) / v.prior.length;
      if (avgPrior <= 0 || v.this < avgPrior * 1.3 || v.this < 50_00) continue; // ignore tiny / <50 units
      if (!catSpike || v.this / avgPrior > catSpike.thisMonth / catSpike.avgPrior) catSpike = { name, thisMonth: v.this, avgPrior };
    }

    const ctx: GenContext = {
      currency, now, days, months, cats, labels, budgets, streak, txnDays7,
      topExpenses, weekday, weekdayTop, subs, subsTotal, goals, pace, noSpend, avgDaily, catSpike,
    };
    return composeStack(ctx);
  }, [dayRows, monthRows, catRows, labelRows, budgetRows, budgetCatRows, activeDayRows, expDayRows, topExpRows, subRows, goalRows, catMonthRows, currency, now, thisM]);

  const [activeIndex, setActiveIndex] = useState(0);
  const total = cards.length;
  const remaining = Math.max(0, total - (activeIndex + 1));

  return { cards, total, activeIndex, setActiveIndex, remaining };
}
