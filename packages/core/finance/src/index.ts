/**
 * @pocketcare/finance — pure financial math (no I/O, no money formatting).
 *
 * Amounts are plain numbers in MINOR UNITS (integers in, rounded integers out
 * for money results). Rates are decimals per period unless noted. Deterministic
 * and unit-tested — powers goal ETAs (feature #15) and the subscription
 * impact simulator (feature #11).
 */
import type { Period } from "@pocketcare/types";

/** How many times each budgeting/commitment period occurs per year. */
export const PERIODS_PER_YEAR: Record<Period, number> = {
  daily: 365,
  weekly: 52,
  monthly: 12,
  yearly: 1,
};

/**
 * Future value of a starting principal plus a recurring contribution made every
 * period, compounded at `periodicRate` (decimal, e.g. 0.01 = 1%/period).
 *   FV = P(1+r)^n + PMT * ((1+r)^n - 1) / r
 * Returns a rounded minor-unit integer.
 */
export function futureValue(
  principal: number,
  contribution: number,
  periodicRate: number,
  periods: number,
): number {
  if (periods < 0) throw new Error("periods must be >= 0");
  let fv: number;
  if (periodicRate === 0) {
    fv = principal + contribution * periods;
  } else {
    const growth = (1 + periodicRate) ** periods;
    fv = principal * growth + contribution * ((growth - 1) / periodicRate);
  }
  return Math.round(fv);
}

/** Convert an annual percentage rate (e.g. 8 for 8%) to a per-period decimal. */
export function periodicRateFromAnnual(annualPct: number, period: Period): number {
  return annualPct / 100 / PERIODS_PER_YEAR[period];
}

/**
 * Number of whole periods until `current` grows to `target`, given a recurring
 * `contribution` each period compounding at `periodicRate`.
 * Returns Infinity if the goal can never be reached.
 * Closed form: n = ln((T·r + PMT) / (P·r + PMT)) / ln(1 + r)
 */
export function periodsToGoal(
  current: number,
  target: number,
  contribution: number,
  periodicRate: number,
): number {
  if (current >= target) return 0;
  if (periodicRate === 0) {
    if (contribution <= 0) return Infinity;
    return Math.ceil((target - current) / contribution);
  }
  const numerator = target * periodicRate + contribution;
  const denominator = current * periodicRate + contribution;
  if (denominator <= 0 || numerator <= 0) return Infinity;
  const n = Math.log(numerator / denominator) / Math.log(1 + periodicRate);
  if (!Number.isFinite(n) || n < 0) return Infinity;
  return Math.ceil(n);
}

/** Normalize any period amount to its monthly equivalent (rounded minor units). */
export function monthlyEquivalent(amount: number, period: Period): number {
  const perYear = PERIODS_PER_YEAR[period];
  return Math.round((amount * perYear) / 12);
}

export interface RecurringLike {
  amount: number;
  frequency: Period;
}

/** Total monthly cost of a set of recurring commitments (EMIs, subs, expenses). */
export function recurringMonthlyTotal(items: readonly RecurringLike[]): number {
  return items.reduce((acc, it) => acc + monthlyEquivalent(it.amount, it.frequency), 0);
}

/** What percentage of monthly income the given monthly amount represents. */
export function percentOfIncome(monthlyAmount: number, monthlyIncome: number): number {
  if (monthlyIncome <= 0) return Infinity;
  return (monthlyAmount / monthlyIncome) * 100;
}

export interface SubscriptionImpact {
  /** Total nominal spend over the horizon. */
  totalPaid: number;
  /**
   * Opportunity cost: what that same recurring spend would have grown to if
   * invested instead, over the horizon. Highlights the true cost (feature #11).
   */
  opportunityCost: number;
}

/**
 * Project the impact of a subscription over `years`, assuming the money could
 * otherwise be invested at `annualReturnPct`. Contributions are modelled monthly.
 */
export function subscriptionImpact(
  amount: number,
  frequency: Period,
  years: number,
  annualReturnPct: number,
): SubscriptionImpact {
  const monthly = monthlyEquivalent(amount, frequency);
  const months = Math.round(years * 12);
  const totalPaid = monthly * months;
  const r = annualReturnPct / 100 / 12;
  const invested = futureValue(0, monthly, r, months);
  return { totalPaid, opportunityCost: invested };
}

