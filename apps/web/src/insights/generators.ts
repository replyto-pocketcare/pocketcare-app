// Pure insight generators. Each takes a GenContext (already-aggregated numbers
// from PowerSync) and returns zero or more InsightCards. No I/O here — trivially
// testable and portable to a backend later.

import { money, format } from "@pocketcare/money";
import type { CurrencyCode } from "@pocketcare/types";
import type { InsightCard, SeriesPoint } from "./types";

// ---- Aggregate inputs (amounts in MINOR units unless noted) ----
export interface DayAgg { day: string; income: number; expense: number }
export interface MonthAgg { ym: string; income: number; expense: number }
export interface CatAgg { name: string; expense: number }
export interface BudgetAgg { name: string; limit: number; spent: number }
export interface TopExpense { label: string; amount: number }
export interface SubAgg { name: string; monthly: number }
export interface GoalAgg { name: string; target: number; saved: number; emergency: boolean }

export interface GenContext {
  currency: string;
  locale?: string;
  now: Date;
  days: DayAgg[];     // ascending, ~last 14 days
  months: MonthAgg[]; // ascending, ~last 8 months
  cats: CatAgg[];     // this month, descending by expense
  labels: CatAgg[];   // this month, descending
  budgets: BudgetAgg[];
  streak: number;
  txnDays7: { day: string; count: number }[];
  topExpenses: TopExpense[];              // this month, descending
  weekday: SeriesPoint[];                 // avg expense (major) per weekday, last 60d
  weekdayTop: string;
  subs: SubAgg[];                         // active subscriptions, monthly-normalised
  subsTotal: number;
  goals: GoalAgg[];
  pace: { thisSoFar: number; lastSameSoFar: number; lastFull: number; dayOfMonth: number; daysInMonth: number; cumulative: SeriesPoint[] };
  noSpend: { noSpendDays: number; daysElapsed: number; spendDays: number };
  avgDaily: { thisAvg: number; lastAvg: number };
  catSpike: { name: string; thisMonth: number; avgPrior: number } | null;
}

const fmt = (minor: number, ctx: GenContext) => format(money(Math.round(minor), ctx.currency as CurrencyCode), ctx.locale);
const major = (minor: number) => Math.round(minor) / 100;
const pct = (a: number, b: number) => (b === 0 ? (a > 0 ? 100 : 0) : Math.round(((a - b) / Math.abs(b)) * 100));
const weekday = (iso: string) => new Date(iso + "T00:00:00").toLocaleDateString(undefined, { weekday: "short" });
const monShort = (ym: string) => new Date(ym + "-01T00:00:00").toLocaleDateString(undefined, { month: "short" });
const trunc = (s: string, n = 22) => (s.length > n ? s.slice(0, n - 1) + "…" : s);

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
    id: `weekly:${last7[0]!.day}`, type: "weekly_summary", theme: net >= 0 ? "positive" : "warning",
    generatedAt: ctx.now.toISOString(), period: { start: last7[0]!.day, end: last7[last7.length - 1]!.day }, priority: 92,
    headline: net >= 0 ? `You saved ${fmt(net, ctx)} this week` : `You spent ${fmt(-net, ctx)} more than you earned`,
    subhead: "Last 7 days",
    bullets: [
      `Money in: ${fmt(inc, ctx)}`, `Money out: ${fmt(exp, ctx)}`,
      prev7.length ? `${net >= prevNet ? "Up" : "Down"} ${fmt(Math.abs(net - prevNet), ctx)} vs the week before` : "Your first week of tracking",
    ],
    metric: { display: fmt(net, ctx), raw: major(net), deltaPct: prev7.length && prevNet !== 0 ? pct(net, prevNet) : undefined, direction: net >= prevNet ? "up" : "down" },
    visual: { kind: "area", series }, cadence: { key: "weekly_summary", frequency: "weekly" },
  }];
}

