import { test } from "node:test";
import assert from "node:assert/strict";
import {
  periodBounds,
  budgetProgress,
  crossedThreshold,
  billingCycle,
} from "./index.ts";
import { money } from "@pocketcare/money";

const iso = (d: Date) => d.toISOString().slice(0, 10);

test("monthly period bounds", () => {
  const w = periodBounds("monthly", new Date("2026-07-02T12:00:00Z"));
  assert.equal(iso(w.start), "2026-07-01");
  assert.equal(iso(w.endExclusive), "2026-08-01");
});

test("yearly period bounds", () => {
  const w = periodBounds("yearly", new Date("2026-07-02T00:00:00Z"));
  assert.equal(iso(w.start), "2026-01-01");
  assert.equal(iso(w.endExclusive), "2027-01-01");
});

test("weekly bounds start Monday", () => {
  // 2026-07-02 is a Thursday -> week starts Mon 2026-06-29
  const w = periodBounds("weekly", new Date("2026-07-02T00:00:00Z"));
  assert.equal(iso(w.start), "2026-06-29");
  assert.equal(iso(w.endExclusive), "2026-07-06");
});

test("daily bounds", () => {
  const w = periodBounds("daily", new Date("2026-07-02T23:59:00Z"));
  assert.equal(iso(w.start), "2026-07-02");
  assert.equal(iso(w.endExclusive), "2026-07-03");
});

test("budgetProgress computes pct, remaining, flags", () => {
  const p = budgetProgress(money(100000, "USD"), money(85000, "USD"), 80);
  assert.equal(p.pct, 85);
  assert.deepEqual(p.remaining, money(15000, "USD"));
  assert.ok(p.atOrOverThreshold);
  assert.ok(!p.overLimit);
});

test("budgetProgress flags over limit", () => {
  const p = budgetProgress(money(100000, "USD"), money(120000, "USD"), 80);
  assert.ok(p.overLimit);
  assert.deepEqual(p.remaining, money(-20000, "USD"));
});

test("crossedThreshold fires only on the crossing edge", () => {
  const limit = money(100000, "USD");
  // 79% -> 81% crosses 80%
  assert.ok(crossedThreshold(money(79000, "USD"), money(81000, "USD"), limit, 80));
  // already above: 81% -> 90% does not re-fire
  assert.ok(!crossedThreshold(money(81000, "USD"), money(90000, "USD"), limit, 80));
  // stays below
  assert.ok(!crossedThreshold(money(10000, "USD"), money(20000, "USD"), limit, 80));
});

test("billingCycle before statement day", () => {
  // statement 15th, due 5th, asOf Jul 2 -> open cycle Jun16..Jul15, due Aug 5
  const c = billingCycle(15, 5, new Date("2026-07-02T00:00:00Z"));
  assert.equal(iso(c.cycleStart), "2026-06-16");
  assert.equal(iso(c.statementDate), "2026-07-15");
  assert.equal(iso(c.dueDate), "2026-08-05");
});

test("billingCycle after statement day", () => {
  // asOf Jul 20 -> open cycle Jul16..Aug15, due Sep 5
  const c = billingCycle(15, 5, new Date("2026-07-20T00:00:00Z"));
  assert.equal(iso(c.cycleStart), "2026-07-16");
  assert.equal(iso(c.statementDate), "2026-08-15");
  assert.equal(iso(c.dueDate), "2026-09-05");
});

test("billingCycle clamps to short months", () => {
  // statement 31st: Feb has no 31 -> clamps to Feb 28 (2026 not leap)
  const c = billingCycle(31, 20, new Date("2026-02-10T00:00:00Z"));
  assert.equal(iso(c.statementDate), "2026-02-28");
});
