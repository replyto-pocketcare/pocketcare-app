import { test } from "node:test";
import assert from "node:assert/strict";
import { parseStatementCsv, parseDate } from "./parseCsv.ts";
import { summarize, byCategory, outliers, recurringCandidates, normalizeMerchant } from "./analysis.ts";
import { reconcile } from "./reconcile.ts";
import type { StatementTxn } from "./types.ts";

// --- date parsing ---
test("parseDate: day-first + ISO + mon formats", () => {
  assert.equal(parseDate("23/03/2026"), "2026-03-23");
  assert.equal(parseDate("23-03-26"), "2026-03-23");
  assert.equal(parseDate("2026-03-23"), "2026-03-23");
  assert.equal(parseDate("23-Mar-2026"), "2026-03-23");
  assert.equal(parseDate("not a date"), null);
});

// --- CSV parsing (HDFC/ICICI-style debit/credit + balance) ---
const CSV = `Account Statement\nAccount No 12345\n\nDate,Narration,Debit,Credit,Balance\n01/03/2026,SALARY CREDIT,,50000.00,60000.00\n03/03/2026,UPI/SWIGGY/ref123,450.00,,59550.00\n10/03/2026,UPI/SWIGGY/ref999,500.00,,59050.00\nnot,a,real,row,\n15/03/2026,ATM WITHDRAWAL,20000.00,,39050.00\n`;

test("parseStatementCsv: finds header, maps columns, signs amounts", () => {
  const s = parseStatementCsv(CSV, { currency: "INR", kind: "bank" });
  assert.equal(s.txns.length, 4);
  assert.equal(s.txns[0]!.amount, 5000000);   // +50,000 credit
  assert.equal(s.txns[1]!.amount, -45000);     // −450 debit
  assert.equal(s.txns[3]!.balance, 3905000);
  assert.equal(s.period.from, "2026-03-01");
  assert.equal(s.period.to, "2026-03-15");
  assert.equal(s.closingBalance, 3905000);
});

// --- analysis ---
const txns: StatementTxn[] = [
  { date: "2026-03-01", description: "Salary", amount: 5000000, category: null },
  { date: "2026-03-03", description: "Swiggy order", amount: -45000, category: "Food" },
  { date: "2026-03-10", description: "Swiggy order", amount: -50000, category: "Food" },
  { date: "2026-03-12", description: "Uber", amount: -30000, category: "Transport" },
  { date: "2026-03-15", description: "ATM withdrawal", amount: -2000000, category: null },
];

test("summarize: credits, debits, net, window", () => {
  const s = summarize(txns);
  assert.equal(s.credits, 5000000);
  assert.equal(s.debits, 2125000);
  assert.equal(s.net, 2875000);
  assert.equal(s.from, "2026-03-01");
  assert.equal(s.to, "2026-03-15");
});

test("byCategory: spends grouped, sorted desc", () => {
  const cats = byCategory(txns);
  assert.equal(cats[0]!.name, "Uncategorised"); // the 20k ATM
  assert.equal(cats[0]!.total, 2000000);
  const food = cats.find((c) => c.name === "Food")!;
  assert.equal(food.total, 95000);
  assert.equal(food.count, 2);
});

test("outliers: flags the unusually large debit", () => {
  const o = outliers(txns);
  assert.ok(o.some((x) => x.txn.description === "ATM withdrawal"));
});

test("normalizeMerchant strips refs/noise", () => {
  assert.equal(normalizeMerchant("UPI/SWIGGY/ref123456"), "swiggy");
});

test("recurringCandidates: repeated similar debit is detected", () => {
  const r = recurringCandidates([
    { date: "2026-01-05", description: "NETFLIX SUBSCRIPTION", amount: -19900 },
    { date: "2026-02-05", description: "NETFLIX SUBSCRIPTION", amount: -19900 },
    { date: "2026-03-05", description: "NETFLIX SUBSCRIPTION", amount: -19900 },
  ]);
  assert.equal(r.length, 1);
  assert.equal(r[0]!.count, 3);
  assert.equal(r[0]!.cadence, "monthly");
  assert.equal(r[0]!.amount, 19900);
});

// --- reconcile ---
test("reconcile: matches by amount+date+desc, flags the missing one", () => {
  const parsed: StatementTxn[] = [
    { date: "2026-03-03", description: "SWIGGY", amount: -45000 },
    { date: "2026-03-10", description: "SWIGGY", amount: -50000 },
    { date: "2026-03-15", description: "ATM", amount: -2000000 },
  ];
  const recorded = [
    { id: "a", amount: -45000, date: "2026-03-03", description: "Swiggy dinner" },
    { id: "b", amount: -50000, date: "2026-03-11", description: "Swiggy lunch" }, // 1 day off
  ];
  const rec = reconcile(parsed, recorded);
  assert.equal(rec.matched.length, 2);
  assert.equal(rec.missingOnPlatform.length, 1);
  assert.equal(rec.missingOnPlatform[0]!.description, "ATM");
  assert.equal(rec.onlyOnPlatform.length, 0);
});

test("reconcile: same amount outside the date window stays unmatched", () => {
  const rec = reconcile(
    [{ date: "2026-03-01", description: "X", amount: -1000 }],
    [{ id: "z", amount: -1000, date: "2026-03-20", description: "X" }],
  );
  assert.equal(rec.matched.length, 0);
  assert.equal(rec.missingOnPlatform.length, 1);
  assert.equal(rec.onlyOnPlatform.length, 1);
});
