package com.sanvya.app.data.sync

import com.powersync.PowerSyncDatabase
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.diagnostics.logDiagnostic
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Connects PowerSync to the server, and keeps that connection matched to who is
 * signed in.
 *
 * ## Why this file exists
 *
 * Until it did, **neither native app ever called
 * `PowerSyncDatabase.connect(connector)`.** `SupabaseConnector` was constructed
 * in DI on both platforms and then never handed to anything. The consequence is
 * not a missing feature — it is that both apps were purely local databases:
 * nothing written on a phone ever reached Supabase, and nothing written on web
 * ever arrived. Every screen worked, every write succeeded, every read returned
 * the right rows, and the data never left the device.
 *
 * Several things that looked like separate problems were this one wearing
 * different clothes: `hasSynced` never flipped (so every first-sync gate ran to
 * its ten-second deadline on every launch), `connected` was permanently false,
 * `lastSyncedAt` was permanently null, and the sync-status strip's warning
 * branch had nothing to be about.
 *
 * ## What it mirrors
 *
 * `apps/web/src/powersync.ts`'s `initSystem()` and its `onAuthStateChange`
 * handler, which are the only places web connects. The four rules, in web's
 * own order:
 *
 *  1. **Connect only when a session already exists.** No auto-created guest. A
 *     brand-new install stays unauthenticated and goes to onboarding to choose
 *     — create an account, sign in, or explicitly try as a guest.
 *  2. **In the background, never blocking first paint.** A slow or unreachable
 *     PowerSync must not hold the UI: local SQLite already has the answer, and
 *     a spinner over readable data is strictly worse than stale data.
 *  3. **Re-key when the signed-in identity CHANGES.** The app can boot as a
 *     guest and later sign in without a process restart, so the connection has
 *     to be torn down, the guest's local rows cleared, and a new connection
 *     opened under the real JWT — otherwise the account never downloads.
 *  4. **A same-id transition does NOT clear.** Guest → registered via
 *     `updateUser` keeps the user id, and clearing there would throw away local
 *     writes that have not been uploaded yet. Keying on *change* rather than on
 *     the sign-in event is what gets this right.
 *
 * ## What it deliberately does not do
 *
 * It does not create a session, and it does not decide when one should exist.
 * That is `AuthRepository`'s job, and conflating the two is how you end up with
 * a sync layer that silently signs people in.
 */
class SyncBootstrap(
    private val db: PowerSyncDatabase,
    private val connector: SupabaseConnector,
    private val auth: AuthRepository,
) {
    /**
     * The identity the current connection was opened for.
     *
     * Empty means "not connected". This is the whole state machine: every
     * decision below is a comparison between this and the id the auth flow just
     * emitted.
     */
    private var connectedUserId: String = ""

    /**
     * Serialises connect / disconnect / clear.
     *
     * These are not reentrant and they race in a way that is very hard to see:
     * a sign-out arriving mid-`connect` can leave the database connected under
     * a JWT for a user who is no longer signed in, which uploads their local
     * writes to the wrong account. One lock makes the sequence a queue.
     */
    private val gate = Mutex()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * Begin following the session. Idempotent and safe to call once from
     * application startup.
     */
    fun start() {
        scope.launch {
            auth.currentUserId.collect { userId -> apply(userId.orEmpty()) }
        }
    }

    /** Web's `forceSync()`: drop the connection and open a fresh one. */
    suspend fun forceSync() {
        gate.withLock {
            if (connectedUserId.isEmpty()) return@withLock
            runCatching { db.disconnect() }
            openConnection(connectedUserId, clearFirst = false)
        }
    }

    private suspend fun apply(userId: String) {
        gate.withLock {
            when {
                // Signed out. Drop the connection AND the local rows -- the
                // next person to use this device must not find them.
                userId.isEmpty() && connectedUserId.isNotEmpty() -> {
                    connectedUserId = ""
                    runCatching { db.disconnectAndClear() }
                        .onFailure { logDiagnostic("error", "sync", "disconnectAndClear failed: ${it.message}") }
                }
                userId.isEmpty() -> Unit
                // Already connected as this person. Nothing to do -- and in
                // particular do NOT reconnect, which would re-download
                // everything on every emission of the session flow.
                userId == connectedUserId -> Unit
                // A DIFFERENT person. Clear the previous identity's rows before
                // opening the new connection. A same-id guest-to-registered
                // transition never reaches here, which is the point.
                connectedUserId.isNotEmpty() -> openConnection(userId, clearFirst = true)
                else -> openConnection(userId, clearFirst = false)
            }
        }
    }

    private suspend fun openConnection(userId: String, clearFirst: Boolean) {
        if (clearFirst) {
            runCatching { db.disconnectAndClear() }
                .onFailure { logDiagnostic("error", "sync", "clear before re-key failed: ${it.message}") }
        }
        connectedUserId = userId
        runCatching { db.connect(connector) }
            .onFailure {
                // Leave `connectedUserId` set. PowerSync retries internally, and
                // clearing it here would make the next session emission look
                // like a fresh sign-in and clear the user's local data.
                logDiagnostic("error", "sync", "connect failed: ${it.message}")
            }
    }
}
