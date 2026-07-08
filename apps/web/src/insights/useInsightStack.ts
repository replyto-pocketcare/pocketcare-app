"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@powersync/react";
import { useBaseCurrency } from "../prefs";
import { composeStack, type GenContext, type DayAgg, type MonthAgg, type CatAgg, type BudgetAgg } from "./generators";
import type { InsightCard } from "./types";

const iso = (d: Date) => d.toISOString().slice(0, 10);
const ymOf = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;

interface TypeRow { key: string; type: string; total: number }

/**
 * Builds today's insight stack from the local (PowerSync) ledger. All heavy
 * lifting is SQL aggregates + pure generators, so it recomputes reactively as
 * the data syncs and stays fully offline-first.
 */
export function useInsightStack() {
  const currency = useBaseCurrency();
  const now = useMemo(() => new Date(), []);
  const thisM = ymOf(now);

  // Daily income/expense, last 14 days.
  const { data: dayRows = [] } = useQuery<TypeRow>(
    "SELECT date(occurred_at) as key, type, SUM(amount) as total FROM transactions WHERE deleted_at IS NULL AND type IN ('income','expense') AND occurred_at >= date('now','-14 days') GROUP BY key, type",
  );
  // Monthly income/expense (all history; we slice the tail).
  const { data: monthRows = [] } = useQuery<TypeRow>(
    "SELECT strftime('%Y-%m', occurred_at) as key, type, SUM(amount) as total FROM transactions WHERE deleted_at IS NULL AND type IN ('income','expense') GROUP BY key, type",
  );
  // This month's expenses by category.
  const { data: catRows = [] } = useQuery<{ name: string | null; cid: string | null; total: number }>(
    "SELECT c.name as name, t.category_id as cid, SUM(t.amount) as total FROM transactions t LEFT JOIN categories c ON c.id = t.category_id WHERE t.deleted_at IS NULL AND t.type='expense' AND strftime('%Y-%m', t.occurred_at)=? GROUP BY t.category_id ORDER BY total DESC",
    [thisM],
  );
  // Budgets + their category scope.
  const { data: budgetRows = [] } = useQuery<{ id: string; name: string | null; limit_amount: number; period: string | null }>(
    "SELECT id, name, limit_amount, period FROM budgets WHERE deleted_at IS NULL",
  );
  const { data: budgetCatRows = [] } = useQuery<{ budget_id: string; category_id: string }>(
    "SELECT budget_id, category_id FROM budget_categories",
  );
  // Days with any activity (for the streak), last 30 days.
  const { data: activeDayRows = [] } = useQuery<{ day: string; c: number }>(
    "SELECT date(occurred_at) as day, COUNT(*) as c FROM transactions WHERE deleted_at IS NULL AND occurred_at >= date('now','-30 days') GROUP BY day ORDER BY day",
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

    // ---- categories this month ----
    const cats: CatAgg[] = catRows.map((r) => ({ name: r.name ?? "Uncategorised", expense: r.total }));
    const catExpense = new Map<string, number>();
    for (const r of catRows) if (r.cid) catExpense.set(r.cid, r.total);
    const totalMonthExpense = catRows.reduce((s, r) => s + r.total, 0);

    // ---- budgets (simplified monthly spend vs limit) ----
    const budgetCats = new Map<string, string[]>();
    for (const r of budgetCatRows) {
      const arr = budgetCats.get(r.budget_id) ?? []; arr.push(r.category_id); budgetCats.set(r.budget_id, arr);
    }
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
    if (!daySet.has(iso(cur))) cur.setDate(cur.getDate() - 1); // allow "through yesterday"
    while (daySet.has(iso(cur))) { streak++; cur.setDate(cur.getDate() - 1); }
    const txnDays7: { day: string; count: number }[] = [];
    for (let i = 6; i >= 0; i--) {
      const d = new Date(now); d.setDate(d.getDate() - i); const k = iso(d);
      txnDays7.push({ day: k, count: countByDay.get(k) ?? 0 });
    }

    const ctx: GenContext = { currency, now, days, months, cats, budgets, streak, txnDays7 };
    return composeStack(ctx);
  }, [dayRows, monthRows, catRows, budgetRows, budgetCatRows, activeDayRows, currency, now]);

  const [activeIndex, setActiveIndex] = useState(0);
  const total = cards.length;
  const remaining = Math.max(0, total - (activeIndex + 1));

  return { cards, total, activeIndex, setActiveIndex, remaining };
}
