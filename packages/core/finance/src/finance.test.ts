import { test } from "node:test";
import assert from "node:assert/strict";
import {
  futureValue,
  periodicRateFromAnnual,
  periodsToGoal,
  monthlyEquivalent,
  recurringMonthlyTotal,
  chargesToDate,
  estimatedSpentToDate,
  percentOfIncome,
  subscriptionImpact,
  projectCashflow,
  yearlyEquivalent,
  timeframeTotal,
  amortizationSchedule,
  emiFromPrincipal,
  emiDueDate,
  isDuePassed,
  effectivePaidEmis,
  PERIODS_PER_YEAR,
} from "./index.ts";

test("futureValue with zero rate is linear", () => {
  assert.equal(futureValue(1000, 100, 0, 12), 1000 + 100 * 12);
});

test("futureValue compounds a lump sum", () => {
  // 1000 @ 10%/period for 2 periods = 1210
  assert.equal(futureValue(1000, 0, 0.1, 2), 1210);
});

test("futureValue compounds contributions (annuity)", () => {
  // PMT 100 @ 10% for 3 periods: 100*((1.1^3-1)/0.1)=331
  assert.equal(futureValue(0, 100, 0.1, 3), 331);
});

test("periodicRateFromAnnual splits by period count", () => {
  assert.equal(periodicRateFromAnnual(12, "monthly"), 0.01);
  assert.equal(periodicRateFromAnnual(52, "weekly"), 0.01);
});

test("periodsToGoal with zero rate divides evenly", () => {
  // need 1000 more at 100/period -> 10 periods
  assert.equal(periodsToGoal(0, 1000, 100, 0), 10);
});

test("periodsToGoal returns 0 when already funded", () => {
  assert.equal(periodsToGoal(1500, 1000, 100, 0.01), 0);
});

test("periodsToGoal is unreachable without growth or contribution", () => {
  assert.equal(periodsToGoal(0, 1000, 0, 0), Infinity);
});

test("periodsToGoal with compounding reaches sooner than linear", () => {
  const linear = periodsToGoal(0, 100000, 1000, 0);
  const compounded = periodsToGoal(0, 100000, 1000, 0.02);
  assert.ok(compounded < linear);
});

test("monthlyEquivalent normalizes periods", () => {
  assert.equal(monthlyEquivalent(1200, "yearly"), 100);
  assert.equal(monthlyEquivalent(100, "monthly"), 100);
  assert.equal(monthlyEquivalent(100, "weekly"), Math.round((100 * 52) / 12));
});

test("recurringMonthlyTotal sums normalized costs", () => {
  const total = recurringMonthlyTotal([
    { amount: 1200, frequency: "yearly" }, // 100/mo
    { amount: 500, frequency: "monthly" }, // 500/mo
  ]);
  assert.equal(total, 600);
});

test("percentOfIncome", () => {
  assert.equal(percentOfIncome(600, 3000), 20);
  assert.equal(percentOfIncome(100, 0), Infinity);
});

test("subscriptionImpact: totalPaid and opportunity cost", () => {
  const impact = subscriptionImpact(999, "monthly", 5, 8);
  assert.equal(impact.totalPaid, 999 * 60);
  // Invested at a positive return, opportunity cost exceeds nominal spend.
  assert.ok(impact.opportunityCost > impact.totalPaid);
});

test("PERIODS_PER_YEAR is complete", () => {
  assert.deepEqual(PERIODS_PER_YEAR, { daily: 365, weekly: 52, monthly: 12, yearly: 1 });
});

test("yearlyEquivalent scales by period count", () => {
  assert.equal(yearlyEquivalent(100, "monthly"), 1200);
  assert.equal(yearlyEquivalent(100, "weekly"), 5200);
  assert.equal(yearlyEquivalent(100, "yearly"), 100);
});

test("timeframeTotal multiplies monthly amount by bucket length", () => {
  assert.equal(timeframeTotal(1000, "monthly"), 1000);
  assert.equal(timeframeTotal(1000, "quarterly"), 3000);
  assert.equal(timeframeTotal(1000, "yearly"), 12000);
});

test("projectCashflow returns one snapshot per year", () => {
  const rows = projectCashflow(
    { monthlyIncome: 100000, monthlyPayments: 40000, monthlySavings: 20000, currentSavings: 0, annualReturnPct: 12, annualInflationPct: 0 },
    3,
  );
  assert.equal(rows.length, 3);
  assert.equal(rows[0]!.year, 1);
  assert.equal(rows[2]!.year, 3);
});

test("projectCashflow: net cashflow = income − payments − savings (no inflation)", () => {
  const [y1] = projectCashflow(
    { monthlyIncome: 100000, monthlyPayments: 40000, monthlySavings: 20000, currentSavings: 0, annualReturnPct: 0, annualInflationPct: 0 },
    1,
  );
  assert.equal(y1!.income, 100000 * 12);
  assert.equal(y1!.payments, 40000 * 12);
  assert.equal(y1!.savingsContributed, 20000 * 12);
  assert.equal(y1!.netCashflow, (100000 - 40000 - 20000) * 12);
});

