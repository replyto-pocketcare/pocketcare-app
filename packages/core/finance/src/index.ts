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

// ---------------------------------------------------------------------------
// Loan amortization (reducing-balance EMI schedule)
// All money is minor-unit integers. Powers the loan detail page's month-by-month
// principal-vs-interest breakdown.
// ---------------------------------------------------------------------------

export interface AmortRow {
  /** 1-based EMI number. */
  month: number;
  /** EMI actually paid this month (equals `emi`, except a smaller final payment). */
  emi: number;
  /** Interest portion of this EMI. */
  interest: number;
  /** Principal portion of this EMI. */
  principal: number;
  /** Outstanding principal after this EMI. */
  balance: number;
}

/**
 * Standard reducing-balance EMI for a fixed-rate loan (minor-unit integer).
 *   EMI = P·r·(1+r)^n / ((1+r)^n − 1),  r = monthly rate, n = tenure in months.
 * A 0% (or missing) rate gives the flat P/n. Returns 0 for a non-positive tenure.
 */
export function emiFromPrincipal(principal: number, annualRatePct: number, tenureMonths: number): number {
  const P = Math.max(0, Math.round(principal));
  const n = Math.max(0, Math.floor(tenureMonths || 0));
  if (P <= 0 || n <= 0) return 0;
  const r = (annualRatePct || 0) / 100 / 12;
  if (r <= 0) return Math.round(P / n);
  const pow = Math.pow(1 + r, n);
  return Math.round((P * r * pow) / (pow - 1));
}

/**
 * Reducing-balance amortization schedule. Each month, interest = balance × monthly
 * rate, and the rest of the EMI reduces principal. A 0% rate gives a flat
 * principal-only schedule. Stops at `maxMonths` (the tenure) or when the balance
 * hits zero; returns `[]` if the EMI can't even cover the first month's interest
 * (i.e. the loan would never amortize).
 */
export function amortizationSchedule(
  principal: number,
  annualRatePct: number,
  emi: number,
  maxMonths: number,
): AmortRow[] {
  const rows: AmortRow[] = [];
  const r = annualRatePct / 100 / 12;
  let balance = Math.max(0, Math.round(principal));
  const emiRounded = Math.round(emi);
  const cap = Math.min(Math.max(0, Math.round(maxMonths || 0)) || 1200, 1200);

  for (let m = 1; m <= cap && balance > 0; m++) {
    const interest = Math.round(balance * r);
    let principalPaid = emiRounded - interest;
    if (principalPaid <= 0) break; // EMI doesn't cover interest → never amortizes
    let pay = emiRounded;
    if (principalPaid >= balance) {
      principalPaid = balance; // final (partial) payment
      pay = balance + interest;
    }
    balance -= principalPaid;
    rows.push({ month: m, emi: pay, interest, principal: principalPaid, balance });
  }
  return rows;
}

/** Convert a monthly minor-unit amount to a given timeframe bucket total. */
export function timeframeTotal(monthlyAmount: number, timeframe: "monthly" | "quarterly" | "yearly"): number {
  const mult = timeframe === "monthly" ? 1 : timeframe === "quarterly" ? 3 : 12;
  return Math.round(monthlyAmount * mult);
}

// --- Loan EMI scheduling -----------------------------------------------------
// Pure date math for "which EMI is due when" and "which EMIs count as paid".
// Dates are handled as UTC calendar days (YYYY-MM-DD) to avoid timezone drift.

/** Parse a YYYY-MM-DD (or ISO) string into {y, m (0-based), d}, or null. */
function ymd(iso: string | null | undefined): { y: number; m: number; d: number } | null {
  if (!iso) return null;
  const s = String(iso).slice(0, 10);
  const mMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!mMatch) return null;
  const y = Number(mMatch[1]), m = Number(mMatch[2]) - 1, d = Number(mMatch[3]);
  if (m < 0 || m > 11 || d < 1 || d > 31) return null;
  return { y, m, d };
}

/** Days in a given month (month is 0-based). */
function daysInMonth(y: number, m: number): number {
  return new Date(Date.UTC(y, m + 1, 0)).getUTCDate();
}

/** Build a YYYY-MM-DD for (y, m 0-based, day) clamping day to the month length. */
function isoOf(y: number, m: number, day: number): string {
  // normalise month overflow/underflow
  const base = new Date(Date.UTC(y, m, 1));
  const ny = base.getUTCFullYear(), nm = base.getUTCMonth();
  const clamped = Math.min(day, daysInMonth(ny, nm));
  const mm = String(nm + 1).padStart(2, "0");
  const dd = String(clamped).padStart(2, "0");
  return `${ny}-${mm}-${dd}`;
}

/**
 * Due date (YYYY-MM-DD) of EMI number `emiNo` (1-based).
 *
 * `startIso` is when the loan started. `dueDay` (1–31) is the day of the month
 * each EMI falls on; if omitted, the start date's own day-of-month is used.
 * The FIRST EMI is the first occurrence of `dueDay` strictly on/after the start
 * date, and each subsequent EMI is one calendar month later (day clamped to the
 * month, e.g. a 31 due-day lands on Feb 28/29).
 */
export function emiDueDate(startIso: string | null | undefined, dueDay: number | null | undefined, emiNo: number): string | null {
  const start = ymd(startIso);
  if (!start) return null;
  const day = dueDay && dueDay >= 1 && dueDay <= 31 ? Math.floor(dueDay) : start.d;
  // First due: dueDay in the start month, rolled to next month if already passed.
  let firstMonthOffset = 0;
  if (day < start.d) firstMonthOffset = 1;
  const n = Math.max(1, Math.floor(emiNo));
  return isoOf(start.y, start.m + firstMonthOffset + (n - 1), day);
}

/** True if `dueIso` is on or before `asOfIso` (both YYYY-MM-DD, UTC compare). */
export function isDuePassed(dueIso: string | null, asOfIso: string): boolean {
  if (!dueIso) return false;
  return dueIso <= asOfIso.slice(0, 10);
}

/**
 * The set of EMI numbers that count as paid, given manually-marked EMIs and an
 * optional "auto-mark past-due" policy. Derived (not persisted) so toggling
 * `autoMark` off instantly reverts the auto ones; manual marks always win.
 *
 * @param manual   EMI numbers the user marked paid by hand.
 * @param totalEmis how many EMIs the schedule has.
 * @param opts.autoMark  when true, every EMI whose due date has passed counts as paid.
 * @param opts.startIso  loan start date (for due-date derivation).
 * @param opts.dueDay    day-of-month the EMI is due.
 * @param opts.asOfIso   "today" (YYYY-MM-DD); defaults to the real current UTC day.
 */
export function effectivePaidEmis(
  manual: Iterable<number>,
  totalEmis: number,
  opts: { autoMark?: boolean; startIso?: string | null; dueDay?: number | null; asOfIso?: string } = {},
): Set<number> {
  const out = new Set<number>();
  for (const m of manual) if (Number.isFinite(m)) out.add(Math.floor(m));
  const total = Math.max(0, Math.floor(totalEmis || 0));
  if (opts.autoMark && total > 0) {
    const asOf = (opts.asOfIso ?? new Date().toISOString()).slice(0, 10);
    for (let n = 1; n <= total; n++) {
      const due = emiDueDate(opts.startIso, opts.dueDay, n);
      if (isDuePassed(due, asOf)) out.add(n);
    }
  }
  return out;
}