// ---- budget_warning ----
export function genBudgetWarnings(ctx: GenContext): InsightCard[] {
  return ctx.budgets
    .filter((b) => b.limit > 0 && b.spent / b.limit >= 0.8)
    .sort((a, b) => b.spent / b.limit - a.spent / a.limit)
    .slice(0, 2)
    .map((b) => {
      const ratio = b.spent / b.limit, over = b.spent > b.limit;
      return {
        id: `budget:${b.name}:${ctx.now.getFullYear()}-${ctx.now.getMonth()}`, type: "budget_warning", theme: "warning",
        generatedAt: ctx.now.toISOString(), period: { start: "", end: "" }, priority: over ? 100 : 96,
        headline: over ? `${b.name} budget is over by ${fmt(b.spent - b.limit, ctx)}` : `${b.name} budget is ${Math.round(ratio * 100)}% used`,
        subhead: over ? "Over budget" : "Almost there",
        bullets: [`Spent ${fmt(b.spent, ctx)} of ${fmt(b.limit, ctx)}`, over ? "Consider easing off this category" : `${fmt(b.limit - b.spent, ctx)} left this period`],
        metric: { display: `${Math.round(ratio * 100)}%`, raw: Math.round(ratio * 100) },
        visual: { kind: "gauge", value: major(b.spent), max: major(b.limit), warnAt: major(b.limit) * 0.8, dangerAt: major(b.limit), centerLabel: `${Math.round(ratio * 100)}%` },
        cta: { label: "Review budgets", target: "/budgets" }, cadence: { key: `budget_warning:${b.name}`, frequency: "daily" },
      };
    });
}

// ---- savings_achievement ----
export function genSavingsAchievement(ctx: GenContext): InsightCard[] {
  const m = ctx.months; if (!m.length) return [];
  const cur = m[m.length - 1]!, net = cur.income - cur.expense;
  if (net <= 0 || cur.income <= 0) return [];
  const rate = Math.round((net / cur.income) * 100);
  const prev = m.length > 1 ? m[m.length - 2]! : null, prevNet = prev ? prev.income - prev.expense : 0;
  return [{
    id: `savings:${cur.ym}`, type: "savings_achievement", theme: "celebratory",
    generatedAt: ctx.now.toISOString(), period: { start: `${cur.ym}-01`, end: `${cur.ym}-01` }, priority: 84,
    headline: `You saved ${fmt(net, ctx)} in ${monShort(cur.ym)}`, subhead: `That's a ${rate}% savings rate`,
    bullets: [`Kept ${rate}% of what you earned`, prev && net > prevNet ? `Beat last month by ${fmt(net - prevNet, ctx)}` : "Every bit compounds"],
    metric: { display: `${rate}%`, raw: rate, direction: "up" },
    visual: { kind: "progress", value: net, target: cur.income, centerLabel: `${rate}%` }, cadence: { key: "savings_achievement", frequency: "monthly" },
  }];
}

// ---- spending_trend ----
export function genSpendingTrend(ctx: GenContext): InsightCard[] {
  const m = ctx.months.slice(-6); if (m.length < 4) return [];
  const half = Math.floor(m.length / 2);
  const avg = (arr: MonthAgg[]) => arr.reduce((s, x) => s + x.expense, 0) / (arr.length || 1);
  const recent = avg(m.slice(half)), older = avg(m.slice(0, half)), down = recent <= older, delta = pct(recent, older);
  const series: SeriesPoint[] = m.map((x) => ({ label: monShort(x.ym), value: major(x.expense) }));
  return [{
    id: `trend:${m[m.length - 1]!.ym}`, type: "spending_trend", theme: down ? "positive" : "warning",
    generatedAt: ctx.now.toISOString(), period: { start: `${m[0]!.ym}-01`, end: `${m[m.length - 1]!.ym}-01` }, priority: 72,
    headline: down ? "Your spending is trending down" : "Your spending is creeping up", subhead: `Over the last ${m.length} months`,
    bullets: [`Recent months average ${fmt(recent, ctx)}`, `${down ? "Down" : "Up"} ${Math.abs(delta)}% vs earlier months`],
    metric: { display: `${delta > 0 ? "+" : ""}${delta}%`, raw: delta, direction: down ? "down" : "up" },
    visual: { kind: "area", series }, cadence: { key: "spending_trend", frequency: "weekly" },
  }];
}

// ---- category_breakdown ----
export function genCategoryBreakdown(ctx: GenContext): InsightCard[] {
  const top = ctx.cats.filter((c) => c.expense > 0).slice(0, 6); if (top.length < 2) return [];
  const total = top.reduce((s, c) => s + c.expense, 0), lead = top[0]!;
  return [{
    id: `cats:${ctx.now.getFullYear()}-${ctx.now.getMonth()}`, type: "category_breakdown", theme: "neutral",
    generatedAt: ctx.now.toISOString(), period: { start: "", end: "" }, priority: 62,
    headline: "Where your money went", subhead: "This month, by category",
    bullets: [`${lead.name} led at ${fmt(lead.expense, ctx)}`, `${Math.round((lead.expense / total) * 100)}% of your tracked spending`],
    metric: { display: fmt(total, ctx), raw: major(total) },
    visual: { kind: "donut", series: top.map((c) => ({ label: c.name, value: major(c.expense) })), centerLabel: fmt(total, ctx), centerSub: "this month" },
    cadence: { key: "category_breakdown", frequency: "weekly" },
  }];
}

