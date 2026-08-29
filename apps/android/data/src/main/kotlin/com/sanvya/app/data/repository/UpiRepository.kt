package com.sanvya.app.data.repository

/**
 * Read facade and helper methods for UPI payment handles (P2.5, extended P3.9
 * for Splits settle-up). Mirrors apps/web/src/payments/handles.ts.
 * Note: payment_handles is a server-only table (not synced in local SQLite),
 * so handles are fetched online or via Edge Function call.
 * Local masked hint is cached in SharedPreferences for offline UI display.
 */

import android.content.Context
import android.content.SharedPreferences
import com.powersync.PowerSyncDatabase
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import com.sanvya.app.domain.upi.IntentParams
import com.sanvya.app.domain.upi.buildIntentUrl
import com.sanvya.app.domain.upi.maskVpa
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.ktor.client.statement.bodyAsText
import io.ktor.http.Headers
import io.ktor.http.HttpHeaders
import kotlinx.coroutines.flow.Flow
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

/**
 * One row of `payment_handle_disclosures` -- who fetched your UPI ID, and when.
 *
 * [viewerName] is null when neither profile table knows this viewer, so the
 * VIEW can name them in the user's language rather than this layer hardcoding
 * "Someone" (the same rule LedgerRepository's split-banner participants follow).
 */
data class HandleDisclosure(
    val id: String,
    val viewerUserId: String,
    val createdAtIso: String,
    val viewerName: String?,
)

/** Mirrors web's HandleError: [code] is machine-readable so the UI can offer
 * the right next step -- "no_handle" | "no_group" | "no_balance" |
 * "rate_limited" (per handles.ts's own doc comment on fetchCounterpartyHandle). */
class UpiHandleError(message: String, val code: String? = null) : Exception(message)

