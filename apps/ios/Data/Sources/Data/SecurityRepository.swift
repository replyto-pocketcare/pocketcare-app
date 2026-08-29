import Domain
import Foundation
import PowerSync
import Supabase

/**
 A support grant the user has issued and can still revoke.

 Mirrors `ActiveGrant` in `apps/web/src/crypto/support.ts` — read from the
 synced local copy, not from the network, so the list survives being offline.
 */
public struct SupportGrant: Sendable, Identifiable, Equatable {
    public let id: String
    public let scope: String
    public let expiresAtIso: String
    public let createdAtIso: String

    public init(id: String, scope: String, expiresAtIso: String, createdAtIso: String) {
        self.id = id
        self.scope = scope
        self.expiresAtIso = expiresAtIso
        self.createdAtIso = createdAtIso
    }
}

/// A newly issued grant, as `issueSupportGrant` returns it on web.
public struct IssuedGrant: Sendable {
    public let grantId: String
    public let expiresAtIso: String
}

/// What the panel needs to pick one of web's four states.
public struct SecuritySnapshot: Sendable {
    /// Nil until the `user_keys` row has been looked for.
    public let hasKeys: Bool?
    public let unlocked: Bool
}

/**
 Anything the panel should say out loud, carried as an i18n KEY.

 Web throws `new Error("Wrong passphrase.")` and renders the message. It cannot
 do that here: the string has to come out of the `security` catalogue in the
 user's language, and a repository has no business knowing which language that
 is. So the key travels and the view resolves it — the same shape
 `voiceLabelKey()` and `feedbackAreaKey()` already use.
 */
public struct SecurityActionError: Error, CustomStringConvertible, Sendable {
    public let messageKey: String
    public init(_ messageKey: String) { self.messageKey = messageKey }
    public var description: String { messageKey }
}

/// The i18n keys this repository can raise, in the `security` namespace.
public enum SecurityMessageKey {
    public static let notSignedIn = "notSignedIn"
    public static let setupFailed = "setupFailed"
    /// The database refused to replace an existing `user_keys` row. No web
    /// counterpart, because web's `upsert` never refuses — it silently
    /// destroys the old keys instead. See `setupEncryption`.
    public static let alreadySetUp = "alreadySetUp"
    public static let notSetUp = "notSetUp"
    public static let noRecoveryKey = "noRecoveryKey"
    public static let wrongPassphrase = "wrongPassphrase"
    public static let invalidRecovery = "invalidRecovery"
    public static let unlockForContent = "unlockForContent"
    public static let supportNotConfigured = "supportNotConfigured"
    public static let unlockToAuthorize = "unlockToAuthorize"
    public static let grantFailed = "grantFailed"
}

/// Web's two `GrantScope` values, and the DB's CHECK constraint.
public enum SecurityGrantScope {
    public static let content = "content"
    public static let structural = "structural"
}

/**
 The client-side encryption session — the key lifecycle for the Hybrid
 zero-trust model.

 Ported from `apps/web/src/crypto/session.ts` + `support.ts` + `fields.ts`,
 which are three files there only because two of them are React hooks.

 WHERE EACH WRITE GOES, AND WHY IT IS NOT UNIFORM. `user_keys`,
 `support_grants` and `security_audit` are written STRAIGHT to Postgres, not
 through PowerSync's queue — exactly as web does. Two reasons, both web's: the
 rows carry wrapped key material whose whole point is that it reaches the
 server intact and immediately, and `security_audit` has a before-insert
 trigger that computes the hash chain, so a row must arrive as an INSERT the
 server sees. Reads come from the synced local copy, which is why the grant
 list still renders offline.

 WHAT NEVER LEAVES THIS CLASS. The DEK and the signing private key. They are
 held in memory for the session and, unlike web, also in the Keychain (see
 `SecureKeyStore` for why a browser can get away with memory-only and a phone
 cannot). Neither is ever written to a synced table, a log, or a crash report.

 `@unchecked Sendable` with an explicit lock, not an actor: `encryptForWrite`
 is called from the transaction form's save path, which is synchronous by the
 time it reaches here, and an actor would make every one of those call sites
 `await` for a hop that guards four bytes of state.

 Mirrors Android's SecurityRepository.
 */
public final class SecurityRepository: @unchecked Sendable {

