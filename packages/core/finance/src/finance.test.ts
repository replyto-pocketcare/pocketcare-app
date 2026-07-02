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
