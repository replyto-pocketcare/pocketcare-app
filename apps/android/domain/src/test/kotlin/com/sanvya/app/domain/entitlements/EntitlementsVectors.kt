package com.sanvya.app.domain.entitlements

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.long
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// P1.7a: wires the real Entitlements.kt port into FunctionRegistry so
// entitlements.json's vectors un-skip.

fun registerEntitlementsVectors() {
    val domain = "entitlements"

    FunctionRegistry.register(domain, "canUse") { input ->
        val o = input.jsonObject
        JsonPrimitive(canUse(o.getValue("feature").jsonPrimitive.content, o.getValue("tier").jsonPrimitive.content))
    }
    FunctionRegistry.register(domain, "isPremiumFeature") { input ->
        JsonPrimitive(isPremiumFeature(input.jsonObject.getValue("feature").jsonPrimitive.content))
    }

    FunctionRegistry.register(domain, "entitlementState") { input ->
        val o = input.jsonObject
        fun str(k: String): String? = o[k]?.jsonPrimitive?.contentOrNull
        fun int(k: String): Int? = o[k]?.jsonPrimitive?.contentOrNull?.toIntOrNull()
        val s = entitlementState(
            tier = str("tier"),
            premiumTrialStartDate = str("premiumTrialStartDate"),
            compTier = str("compTier"),
            compUntil = str("compUntil"),
            nowMillis = o.getValue("nowMillis").jsonPrimitive.long,
            monthlyQuotaTotal = int("monthlyQuotaTotal"),
            monthlyQuotaUsed = int("monthlyQuotaUsed"),
            purchasedQuotaRemaining = int("purchasedQuotaRemaining"),
            additionalPurchasedQuota = int("additionalPurchasedQuota"),
        )
        JsonObject(
            mapOf(
                "tier" to JsonPrimitive(s.tier),
                "isPaid" to JsonPrimitive(s.isPaid),
                "isTrial" to JsonPrimitive(s.isTrial),
                "trialDaysLeft" to JsonPrimitive(s.trialDaysLeft),
                "quotaTotal" to JsonPrimitive(s.quotaTotal),
                "quotaUsed" to JsonPrimitive(s.quotaUsed),
                "purchased" to JsonPrimitive(s.purchased),
                "quotaLeft" to JsonPrimitive(s.quotaLeft),
            )
        )
    }
}