// ---------------------------------------------------------------------------
// Planned Cashflow projection engine (BETA)
// Deterministic, offline, inflation-aware forecast powering the 1/2/3-year
// "future financial structure" in the Planned Cashflow hub. All money values
// are minor-unit integers in and out. Modelled month-by-month so compounding is
// accurate; income/payments grow annually, savings compound at a real return.
// ---------------------------------------------------------------------------

export interface CashflowInputs {
  /** Recurring income normalised to a monthly minor-unit amount. */
  monthlyIncome: number;
  /** Planned payments (subscriptions + loan EMIs + household) per month. */
  monthlyPayments: number;
  /** Planned savings/investment contributions per month. */
  monthlySavings: number;
  /** Starting savings/investment balance (minor units). */
  currentSavings: number;
  /** Expected blended annual return on savings, percent (e.g. 8). */
  annualReturnPct: number;
  /** Expected annual inflation, percent (e.g. 6). Grows payments + deflates real value. */
  annualInflationPct: number;
  /** Optional annual income growth (raises), percent. Defaults to 0. */
  incomeGrowthPct?: number;
}

export interface YearProjection {
  /** 1-based year offset from today. */
  year: number;
  /** Nominal income received across the year. */
  income: number;
  /** Nominal planned payments across the year (inflation-grown). */
  payments: number;
  /** Nominal savings contributed across the year. */
  savingsContributed: number;
  /** Surplus after payments and savings contributions (income − payments − savings). */
  netCashflow: number;
  /** Projected end-of-year savings balance incl. compounded growth. */
  savingsBalance: number;
  /** Savings balance expressed in today's money (inflation-adjusted). */
  realSavingsBalance: number;
}

/**
 * Project year-by-year cashflow and savings growth over `years`.
 * Income and payments step up once per year (raises / inflation); savings
 * compound monthly at the annual return and receive the monthly contribution.
 */
export function projectCashflow(inp: CashflowInputs, years: number): YearProjection[] {
  if (years < 0) throw new Error("years must be >= 0");
  const monthlyReturn = inp.annualReturnPct / 100 / 12;
  const inflation = inp.annualInflationPct / 100;
  const incomeGrowth = (inp.incomeGrowthPct ?? 0) / 100;

  let savings = inp.currentSavings;
  const out: YearProjection[] = [];

  for (let y = 1; y <= years; y++) {
    // Annual step-ups applied at the start of each year.
    const growthFactor = (1 + incomeGrowth) ** (y - 1);
    const inflationFactor = (1 + inflation) ** (y - 1);
    const income = Math.round(inp.monthlyIncome * growthFactor);
    const payments = Math.round(inp.monthlyPayments * inflationFactor);
    const contribution = Math.round(inp.monthlySavings * inflationFactor);

    let yearIncome = 0;
    let yearPayments = 0;
    let yearContrib = 0;
    for (let m = 0; m < 12; m++) {
      yearIncome += income;
      yearPayments += payments;
      yearContrib += contribution;
      savings = savings * (1 + monthlyReturn) + contribution;
    }
    const realDeflator = (1 + inflation) ** y;
    out.push({
      year: y,
      income: yearIncome,
      payments: yearPayments,
      savingsContributed: yearContrib,
      netCashflow: yearIncome - yearPayments - yearContrib,
      savingsBalance: Math.round(savings),
      realSavingsBalance: Math.round(savings / realDeflator),
    });
  }
  return out;
}

/** Convert an amount from any period to its yearly equivalent (rounded minor units). */
export function yearlyEquivalent(amount: number, period: Period): number {
  return Math.round(amount * PERIODS_PER_YEAR[period]);
}

/** Convert a monthly minor-unit amount to a given timeframe bucket total. */
export function timeframeTotal(monthlyAmount: number, timeframe: "monthly" | "quarterly" | "yearly"): number {
  const mult = timeframe === "monthly" ? 1 : timeframe === "quarterly" ? 3 : 12;
  return Math.round(monthlyAmount * mult);
}
