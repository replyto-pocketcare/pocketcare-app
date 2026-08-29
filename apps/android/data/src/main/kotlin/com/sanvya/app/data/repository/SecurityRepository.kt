package com.sanvya.app.data.repository

import com.powersync.PowerSyncDatabase
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import com.sanvya.app.data.diagnostics.logDiagnostic
import com.sanvya.app.data.security.SecureKeyStore
import com.sanvya.app.domain.security.SECURITY_GRANT_TTL_HOURS
import com.sanvya.app.domain.security.SecurityEnvelopeError
import com.sanvya.app.domain.security.SigningKeypairJwk
import com.sanvya.app.domain.security.canonicalGrantJson
import com.sanvya.app.domain.security.decryptField
import com.sanvya.app.domain.security.deriveKek
import com.sanvya.app.domain.security.encryptField
import com.sanvya.app.domain.security.generateDek
import com.sanvya.app.domain.security.generateRecoveryCode
import com.sanvya.app.domain.security.generateSigningKeypair
import com.sanvya.app.domain.security.grantExpiryMillis
import com.sanvya.app.domain.security.isEncryptedEnvelope
import com.sanvya.app.domain.security.newSecuritySalt
import com.sanvya.app.domain.security.normalizeRecoveryCode
import com.sanvya.app.domain.security.securityBase64Decode
import com.sanvya.app.domain.security.securityBase64Encode
import com.sanvya.app.domain.security.signGrant
import com.sanvya.app.domain.security.unwrapDek
import com.sanvya.app.domain.security.wrapDek
import com.sanvya.app.domain.security.wrapDekForSupport
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import java.security.GeneralSecurityException
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/**
 * A support grant the user has issued and can still revoke.
 *
 * Mirrors `ActiveGrant` in `apps/web/src/crypto/support.ts` — read from the
 * synced local copy, not from the network, so the list survives being offline.
 */
data class SupportGrant(
    val id: String,
    val scope: String,
    val expiresAtIso: String,
    val createdAtIso: String,
)

/** A newly issued grant, as `issueSupportGrant` returns it on web. */
data class IssuedGrant(val grantId: String, val expiresAtIso: String)

/**
 * Anything the panel should say out loud, carried as an i18n KEY.
 *
 * Web throws `new Error("Wrong passphrase.")` and renders the message. It
 * cannot do that here: the string has to come out of the `security`
 * catalogue in the user's language, and a repository has no business knowing
 * which language that is. So the key travels and the view resolves it — the
 * same shape `voiceLabelKey()` and `feedbackAreaKey()` already use.
 */
class SecurityActionException(val messageKey: String) : Exception(messageKey)

/**
 * The client-side encryption session — the key lifecycle for the Hybrid
 * zero-trust model.
 *
 * Ported from `apps/web/src/crypto/session.ts` + `support.ts` + `fields.ts`,
 * which are three files there only because two of them are React hooks.
 *
 * WHERE EACH WRITE GOES, AND WHY IT IS NOT UNIFORM. `user_keys`,
 * `support_grants` and `security_audit` are written STRAIGHT to Postgres, not
 * through PowerSync's queue — exactly as web does. Two reasons, both web's:
 * the rows carry wrapped key material whose whole point is that it reaches
 * the server intact and immediately, and `security_audit` has a before-insert
 * trigger that computes the hash chain, so a row must arrive as an INSERT the
 * server sees. Reads come from the synced local copy, which is why the grant
 * list still renders offline.
 *
 * WHAT NEVER LEAVES THIS CLASS. The DEK and the signing private key. They are
 * held in memory for the session and, unlike web, also in the Android Keystore
 * (see [SecureKeyStore] for why a browser can get away with memory-only and a
 * phone cannot). Neither is ever written to a synced table, a log, or a crash
 * report.
 */