    private let db: PowerSyncDatabaseProtocol
    private let client: SupabaseClient
    private let store: SecureKeyStore
    /**
     The signed-in user, read on every call rather than captured once.

     Same shape `ReceiptsRepository` and `RepairRepository` already take, and
     here it is load-bearing rather than conventional: the transaction screens
     encrypt a note without ever having asked this class to load anything, so
     it has to be able to work out on its own whose keys to restore from the
     Keychain.
     */
    private let getUserId: @Sendable () -> String?
    /**
     The SUPPORT public key, as the JWK document web reads out of
     `NEXT_PUBLIC_SUPPORT_PUBLIC_JWK`. Nil or blank on a deployment that has no
     support keypair — the same state web is in without the env var, and it
     produces the same refusal.
     */
    private let supportPublicJwk: String?

    private let lock = NSLock()
    private var dekBytes: Data?
    private var signingPrivateJwk: String?
    private var currentUserId: String?
    private var hasKeys: Bool?
    /// Whose Keychain items have already been looked for, hit or miss.
    private var restoreAttemptedFor: String?

    public init(
        db: PowerSyncDatabaseProtocol,
        client: SupabaseClient,
        store: SecureKeyStore,
        getUserId: @escaping @Sendable () -> String?,
        supportPublicJwk: String?
    ) {
        self.db = db
        self.client = client
        self.store = store
        self.getUserId = getUserId
        self.supportPublicJwk = supportPublicJwk
    }

    // MARK: - Session state

    /// What the panel renders from. Web's `useCryptoStatus()` inputs.
    public func snapshot() -> SecuritySnapshot {
        lock.lock()
        defer { lock.unlock() }
        return SecuritySnapshot(hasKeys: hasKeys, unlocked: dekBytes != nil)
    }

