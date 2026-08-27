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

/**
 * Ported from apps/web/src/entitlement.ts's useEntitlement() -- the "isPaid"
 * half only (quota/trial-days-left display isn't needed by any mobile
 * screen yet). Added 2026-08-06 for Insights (task #28), the first mobile
 * screen to gate on entitlement at all (canUse()/Feature above have zero
 * other call sites in the app). tier is compared post-normalisation:
 * "premium"/"pro" -> pro, "lite" -> lite, else free; a redeemed coupon's
 * comp_tier wins over the base tier while compUntil is still in the future;
 * a 14-day-old-or-less premium_trial_start_date grants paid access even on
 * the free tier.
 */
fun isPaid(tier: String?, premiumTrialStartDate: String?, compTier: String?, compUntil: String?, nowMillis: Long): Boolean =
    entitlementState(
        tier = tier,
        premiumTrialStartDate = premiumTrialStartDate,
        compTier = compTier,
        compUntil = compUntil,
        nowMillis = nowMillis,
    ).isPaid

/**
 * The whole of apps/web/src/entitlement.ts's `Entitlement` -- effective tier,
 * paid/trial state, trial days left, and the AI quota arithmetic.
 *
 * [isPaid] above used to reimplement the paid half inline; it now delegates
 * here, so there is exactly one place that decides what a tier means. Added
 * 2026-08-23 for the first-run walkthrough, whose step 7 needs `isTrial`
 * specifically -- "your trial is running" and "you are on a paid plan" are
 * different sentences, and only the trial one has a countdown.
 *
 * Note the trial rule ported verbatim from web: a trial only counts while the
 * EFFECTIVE tier is free. A paid subscriber with a stale
 * `premium_trial_start_date` is not on trial, they are a customer.
 */
data class EntitlementState(
    /** "free" | "lite" | "pro" -- comp tier folded in, highest rank wins. */
    val tier: String,
    /** Feature gate: any paid tier OR an active trial. */
    val isPaid: Boolean,
    val isTrial: Boolean,
    val trialDaysLeft: Int,
    val quotaTotal: Int,
    val quotaUsed: Int,
    val purchased: Int,
    val quotaLeft: Int,
)

/** Millis for an ISO-8601 instant, or null when it is absent/unparseable. */
private fun epochMillisOrNull(iso: String?): Long? {
    if (iso == null) return null
    return runCatching { java.time.Instant.parse(iso).toEpochMilli() }.getOrNull()
}

private fun tierRank(t: String?): Int = when (t) { "pro", "premium" -> 2; "lite" -> 1; else -> 0 }

private fun tierName(rank: Int): String = when (rank) { 2 -> "pro"; 1 -> "lite"; else -> "free" }

fun entitlementState(
    tier: String?,
    premiumTrialStartDate: String?,
    compTier: String?,
    compUntil: String?,
    nowMillis: Long,
    monthlyQuotaTotal: Int? = null,
    monthlyQuotaUsed: Int? = null,
    purchasedQuotaRemaining: Int? = null,
    additionalPurchasedQuota: Int? = null,
): EntitlementState {
    val baseRank = tierRank(tier)
    val compActive = (epochMillisOrNull(compUntil) ?: 0L) > nowMillis
    val compRank = if (compActive) tierRank(compTier) else 0
    val effectiveRank = kotlin.math.max(baseRank, compRank)

    var isTrial = false
    var trialDaysLeft = 0
    val trialStart = epochMillisOrNull(premiumTrialStartDate)
    if (trialStart != null && effectiveRank == 0) {
        val days = Math.ceil((nowMillis - trialStart) / 86_400_000.0).toInt()
        if (days <= 14) {
            isTrial = true
            trialDaysLeft = kotlin.math.max(0, 14 - days)
        }
    }

    val quotaTotal = monthlyQuotaTotal ?: 0
    val quotaUsed = monthlyQuotaUsed ?: 0
    val purchased = (purchasedQuotaRemaining ?: 0) + (additionalPurchasedQuota ?: 0)
    return EntitlementState(
        tier = tierName(effectiveRank),
        isPaid = effectiveRank > 0 || isTrial,
        isTrial = isTrial,
        trialDaysLeft = trialDaysLeft,
        quotaTotal = quotaTotal,
        quotaUsed = quotaUsed,
        purchased = purchased,
        quotaLeft = kotlin.math.max(0, quotaTotal - quotaUsed) + purchased,
    )
}