class SecurityRepository(
    private val db: PowerSyncDatabase,
    private val client: SupabaseClient,
    private val store: SecureKeyStore,
    /**
     * The signed-in user, read on every call rather than captured once.
     *
     * Same shape `ReceiptsRepository` and `RepairRepository` already take, and
     * here it is load-bearing rather than conventional: the transaction
     * screens encrypt a note without ever having asked this class to load
     * anything, so it has to be able to work out on its own whose keys to
     * restore from the Keystore.
     */
    private val getUserId: () -> String?,
    /**
     * The SUPPORT public key, as the JWK document web reads out of
     * `NEXT_PUBLIC_SUPPORT_PUBLIC_JWK`. Null or blank on a deployment that has
     * not generated a support keypair — which is the same state web is in
     * without the env var, and produces the same refusal.
     */
    private val supportPublicJwk: String?,
) {

    private val json = Json { ignoreUnknownKeys = true }

    /**
     * Null until the `user_keys` row has been looked for.
     *
     * Web's `hasKeys: boolean | null`, and the distinction is load-bearing:
     * rendering the setup form for a moment because the answer had not
     * arrived yet would invite a user who already has keys to make a second
     * set, which would orphan everything encrypted under the first.
     */
    private val _hasKeys = MutableStateFlow<Boolean?>(null)
    val hasKeys: StateFlow<Boolean?> = _hasKeys.asStateFlow()

    private val _unlocked = MutableStateFlow(false)
    val unlocked: StateFlow<Boolean> = _unlocked.asStateFlow()

    // In memory for the life of the process; mirrored into the Keystore so the
    // unlock survives the process being killed in the background.
    private var dek: ByteArray? = null
    private var signingPrivateJwk: String? = null
    private var currentUserId: String? = null
    /** Whose Keystore entries have already been looked for, hit or miss. */
    private var restoreAttemptedFor: String? = null

    /**
     * The DEK, if this session is unlocked. Never touches storage.
     *
     * Returns a COPY, and that is not defensive style: [forgetInMemory] zeroes
     * the backing array, so a caller holding the original would find its key
     * turning into 32 zero bytes mid-encrypt if the user hit Lock (or signed
     * out) while a transaction was being saved. The result would be a note
     * sealed under a key nobody has. A copy costs 32 bytes.
     */
    fun dek(): ByteArray? = dek?.copyOf()

    /**
     * Restore a previous unlock from the Keystore, once per user per process.
     *
     * WHY LAZILY, AND NOT ONLY IN [refreshKeyState]. The Settings panel is not
     * the only caller: the Add- and Edit-transaction screens encrypt and
     * decrypt notes, and a user who unlocked yesterday and opens Add
     * Transaction straight from the launcher today has never been near
     * Settings in this process. Without this, that note would be written in
     * plaintext and the old ones would render as `v1.…` — silently, which is
     * the worst possible way for an encryption feature to fail.
     *
     * WHY IT SUSPENDS. Reading an entry runs an AES-GCM `Cipher` against a
     * key held by the Keystore, which on most devices is a round trip to
     * `keystore2` and on some to a secure element. Tens of milliseconds, on
     * whatever thread asked — and the thread that asks is the transaction
     * form's save path, running on `Dispatchers.Main.immediate`. It is off the
     * main thread now, and the sync [dek] above is what stayed sync.
     */
    suspend fun ensureRestored() {
        val uid = getUserId() ?: return
        if (currentUserId != null && currentUserId != uid) {
            // A different account on the same device. The old DEK cannot open
            // this user's rows and must not linger in memory.
            forgetInMemory()
            restoreAttemptedFor = null
        }
        currentUserId = uid
        if (dek != null || restoreAttemptedFor == uid) return
        val restored = withContext(Dispatchers.IO) {
            store.get(dekEntry(uid)) to store.get(signingEntry(uid))
        }
        restoreAttemptedFor = uid
        dek = restored.first
        signingPrivateJwk = restored.second?.toString(Charsets.UTF_8)
        _unlocked.value = dek != null
    }

    // ---- key state -------------------------------------------------------

    /**
     * Load whether this user has set up encryption, and restore a previous
     * unlock from the Keystore.
     *
     * THIS IS THE GUARD AGAINST DESTROYING SOMEBODY'S DATA, so it is worth
     * being exact about. Web's `refreshKeyState()` reads `user_keys` and calls
     * a missing row "no encryption set up", which drives the panel into the
     * setup form. Copying that here would be a bug with permanent
     * consequences: this app reads `user_keys` from the LOCAL PowerSync
     * mirror, and on a fresh install that table is empty until the first sync
     * lands. A user who opens Settings inside that window is offered setup,
     * creates a SECOND key set, and every note written under the first DEK
     * becomes unreadable on every device, forever. There is no recovery path,
     * because the row that could unwrap the old DEK has been replaced.
     *
     * So absence is never inferred locally:
     *
     *  * a local row is POSITIVE proof and needs no network,
     *  * absence is only believed when PostgREST — the same source of truth
     *    every write here goes to — says the row is not there,
     *  * anything else (offline, RLS refusal, timeout) leaves the answer NULL,
     *    which renders as "Checking…" and never as the setup form.
     *
     * Chosen over gating on `SyncStatusRepository.hasSynced`, which is the
     * other obvious fix, for two reasons. It answers the actual question
     * ("does this account have keys?") rather than a proxy for it ("has some
     * sync finished?"). And `hasSynced` can stay false indefinitely on a
     * healthy connection — SyncStatusStore.swift documents exactly that, which
     * is why it carries a ten-second deadline — so a gate built on it would
     * either make the feature unreachable or fall back to the same guess.
     */
    suspend fun refreshKeyState() {
        val userId = getUserId() ?: return
        ensureRestored()
        if (readKeyRow(userId) != null) {
            _hasKeys.value = true
            return
        }
        // Already answered definitively this session; the local read above is
        // what keeps watching for a row that arrives by sync afterwards.
        if (_hasKeys.value != null) return
        _hasKeys.value = serverHasKeyRow(userId)
    }

    /**
     * Does the SERVER hold a `user_keys` row for this user? Null when we could
     * not find out, which is a different answer from "no" and is treated as one.
     */
    private suspend fun serverHasKeyRow(userId: String): Boolean? = try {
        client.postgrest[SCHEMA, TABLE_USER_KEYS]
            .select(columns = Columns.raw("user_id")) {
                filter { eq("user_id", userId) }
            }
            .decodeList<Map<String, String>>()
            .isNotEmpty()
    } catch (e: Exception) {
        logDiagnostic(
            level = "warn",
            scope = "security",
            message = "could not confirm whether encryption keys exist: ${e.describeForLog()}",
        )
        null
    }

    /** Everything [setupEncryption] derives before it writes anything. */
    private data class SetupMaterial(
        val signing: SigningKeypairJwk,
        val wrappedPassphrase: String,
        val wrappedRecovery: String,
        val wrappedSigningPrivate: String,
    )

    /** The two products of [issueSupportGrant]'s crypto, kept together. */
    private data class GrantMaterial(val wrappedForSupport: String?, val signature: String)

    private data class KeyRow(
        val salt: String,
        val wrappedDekPassphrase: String,
        val wrappedDekRecovery: String?,
        val wrappedSigningPrivate: String?,
    )

    private suspend fun readKeyRow(userId: String): KeyRow? = db.getOptional(
        sql = "SELECT salt, wrapped_dek_passphrase, wrapped_dek_recovery, wrapped_signing_private " +
            "FROM user_keys WHERE user_id = ? LIMIT 1",
        parameters = listOf(userId),
        mapper = { c ->
            KeyRow(
                salt = c.getString("salt"),
                wrappedDekPassphrase = c.getString("wrapped_dek_passphrase"),
                wrappedDekRecovery = c.getStringOptional("wrapped_dek_recovery"),
                wrappedSigningPrivate = c.getStringOptional("wrapped_signing_private"),
            )
        },
    )

    // ---- setup / unlock / lock ------------------------------------------

    /**
     * First-time setup. Returns the one-time recovery code, which is shown
     * once and never stored in the clear — web's `setupEncryption`.
     *
     * The order matters and is web's: the row is written BEFORE the session is
     * declared unlocked, so a failed upload leaves the account exactly as it
     * was rather than with a DEK on the phone and nothing on the server.
     *
     * INSERT, NOT UPSERT, and that is the one deliberate difference from web.
     * `user_keys.user_id` is the primary key, so an INSERT over an existing
     * row is refused by Postgres itself. Web's `upsert` would happily replace
     * it, and replacing it is exactly the irreversible accident this whole
     * feature has to be protected from — every note under the old DEK becomes
     * unreadable the moment the old wrapped key is overwritten. [refreshKeyState]
     * already refuses to offer this form unless the server confirmed there is
     * no row; this is the second lock on the same door, and it is the one the
     * database enforces rather than the one the client remembers to check.
     */
    suspend fun setupEncryption(passphrase: String): String {
        val userId = requireUserId()
        val salt = newSecuritySalt()
        val freshDek = generateDek()
        val recoveryCode = generateRecoveryCode()
        // `try` as an EXPRESSION, not four `val`s assigned inside a try block:
        // Kotlin's definite-assignment analysis across try/catch is the kind of
        // thing that compiles on one compiler version and not the next, and
        // there is no local compiler to ask.
        val material = try {
            val signing = generateSigningKeypair()
            SetupMaterial(
                signing = signing,
                wrappedPassphrase = wrapDek(freshDek, deriveKek(passphrase, salt)),
                wrappedRecovery = wrapDek(freshDek, deriveKek(recoveryCode, salt)),
                wrappedSigningPrivate = encryptField(signing.privateJwkJson, freshDek),
            )
        } catch (e: GeneralSecurityException) {
            // A missing or broken JCE provider (an OEM ROM without an EC
            // KeyPairGenerator, say). Undiagnosable from the panel, which can
            // only say "Setup failed." -- so the real exception goes into the
            // diagnostics log, which is what ships with a bug report.
            logDiagnostic(
                level = "error",
                scope = "security",
                message = "encryption setup failed in the crypto provider: ${e.describeForLog()}",
            )
            throw SecurityActionException(KEY_SETUP_FAILED)
        }

        val row = buildJsonObject {
            put("user_id", userId)
            put("salt", securityBase64Encode(salt))
            put("wrapped_dek_passphrase", material.wrappedPassphrase)
            put("wrapped_dek_recovery", material.wrappedRecovery)
            // jsonb column: it has to arrive as an OBJECT, not as a string
            // holding JSON, or the browser's `importKey("jwk", …)` gets a
            // string back and fails.
            put("signing_public_jwk", json.parseToJsonElement(material.signing.publicJwkJson))
            put("wrapped_signing_private", material.wrappedSigningPrivate)
            put("updated_at", Instant.now().toString())
        }
        try {
            client.postgrest[SCHEMA, TABLE_USER_KEYS].insert(row)
        } catch (e: Exception) {
            // Ask the server WHY before deciding what to say. A refused INSERT
            // over an existing row is a completely different event from a
            // network failure -- it means this account already has keys and we
            // very nearly replaced them -- and the difference has to reach the
            // user, because "try again" is right for one and catastrophic for
            // the other. Re-probing rather than parsing the PostgREST error
            // body keeps this independent of how the driver surfaces a 23505.
            val existsNow = serverHasKeyRow(userId)
            if (existsNow == true) {
                _hasKeys.value = true
                logDiagnostic(
                    level = "warn",
                    scope = "security",
                    message = "setup refused: this account already has encryption keys",
                )
                throw SecurityActionException(KEY_ALREADY_SET_UP)
            }
            logDiagnostic(
                level = "error",
                scope = "security",
                message = "could not store encryption keys: ${e.describeForLog()}",
            )
            throw SecurityActionException(KEY_SETUP_FAILED)
        }

        retain(userId, freshDek, material.signing.privateJwkJson)
        _hasKeys.value = true
        return recoveryCode
    }

    /** Unlock with the passphrase. Web's `unlock`. */
    suspend fun unlock(passphrase: String) = unwrapWith(passphrase, recovery = false)

    /**
     * Unlock with the recovery code. Web's `unlockWithRecovery`, including its
     * `.trim().toUpperCase()` — the dashes stay, because they were part of the
     * string the KEK was derived from.
     */
    suspend fun unlockWithRecovery(code: String) =
        unwrapWith(normalizeRecoveryCode(code), recovery = true)

    private suspend fun unwrapWith(secret: String, recovery: Boolean) {
        val userId = requireUserId()
        val row = readKeyRow(userId) ?: throw SecurityActionException(KEY_NOT_SET_UP)
        val wrapped = if (recovery) row.wrappedDekRecovery else row.wrappedDekPassphrase
        if (wrapped == null) throw SecurityActionException(KEY_NO_RECOVERY_KEY)
        val kek = try {
            deriveKek(secret, securityBase64Decode(row.salt))
        } catch (e: GeneralSecurityException) {
            // Not a wrong passphrase -- the provider could not do PBKDF2 at
            // all. Telling the user "Wrong passphrase." for this would send
            // them hunting for a password that was never the problem.
            logDiagnostic(
                level = "error",
                scope = "security",
                message = "key derivation failed in the crypto provider: ${e.describeForLog()}",
            )
            throw SecurityActionException(KEY_SETUP_FAILED)
        }
        val opened = try {
            unwrapDek(wrapped, kek)
        } catch (_: SecurityEnvelopeError) {
            throw SecurityActionException(if (recovery) KEY_INVALID_RECOVERY else KEY_WRONG_PASSPHRASE)
        }
        // Web tolerates a signing key it cannot read and carries on with a null
        // one -- the DEK is what the user came for, and support access is the
        // rarer path. Same here.
        val privateJwk = row.wrappedSigningPrivate?.let {
            try {
                decryptField(it, opened)
            } catch (_: SecurityEnvelopeError) {
                null
            }
        }
        retain(userId, opened, privateJwk)
    }

    /** Drop the keys. Web's `lock()`, plus erasing the Keystore copies. */
    fun lock() {
        // getUserId() first, not the cached currentUserId: sign-out from a cold
        // start is exactly the case where nothing in this process has ever
        // restored a key, so currentUserId is null and the Keystore entries
        // would survive the sign-out that was supposed to erase them.
        val userId = getUserId() ?: currentUserId
        if (userId != null) {
            store.remove(dekEntry(userId))
            store.remove(signingEntry(userId))
        }
        forgetInMemory()
        currentUserId = null
        restoreAttemptedFor = null
    }

    /** Suspending for the same reason [ensureRestored] is: `put` runs a Keystore cipher. */
    private suspend fun retain(userId: String, freshDek: ByteArray, privateJwk: String?) {
        dek = freshDek
        signingPrivateJwk = privateJwk
        currentUserId = userId
        restoreAttemptedFor = userId
        withContext(Dispatchers.IO) {
            store.put(dekEntry(userId), freshDek)
            if (privateJwk != null) store.put(signingEntry(userId), privateJwk.toByteArray(Charsets.UTF_8))
        }
        _unlocked.value = true
    }

    private fun forgetInMemory() {
        // Zero the bytes before dropping the reference. Kotlin will not do it
        // and a heap dump of a killed process is a real artefact.
        dek?.fill(0)
        dek = null
        signingPrivateJwk = null
        _unlocked.value = false
    }

    // ---- field encryption ------------------------------------------------

    /**
     * Encrypt a value for storage if the session is unlocked; otherwise pass
     * it through. Web's `encryptForWrite`, backward-compatible by design:
     * writes made while locked or before setup stay plaintext, because the
     * alternative is refusing to save a transaction over a note.
     */
    suspend fun encryptForWrite(plaintext: String?): String? {
        if (plaintext.isNullOrEmpty()) return plaintext
        if (isEncryptedEnvelope(plaintext)) return plaintext
        ensureRestored()
        val key = dek() ?: return plaintext
        return try {
            encryptField(plaintext, key)
        } catch (e: GeneralSecurityException) {
            // Storing the plaintext is the wrong answer and refusing the save
            // is worse -- the user would lose a transaction over a note. Web's
            // pass-through is the documented fallback for "no key"; this is the
            // same fallback for "no cipher", logged so it is not invisible.
            logDiagnostic(
                level = "error",
                scope = "security",
                message = "could not encrypt a field, stored as-is: ${e.describeForLog()}",
            )
            plaintext
        }
    }

    /**
     * The read side, exactly as web's edit screen does it: decrypt when this
     * is an envelope AND we hold the key, and otherwise hand back what was
     * stored.
     *
     * Handing back the raw envelope while locked is web's behaviour, not an
     * oversight of this port — `fields.ts` has a masking helper (`•••••`) that
     * web's own edit page does not call, so copying the helper instead of the
     * call site would make the phone and the browser show different things.
     * Flagged in the report rather than quietly improved here.
     */
    suspend fun decryptForRead(value: String?): String? {
        if (value == null) return null
        if (!isEncryptedEnvelope(value)) return value
        ensureRestored()
        val key = dek() ?: return value
        return try {
            decryptField(value, key)
        } catch (_: SecurityEnvelopeError) {
            value
        }
    }

    /**
     * True when this value is an envelope this session cannot open.
     *
     * The edit form asks so it can make the note field READ-ONLY. Web renders
     * the raw `v1.…` into an editable input, and that is not a cosmetic wart:
     * touch one character and the mangled string is saved back -- it still
     * starts with `v1.`, so `encryptForWrite` passes it through untouched --
     * and the note is destroyed with no error and no undo. Showing the
     * envelope is web parity; letting it be typed into is a data-loss bug, and
     * this port does not reproduce it.
     */
    suspend fun isLockedEnvelope(value: String?): Boolean {
        if (value == null || !isEncryptedEnvelope(value)) return false
        ensureRestored()
        return dek() == null
    }

    // ---- support grants --------------------------------------------------

    /** The user's unexpired, unrevoked grants, from the synced local copy. */
    suspend fun activeGrants(): List<SupportGrant> = db.getAll(
        sql = "SELECT id, scope, expires_at, created_at FROM support_grants " +
            "WHERE user_id = ? AND revoked_at IS NULL AND expires_at > ? ORDER BY created_at DESC",
        parameters = listOf(getUserId().orEmpty(), Instant.now().toString()),
        mapper = { c ->
            SupportGrant(
                id = c.getString("id"),
                scope = c.getString("scope"),
                expiresAtIso = c.getString("expires_at"),
                createdAtIso = c.getString("created_at"),
            )
        },
    )

    /**
     * Issue a support grant. `content` additionally re-wraps the DEK for the
     * support public key; `structural` carries no key at all and only
     * authorises the drift checksums. Both are signed by the user, which is
     * what proves a human agreed.
     */
    suspend fun issueSupportGrant(
        scope: String,
        ttlHours: Int = SECURITY_GRANT_TTL_HOURS,
    ): IssuedGrant {
        val userId = requireUserId()
        // newId(), not UUID.randomUUID().toString() directly: WriteHelpers.kt
        // owns id generation for this module and every other row goes through it.
        val grantId = newId()
        val expiryMs = grantExpiryMillis(System.currentTimeMillis(), ttlHours)
        val expiresAtIso = Instant.ofEpochMilli(expiryMs).toString()

        // Restores signingPrivateJwk alongside the DEK, and does the Keystore
        // read off the main thread.
        ensureRestored()
        if (dek() == null) {
            throw SecurityActionException(
                if (scope == GRANT_SCOPE_CONTENT) KEY_UNLOCK_FOR_CONTENT else KEY_UNLOCK_TO_AUTHORIZE,
            )
        }
        val privateJwk = signingPrivateJwk ?: throw SecurityActionException(KEY_UNLOCK_TO_AUTHORIZE)
        val d = jwkField(privateJwk, "d") ?: throw SecurityActionException(KEY_UNLOCK_TO_AUTHORIZE)

        val payload = canonicalGrantJson(userId = userId, grantId = grantId, exp = expiryMs, scope = scope)
        // `try` as an expression, for the same reason as setupEncryption's.
        val sealed = try {
            GrantMaterial(
                wrappedForSupport = if (scope == GRANT_SCOPE_CONTENT) {
                    val key = dek() ?: throw SecurityActionException(KEY_UNLOCK_FOR_CONTENT)
                    val jwk = supportPublicKeyOrNull()
                        ?: throw SecurityActionException(KEY_SUPPORT_NOT_CONFIGURED)
                    wrapDekForSupport(key, jwk.first, jwk.second)
                } else {
                    null
                },
                signature = securityBase64Encode(signGrant(payload, d)),
            )
        } catch (e: GeneralSecurityException) {
            // RSA-OAEP-SHA256 and SHA256withECDSA are the two algorithms in
            // this file a device is most likely to lack, and "Couldn't create
            // grant." tells whoever is helping the user precisely nothing.
            // The provider's own words go to the diagnostics log.
            logDiagnostic(
                level = "error",
                scope = "security",
                message = "support grant could not be signed or wrapped: ${e.describeForLog()}",
            )
            throw SecurityActionException(KEY_GRANT_FAILED)
        }

        try {
            client.postgrest[SCHEMA, TABLE_SUPPORT_GRANTS].insert(
                buildJsonObject {
                    put("id", grantId)
                    put("user_id", userId)
                    put("scope", scope)
                    put("wrapped_dek_for_support", sealed.wrappedForSupport)
                    put("signature", sealed.signature)
                    put("expires_at", expiresAtIso)
                },
            )
            audit(userId, action = "grant_issued", grantId = grantId, detail = "scope=$scope")
        } catch (e: SecurityActionException) {
            // Already a message the panel can show -- re-wrapping it as
            // "Couldn't create grant." would replace the useful sentence
            // ("Unlock encryption first…") with a useless one.
            throw e
        } catch (e: Exception) {
            logDiagnostic(
                level = "error",
                scope = "security",
                message = "support grant could not be stored: ${e.describeForLog()}",
            )
            throw SecurityActionException(KEY_GRANT_FAILED)
        }
        return IssuedGrant(grantId = grantId, expiresAtIso = expiresAtIso)
    }

    /** Revoke a grant early. Web's `revokeGrant`. */
    suspend fun revokeGrant(grantId: String) {
        val userId = requireUserId()
        val relation = client.postgrest[SCHEMA, TABLE_SUPPORT_GRANTS]
        relation.update(
            buildJsonObject { put("revoked_at", Instant.now().toString()) },
        ) {
            filter {
                eq("id", grantId)
                eq("user_id", userId)
            }
        }
        audit(userId, action = "grant_revoked", grantId = grantId, detail = null)
    }

    /**
     * One row into the hash-chained `security_audit`.
     *
     * `prev_hash`/`row_hash` are deliberately absent: migration 0021's
     * before-insert trigger computes them server-side, and a client that sent
     * its own would be claiming to know the chain's head, which it cannot.
     */
    private suspend fun audit(userId: String, action: String, grantId: String, detail: String?) {
        client.postgrest[SCHEMA, TABLE_SECURITY_AUDIT].insert(
            buildJsonObject {
                put("actor", "user:$userId")
                put("action", action)
                put("subject_user", userId)
                put("grant_id", grantId)
                put("detail", detail)
            },
        )
    }

    /** The support key's `n` and `e`, or null when none is configured. */
    private fun supportPublicKeyOrNull(): Pair<String, String>? {
        val raw = supportPublicJwk?.takeIf { it.isNotBlank() } ?: return null
        return try {
            val obj = json.parseToJsonElement(raw) as? JsonObject ?: return null
            val n = obj["n"]?.jsonPrimitive?.content ?: return null
            val e = obj["e"]?.jsonPrimitive?.content ?: return null
            n to e
        } catch (_: Exception) {
            null
        }
    }

    private fun jwkField(document: String, field: String): String? = try {
        (json.parseToJsonElement(document) as? JsonObject)?.get(field)?.jsonPrimitive?.content
    } catch (_: Exception) {
        null
    }

    /**
     * What is safe to write into a diagnostics log about a failure here.
     *
     * Class name plus message, never the exception's full `toString()` and
     * never a cause chain: this text ships inside bug reports, and the one
     * thing that must never travel with one is key material. JCE and PostgREST
     * messages are descriptions of what went wrong, not dumps of what was
     * being operated on, so the pair is both safe and enough to act on.
     */
    private fun Exception.describeForLog(): String =
        "${this::class.simpleName}: ${message ?: "no message"}"

    private fun requireUserId(): String =
        getUserId() ?: throw SecurityActionException(KEY_NOT_SIGNED_IN)

    private fun dekEntry(userId: String) = "dek:$userId"
    private fun signingEntry(userId: String) = "signing:$userId"

    companion object {
        /** Web's two `GrantScope` values, and the DB's CHECK constraint. */
        const val GRANT_SCOPE_CONTENT = "content"
        const val GRANT_SCOPE_STRUCTURAL = "structural"

        // i18n keys in the `security` namespace. They are the messages web
        // throws, in the one form a translated app can carry them.
        const val KEY_NOT_SIGNED_IN = "notSignedIn"
        const val KEY_SETUP_FAILED = "setupFailed"

        /**
         * The database refused to replace an existing `user_keys` row.
         *
         * No web counterpart, because web's `upsert` never refuses -- it
         * silently destroys the old keys instead. See [setupEncryption].
         */
        const val KEY_ALREADY_SET_UP = "alreadySetUp"
        const val KEY_NOT_SET_UP = "notSetUp"
        const val KEY_NO_RECOVERY_KEY = "noRecoveryKey"
        const val KEY_WRONG_PASSPHRASE = "wrongPassphrase"
        const val KEY_INVALID_RECOVERY = "invalidRecovery"
        const val KEY_UNLOCK_FOR_CONTENT = "unlockForContent"
        const val KEY_SUPPORT_NOT_CONFIGURED = "supportNotConfigured"
        const val KEY_UNLOCK_TO_AUTHORIZE = "unlockToAuthorize"
        const val KEY_GRANT_FAILED = "grantFailed"

        private const val SCHEMA = "pocketcare"
        private const val TABLE_USER_KEYS = "user_keys"
        private const val TABLE_SUPPORT_GRANTS = "support_grants"
        private const val TABLE_SECURITY_AUDIT = "security_audit"
    }
}
