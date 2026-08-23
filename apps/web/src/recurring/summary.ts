"use client";

/**
 * Monthly view of recurring commitments.
 *
 * Everything on the Recurring screens is expressed "per month" so a weekly bill
 * and a yearly subscription can be compared and added up. `monthlyEquivalent`
 * does the normalising; nothing here should ever sum raw amounts across
 * different frequencies.
 */
import { useMemo } from "react";
import { useQuery } from "@powersync/react";
import { monthlyEquivalent } from "@sanvya/finance";
import type { Period } from "@sanvya/types";
import type { RecurringItem, RecurringDirection } from "../cashflow/recurring";

export interface CategorySlice {
  id: string;
  name: string;
  monthly: number;   // minor units per month
  share: number;     // 0..1 of the direction's total
}

export interface DirectionSummary {
  direction: RecurringDirection;
  items: RecurringItem[];
  /** Minor units per month, always POSITIVE — the sign is the direction's job. */
  monthly: number;
  categories: CategorySlice[];
}

const perMonth = (it: RecurringItem): number =>
  monthlyEquivalent(it.amount, (it.frequency as Period) ?? "monthly");

export function useCategoryNames(): Map<string, string> {
  const { data = [] } = useQuery<{ id: string; name: string }>(
    "SELECT id, name FROM categories WHERE deleted_at IS NULL",
  );
  return useMemo(() => new Map(data.map((c) => [c.id, c.name])), [data]);
}

export function summarise(
  items: RecurringItem[],
  direction: RecurringDirection,
  catNames: Map<string, string>,
): DirectionSummary {
  const mine = items.filter((i) => i.direction === direction);
  const monthly = mine.reduce((s, i) => s + perMonth(i), 0);

  const byCat = new Map<string, number>();
  for (const it of mine) {
    const key = it.category_id ?? "uncategorised";
    byCat.set(key, (byCat.get(key) ?? 0) + perMonth(it));
  }
  const categories: CategorySlice[] = [...byCat.entries()]
    .map(([id, m]) => ({
      id,
      name: id === "uncategorised" ? "Uncategorised" : catNames.get(id) ?? "Uncategorised",
      monthly: m,
      share: monthly > 0 ? m / monthly : 0,
    }))
    .sort((a, b) => b.monthly - a.monthly);

  return { direction, items: mine, monthly, categories };
}

/**
 * Net monthly cashflow = recurring income − recurring expenses.
 *
 * Savings are deliberately EXCLUDED, and not summarised at all. A SIP is a
 * transfer between your own accounts: the money leaves your current account
 * but does not leave your net worth, so counting it as an outflow would
 * understate what you actually have spare each month. Recurring savings live
 * in Investments, next to the holding they fund.
 */
export function useRecurringSummary(items: RecurringItem[]) {
  const catNames = useCategoryNames();
  return useMemo(() => {
    const income = summarise(items, "income", catNames);
    const expense = summarise(items, "payment", catNames);
    return { income, expense, net: income.monthly - expense.monthly };
  }, [items, catNames]);
}
