/**
 * @pocketcare/entitlements — freemium feature gating (features #19/#20).
 * Pure + synchronous so it works offline; the current tier comes from the
 * locally-cached `entitlements` row (validated on reconnect via RevenueCat).
 */
import type { Tier } from "@pocketcare/types";

export const Feature = {
  // Free
  TrackTransactions: "track_transactions",
  BasicBudget: "basic_budget",
  Search: "search",
  BalanceView: "balance_view",
  // Premium
  AdvancedAnalytics: "advanced_analytics",
  MultiBudget: "multi_budget",
  BudgetNotifications: "budget_notifications",
  Goals: "goals",
  Projections: "projections",
  SubscriptionSimulator: "subscription_simulator",
  InvestmentAutoFetch: "investment_autofetch",
  Statements: "statements",
  Widgets: "widgets",
  PeriodComparison: "period_comparison",
} as const;
export type Feature = (typeof Feature)[keyof typeof Feature];

/** Features available on the free tier. Everything else requires premium. */
const FREE_FEATURES: ReadonlySet<Feature> = new Set([
  Feature.TrackTransactions,
  Feature.BasicBudget,
  Feature.Search,
  Feature.BalanceView,
]);

/** True if the given tier may use the feature. */
export function canUse(feature: Feature, tier: Tier): boolean {
  if (tier === "premium") return true;
  return FREE_FEATURES.has(feature);
}

/** True if the feature sits behind the paywall regardless of current tier. */
export function isPremiumFeature(feature: Feature): boolean {
  return !FREE_FEATURES.has(feature);
}