test("projectCashflow: zero-return savings balance is sum of contributions", () => {
  const [y1] = projectCashflow(
    { monthlyIncome: 0, monthlyPayments: 0, monthlySavings: 5000, currentSavings: 10000, annualReturnPct: 0, annualInflationPct: 0 },
    1,
  );
  assert.equal(y1!.savingsBalance, 10000 + 5000 * 12);
});

test("projectCashflow: positive return grows savings above contributions", () => {
  const [y1] = projectCashflow(
    { monthlyIncome: 0, monthlyPayments: 0, monthlySavings: 5000, currentSavings: 0, annualReturnPct: 12, annualInflationPct: 0 },
    1,
  );
  assert.ok(y1!.savingsBalance > 5000 * 12);
});

test("amortizationSchedule: zero interest is flat principal, ends at zero", () => {
  const rows = amortizationSchedule(12000, 0, 1000, 12);
  assert.equal(rows.length, 12);
  assert.equal(rows[0]!.interest, 0);
  assert.equal(rows[0]!.principal, 1000);
  assert.equal(rows[11]!.balance, 0);
});

test("amortizationSchedule: with interest, interest falls and principal rises", () => {
  const rows = amortizationSchedule(100000, 12, 8885, 12); // ~1yr @12%
  assert.ok(rows.length >= 12 - 1 && rows.length <= 13);
  assert.ok(rows[0]!.interest > rows[rows.length - 1]!.interest);
  assert.ok(rows[0]!.principal < rows[rows.length - 1]!.principal);
  assert.equal(rows[rows.length - 1]!.balance, 0);
  // each EMI = interest + principal
  for (const r of rows) assert.equal(r.emi, r.interest + r.principal);
});

test("amortizationSchedule: EMI below interest never amortizes → empty", () => {
  assert.deepEqual(amortizationSchedule(100000, 12, 100, 60), []);
});

test("amortizationSchedule: caps at tenure", () => {
  const rows = amortizationSchedule(1000000, 10, 5000, 6);
  assert.ok(rows.length <= 6);
});

test("projectCashflow: inflation deflates real savings below nominal", () => {
  const [y1] = projectCashflow(
    { monthlyIncome: 0, monthlyPayments: 0, monthlySavings: 5000, currentSavings: 0, annualReturnPct: 0, annualInflationPct: 8 },
    1,
  );
  assert.ok(y1!.realSavingsBalance < y1!.savingsBalance);
});

// --- EMI from principal ---

test("emiFromPrincipal: 0% rate is the flat P/n", () => {
  assert.equal(emiFromPrincipal(120000, 0, 12), 10000);
});

test("emiFromPrincipal: standard reducing-balance formula", () => {
  // ₹1,00,000 @ 12% p.a. (1%/mo) over 12 months → ≈ ₹8,885 EMI.
  assert.equal(emiFromPrincipal(100000, 12, 12), 8885);
});

test("emiFromPrincipal: non-positive tenure or principal → 0", () => {
  assert.equal(emiFromPrincipal(100000, 10, 0), 0);
  assert.equal(emiFromPrincipal(0, 10, 12), 0);
});

test("emiFromPrincipal: computed EMI amortizes the loan within the tenure", () => {
  const P = 500000, rate = 9, n = 24;
  const emi = emiFromPrincipal(P, rate, n);
  const rows = amortizationSchedule(P, rate, emi, n);
  assert.ok(rows.length <= n);                                   // never runs past the tenure
  assert.ok((rows[rows.length - 1]!.balance) < emi);             // essentially cleared by the last EMI
});

// --- Loan EMI scheduling ---

test("emiDueDate: first EMI on the due-day of the start month when due-day >= start day", () => {
  // started on the 3rd, EMI due on the 5th → first EMI same month on the 5th.
  assert.equal(emiDueDate("2026-01-03", 5, 1), "2026-01-05");
  assert.equal(emiDueDate("2026-01-03", 5, 2), "2026-02-05");
  assert.equal(emiDueDate("2026-01-03", 5, 13), "2027-01-05");
});

test("emiDueDate: rolls to next month when the due-day already passed at start", () => {
  // started on the 20th, EMI due on the 5th → first EMI next month.
  assert.equal(emiDueDate("2026-01-20", 5, 1), "2026-02-05");
  assert.equal(emiDueDate("2026-01-20", 5, 2), "2026-03-05");
});

test("emiDueDate: clamps a 31 due-day to short months", () => {
  assert.equal(emiDueDate("2026-01-31", 31, 2), "2026-02-28"); // Feb (non-leap)
  assert.equal(emiDueDate("2024-01-31", 31, 2), "2024-02-29"); // Feb (leap)
  assert.equal(emiDueDate("2026-01-31", 31, 4), "2026-04-30"); // Apr
});

test("emiDueDate: falls back to the start day when no due-day given", () => {
  assert.equal(emiDueDate("2026-03-12", null, 1), "2026-03-12");
  assert.equal(emiDueDate("2026-03-12", null, 3), "2026-05-12");
});

test("emiDueDate: null start → null", () => {
  assert.equal(emiDueDate(null, 5, 1), null);
});

