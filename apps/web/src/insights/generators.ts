// Pure insight generators. Each takes a GenContext (already-aggregated numbers
// from PowerSync) and returns zero or more InsightCards. No I/O here — this keeps
// them trivially testable and portable to a backend later.

import { money, format } from "@pocketcare/money";
import type { CurrencyCode } from "@pocketcare/types";
import type { InsightCard, SeriesPoint } from "./types";

// ---- Aggregate inputs (all amounts in MINOR units) ----
export interface DayAgg { day: string; income: number; expense: number }
export interface MonthAgg { ym: string; income: number; expense: number }
export interface CatAgg { name: string; expense: number }
export interface BudgetAgg { name: string; limit: number; spent: number }

export interface GenContext {
  currency: string;
  locale?: string;
  now: Date;
  days: DayAgg[];    // ascending, ~last 14 days
  months: MonthAgg[]; // ascending, ~last 8 months
  cats: CatAgg[];     // this month, descending by expense
  budgets: BudgetAgg[];
  streak: number;     // consecutive days with a logged transaction (through today/yesterday)
  txnDays7: { day: string; count: number }[]; // last 7 days, ascending
}

const fmt = (minor: number, ctx: GenContext) =>
  format(money(Math.round(minor), ctx.currency as CurrencyCode), ctx.locale);

const major = (minor: number) => Math.round(minor) / 100;
const pct = (a: number, b: number) => (b === 0 ? (a > 0 ? 100 : 0) : Math.round(((a - b) / Math.abs(b)) * 100));
const weekday = (iso: string) => new Date(iso + "T00:00:00").toLocaleDateString(undefined, { weekday: "short" });
const monShort = (ym: string) => new Date(ym + "-01T00:00:00").toLocaleDateString(undefined, { month: "short" });

// ---- weekly_summary ----
export function genWeeklySummary(ctx: GenContext): InsightCard[] {
  const last7 = ctx.days.slice(-7);
  if (last7.length < 3) return [];
  const prev7 = ctx.days.slice(-14, -7);
  const sum = (arr: DayAgg[], k: "income" | "expense") => arr.reduce((s, d) => s + d[k], 0);
  const inc = sum(last7, "income"), exp = sum(last7, "expense"), net = inc - exp;
  const prevNet = sum(prev7, "income") - sum(prev7, "expense");
  const series: SeriesPoint[] = last7.map((d) => ({ label: weekday(d.day), value: major(d.income - d.expense) }));
  return [{
    id: `weekly:${last7[0]!.day}`,
    type: "weekly_summary",
    theme: net >= 0 ? "positive" : "warning",
    generatedAt: ctx.now.toISOString(),
    period: { start: last7[0]!.day, end: last7[last7.length - 1]!.day },
    priority: 92,
    headline: net >= 0 ? `You saved ${fmt(net, ctx)} this week` : `You spent ${fmt(-net, ctx)} more than you earned`,
    subhead: "Last 7 days",
    bullets: [
      `Money in: ${fmt(inc, ctx)}`,
      `Money out: ${fmt(exp, ctx)}`,
      prev7.length ? `${net >= prevNet ? "Up" : "Down"} ${fmt(Math.abs(net - prevNet), ctx)} vs the week before` : "Your first week of tracking",
    ],
    metric: { display: fmt(net, ctx), raw: major(net), deltaPct: prev7.length ? pct(net, prevNet) : undefined, direction: net >= prevNet ? "up" : "down" },
    visual: { kind: "ribbon3d", series },
    cadence: { key: "weekly_summary", frequency: "weekly" },
  }];
}

// ---- budget_warning ----
export function genBudgetWarnings(ctx: GenContext): InsightCard[] {
  const flagged = ctx.budgets
    .filter((b) => b.limit > 0 && b.spent / b.limit >= 0.8)
    .sort((a, b) => b.spent / b.limit - a.spent / a.limit)
    .slice(0, 2);
  return flagged.map((b) => {
    const ratio = b.spent / b.limit;
    const over = b.spent > b.limit;
    return {
      id: `budget:${b.name}:${ctx.now.getFullYear()}-${ctx.now.getMonth()}`,
      type: "budget_warning",
      theme: "warning",
      generatedAt: ctx.now.toISOString(),
      period: { start: "", end: "" },
      priority: over ? 100 : 96,
      headline: over ? `${b.name} budget is over by ${fmt(b.spent - b.limit, ctx)}` : `${b.name} budget is ${Math.round(ratio * 100)}% used`,
      subhead: over ? "Over budget" : "Almost there",
      bullets: [
        `Spent ${fmt(b.spent, ctx)} of ${fmt(b.limit, ctx)}`,
        over ? "Consider easing off this category" : `${fmt(b.limit - b.spent, ctx)} left this period`,
      ],
      metric: { display: `${Math.round(ratio * 100)}%`, raw: Math.round(ratio * 100), direction: "up" },
      visual: { kind: "gauge3d", value: major(b.spent), max: major(b.limit), warnAt: major(b.limit) * 0.8, dangerAt: major(b.limit) },
      cta: { label: "Review budgets", target: "/budgets" },
      cadence: { key: `budget_warning:${b.name}`, frequency: "daily" },
    };
  });
}