// ---- streak ----
export function genStreak(ctx: GenContext): InsightCard[] {
  if (ctx.streak < 3) return [];
  return [{
    id: `streak:${ctx.now.toISOString().slice(0, 10)}`, type: "streak", theme: "celebratory",
    generatedAt: ctx.now.toISOString(), period: { start: "", end: "" }, priority: 55,
    headline: `${ctx.streak}-day logging streak`, subhead: "Consistency pays off",
    bullets: [`You've logged transactions ${ctx.streak} days running`, "The best budgets are the ones you actually keep"],
    metric: { display: `${ctx.streak}`, raw: ctx.streak, direction: "up" },
    visual: { kind: "bars", series: ctx.txnDays7.map((d) => ({ label: weekday(d.day), value: d.count })), unit: "txns" },
    cadence: { key: "streak", frequency: "daily" },
  }];
}

// ---- biggest_expense ----
export function genBiggestExpense(ctx: GenContext): InsightCard[] {
  const top = ctx.topExpenses.filter((t) => t.amount > 0).slice(0, 5); if (!top.length) return [];
  const lead = top[0]!;
  return [{
    id: `bigexp:${ctx.now.getFullYear()}-${ctx.now.getMonth()}`, type: "biggest_expense", theme: "neutral",
    generatedAt: ctx.now.toISOString(), period: { start: "", end: "" }, priority: 68,
    headline: `Your biggest expense was ${fmt(lead.amount, ctx)}`, subhead: lead.label || "This month",
    bullets: top.slice(0, 3).map((t) => `${t.label}: ${fmt(t.amount, ctx)}`),
    metric: { display: fmt(lead.amount, ctx), raw: major(lead.amount) },
    visual: { kind: "bars", horizontal: true, series: top.map((t) => ({ label: trunc(t.label, 16), value: major(t.amount) })) },
    cadence: { key: "biggest_expense", frequency: "weekly" },
  }];
}

// ---- weekday_pattern ----
export function genWeekdayPattern(ctx: GenContext): InsightCard[] {
  const nonzero = ctx.weekday.filter((w) => w.value > 0); if (nonzero.length < 3) return [];
  const top = ctx.weekday.reduce((a, b) => (b.value > a.value ? b : a));
  return [{
    id: `weekday:${ctx.now.toISOString().slice(0, 7)}`, type: "weekday_pattern", theme: "neutral",
    generatedAt: ctx.now.toISOString(), period: { start: "", end: "" }, priority: 50,
    headline: `${ctx.weekdayTop} is your priciest day`, subhead: "Average spend by weekday · last 60 days",
    bullets: [`You spend most on ${ctx.weekdayTop}s`, `Around ${fmt(top.value * 100, ctx)} on an average ${ctx.weekdayTop}`],
    visual: { kind: "bars", series: ctx.weekday }, cadence: { key: "weekday_pattern", frequency: "weekly" },
  }];
}

// ---- label_breakdown ----
export function genLabelBreakdown(ctx: GenContext): InsightCard[] {
  const top = ctx.labels.filter((l) => l.expense > 0).slice(0, 6); if (top.length < 2) return [];
  const total = top.reduce((s, l) => s + l.expense, 0), lead = top[0]!;
  return [{
    id: `labels:${ctx.now.getFullYear()}-${ctx.now.getMonth()}`, type: "label_breakdown", theme: "neutral",
    generatedAt: ctx.now.toISOString(), period: { start: "", end: "" }, priority: 54,
    headline: "Spending by label", subhead: "This month, across your tags",
    bullets: [`${lead.name} topped your labels at ${fmt(lead.expense, ctx)}`, `${top.length} labels tracked this month`],
    metric: { display: fmt(total, ctx), raw: major(total) },
    visual: { kind: "donut", series: top.map((l) => ({ label: l.name, value: major(l.expense) })), centerLabel: fmt(total, ctx), centerSub: "labelled" },
    cadence: { key: "label_breakdown", frequency: "weekly" },
  }];
}

