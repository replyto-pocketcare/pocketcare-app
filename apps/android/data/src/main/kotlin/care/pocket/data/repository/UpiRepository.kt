package care.pocket.data.repository

/**
 * Read facade and helper methods for UPI payment handles (P2.5).
 * Mirrors apps/web/src/payments/handles.ts.
 * Note: payment_handles is a server-only table (not synced in local SQLite),
 * so handles are fetched online or via Edge Function call.
 * Local masked hint is cached in-memory/preferences for offline UI display.
 */

import care.pocket.domain.upi.buildUpiUrl
import care.pocket.domain.upi.maskVpa
import care.pocket.domain.upi.validateVpa

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

    fun isValidVpa(vpa: String): Boolean = validateVpa(vpa)

    fun createPaymentUrl(
        payeeVpa: String,
        payeeName: String?,
        amountMinor: Long,
        currency: String = "INR",
        transactionRef: String? = null,
        note: String? = null
    ): String {
        return buildUpiUrl(
            payeeVpa = payeeVpa,
            payeeName = payeeName,
            amountMinor = amountMinor,
            currency = currency,
            transactionRef = transactionRef,
            note = note
        )
    }
}