test("isDuePassed: on-or-before as-of counts as passed", () => {
  assert.equal(isDuePassed("2026-01-05", "2026-01-05"), true);
  assert.equal(isDuePassed("2026-01-05", "2026-01-04"), false);
  assert.equal(isDuePassed("2026-01-05", "2026-06-01"), true);
  assert.equal(isDuePassed(null, "2026-06-01"), false);
});

test("effectivePaidEmis: manual only when autoMark off", () => {
  const p = effectivePaidEmis([1, 3], 12, { autoMark: false, startIso: "2026-01-05", dueDay: 5, asOfIso: "2026-12-31" });
  assert.deepEqual([...p].sort((a, b) => a - b), [1, 3]);
});

test("effectivePaidEmis: autoMark adds every past-due EMI, keeps manual future ones", () => {
  // As of 2026-04-10, EMIs due Jan/Feb/Mar/Apr 5th have passed → 1..4 auto-paid.
  // EMI 7 was manually marked (future) and must stay.
  const p = effectivePaidEmis([7], 12, { autoMark: true, startIso: "2026-01-05", dueDay: 5, asOfIso: "2026-04-10" });
  assert.deepEqual([...p].sort((a, b) => a - b), [1, 2, 3, 4, 7]);
});

test("effectivePaidEmis: autoMark before the first due date paints nothing", () => {
  const p = effectivePaidEmis([], 12, { autoMark: true, startIso: "2026-01-05", dueDay: 5, asOfIso: "2026-01-01" });
  assert.equal(p.size, 0);
});

// ---------------------------------------------------------------------------
// chargesToDate / estimatedSpentToDate — lifetime subscription spend
// ---------------------------------------------------------------------------

test("chargesToDate: the signup-day charge counts as the first one", () => {
  // You pay when you subscribe, so day zero is 1 charge, not 0.
  assert.equal(chargesToDate("2026-06-01", "monthly", "2026-06-01"), 1);
  assert.equal(chargesToDate("2026-06-01", "yearly", "2026-06-01"), 1);
});

test("chargesToDate: monthly counts only billing days that have passed", () => {
  assert.equal(chargesToDate("2026-01-15", "monthly", "2026-04-14"), 3); // Jan, Feb, Mar
  assert.equal(chargesToDate("2026-01-15", "monthly", "2026-04-15"), 4); // April's just billed
});

test("chargesToDate: a 31st subscription bills on Feb 28, not March", () => {
  // The billing day is clamped to the month. Treating February as 'not yet the
  // 31st' would skip a charge the user was really billed for.
  assert.equal(chargesToDate("2026-01-31", "monthly", "2026-02-28"), 2);
  assert.equal(chargesToDate("2026-01-31", "monthly", "2026-02-27"), 1);
});

test("chargesToDate: yearly respects the anniversary, including Feb 29", () => {
  // In a non-leap year the anniversary clamps to Feb 28, so it HAS billed —
  // consistent with a 31st monthly subscription billing on Feb 28.
  assert.equal(chargesToDate("2024-02-29", "yearly", "2025-02-28"), 2);
  assert.equal(chargesToDate("2024-02-29", "yearly", "2025-02-27"), 1); // still year one
  assert.equal(chargesToDate("2024-02-29", "yearly", "2026-03-01"), 3);
});

test("chargesToDate: months are calendar months, never 30 days", () => {
  // 30-day months would drift an extra charge every ~5 years. Over a lifetime
  // total that's the error someone spots and stops trusting the number.
  assert.equal(chargesToDate("2020-01-01", "monthly", "2030-01-01"), 121);
});

test("chargesToDate: weekly and daily", () => {
  assert.equal(chargesToDate("2026-06-01", "weekly", "2026-06-07"), 1);
  assert.equal(chargesToDate("2026-06-01", "weekly", "2026-06-08"), 2);
  assert.equal(chargesToDate("2026-06-01", "daily", "2026-06-10"), 10);
});

test("chargesToDate: a future start has billed nothing", () => {
  assert.equal(chargesToDate("2027-01-01", "monthly", "2026-06-01"), 0);
});

test("chargesToDate: missing or unparseable start yields 0, never NaN", () => {
  // These feed a money display; NaN would render as garbage next to a currency.
  assert.equal(chargesToDate(null, "monthly", "2026-06-01"), 0);
  assert.equal(chargesToDate(undefined, "monthly", "2026-06-01"), 0);
  assert.equal(chargesToDate("", "monthly", "2026-06-01"), 0);
  assert.equal(chargesToDate("not a date", "monthly", "2026-06-01"), 0);
});

test("chargesToDate: accepts a full ISO timestamp, not just YYYY-MM-DD", () => {
  assert.equal(chargesToDate("2026-01-15T09:30:00.000Z", "monthly", "2026-04-15"), 4);
});

test("estimatedSpentToDate: price × charges, exact in minor units", () => {
  // ₹499/mo since 15 Jan, as of 15 Apr → 4 charges.
  assert.equal(estimatedSpentToDate(49900, "2026-01-15", "monthly", "2026-04-15"), 199600);
  assert.equal(estimatedSpentToDate(49900, null, "monthly", "2026-04-15"), 0);
});