// ---- subscriptions_load ----
export function genSubscriptions(ctx: GenContext): InsightCard[] {
  const subs = ctx.subs.filter((s) => s.monthly > 0); if (!subs.length) return [];
  const top = [...subs].sort((a, b) => b.monthly - a.monthly).slice(0, 6);
  return [{
    id: `subs:${ctx.now.toISOString().slice(0, 7)}`, type: "subscriptions_load", theme: "neutral",
    generatedAt: ctx.now.toISOString(), period: { start: "", end: "" }, priority: 64,
    headline: `${fmt(ctx.subsTotal, ctx)}/mo on subscriptions`, subhead: `${subs.length} active subscription${subs.length === 1 ? "" : "s"}`,
    bullets: [`Biggest: ${top[0]!.name} at ${fmt(top[0]!.monthly, ctx)}/mo`, `That's ${fmt(ctx.subsTotal * 12, ctx)} a year`],
    metric: { display: fmt(ctx.subsTotal, ctx), raw: major(ctx.subsTotal) },
    visual: { kind: "donut", series: top.map((s) => ({ label: s.name, value: major(s.monthly) })), centerLabel: fmt(ctx.subsTotal, ctx), centerSub: "per month" },
    cta: { label: "Manage subscriptions", target: "/subscriptions" }, cadence: { key: "subscriptions_load", frequency: "monthly" },
  }];
}

// ---- month_pace ----
export function genMonthPace(ctx: GenContext): InsightCard[] {
  const p = ctx.pace; if (p.dayOfMonth < 3 || p.lastSameSoFar <= 0) return [];
  const projected = (p.thisSoFar / p.dayOfMonth) * p.daysInMonth;
  const faster = p.thisSoFar > p.lastSameSoFar;
  return [{
    id: `pace:${ctx.now.toISOString().slice(0, 7)}`, type: "month_pace", theme: faster ? "warning" : "positive",
    generatedAt: ctx.now.toISOString(), period: { start: "", end: "" }, priority: 74,
    headline: faster ? "You're spending faster than last month" : "You're pacing under last month",
    subhead: `Day ${p.dayOfMonth} of ${p.daysInMonth}`,
    bullets: [`Spent ${fmt(p.thisSoFar, ctx)} so far (was ${fmt(p.lastSameSoFar, ctx)} by now last month)`, `On track for about ${fmt(projected, ctx)} vs ${fmt(p.lastFull, ctx)} last month`],
    metric: { display: fmt(projected, ctx), raw: major(projected), direction: faster ? "up" : "down" },
    visual: { kind: "area", series: p.cumulative }, cadence: { key: "month_pace", frequency: "daily" },
  }];
}

// ---- no_spend_days ----
export function genNoSpendDays(ctx: GenContext): InsightCard[] {
  const n = ctx.noSpend; if (n.daysElapsed < 5) return [];
  return [{
    id: `nospend:${ctx.now.toISOString().slice(0, 7)}`, type: "no_spend_days", theme: "positive",
    generatedAt: ctx.now.toISOString(), period: { start: "", end: "" }, priority: 48,
    headline: `${n.noSpendDays} no-spend day${n.noSpendDays === 1 ? "" : "s"} this month`, subhead: `Out of ${n.daysElapsed} days so far`,
    bullets: [`You didn't spend on ${n.noSpendDays} of ${n.daysElapsed} days`, "No-spend days are an easy savings win"],
    metric: { display: `${n.noSpendDays}`, raw: n.noSpendDays },
    visual: { kind: "donut", series: [{ label: "No-spend", value: n.noSpendDays, color: "var(--positive)" }, { label: "Spent", value: n.spendDays, color: "var(--border)" }], centerLabel: `${n.noSpendDays}`, centerSub: "no-spend days" },
    cadence: { key: "no_spend_days", frequency: "weekly" },
  }];
}

