/**
 * @pocketcare/budget — pure budgeting + credit-card cycle math.
 * All date logic is computed in UTC for determinism. Weeks start Monday (ISO).
 * Money amounts are minor units via @pocketcare/money.
 */
import type { Period } from "@pocketcare/types";
import { subtract, type Money } from "@pocketcare/money";

/** Half-open date window [start, endExclusive). */
export interface DateWindow {
  start: Date;
  endExclusive: Date;
}

function utcMidnight(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}

function addDays(d: Date, days: number): Date {
  return new Date(d.getTime() + days * 86_400_000);
}

/** The budget period window that `date` falls into (UTC, Monday-based weeks). */
export function periodBounds(period: Period, date: Date): DateWindow {
  const day = utcMidnight(date);
  const y = day.getUTCFullYear();
  const m = day.getUTCMonth();
  switch (period) {
    case "daily":
      return { start: day, endExclusive: addDays(day, 1) };
    case "weekly": {
      const dow = day.getUTCDay(); // 0=Sun..6=Sat
      const backToMonday = (dow + 6) % 7;
      const start = addDays(day, -backToMonday);
      return { start, endExclusive: addDays(start, 7) };
    }
    case "monthly":
      return {
        start: new Date(Date.UTC(y, m, 1)),
        endExclusive: new Date(Date.UTC(y, m + 1, 1)),
      };
    case "yearly":
      return {
        start: new Date(Date.UTC(y, 0, 1)),
        endExclusive: new Date(Date.UTC(y + 1, 0, 1)),
      };
  }
}

export interface BudgetProgress {
  /** Percentage of the limit spent (0–∞); Infinity if the limit is 0. */
  pct: number;
  remaining: Money;
  atOrOverThreshold: boolean;
  overLimit: boolean;
}

/** Progress of `spent` against a budget `limit`, flagging threshold/limit breaches. */
export function budgetProgress(limit: Money, spent: Money, thresholdPct: number): BudgetProgress {
  if (limit.currency !== spent.currency) {
    throw new Error("budgetProgress: limit and spent must share a currency");
  }
  const pct = limit.amount === 0 ? Infinity : (spent.amount / limit.amount) * 100;
  return {
    pct,
    remaining: subtract(limit, spent),
    atOrOverThreshold: pct >= thresholdPct,
    overLimit: spent.amount > limit.amount,
  };
}

/**
 * True when spend crosses the threshold on THIS update (was below, now at/above)
 * — the edge to fire a single notification on (feature #5). Idempotent: no repeat
 * alerts while already over.
 */
export function crossedThreshold(
  previousSpent: Money,
  newSpent: Money,
  limit: Money,
  thresholdPct: number,
): boolean {
  const thresholdAmount = (limit.amount * thresholdPct) / 100;
  return previousSpent.amount < thresholdAmount && newSpent.amount >= thresholdAmount;
}

// ---------------- Credit-card billing cycle ----------------

function clampDay(year: number, monthIndex: number, day: number): Date {
  const lastDay = new Date(Date.UTC(year, monthIndex + 1, 0)).getUTCDate();
  return new Date(Date.UTC(year, monthIndex, Math.min(day, lastDay)));
}

function mostRecentDayOnOrBefore(asOf: Date, day: number): Date {
  const cand = clampDay(asOf.getUTCFullYear(), asOf.getUTCMonth(), day);
  if (cand.getTime() <= asOf.getTime()) return cand;
  return clampDay(asOf.getUTCFullYear(), asOf.getUTCMonth() - 1, day);
}

function nextDayStrictlyAfter(from: Date, day: number): Date {
  const cand = clampDay(from.getUTCFullYear(), from.getUTCMonth(), day);
  if (cand.getTime() > from.getTime()) return cand;
  return clampDay(from.getUTCFullYear(), from.getUTCMonth() + 1, day);
}

export interface BillingCycle {
  /** First day of the currently-open cycle. */
  cycleStart: Date;
  /** The day the open cycle closes (its statement date). */
  statementDate: Date;
  /** Payment due date for that statement. */
  dueDate: Date;
}

/**
 * The currently-open billing cycle for a card (feature #6). Charges made now
 * belong to this cycle; it closes on `statementDate` and is due on `dueDate`.
 * Handles months shorter than the chosen day (e.g. a 31st statement day in Feb).
 */
export function billingCycle(statementDay: number, dueDay: number, asOf: Date): BillingCycle {
  const day = utcMidnight(asOf);
  const previousStatement = mostRecentDayOnOrBefore(day, statementDay);
  const cycleStart = addDays(previousStatement, 1);
  const statementDate = nextDayStrictlyAfter(previousStatement, statementDay);
  const dueDate = nextDayStrictlyAfter(statementDate, dueDay);
  return { cycleStart, statementDate, dueDate };
}
