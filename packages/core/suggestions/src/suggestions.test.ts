import { test } from "node:test";
import assert from "node:assert/strict";
import {
  pickSuggestions,
  isFeatureId,
  RULES,
  FEATURES,
  MAX_VISIBLE,
  type UsageCounts,
} from "./index.ts";

/** An established user: plenty of history, nothing else set up. */
const ACTIVE: UsageCounts = { accounts: 2, transactions: 40 };

test("a brand-new user is suggested nothing at all", () => {
  // The first-run walkthrough owns this moment. A suggestion strip on top of it
  // is clutter, and every card would fire at once.
  assert.deepEqual(pickSuggestions({}), []);
  assert.deepEqual(pickSuggestions({ accounts: 0, transactions: 0 }), []);
});

test("suggestions have to be earned — nothing fires on a near-empty account", () => {
  // One transaction is not enough evidence to recommend budgeting.
  assert.deepEqual(pickSuggestions({ accounts: 1, transactions: 1 }), []);
});

test("subscriptions unlock first, being the cheapest useful thing to add", () => {
  assert.deepEqual(pickSuggestions({ accounts: 1, transactions: 5 }), ["subscriptions"]);
});

test("an established user gets several, in weight order, capped", () => {
  const picked = pickSuggestions(ACTIVE);
  assert.equal(picked.length, MAX_VISIBLE);
  assert.equal(picked[0], "subscriptions");
  assert.equal(picked[1], "budgets");
  // Never more than the cap, however much is unused — a wall of cards is a demand.
  assert.ok(picked.length <= MAX_VISIBLE);
});

test("using a feature removes its suggestion, and nothing else", () => {
  const before = pickSuggestions(ACTIVE);
  const after = pickSuggestions({ ...ACTIVE, subscriptions: 1 });
  assert.ok(before.includes("subscriptions"));
  assert.ok(!after.includes("subscriptions"));
  assert.ok(after.includes("budgets"));
});

test("dismissal is permanent and per-feature", () => {
  const after = pickSuggestions(ACTIVE, { dismissed: ["subscriptions", "budgets"] });
  assert.ok(!after.includes("subscriptions"));
  assert.ok(!after.includes("budgets"));
  assert.ok(after.length > 0, "dismissing two shouldn't silence the rest");
});

test("dismissing everything yields an empty strip, not a fallback", () => {
  assert.deepEqual(pickSuggestions(ACTIVE, { dismissed: FEATURES }), []);
});

test("credit cards are suggested only to someone who holds one", () => {
  assert.ok(!pickSuggestions(ACTIVE).includes("creditCards"));
  const withCard = pickSuggestions({ ...ACTIVE, creditCardAccounts: 1 });
  assert.ok(withCard.includes("creditCards"), "a card account makes it relevant");
});

test("premium features are never suggested to a free user", () => {
  // Suggesting something they'd have to pay to touch is an ad, not a tip.
  //
  // Asserted against the rule table rather than one named feature: Planned
  // Cashflow was the only premium suggestion and it has been removed, so
  // naming a feature here would have meant deleting this test and leaving the
  // gating in pickSuggestions untested until someone marked something premium
  // again. Written this way it passes vacuously today and starts biting the
  // moment a premium rule reappears.
  const premiumIds = RULES.filter((r) => r.premium).map((r) => r.id);
  const free = pickSuggestions({ ...ACTIVE, transactions: 200 }, { isPaid: false, max: 99 });
  for (const id of premiumIds) {
    assert.ok(!free.includes(id), `premium feature ${id} was suggested to a free user`);
  }
  const paid = pickSuggestions({ ...ACTIVE, transactions: 200 }, { isPaid: true, max: 99 });
  for (const id of premiumIds) {
    assert.ok(paid.includes(id), `premium feature ${id} should be suggested to a paid user`);
  }
});

test("a fully-explored user is suggested nothing", () => {
  const done: UsageCounts = {
    accounts: 3, transactions: 500,
    subscriptions: 1, loans: 1, budgets: 1, goals: 1, splitGroups: 1, receipts: 1,
    recurring: 1, holdings: 1, creditCards: 1, creditCardAccounts: 1,
  };
  assert.deepEqual(pickSuggestions(done, { isPaid: true, max: 99 }), []);
});

test("undefined and NaN counts are treated as zero, never as usage", () => {
  // These arrive from SQL COUNT() through a loading state; a NaN slipping
  // through as "truthy usage" would silently hide a suggestion forever.
  const u = { accounts: 1, transactions: 40, subscriptions: NaN as number };
  assert.ok(pickSuggestions(u).includes("subscriptions"));
});

test("max: 0 yields nothing rather than everything", () => {
  assert.deepEqual(pickSuggestions(ACTIVE, { max: 0 }), []);
});

test("every rule id is a known feature, and ids are unique", () => {
  // Ids are persisted in dismissals, so a duplicate or a stray would silently
  // mute the wrong card.
  const ids = RULES.map((r) => r.id);
  assert.equal(new Set(ids).size, ids.length);
  for (const id of ids) assert.ok(isFeatureId(id), `${id} missing from FEATURES`);
  assert.equal(ids.length, FEATURES.length);
});

test("isFeatureId rejects an unknown persisted id", () => {
  assert.equal(isFeatureId("subscriptions"), true);
  assert.equal(isFeatureId("crypto-staking"), false);
});
