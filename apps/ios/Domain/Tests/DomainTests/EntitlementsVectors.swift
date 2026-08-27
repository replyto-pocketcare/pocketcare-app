import Foundation
@testable import Domain

// P1.7b: wires the real Entitlements.swift port into FunctionRegistry so
// entitlements.json's vectors un-skip. Mirrors Android's
// EntitlementsVectors.kt.

func registerEntitlementsVectors() {
    let domain = "entitlements"

    FunctionRegistry.register(domain: domain, fn: "canUse") { input in
        let d = input as! [String: Any]
        return canUse(d["feature"] as! String, d["tier"] as! String)
    }
    FunctionRegistry.register(domain: domain, fn: "isPremiumFeature") { input in
        let d = input as! [String: Any]
        return isPremiumFeature(d["feature"] as! String)
    }

    FunctionRegistry.register(domain: domain, fn: "entitlementState") { input in
        let d = input as! [String: Any]
        func str(_ k: String) -> String? { d[k] as? String }
        func int(_ k: String) -> Int? { (d[k] as? NSNumber)?.intValue }
        let s = entitlementState(
            tier: str("tier"),
            premiumTrialStartDate: str("premiumTrialStartDate"),
            compTier: str("compTier"),
            compUntil: str("compUntil"),
            nowMillis: (d["nowMillis"] as! NSNumber).int64Value,
            monthlyQuotaTotal: int("monthlyQuotaTotal"),
            monthlyQuotaUsed: int("monthlyQuotaUsed"),
            purchasedQuotaRemaining: int("purchasedQuotaRemaining"),
            additionalPurchasedQuota: int("additionalPurchasedQuota")
        )
        return [
            "tier": s.tier,
            "isPaid": s.isPaid,
            "isTrial": s.isTrial,
            "trialDaysLeft": s.trialDaysLeft,
            "quotaTotal": s.quotaTotal,
            "quotaUsed": s.quotaUsed,
            "purchased": s.purchased,
            "quotaLeft": s.quotaLeft,
        ] as [String: Any]
    }
}
