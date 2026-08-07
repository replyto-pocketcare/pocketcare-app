package com.sanvya.app.data.repository

/**
 * Read facade and helper methods for UPI payment handles (P2.5, extended P3.9
 * for Splits settle-up). Mirrors apps/web/src/payments/handles.ts.
 * Note: payment_handles is a server-only table (not synced in local SQLite),
 * so handles are fetched online or via Edge Function call.
 * Local masked hint is cached in-memory/preferences for offline UI display.
 */

import com.sanvya.app.domain.upi.IntentParams
import com.sanvya.app.domain.upi.buildIntentUrl
import com.sanvya.app.domain.upi.isValidVpa
import com.sanvya.app.domain.upi.maskVpa
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.functions.functions
import io.ktor.client.statement.bodyAsText
import io.ktor.http.Headers
import io.ktor.http.HttpHeaders
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

data class UpiPaymentHandle(
    val vpa: String,
    val displayName: String?,
)

/** Mirrors web's HandleError: [code] is machine-readable so the UI can offer
 * the right next step -- "no_handle" | "no_group" | "no_balance" |
 * "rate_limited" (per handles.ts's own doc comment on fetchCounterpartyHandle). */
class UpiHandleError(message: String, val code: String? = null) : Exception(message)

class UpiRepository(private val client: SupabaseClient) {
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
            name = payeeName ?: "Sanvya",
            amountMinor = amountMinor.toDouble(),
            note = note,
            ref = transactionRef,
            currency = currency,
        )
        return buildIntentUrl(params).url
    }

    /**
     * Fetch someone's UPI ID in order to pay them. Straight port of
     * fetchCounterpartyHandle() in handles.ts: calls the real `payment-handle`
     * Edge Function with {action:"get", counterpartyId}. NEVER cached to disk
     * (this class's [cachedHint]/[rememberHint] are for the CALLER's own
     * handle only -- a different, already-existing concept; a counterparty's
     * VPA is held in memory for one settle-up interaction and dropped).
     *
     * API surface verified against supabase-kt's real Functions.kt source
     * before writing this (nothing under apps/android called
     * client.functions before this pass): the reified invoke(function, body,
     * region, headers) overload's own doc comment warns the JSON
     * Content-Type header must be set explicitly, so it's passed here rather
     * than assumed. Response is read via bodyAsText() + manual JSON parse
     * (not the ContentNegotiation-dependent response.body<T>() call) since
     * whether supabase-kt's shared HttpClient has a JSON converter installed
     * for arbitrary Functions responses (as opposed to Postgrest's own
     * decoding path) was not verified against real source -- this is the
     * riskiest guess in this method; first place to look if a real
     * compiler/runtime error surfaces from a settle-up call specifically.
     * On a non-2xx response, supabase-kt throws a RestException subclass
     * whose message is the raw response body text (per Functions.kt's
     * parseErrorResponse) -- parsed here the same way web's own
     * edgeFnMessage() unwraps the equivalent opaque top-level error.
     */
    suspend fun fetchCounterpartyHandle(counterpartyId: String): UpiPaymentHandle {
        val body = buildJsonObject {
            put("action", "get")
            put("counterpartyId", counterpartyId)
        }
        val json: JsonObject = try {
            val response = client.functions.invoke(
                function = "payment-handle",
                body = body,
                headers = Headers.build { append(HttpHeaders.ContentType, "application/json") },
            )
            Json.parseToJsonElement(response.bodyAsText()).jsonObject
        } catch (e: RestException) {
            val parsed = runCatching { Json.parseToJsonElement(e.message ?: "").jsonObject }.getOrNull()
            val msg = parsed?.get("error")?.jsonPrimitive?.contentOrNull ?: (e.message ?: "Couldn't reach the payments service.")
            val code = parsed?.get("code")?.jsonPrimitive?.contentOrNull
            throw UpiHandleError(msg, code)
        } catch (e: Exception) {
            throw UpiHandleError(e.message ?: "Couldn't reach the payments service. Check your connection.")
        }

        if (json["error"] != null) {
            val msg = json["error"]?.jsonPrimitive?.contentOrNull ?: "Couldn't fetch payment details."
            val code = json["code"]?.jsonPrimitive?.contentOrNull
            throw UpiHandleError(msg, code)
        }
        val vpa = json["vpa"]?.jsonPrimitive?.contentOrNull
            ?: throw UpiHandleError("They haven't added a UPI ID yet.", "no_handle")
        val displayName = json["displayName"]?.jsonPrimitive?.contentOrNull
        return UpiPaymentHandle(vpa, displayName)
    }
}
