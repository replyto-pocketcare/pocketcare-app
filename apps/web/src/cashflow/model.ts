/**
 * Planned Cashflow (BETA) — pure model layer.
 *
 * Shapes, quick-start templates, bucket metadata and aggregation helpers for the
 * Planned Cashflow hub. No React, no I/O — so it stays unit-testable and shared.
 * Money is always minor-unit integers; normalisation goes through
 * `monthlyEquivalent` from @pocketcare/finance.
 */
import type { Period } from "@pocketcare/types";
import { monthlyEquivalent } from "@pocketcare/finance";

export type Direction = "income" | "payment" | "saving";
export type Timeframe = "monthly" | "quarterly" | "yearly";

export const TIMEFRAMES: { key: Timeframe; label: string; months: number }[] = [
  { key: "monthly", label: "Monthly", months: 1 },
  { key: "quarterly", label: "Quarterly", months: 3 },
  { key: "yearly", label: "Yearly", months: 12 },
];

/** A row of the synced `planned_cashflow` table (income / payment / saving). */
export interface PlannedItem {
  id: string;
  name: string;
  direction: Direction;
  bucket: string;
  amount: number;
  currency: string;
  frequency: Period;
  timeframe: Timeframe;
  next_due: string | null;
  expected_return: number | null; // annual % ×100
  is_active: number;
}

/** Bucket palette + icon per direction — keeps the UI legible and on-brand. */
export const BUCKETS: Record<Direction, { key: string; label: string; icon: string }[]> = {
  income: [
    { key: "salary", label: "Salary", icon: "◆" },
    { key: "freelance", label: "Freelance", icon: "✦" },
    { key: "rental", label: "Rental", icon: "▤" },
    { key: "other", label: "Other income", icon: "＋" },
  ],
  payment: [
    { key: "household", label: "Household", icon: "⌂" },
    { key: "subscription", label: "Subscription", icon: "↻" },
    { key: "loan", label: "Loan / EMI", icon: "≈" },
    { key: "other", label: "Other", icon: "•" },
  ],
  saving: [
    { key: "fd", label: "Fixed Deposit", icon: "▦" },
    { key: "emergency", label: "Emergency Fund", icon: "◈" },
    { key: "mutual_fund", label: "Mutual Fund", icon: "◱" },
    { key: "stocks", label: "Stocks", icon: "▲" },
    { key: "crypto", label: "Crypto", icon: "◇" },
    { key: "other", label: "Other", icon: "•" },
  ],
};

export function bucketLabel(direction: Direction, key: string): string {
  return BUCKETS[direction]?.find((b) => b.key === key)?.label ?? key;
}
export function bucketIcon(direction: Direction, key: string): string {
  return BUCKETS[direction]?.find((b) => b.key === key)?.icon ?? "•";
}

/** Quick-start templates: one tap pre-fills the add form. */
export interface Template {
  label: string;
  direction: Direction;
  bucket: string;
  frequency: Period;
  timeframe: Timeframe;
  expectedReturnPct?: number; // annual %, savings only
}

export const TEMPLATES: Template[] = [
  // Incomes
  { label: "Monthly Salary", direction: "income", bucket: "salary", frequency: "monthly", timeframe: "monthly" },
  { label: "Freelance Payment", direction: "income", bucket: "freelance", frequency: "monthly", timeframe: "monthly" },
  { label: "Rental Income", direction: "income", bucket: "rental", frequency: "monthly", timeframe: "monthly" },
  // Household / general payments
  { label: "Rent", direction: "payment", bucket: "household", frequency: "monthly", timeframe: "monthly" },
  { label: "Electricity Bill", direction: "payment", bucket: "household", frequency: "monthly", timeframe: "monthly" },
  { label: "House Help", direction: "payment", bucket: "household", frequency: "monthly", timeframe: "monthly" },
  { label: "Groceries", direction: "payment", bucket: "household", frequency: "monthly", timeframe: "monthly" },
  { label: "Internet", direction: "payment", bucket: "household", frequency: "monthly", timeframe: "monthly" },
  // Savings & investments
  { label: "Fixed Deposit", direction: "saving", bucket: "fd", frequency: "monthly", timeframe: "monthly", expectedReturnPct: 7 },
  { label: "Emergency Fund", direction: "saving", bucket: "emergency", frequency: "monthly", timeframe: "monthly", expectedReturnPct: 4 },
  { label: "Mutual Fund SIP", direction: "saving", bucket: "mutual_fund", frequency: "monthly", timeframe: "monthly", expectedReturnPct: 12 },
  { label: "Stocks", direction: "saving", bucket: "stocks", frequency: "monthly", timeframe: "monthly", expectedReturnPct: 11 },
  { label: "Crypto", direction: "saving", bucket: "crypto", frequency: "monthly", timeframe: "monthly", expectedReturnPct: 15 },
];

/** A minimal recurring-like the aggregation helpers accept (subs & loans too). */
export interface MonthlyLike {
  amount: number;
  frequency: Period;
}

/** Sum a set of items as monthly-equivalent minor units. */
export function sumMonthly(items: readonly MonthlyLike[]): number {
  return items.reduce((acc, it) => acc + monthlyEquivalent(it.amount, it.frequency), 0);
}

/** Scale a monthly minor-unit amount to a timeframe window (×1 / ×3 / ×12). */
export function scaleToTimeframe(monthly: number, timeframe: Timeframe): number {
  const t = TIMEFRAMES.find((x) => x.key === timeframe);
  return Math.round(monthly * (t?.months ?? 1));
}

export interface CashflowTotals {
  income: number;
  payments: number;
  savings: number;
  net: number; // income − payments (savings excluded — that's chosen surplus routing)
  surplus: number; // income − payments − savings (truly free cash)
}

/** Roll subscriptions + loans + planned items into monthly-equivalent totals. */
export function computeTotals(args: {
  incomes: readonly MonthlyLike[];
  household: readonly MonthlyLike[];
  savings: readonly MonthlyLike[];
  subscriptions: readonly MonthlyLike[];
  loanEmis: readonly MonthlyLike[];
}): CashflowTotals {
  const income = sumMonthly(args.incomes);
  const payments = sumMonthly(args.household) + sumMonthly(args.subscriptions) + sumMonthly(args.loanEmis);
  const savings = sumMonthly(args.savings);
  return { income, payments, savings, net: income - payments, surplus: income - payments - savings };
}

/** Blended expected annual return across savings items, weighted by monthly contribution. */
export function blendedReturnPct(savings: readonly { amount: number; frequency: Period; expected_return: number | null }[]): number {
  let weight = 0;
  let acc = 0;
  for (const s of savings) {
    const m = monthlyEquivalent(s.amount, s.frequency);
    const r = (s.expected_return ?? 0) / 100; // stored ×100
    weight += m;
    acc += m * r;
  }
  return weight > 0 ? acc / weight : 0;
}
