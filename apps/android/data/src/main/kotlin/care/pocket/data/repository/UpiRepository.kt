package care.pocket.data.repository

/**
 * Read facade and helper methods for UPI payment handles (P2.5).
 * Mirrors apps/web/src/payments/handles.ts.
 * Note: payment_handles is a server-only table (not synced in local SQLite),
 * so handles are fetched online or via Edge Function call.
 * Local masked hint is cached in-memory/preferences for offline UI display.
 */

import care.pocket.domain.upi.IntentParams
import care.pocket.domain.upi.buildIntentUrl
import care.pocket.domain.upi.isValidVpa
import care.pocket.domain.upi.maskVpa

data class UpiPaymentHandle(
    val vpa: String,
    val displayName: String?,
)

class UpiRepository {
    private var cachedHint: String? = null

    fun getCachedHint(): String? = cachedHint

    fun rememberHint(hint: String?) {
        cachedHint = hint
    }

    fun maskHandle(vpa: String): String = maskVpa(vpa)

    fun isValidVpa(vpa: String): Boolean = isValidVpa(vpa)

    fun createPaymentUrl(
        payeeVpa: String,
        payeeName: String?,
        amountMinor: Long,
        currency: String = "INR",
        transactionRef: String? = null,
        note: String? = null
    ): String {
        val params = IntentParams(
            vpa = payeeVpa,
            name = payeeName ?: "PocketCare",
            amountMinor = amountMinor.toDouble(),
            note = note,
            ref = transactionRef,
            currency = currency,
        )
        return buildIntentUrl(params).url
    }
}