    /**
     The DEK, if this session is unlocked. Never touches the Keychain.

     `Data` is a value type with copy-on-write, so what comes back is the
     caller's own copy: `lockSession()` dropping the stored one cannot pull the
     key out from under an encrypt that is already in flight. (Android's twin
     has to return an explicit `copyOf()` for this, because a `ByteArray` is a
     reference and `forgetInMemory()` zeroes it in place.)
     */
    public func dek() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return dekBytes
    }

    /**
     Restore a previous unlock from the Keychain, once per user per process.

     WHY LAZILY, AND NOT ONLY IN `refreshKeyState`. The Settings panel is not
     the only caller: the Add- and Edit-transaction screens encrypt and decrypt
     notes, and a user who unlocked yesterday and opens Add Transaction straight
     from the home screen today has never been near Settings in this process.
     Without this, that note would be written in plaintext and the old ones
     would render as `v1.…` — silently, which is the worst possible way for an
     encryption feature to fail.

     WHY IT IS `async` WHEN IT AWAITS NOTHING. `SecItemCopyMatching` is an IPC
     round trip to `securityd` and, for a `ThisDeviceOnly` item, a decrypt
     against the device key — tens of milliseconds, on whatever thread asked.
     The thread that asks is the transaction form's save path, which is on the
     main actor. This type is not actor-isolated, so a `nonisolated async`
     method called from `@MainActor` runs on the cooperative pool rather than
     inheriting the caller's actor (SE-0338), and the work lands off the main
     thread purely by being spelled `async`. The synchronous `dek()` above is
     the one that stayed synchronous, and it is the one that touches nothing.
     */
    public func ensureRestored() async {
        guard let uid = getUserId() else { return }
        lock.lock()
        if let existing = currentUserId, existing != uid {
            // A different account on the same device. The old DEK cannot open
            // this user's rows and must not linger in memory.
            forgetLocked()
            restoreAttemptedFor = nil
        }
        currentUserId = uid
        let alreadyDone = dekBytes != nil || restoreAttemptedFor == uid
        lock.unlock()
        if alreadyDone { return }

        let storedDek = store.get(dekEntry(uid))
        let storedSigning = store.get(signingEntry(uid))

        lock.lock()
        restoreAttemptedFor = uid
        dekBytes = storedDek
        signingPrivateJwk = storedSigning.flatMap { String(data: $0, encoding: .utf8) }
        lock.unlock()
    }

    /**
     Load whether this user has set up encryption, and restore a previous
     unlock from the Keychain.

     THIS IS THE GUARD AGAINST DESTROYING SOMEBODY'S DATA, so it is worth being
     exact about. Web's `refreshKeyState()` reads `user_keys` and calls a
     missing row "no encryption set up", which drives the panel into the setup
     form. Copying that here would be a bug with permanent consequences: this
     app reads `user_keys` from the LOCAL PowerSync mirror, and on a fresh
     install that table is empty until the first sync lands. A user who opens
     Settings inside that window is offered setup, creates a SECOND key set,
     and every note written under the first DEK becomes unreadable on every
     device, forever. There is no recovery path, because the row that could
     unwrap the old DEK has been replaced.

     So absence is never inferred locally:

      * a local row is POSITIVE proof and needs no network,
      * absence is only believed when PostgREST — the same source of truth
        every write here goes to — says the row is not there,
      * anything else (offline, RLS refusal, timeout) leaves the answer nil,
        which renders as "Checking…" and never as the setup form.

     Chosen over gating on `SyncStatusStore.hasSynced`, which is the other
     obvious fix, for two reasons. It answers the actual question ("does this
     account have keys?") rather than a proxy for it ("has some sync
     finished?"). And `hasSynced` can stay false indefinitely on a healthy
     connection — this file's neighbour documents exactly that, which is why
     `initialSyncPending` carries a ten-second deadline — so a gate built on it
     would either make the feature unreachable or fall back to the same guess.
     */
    public func refreshKeyState() async throws {
        guard let userId = getUserId() else { return }
        await ensureRestored()
        // Hoisted rather than `if try await f() != nil`: keeping `try await`
        // out of a binary-operator expression is the spelling that never has to
        // be argued about with a compiler nobody here can run.
        let localRow = try await readKeyRow(userId: userId)
        if localRow != nil {
            lock.lock()
            hasKeys = true
            lock.unlock()
            return
        }
        // Already answered definitively this session; the local read above is
        // what keeps watching for a row that arrives by sync afterwards.
        lock.lock()
        let answered = hasKeys != nil
        lock.unlock()
        if answered { return }

        let confirmed = await serverHasKeyRow(userId: userId)
        lock.lock()
        hasKeys = confirmed
        lock.unlock()
    }

    /**
     Does the SERVER hold a `user_keys` row for this user? Nil when we could not
     find out, which is a different answer from "no" and is treated as one.
     */
    private func serverHasKeyRow(userId: String) async -> Bool? {
        do {
            let rows: [[String: String]] = try await client.schema(securitySchema)
                .from(userKeysTable)
                .select("user_id")
                .eq("user_id", value: userId)
                .execute()
                .value
            return !rows.isEmpty
        } catch {
            logDiagnostic(
                level: "warn",
                scope: "security",
                message: "could not confirm whether encryption keys exist: \(describeForLog(error))"
            )
            return nil
        }
    }

    private struct KeyRow: Sendable {
        let salt: String
        let wrappedDekPassphrase: String
        let wrappedDekRecovery: String?
        let wrappedSigningPrivate: String?
    }

    private func readKeyRow(userId: String) async throws -> KeyRow? {
        try await db.getOptional(
            sql: """
                SELECT salt, wrapped_dek_passphrase, wrapped_dek_recovery, wrapped_signing_private
                FROM user_keys WHERE user_id = ? LIMIT 1
                """,
            parameters: [userId],
            mapper: { cursor in
                KeyRow(
                    salt: try cursor.getString(name: "salt"),
                    wrappedDekPassphrase: try cursor.getString(name: "wrapped_dek_passphrase"),
                    wrappedDekRecovery: try cursor.getStringOptional(name: "wrapped_dek_recovery"),
                    wrappedSigningPrivate: try cursor.getStringOptional(name: "wrapped_signing_private")
                )
            }
        )
    }

    // MARK: - Setup / unlock / lock

    /**
     First-time setup. Returns the one-time recovery code, which is shown once
     and never stored in the clear — web's `setupEncryption`.

     The order matters and is web's: the row is written BEFORE the session is
     declared unlocked, so a failed upload leaves the account exactly as it was
     rather than with a DEK on the phone and nothing on the server.

     INSERT, NOT UPSERT, and that is the one deliberate difference from web.
     `user_keys.user_id` is the primary key, so an INSERT over an existing row
     is refused by Postgres itself. Web's `upsert` would happily replace it, and
     replacing it is exactly the irreversible accident this whole feature has to
     be protected from — every note under the old DEK becomes unreadable the
     moment the old wrapped key is overwritten. `refreshKeyState` already
     refuses to offer this form unless the server confirmed there is no row;
     this is the second lock on the same door, and it is the one the database
     enforces rather than the one the client remembers to check.
     */
    public func setupEncryption(passphrase: String) async throws -> String {
        guard let userId = getUserId() else { throw SecurityActionError(SecurityMessageKey.notSignedIn) }
        let salt = newSecuritySalt()
        let freshDek = generateDek()
        let recoveryCode = generateRecoveryCode()

        let signing: SigningKeypairJwk
        let wrappedPassphrase: String
        let wrappedRecovery: String
        let wrappedSigningPrivate: String
        do {
            wrappedPassphrase = try wrapDek(dek: freshDek, kek: deriveKek(passphrase: passphrase, salt: salt))
            wrappedRecovery = try wrapDek(dek: freshDek, kek: deriveKek(passphrase: recoveryCode, salt: salt))
            signing = generateSigningKeypair()
            wrappedSigningPrivate = try encryptField(signing.privateJwkJson, dek: freshDek)
        } catch {
            // A CryptoKit failure here is a broken device, not a user mistake.
            // The panel can only say "Setup failed."; the real error goes to
            // the diagnostics log, which is what ships with a bug report.
            logDiagnostic(
                level: "error",
                scope: "security",
                message: "encryption setup failed in the crypto layer: \(describeForLog(error))"
            )
            throw SecurityActionError(SecurityMessageKey.setupFailed)
        }

        var row: [String: AnyJSON] = [
            "user_id": .string(userId),
            "salt": .string(securityBase64Encode(salt)),
            "wrapped_dek_passphrase": .string(wrappedPassphrase),
            "wrapped_dek_recovery": .string(wrappedRecovery),
            "wrapped_signing_private": .string(wrappedSigningPrivate),
            "updated_at": .string(nowIso()),
        ]
        // jsonb column: it has to arrive as an OBJECT, not as a string holding
        // JSON, or the browser's `importKey("jwk", …)` gets a string back and
        // fails.
        row["signing_public_jwk"] = jsonObject(from: signing.publicJwkJson)

        do {
            try await client.schema(securitySchema).from(userKeysTable).insert(row).execute()
        } catch {
            // Ask the server WHY before deciding what to say. A refused INSERT
            // over an existing row is a completely different event from a
            // network failure -- it means this account already has keys and we
            // very nearly replaced them -- and the difference has to reach the
            // user, because "try again" is right for one and catastrophic for
            // the other. Re-probing rather than parsing the PostgREST error
            // body keeps this independent of how the driver surfaces a 23505.
            if await serverHasKeyRow(userId: userId) == true {
                lock.lock()
                hasKeys = true
                lock.unlock()
                logDiagnostic(
                    level: "warn",
                    scope: "security",
                    message: "setup refused: this account already has encryption keys"
                )
                throw SecurityActionError(SecurityMessageKey.alreadySetUp)
            }
            logDiagnostic(
                level: "error",
                scope: "security",
                message: "could not store encryption keys: \(describeForLog(error))"
            )
            throw SecurityActionError(SecurityMessageKey.setupFailed)
        }

        retain(userId: userId, dek: freshDek, privateJwk: signing.privateJwkJson)
        lock.lock()
        hasKeys = true
        lock.unlock()
        return recoveryCode
    }

    /// Unlock with the passphrase. Web's `unlock`.
    public func unlock(passphrase: String) async throws {
        try await unwrap(secret: passphrase, recovery: false)
    }

    /**
     Unlock with the recovery code. Web's `unlockWithRecovery`, including its
     `.trim().toUpperCase()` — the dashes stay, because they were part of the
     string the KEK was derived from.
     */
    public func unlockWithRecovery(code: String) async throws {
        try await unwrap(secret: normalizeRecoveryCode(code), recovery: true)
    }

    private func unwrap(secret: String, recovery: Bool) async throws {
        guard let userId = getUserId() else { throw SecurityActionError(SecurityMessageKey.notSignedIn) }
        guard let row = try await readKeyRow(userId: userId) else {
            throw SecurityActionError(SecurityMessageKey.notSetUp)
        }
        let wrapped = recovery ? row.wrappedDekRecovery : row.wrappedDekPassphrase
        guard let wrapped else { throw SecurityActionError(SecurityMessageKey.noRecoveryKey) }
        let salt: Data
        do {
            salt = try securityBase64Decode(row.salt)
        } catch {
            // A corrupt salt is not a wrong passphrase, and saying so would
            // send the user hunting for a password that was never the problem.
            logDiagnostic(
                level: "error",
                scope: "security",
                message: "stored key material could not be read: \(describeForLog(error))"
            )
            throw SecurityActionError(SecurityMessageKey.setupFailed)
        }
        let kek = deriveKek(passphrase: secret, salt: salt)
        let opened: Data
        do {
            opened = try unwrapDek(wrapped: wrapped, kek: kek)
        } catch {
            throw SecurityActionError(
                recovery ? SecurityMessageKey.invalidRecovery : SecurityMessageKey.wrongPassphrase
            )
        }
        // Web tolerates a signing key it cannot read and carries on with a nil
        // one -- the DEK is what the user came for, and support access is the
        // rarer path. Same here.
        var privateJwk: String?
        if let wrappedSigning = row.wrappedSigningPrivate {
            privateJwk = try? decryptField(wrappedSigning, dek: opened)
        }
        retain(userId: userId, dek: opened, privateJwk: privateJwk)
    }

    /// Drop the keys. Web's `lock()`, plus erasing the Keychain copies.
    public func lockSession() {
        lock.lock()
        // getUserId() first, not the cached currentUserId: sign-out from a cold
        // start is exactly the case where nothing in this process has ever
        // restored a key, so currentUserId is nil and the Keychain items would
        // survive the sign-out that was supposed to erase them.
        if let uid = getUserId() ?? currentUserId {
            store.remove(dekEntry(uid))
            store.remove(signingEntry(uid))
        }
        forgetLocked()
        currentUserId = nil
        restoreAttemptedFor = nil
        lock.unlock()
    }

    private func retain(userId: String, dek: Data, privateJwk: String?) {
        lock.lock()
        dekBytes = dek
        signingPrivateJwk = privateJwk
        currentUserId = userId
        restoreAttemptedFor = userId
        store.put(dekEntry(userId), dek)
        if let privateJwk { store.put(signingEntry(userId), Data(privateJwk.utf8)) }
        lock.unlock()
    }

    /// Caller holds `lock`.
    private func forgetLocked() {
        dekBytes = nil
        signingPrivateJwk = nil
    }

    // MARK: - Field encryption

    /**
     Encrypt a value for storage if the session is unlocked; otherwise pass it
     through. Web's `encryptForWrite`, backward-compatible by design: writes
     made while locked or before setup stay plaintext, because the alternative
     is refusing to save a transaction over a note.
     */
    public func encryptForWrite(_ plaintext: String?) async -> String? {
        guard let plaintext, !plaintext.isEmpty else { return plaintext }
        if isEncryptedEnvelope(plaintext) { return plaintext }
        await ensureRestored()
        guard let key = dek() else { return plaintext }
        do {
            return try encryptField(plaintext, dek: key)
        } catch {
            // Storing the plaintext is the wrong answer and refusing the save
            // is worse -- the user would lose a transaction over a note. Web's
            // pass-through is the documented fallback for "no key"; this is the
            // same fallback for "no cipher", logged so it is not invisible.
            logDiagnostic(
                level: "error",
                scope: "security",
                message: "could not encrypt a field, stored as-is: \(describeForLog(error))"
            )
            return plaintext
        }
    }

    /**
     The read side, exactly as web's edit screen does it: decrypt when this is
     an envelope AND we hold the key, and otherwise hand back what was stored.

     Handing back the raw envelope while locked is web's behaviour, not an
     oversight of this port — `fields.ts` has a masking helper (`•••••`) that
     web's own edit page does not call, so copying the helper instead of the
     call site would make the phone and the browser show different things.
     Flagged in the report rather than quietly improved here.
     */
    public func decryptForRead(_ value: String?) async -> String? {
        guard let value else { return nil }
        if !isEncryptedEnvelope(value) { return value }
        await ensureRestored()
        guard let key = dek() else { return value }
        return (try? decryptField(value, dek: key)) ?? value
    }

    /**
     True when this value is an envelope this session cannot open.

     The edit form asks so it can DISABLE the note field. Web renders the raw
     `v1.…` into an editable input, and that is not a cosmetic wart: touch one
     character and the mangled string is saved back — it still starts with
     `v1.`, so `encryptForWrite` passes it through untouched — and the note is
     destroyed with no error and no undo. Showing the envelope is web parity;
     letting it be typed into is a data-loss bug, and this port does not
     reproduce it.
     */
    public func isLockedEnvelope(_ value: String?) async -> Bool {
        guard let value, isEncryptedEnvelope(value) else { return false }
        await ensureRestored()
        return dek() == nil
    }

    // MARK: - Support grants

    /// The user's unexpired, unrevoked grants, from the synced local copy.
    public func activeGrants() async throws -> [SupportGrant] {
        try await db.getAll(
            sql: """
                SELECT id, scope, expires_at, created_at FROM support_grants
                WHERE user_id = ? AND revoked_at IS NULL AND expires_at > ?
                ORDER BY created_at DESC
                """,
            parameters: [getUserId() ?? "", nowIso()],
            mapper: { cursor in
                SupportGrant(
                    id: try cursor.getString(name: "id"),
                    scope: try cursor.getString(name: "scope"),
                    expiresAtIso: try cursor.getString(name: "expires_at"),
                    createdAtIso: try cursor.getString(name: "created_at")
                )
            }
        )
    }

    /**
     Issue a support grant. `content` additionally re-wraps the DEK for the
     support public key; `structural` carries no key at all and only authorises
     the drift checksums. Both are signed by the user, which is what proves a
     human agreed.
     */
    public func issueSupportGrant(
        scope: String,
        ttlHours: Int = securityGrantTtlHours
    ) async throws -> IssuedGrant {
        guard let userId = getUserId() else { throw SecurityActionError(SecurityMessageKey.notSignedIn) }
        // newId(), not a UUID spelled out here: WriteHelpers.swift owns id
        // generation for this module, and its lowercase canonical form is what
        // Postgres and the other two clients all write. See Data/Ids.swift.
        let grantId = newId()
        let expiryMs = grantExpiryMillis(nowMs: Int64(Date().timeIntervalSince1970 * 1000), ttlHours: ttlHours)
        let expiresAtIso = isoFromMillis(expiryMs)

        // Restores signingPrivateJwk alongside the DEK, and does the Keychain
        // read off the main actor.
        await ensureRestored()
        guard let key = dek() else {
            throw SecurityActionError(
                scope == SecurityGrantScope.content
                    ? SecurityMessageKey.unlockForContent
                    : SecurityMessageKey.unlockToAuthorize
            )
        }
        lock.lock()
        let privateJwk = signingPrivateJwk
        lock.unlock()
        guard let privateJwk, let d = jwkField(privateJwk, "d") else {
            throw SecurityActionError(SecurityMessageKey.unlockToAuthorize)
        }

        let payload = canonicalGrantJson(userId: userId, grantId: grantId, exp: expiryMs, scope: scope)
        var wrappedForSupport: AnyJSON = .null
        let signature: String
        do {
            if scope == SecurityGrantScope.content {
                guard let jwk = supportPublicKeyParts() else {
                    throw SecurityActionError(SecurityMessageKey.supportNotConfigured)
                }
                wrappedForSupport = .string(
                    try wrapDekForSupport(dek: key, modulusB64Url: jwk.n, exponentB64Url: jwk.e)
                )
            }
            signature = securityBase64Encode(try signGrant(canonicalPayload: payload, privateJwkD: d))
        } catch let error as SecurityActionError {
            // Already a message the panel can show ("Support access is not
            // configured…") -- re-wrapping it as "Couldn't create grant."
            // would replace the useful sentence with a useless one.
            throw error
        } catch {
            // RSA-OAEP-SHA256 through `SecKey` and P-256 signing are the two
            // operations here most likely to fail on a device, and "Couldn't
            // create grant." tells whoever is helping the user nothing at all.
            logDiagnostic(
                level: "error",
                scope: "security",
                message: "support grant could not be signed or wrapped: \(describeForLog(error))"
            )
            throw SecurityActionError(SecurityMessageKey.grantFailed)
        }

        let row: [String: AnyJSON] = [
            "id": .string(grantId),
            "user_id": .string(userId),
            "scope": .string(scope),
            "wrapped_dek_for_support": wrappedForSupport,
            "signature": .string(signature),
            "expires_at": .string(expiresAtIso),
        ]
        do {
            try await client.schema(securitySchema).from(supportGrantsTable).insert(row).execute()
            try await audit(userId: userId, action: "grant_issued", grantId: grantId, detail: "scope=\(scope)")
        } catch {
            logDiagnostic(
                level: "error",
                scope: "security",
                message: "support grant could not be stored: \(describeForLog(error))"
            )
            throw SecurityActionError(SecurityMessageKey.grantFailed)
        }
        return IssuedGrant(grantId: grantId, expiresAtIso: expiresAtIso)
    }

    /// Revoke a grant early. Web's `revokeGrant`.
    public func revokeGrant(grantId: String) async throws {
        guard let userId = getUserId() else { return }
        try await client.schema(securitySchema).from(supportGrantsTable)
            .update(["revoked_at": AnyJSON.string(nowIso())])
            .eq("id", value: grantId)
            .eq("user_id", value: userId)
            .execute()
        try await audit(userId: userId, action: "grant_revoked", grantId: grantId, detail: nil)
    }

    /**
     One row into the hash-chained `security_audit`.

     `prev_hash`/`row_hash` are deliberately absent: migration 0021's
     before-insert trigger computes them server-side, and a client that sent
     its own would be claiming to know the chain's head, which it cannot.
     */
    private func audit(userId: String, action: String, grantId: String, detail: String?) async throws {
        let row: [String: AnyJSON] = [
            "actor": .string("user:\(userId)"),
            "action": .string(action),
            "subject_user": .string(userId),
            "grant_id": .string(grantId),
            "detail": detail.map { AnyJSON.string($0) } ?? .null,
        ]
        try await client.schema(securitySchema).from(securityAuditTable).insert(row).execute()
    }

    // MARK: - Small helpers

    /// The support key's `n` and `e`, or nil when none is configured.
    private func supportPublicKeyParts() -> (n: String, e: String)? {
        guard let raw = supportPublicJwk, !raw.isEmpty else { return nil }
        guard let n = jwkField(raw, "n"), let e = jwkField(raw, "e") else { return nil }
        return (n, e)
    }

    private func jwkField(_ document: String, _ field: String) -> String? {
        guard let data = document.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parsed[field] as? String
    }

    /// The public JWK document as an `AnyJSON` object, for the jsonb column.
    private func jsonObject(from document: String) -> AnyJSON {
        guard let data = document.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .null
        }
        var out: [String: AnyJSON] = [:]
        for (key, value) in parsed {
            switch value {
            case let text as String: out[key] = .string(text)
            case let flag as Bool: out[key] = .bool(flag)
            case let list as [String]: out[key] = .array(list.map { AnyJSON.string($0) })
            default: continue
            }
        }
        return .object(out)
    }

    /// The same ISO-8601 shape `nowIso()` writes, for a future instant.
    ///
    /// Default `formatOptions` deliberately, matching WriteHelpers.swift: the
    /// column is a `timestamptz` and Postgres parses either, but two writers in
    /// one app emitting two shapes is how a string comparison somewhere starts
    /// being wrong.
    private func isoFromMillis(_ millis: Int64) -> String {
        ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
    }

    private func dekEntry(_ userId: String) -> String { "dek:\(userId)" }
    private func signingEntry(_ userId: String) -> String { "signing:\(userId)" }
}

/**
 What is safe to write into a diagnostics log about a failure here.

 The error's type plus its description, never a dump of what was being operated
 on: this text ships inside bug reports, and the one thing that must never
 travel with one is key material. CryptoKit, `Security` and PostgREST errors all
 describe what went wrong rather than what it was applied to, so the pair is
 both safe and enough to act on.
 */
private func describeForLog(_ error: Error) -> String {
    "\(type(of: error)): \(error)"
}

private let securitySchema = "pocketcare"
private let userKeysTable = "user_keys"
private let supportGrantsTable = "support_grants"
private let securityAuditTable = "security_audit"
