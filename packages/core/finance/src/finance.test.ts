import { test } from "node:test";
import assert from "node:assert/strict";
import {
  futureValue,
  periodicRateFromAnnual,
  periodsToGoal,
  monthlyEquivalent,
  recurringMonthlyTotal,
  percentOfIncome,
  subscriptionImpact,
  projectCashflow,
  yearlyEquivalent,
  timeframeTotal,
  amortizationSchedule,
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