// ---- goal_progress ----
export function genGoalProgress(ctx: GenContext): InsightCard[] {
  const eligible = ctx.goals.filter((g) => g.target > 0);
  if (!eligible.length) return [];
  // Prefer the closest-to-done goal that isn't finished; else the emergency fund.
  const unfinished = eligible.filter((g) => g.saved < g.target).sort((a, b) => b.saved / b.target - a.saved / a.target);
  const g = unfinished[0] ?? eligible.find((x) => x.emergency) ?? eligible[0]!;
  const ratio = Math.min(1, g.saved / g.target), doneP = Math.round(ratio * 100);
  return [{
    id: `goal:${g.name}`, type: "goal_progress", theme: doneP >= 100 ? "celebratory" : "positive",
    generatedAt: ctx.now.toISOString(), period: { start: "", end: "" }, priority: 60,
    headline: doneP >= 100 ? `${g.name} is fully funded!` : `${g.name} is ${doneP}% funded`, subhead: "Goal progress",
    bullets: [`${fmt(g.saved, ctx)} of ${fmt(g.target, ctx)} set aside`, doneP >= 100 ? "Time to set your next goal" : `${fmt(g.target - g.saved, ctx)} to go`],
    metric: { display: `${doneP}%`, raw: doneP, direction: "up" },
    visual: { kind: "gauge", value: major(g.saved), max: major(g.target), centerLabel: `${doneP}%` },
    cta: { label: "View goals", target: "/goals" }, cadence: { key: `goal_progress:${g.name}`, frequency: "weekly" },
  }];
}

// ---- category_spike ----
export function genCategorySpike(ctx: GenContext): InsightCard[] {
  const s = ctx.catSpike; if (!s) return [];
  const up = pct(s.thisMonth, s.avgPrior);
  return [{
    id: `spike:${s.name}:${ctx.now.toISOString().slice(0, 7)}`, type: "category_spike", theme: "warning",
    generatedAt: ctx.now.toISOString(), period: { start: "", end: "" }, priority: 78,
    headline: `${s.name} spending jumped ${up}%`, subhead: "vs your recent average",
    bullets: [`${fmt(s.thisMonth, ctx)} this month`, `Usually around ${fmt(s.avgPrior, ctx)}`],
    metric: { display: `+${up}%`, raw: up, direction: "up" },
    visual: { kind: "bars", series: [{ label: "Usual", value: major(s.avgPrior), color: "var(--forest)" }, { label: "This mo", value: major(s.thisMonth), color: "var(--warning)" }] },
    cta: { label: "See transactions", target: "/transactions" }, cadence: { key: "category_spike", frequency: "weekly" },
  }];
}

// ---- avg_daily_spend ----
export function genAvgDaily(ctx: GenContext): InsightCard[] {
  const p = ctx.pace; if (p.dayOfMonth < 3) return [];
  const { thisAvg, lastAvg } = ctx.avgDaily; if (thisAvg <= 0 && lastAvg <= 0) return [];
  const lower = thisAvg <= lastAvg;
  return [{
    id: `avgday:${ctx.now.toISOString().slice(0, 7)}`, type: "avg_daily_spend", theme: lower ? "positive" : "neutral",
    generatedAt: ctx.now.toISOString(), period: { start: "", end: "" }, priority: 52,
    headline: `You're averaging ${fmt(thisAvg, ctx)}/day`, subhead: lastAvg > 0 ? `${lower ? "Down from" : "Up from"} ${fmt(lastAvg, ctx)}/day last month` : "So far this month",
    bullets: [`${fmt(thisAvg, ctx)} per day this month`, lastAvg > 0 ? `${fmt(lastAvg, ctx)} per day last month` : "Keep it steady"],
    metric: { display: fmt(thisAvg, ctx), raw: major(thisAvg), direction: lower ? "down" : "up" },
    visual: { kind: "bars", series: [{ label: "Last mo", value: major(lastAvg), color: "var(--forest)" }, { label: "This mo", value: major(thisAvg), color: "var(--accent)" }] },
    cadence: { key: "avg_daily_spend", frequency: "weekly" },
  }];
}

const GENERATORS = [
  genBudgetWarnings, genCategorySpike, genMonthPace, genWeeklySummary, genSpendingTrend,
  genBiggestExpense, genSubscriptions, genCategoryBreakdown, genGoalProgress, genSavingsAchievement,
  genStreak, genLabelBreakdown, genAvgDaily, genWeekdayPattern, genNoSpendDays,
];

/** Run every generator, then rank + dedupe by cadence key, capped to `limit`. */
export function composeStack(ctx: GenContext, limit = 12): InsightCard[] {
  const all = GENERATORS.flatMap((g) => g(ctx));
  const byKey = new Map<string, InsightCard>();
  for (const c of all) {
    const existing = byKey.get(c.cadence.key);
    if (!existing || c.priority > existing.priority) byKey.set(c.cadence.key, c);
  }
  return [...byKey.values()].sort((a, b) => b.priority - a.priority).slice(0, limit);
}
