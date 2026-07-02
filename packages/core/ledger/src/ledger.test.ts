import { test } from "node:test";
import assert from "node:assert/strict";
import {
  signedEffectFor,
  deriveBalance,
  availableBalance,
  aggregateNetWorth,
  type LedgerEntry,
} from "./index.ts";
import { money } from "@pocketcare/money";

const A = "acc-A";
const B = "acc-B";

test("signed effects by type", () => {
  assert.equal(signedEffectFor({ type: "income", account_id: A, amount: 500 }, A), 500);
  assert.equal(signedEffectFor({ type: "expense", account_id: A, amount: 500 }, A), -500);
  assert.equal(signedEffectFor({ type: "opening_balance", account_id: A, amount: 1000 }, A), 1000);
  assert.equal(signedEffectFor({ type: "adjustment", account_id: A, amount: -50 }, A), -50);
});

test("transfer debits source and credits destination", () => {
  const t: LedgerEntry = { type: "transfer", account_id: A, amount: 300, to_account_id: B };
  assert.equal(signedEffectFor(t, A), -300);
  assert.equal(signedEffectFor(t, B), 300);
});

test("cross-currency transfer credits destination with to_amount", () => {
  const t: LedgerEntry = {
    type: "transfer",
    account_id: A,
    amount: 10000, // 100.00 USD out
    to_account_id: B,
    to_amount: 835000, // 8350.00 INR in
  };
  assert.equal(signedEffectFor(t, A), -10000);
  assert.equal(signedEffectFor(t, B), 835000);
});

test("entry not touching the account has zero effect", () => {
  assert.equal(signedEffectFor({ type: "income", account_id: B, amount: 500 }, A), 0);
});

test("deriveBalance sums the ledger", () => {
  const entries: LedgerEntry[] = [
    { type: "opening_balance", account_id: A, amount: 100000 },
    { type: "income", account_id: A, amount: 25000 },
    { type: "expense", account_id: A, amount: 4000 },
    { type: "transfer", account_id: A, amount: 10000, to_account_id: B },
    { type: "income", account_id: B, amount: 999 }, // unrelated to A
  ];
  assert.deepEqual(deriveBalance(A, "USD", entries), money(100000 + 25000 - 4000 - 10000, "USD"));
  assert.deepEqual(deriveBalance(B, "USD", entries), money(10000 + 999, "USD"));
});

test("availableBalance subtracts blocked", () => {
  assert.deepEqual(availableBalance(money(100000, "USD"), money(30000, "USD")), money(70000, "USD"));
});

test("net worth aggregates across currencies", () => {
  // USD 1000.00 + INR 83500.00 -> base USD. Rate INR->USD = 1/83.5
  const rate = (from: string, to: string) => {
    if (from === "INR" && to === "USD") return 1 / 83.5;
    return 1;
  };
  const balances = [
    { balance: money(100000, "USD"), blocked: money(0, "USD") },
    { balance: money(8350000, "INR"), blocked: money(0, "INR") },
  ];
  const nw = aggregateNetWorth(balances, "USD", rate, true);
  // 8350000 paise = 83500 INR -> /83.5 = 1000.00 USD = 100000 cents; +100000 = 200000
  assert.deepEqual(nw, money(200000, "USD"));
});

test("net worth excludes blocked in available view", () => {
  const rate = () => 1;
  const balances = [{ balance: money(100000, "USD"), blocked: money(30000, "USD") }];
  assert.deepEqual(aggregateNetWorth(balances, "USD", rate, true), money(100000, "USD"));
  assert.deepEqual(aggregateNetWorth(balances, "USD", rate, false), money(70000, "USD"));
});
