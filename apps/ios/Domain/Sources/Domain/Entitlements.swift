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

/// Ported from apps/web/src/entitlement.ts's useEntitlement() -- the
/// "isPaid" half only (quota/trial-days-left display isn't needed by any
/// mobile screen yet). Added 2026-08-06 for Insights (task #28), the first
/// mobile screen to gate on entitlement at all. Mirrors Android's
/// domain/entitlements/Entitlements.kt isPaid() added the same session.
/// tier is compared post-normalisation: "premium"/"pro" -> pro, "lite" ->
/// lite, else free; a redeemed coupon's compTier wins over the base tier
/// while compUntil is still in the future; a 14-day-old-or-less
/// premiumTrialStartDate grants paid access even on the free tier.
public func isPaid(tier: String?, premiumTrialStartDate: String?, compTier: String?, compUntil: String?, now: Date) -> Bool {
    entitlementState(
        tier: tier,
        premiumTrialStartDate: premiumTrialStartDate,
        compTier: compTier,
        compUntil: compUntil,
        nowMillis: Int64((now.timeIntervalSince1970 * 1000).rounded())
    ).isPaid
}

/// The whole of apps/web/src/entitlement.ts's `Entitlement` -- effective tier,
/// paid/trial state, trial days left, and the AI quota arithmetic.
///
/// ``isPaid(tier:premiumTrialStartDate:compTier:compUntil:now:)`` above used to
/// reimplement the paid half inline; it now delegates here, so there is exactly
/// one place that decides what a tier means. Added 2026-08-23 for the first-run
/// walkthrough, whose step 7 needs `isTrial` specifically -- "your trial is
/// running" and "you are on a paid plan" are different sentences, and only the
/// trial one has a countdown.
///
/// Note the trial rule ported verbatim from web: a trial only counts while the
/// EFFECTIVE tier is free. A paid subscriber with a stale
/// `premium_trial_start_date` is not on trial, they are a customer.
public struct EntitlementState: Equatable, Sendable {
    /// "free" | "lite" | "pro" -- comp tier folded in, highest rank wins.
    public let tier: String
    /// Feature gate: any paid tier OR an active trial.
    public let isPaid: Bool
    public let isTrial: Bool
    public let trialDaysLeft: Int
    public let quotaTotal: Int
    public let quotaUsed: Int
    public let purchased: Int
    public let quotaLeft: Int
}

/// Millis for an ISO-8601 instant, or nil when it is absent/unparseable.
/// A fresh formatter per call (not cached) -- matches this codebase's
/// established non-Sendable-Foundation-formatter rule; tries fractional seconds
/// first, falls back to the no-fraction variant.
private func epochMillisOrNil(_ iso: String?) -> Int64? {
    guard let iso else { return nil }
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = withFraction.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    guard let date else { return nil }
    return Int64((date.timeIntervalSince1970 * 1000).rounded())
}

private func tierRank(_ t: String?) -> Int {
    switch t { case "pro", "premium": return 2; case "lite": return 1; default: return 0 }
}

private func tierName(_ rank: Int) -> String {
    switch rank { case 2: return "pro"; case 1: return "lite"; default: return "free" }
}

public func entitlementState(
    tier: String?,
    premiumTrialStartDate: String?,
    compTier: String?,
    compUntil: String?,
    nowMillis: Int64,
    monthlyQuotaTotal: Int? = nil,
    monthlyQuotaUsed: Int? = nil,
    purchasedQuotaRemaining: Int? = nil,
    additionalPurchasedQuota: Int? = nil
) -> EntitlementState {
    let baseRank = tierRank(tier)
    let compActive = (epochMillisOrNil(compUntil) ?? 0) > nowMillis
    let compRank = compActive ? tierRank(compTier) : 0
    let effectiveRank = max(baseRank, compRank)

    var isTrial = false
    var trialDaysLeft = 0
    if let trialStart = epochMillisOrNil(premiumTrialStartDate), effectiveRank == 0 {
        let days = Int(ceil(Double(nowMillis - trialStart) / 86_400_000.0))
        if days <= 14 {
            isTrial = true
            trialDaysLeft = max(0, 14 - days)
        }
    }

    let quotaTotal = monthlyQuotaTotal ?? 0
    let quotaUsed = monthlyQuotaUsed ?? 0
    let purchased = (purchasedQuotaRemaining ?? 0) + (additionalPurchasedQuota ?? 0)
    return EntitlementState(
        tier: tierName(effectiveRank),
        isPaid: effectiveRank > 0 || isTrial,
        isTrial: isTrial,
        trialDaysLeft: trialDaysLeft,
        quotaTotal: quotaTotal,
        quotaUsed: quotaUsed,
        purchased: purchased,
        quotaLeft: max(0, quotaTotal - quotaUsed) + purchased
    )
}
