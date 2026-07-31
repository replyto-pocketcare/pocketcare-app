import Foundation

// Ported from packages/core/entitlements/src/index.ts (P1.7b). Mirrors
// apps/android/domain/.../entitlements/Entitlements.kt (P1.7a). Freemium
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

/// Free-tier features. Everything else requires premium.
public enum Feature {
    // Free
    public static let trackTransactions = "track_transactions"
    public static let basicBudget = "basic_budget"
    public static let search = "search"
    public static let balanceView = "balance_view"
    // Premium
    public static let advancedAnalytics = "advanced_analytics"
    public static let multiBudget = "multi_budget"
    public static let budgetNotifications = "budget_notifications"
    public static let goals = "goals"
    public static let projections = "projections"
    public static let subscriptionSimulator = "subscription_simulator"
    public static let investmentAutoFetch = "investment_autofetch"
    public static let statements = "statements"
    public static let widgets = "widgets"
    public static let periodComparison = "period_comparison"
}

/// Features available on the free tier. Everything else requires premium.
private let FREE_FEATURES: Set<String> = [
    Feature.trackTransactions,
    Feature.basicBudget,
    Feature.search,
    Feature.balanceView,
]

/// True if the given tier may use the feature.
public func canUse(_ feature: String, _ tier: String) -> Bool {
    if tier == "premium" { return true }
    return FREE_FEATURES.contains(feature)
}

/// True if the feature sits behind the paywall regardless of current tier.
public func isPremiumFeature(_ feature: String) -> Bool {
    !FREE_FEATURES.contains(feature)
}
