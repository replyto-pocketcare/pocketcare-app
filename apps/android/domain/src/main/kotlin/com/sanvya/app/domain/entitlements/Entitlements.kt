package com.sanvya.app.domain.entitlements

// Ported from packages/core/entitlements/src/index.ts (P1.7a). Freemium
// feature gating (features #19/#20). Pure + synchronous so it works
// offline; the current tier comes from the locally-cached `entitlements`
// row (validated on reconnect via RevenueCat).
//
// NOTE (ported faithfully, not "fixed"): packages/types/src/index.ts's
// `Tier` type has FOUR values ("free" | "lite" | "pro" | "premium"), but
// this file's `canUse()` only special-cases the literal string "premium"
// -- a tier of "lite" or "pro" falls through to the free-feature check
// exactly like "free" would. Whether that's intentional (those tiers
// aren't wired up yet) or a latent gap in the TS source is not this
// porting task's call to make; only "free" and "premium" are exercised by
// any golden vector, and the port mirrors the source's actual behavior
// (a bare `tier == "premium"` check) rather than the four-value type it
// nominally accepts.

/** Free-tier features. Everything else requires premium. */
object Feature {
    // Free
    const val TrackTransactions = "track_transactions"
    const val BasicBudget = "basic_budget"
    const val Search = "search"
    const val BalanceView = "balance_view"
    // Premium
    const val AdvancedAnalytics = "advanced_analytics"
    const val MultiBudget = "multi_budget"
    const val BudgetNotifications = "budget_notifications"
    const val Goals = "goals"
    const val Projections = "projections"
    const val SubscriptionSimulator = "subscription_simulator"
    const val InvestmentAutoFetch = "investment_autofetch"
    const val Statements = "statements"
    const val Widgets = "widgets"
    const val PeriodComparison = "period_comparison"
}

/** Features available on the free tier. Everything else requires premium. */
private val FREE_FEATURES: Set<String> = setOf(
    Feature.TrackTransactions,
    Feature.BasicBudget,
    Feature.Search,
    Feature.BalanceView,
)

/** True if the given tier may use the feature. */
fun canUse(feature: String, tier: String): Boolean {
    if (tier == "premium") return true
    return FREE_FEATURES.contains(feature)
}

/** True if the feature sits behind the paywall regardless of current tier. */
fun isPremiumFeature(feature: String): Boolean = !FREE_FEATURES.contains(feature)