class UpiRepository(
    private val client: SupabaseClient,
    private val db: PowerSyncDatabase,
    private val context: Context,
    private val getUserId: () -> String?,
) {
    /**
     * The masked hint, and ONLY the masked hint.
     *
     * Web keeps this in `localStorage` under `pc_upi_hint`; the same key is
     * used here so the two clients mean the same thing by it. The real VPA is
     * deliberately never persisted on a device -- see the class comment. This
     * exists so the Settings panel can say "you have one" while offline instead
     * of showing an empty form to someone who has already saved a UPI ID.
     *
     * Was an in-memory field until this pass, which on a phone is close to no
     * cache at all: the OS kills a backgrounded process routinely, and every
     * such kill put the panel back to "add a UPI ID".
     */
    private val prefs: SharedPreferences by lazy {
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun getCachedHint(): String? = prefs.getString(HINT_KEY, null)

    fun rememberHint(hint: String?) {
        prefs.edit().apply {
            if (hint == null) remove(HINT_KEY) else putString(HINT_KEY, hint)
        }.apply()
    }

    fun maskHandle(vpa: String): String = maskVpa(vpa)

    /**
     * FULLY QUALIFIED ON PURPOSE. A member function shadows a top-level import
     * of the same name inside its own class, so the previous
     * `fun isValidVpa(vpa: String) = isValidVpa(vpa)` called ITSELF -- a
     * StackOverflowError the moment anything used it. iOS's twin already spelt
     * this `Domain.isValidVpa(...)` for the same reason; nothing had called the
     * Kotlin one yet, which is the only reason it never crashed.
     */
    fun isValidVpa(vpa: String): Boolean = com.sanvya.app.domain.upi.isValidVpa(vpa)

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
     * One call to the `payment-handle` Edge Function, unwrapped the way web's
     * own `callFn()` + `edgeFnMessage()` pair unwraps it.
     *
     * API surface verified against supabase-kt's real Functions.kt source
     * before this was written (nothing under apps/android called
     * client.functions before this repository): the reified invoke(function,
     * body, region, headers) overload's own doc comment warns the JSON
     * Content-Type header must be set explicitly, so it's passed here rather
     * than assumed. Response is read via bodyAsText() + manual JSON parse
     * (not the ContentNegotiation-dependent response.body<T>() call) since
     * whether supabase-kt's shared HttpClient has a JSON converter installed
     * for arbitrary Functions responses (as opposed to Postgrest's own
     * decoding path) was not verified against real source -- this is the
     * riskiest guess in this class; first place to look if a real
     * compiler/runtime error surfaces from a payments call specifically.
     * On a non-2xx response, supabase-kt throws a RestException subclass
     * whose message is the raw response body text (per Functions.kt's
     * parseErrorResponse) -- parsed here the same way web's own
     * edgeFnMessage() unwraps the equivalent opaque top-level error.
     *
     * The function always answers HTTP 200 with `{error, code}` in the body for
     * its own refusals (its `json()` helper says exactly that), so a 2xx body
     * is checked for `error` too -- web's `if (res.error) throw`.
     */
    private suspend fun callFn(body: JsonObject): JsonObject {
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
        return json
    }

    /**
     * The masked hint for your OWN handle, or null if you haven't added one.
     *
     * Read directly from the table rather than through the Edge Function,
     * exactly as web's `getMyPaymentHandle()` does: the owner RLS policy
     * already permits it, and `handle_hint` is masked by construction --
     * `akh****@okhdfcbank` -- so nothing secret crosses the wire. The
     * ciphertext in `handle_enc` stays useless to the client either way, since
     * only the function holds the key.
     *
     * Schema-qualified, per golden rule #3 -- a bare `from()` resolves to
     * `public` and 404s.
     *
     * `deleted_at` is filtered in Kotlin rather than with a PostgREST is-null
     * operator: there is no verified supabase-kt spelling of that filter
     * anywhere in this module, the row set here is at most one per user, and
     * reading the column costs nothing while guessing an API costs a CI round
     * trip.
     *
     * Offline -- or with the 0041 migration not yet applied -- this falls back
     * to the cached hint rather than claiming they have no UPI ID. Telling
     * someone their saved details are gone because the network blinked is worse
     * than showing a stale mask; web's comment says the same.
     */
    suspend fun getMyPaymentHandle(): String? {
        val userId = getUserId() ?: return getCachedHint()
        val rows = try {
            client.postgrest[SCHEMA, TABLE_PAYMENT_HANDLES]
                .select(columns = Columns.raw("handle_hint,deleted_at")) {
                    filter { eq("user_id", userId) }
                }
                .decodeList<JsonObject>()
        } catch (_: Exception) {
            return getCachedHint()
        }
        val hint = rows
            .firstOrNull { it["deleted_at"]?.jsonPrimitive?.contentOrNull == null }
            ?.get("handle_hint")?.jsonPrimitive?.contentOrNull
        rememberHint(hint)
        return hint
    }

    /**
     * Save (or replace) your own UPI ID. Returns the masked hint to show.
     *
     * Rejected for guests server-side too -- a DB trigger, plus the function's
     * own `guest_not_allowed` -- so the panel's guest branch is a courtesy and
     * not the control.
     */
    suspend fun savePaymentHandle(vpa: String, displayName: String? = null): String {
        val res = callFn(
            buildJsonObject {
                put("action", "set")
                put("vpa", vpa)
                if (!displayName.isNullOrBlank()) put("displayName", displayName)
            },
        )
        val hint = res["hint"]?.jsonPrimitive?.contentOrNull ?: maskVpa(vpa)
        rememberHint(hint)
        return hint
    }

    /** Remove your UPI ID. Existing disclosures stay in the audit trail. */
    suspend fun forgetPaymentHandle() {
        callFn(buildJsonObject { put("action", "forget") })
        rememberHint(null)
    }

    /**
     * Who has fetched your UPI ID, newest first. Your own audit trail.
     *
     * `payment_handle_disclosures` IS synced (unlike `payment_handles`), so
     * this reads from local SQLite like everything else and works offline --
     * web's `useHandleDisclosures()` makes the same point in its own comment.
     *
     * Web resolves the viewer's name through a separate `useUserProfiles()`
     * map; the join is done in SQL here because there is no equivalent hook to
     * combine with, and it is the same union: `public_profiles` for co-members
     * you can see, `profiles` for yourself.
     */
    fun watchDisclosures(): Flow<List<HandleDisclosure>> = db.watch(
        sql = """
            SELECT d.id AS id, d.viewer_user_id AS viewer_user_id, d.created_at AS created_at,
                   COALESCE(pub.display_name, own.display_name) AS display_name,
                   COALESCE(pub.email, own.email) AS email
              FROM payment_handle_disclosures d
              LEFT JOIN public_profiles pub ON pub.id = d.viewer_user_id
              LEFT JOIN profiles own ON own.id = d.viewer_user_id
             ORDER BY d.created_at DESC
             LIMIT 50
        """.trimIndent(),
        mapper = { cursor ->
            val name = cursor.getStringOptional("display_name")
            val email = cursor.getStringOptional("email")
            HandleDisclosure(
                id = cursor.getString("id"),
                viewerUserId = cursor.getString("viewer_user_id"),
                createdAtIso = cursor.getString("created_at"),
                viewerName = if (!name.isNullOrEmpty()) name else email?.substringBefore("@"),
            )
        },
    )

    /**
     * Fetch someone's UPI ID in order to pay them. Straight port of
     * fetchCounterpartyHandle() in handles.ts. NEVER cached to disk (this
     * class's [getCachedHint]/[rememberHint] hold the CALLER's own masked hint
     * only -- a different concept; a counterparty's VPA is held in memory for
     * one settle-up interaction and dropped).
     */
    suspend fun fetchCounterpartyHandle(counterpartyId: String): UpiPaymentHandle {
        val json = callFn(
            buildJsonObject {
                put("action", "get")
                put("counterpartyId", counterpartyId)
            },
        )
        val vpa = json["vpa"]?.jsonPrimitive?.contentOrNull
            ?: throw UpiHandleError("They haven't added a UPI ID yet.", "no_handle")
        val displayName = json["displayName"]?.jsonPrimitive?.contentOrNull
        return UpiPaymentHandle(vpa, displayName)
    }

    private companion object {
        /**
         * The schema is `pocketcare`, not `sanvya`: the product was renamed but
         * `0001_init.sql` created -- and every migration since has used -- the
         * `pocketcare` schema. Golden rule 3 in PROJECT_REFERENCE.md.
         */
        const val SCHEMA = "pocketcare"
        const val TABLE_PAYMENT_HANDLES = "payment_handles"

        /** The same SharedPreferences file the rest of the app's device prefs use. */
        const val PREFS_NAME = "sanvya_prefs"

        /** Web's localStorage key, verbatim. */
        const val HINT_KEY = "pc_upi_hint"
    }
}
