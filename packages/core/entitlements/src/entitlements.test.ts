import { test } from "node:test";
import assert from "node:assert/strict";
import { Feature, canUse, isPremiumFeature } from "./index.ts";

test("free tier can track transactions but not advanced analytics", () => {
  assert.ok(canUse(Feature.TrackTransactions, "free"));
  assert.ok(canUse(Feature.BasicBudget, "free"));
  assert.ok(!canUse(Feature.AdvancedAnalytics, "free"));
  assert.ok(!canUse(Feature.Goals, "free"));
});

test("premium tier can use everything", () => {
  for (const f of Object.values(Feature)) {
    assert.ok(canUse(f, "premium"), `premium should allow ${f}`);
  }
});

test("isPremiumFeature classifies correctly", () => {
  assert.ok(!isPremiumFeature(Feature.Search));
  assert.ok(isPremiumFeature(Feature.Statements));
});