// ---- savings_achievement ----
export function genSavingsAchievement(ctx: GenContext): InsightCard[] {
  const m = ctx.months;
  if (!m.length) return [];
  const cur = m[m.length - 1]!;
  const net = cur.income - cur.expense;
  if (net <= 0 || cur.income <= 0) return [];
  const rate = Math.round((net / cur.income) * 100);
  const prev = m.length > 1 ? m[m.length - 2]! : null;
  const prevNet = prev ? prev.income - prev.expense : 0;
  return [{
    id: `savings:${cur.ym}`,
    type: "savings_achievement",
    theme: "celebratory",
    generatedAt: ctx.now.toISOString(),
    period: { start: `${cur.ym}-01`, end: `${cur.ym}-01` },
    priority: 84,
    headline: `You saved ${fmt(net, ctx)} in ${monShort(cur.ym)}`,
    subhead: `That's a ${rate}% savings rate`,
    bullets: [
      `Kept ${rate}% of what you earned`,
      prev && net > prevNet ? `Beat last month by ${fmt(net - prevNet, ctx)}` : "Every bit compounds",
    ],
    metric: { display: `${rate}%`, raw: rate, direction: "up" },
    visual: { kind: "orb3d", value: net, target: cur.income },
    cadence: { key: "savings_achievement", frequency: "monthly" },
  }];
}

// ---- spending_trend ----
export function genSpendingTrend(ctx: GenContext): InsightCard[] {
  const m = ctx.months.slice(-6);
  if (m.length < 4) return [];
  const half = Math.floor(m.length / 2);
  const avg = (arr: MonthAgg[]) => arr.reduce((s, x) => s + x.expense, 0) / (arr.length || 1);
  const recent = avg(m.slice(half)), older = avg(m.slice(0, half));
  const down = recent <= older;
  const delta = pct(recent, older);
  const series: SeriesPoint[] = m.map((x) => ({ label: monShort(x.ym), value: major(x.expense) }));
  return [{
    id: `trend:${m[m.length - 1]!.ym}`,
    type: "spending_trend",
    theme: down ? "positive" : "warning",
    generatedAt: ctx.now.toISOString(),
    period: { start: `${m[0]!.ym}-01`, end: `${m[m.length - 1]!.ym}-01` },
    priority: 72,
    headline: down ? "Your spending is trending down" : "Your spending is creeping up",
    subhead: `Over the last ${m.length} months`,
    bullets: [
      `Recent months average ${fmt(recent, ctx)}`,
      `${down ? "Down" : "Up"} ${Math.abs(delta)}% vs earlier months`,
    ],
    metric: { display: `${delta > 0 ? "+" : ""}${delta}%`, raw: delta, direction: down ? "down" : "up" },
    visual: { kind: "ribbon3d", series },
    cadence: { key: "spending_trend", frequency: "weekly" },
  }];
}

// ---- category_breakdown ----
export function genCategoryBreakdown(ctx: GenContext): InsightCard[] {
  const top = ctx.cats.filter((c) => c.expense > 0).slice(0, 6);
  if (top.length < 2) return [];
  const total = top.reduce((s, c) => s + c.expense, 0);
  const lead = top[0]!;
  const series: SeriesPoint[] = top.map((c) => ({ label: c.name, value: major(c.expense) }));
  return [{
    id: `cats:${ctx.now.getFullYear()}-${ctx.now.getMonth()}`,
    type: "category_breakdown",
    theme: "neutral",
    generatedAt: ctx.now.toISOString(),
    period: { start: "", end: "" },
    priority: 62,
    headline: "Where your money went",
    subhead: "This month, by category",
    bullets: [
      `${lead.name} led at ${fmt(lead.expense, ctx)}`,
      `${Math.round((lead.expense / total) * 100)}% of your tracked spending`,
    ],
    metric: { display: fmt(total, ctx), raw: major(total) },
    visual: { kind: "donut3d", series },
    cadence: { key: "category_breakdown", frequency: "weekly" },
  }];
}

// ---- streak ----
export function genStreak(ctx: GenContext): InsightCard[] {
  if (ctx.streak < 3) return [];
  const series: SeriesPoint[] = ctx.txnDays7.map((d) => ({ label: weekday(d.day), value: d.count }));
  return [{
    id: `streak:${ctx.now.toISOString().slice(0, 10)}`,
    type: "streak",
    theme: "celebratory",
    generatedAt: ctx.now.toISOString(),
    period: { start: "", end: "" },
    priority: 55,
    headline: `${ctx.streak}-day logging streak`,
    subhead: "Consistency pays off",
    bullets: [
      `You've logged transactions ${ctx.streak} days running`,
      "The best budgets are the ones you actually keep",
    ],
    metric: { display: `${ctx.streak}`, raw: ctx.streak, direction: "up" },
    visual: { kind: "bars3d", series, unit: "txns" },
    cadence: { key: "streak", frequency: "daily" },
  }];
}

const GENERATORS = [
  genBudgetWarnings, genWeeklySummary, genSavingsAchievement,
  genSpendingTrend, genCategoryBreakdown, genStreak,
];

/** Run every generator, then rank + dedupe by cadence key, capped to `limit`. */
export function composeStack(ctx: GenContext, limit = 8): InsightCard[] {
  const all = GENERATORS.flatMap((g) => g(ctx));
  const byKey = new Map<string, InsightCard>();
  for (const c of all) {
    const existing = byKey.get(c.cadence.key);
    if (!existing || c.priority > existing.priority) byKey.set(c.cadence.key, c);
  }
  return [...byKey.values()].sort((a, b) => b.priority - a.priority).slice(0, limit);
}
