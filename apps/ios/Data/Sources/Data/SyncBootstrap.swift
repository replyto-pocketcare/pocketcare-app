import Foundation
import Factory
import PowerSync

/**
 Connects PowerSync to the server, and keeps that connection matched to who is
 signed in.

 ## Why this file exists

 Until it did, **neither native app ever called
 `PowerSyncDatabase.connect(connector:)`.** `SupabaseConnector` was constructed
 in DI on both platforms and then never handed to anything. The consequence is
 not a missing feature — it is that both apps were purely local databases:
 nothing written on a phone ever reached Supabase, and nothing written on web
 ever arrived. Every screen worked, every write succeeded, every read returned
 the right rows, and the data never left the device.

 Several things that looked like separate problems were this one wearing
 different clothes: `hasSynced` never flipped (so every first-sync gate ran to
 its ten-second deadline on every launch), `connected` was permanently false,
 `lastSyncedAt` was permanently null, and the sync-status strip's warning branch
 had nothing to be about.

 ## What it mirrors

 `apps/web/src/powersync.ts`'s `initSystem()` and its `onAuthStateChange`
 handler, which are the only places web connects. The four rules, in web's own
 order:

 1. **Connect only when a session already exists.** No auto-created guest. A
    brand-new install stays unauthenticated and goes to onboarding to choose —
    create an account, sign in, or explicitly try as a guest.
 2. **In the background, never blocking first paint.** A slow or unreachable
    PowerSync must not hold the UI: local SQLite already has the answer, and a
    spinner over readable data is strictly worse than stale data.
 3. **Re-key when the signed-in identity CHANGES.** The app can boot as a guest
    and later sign in without a process restart, so the connection has to be torn
    down, the guest's local rows cleared, and a new one opened under the real JWT
    — otherwise the account never downloads.
 4. **A same-id transition does NOT clear.** Guest → registered via `updateUser`
    keeps the user id, and clearing there would throw away local writes that have
    not been uploaded yet. Keying on *change* rather than on the sign-in event is
    what gets this right.

 ## What it deliberately does not do

 It does not create a session, and it does not decide when one should exist.
 That is `AuthRepository`'s job, and conflating the two is how you end up with a
 sync layer that silently signs people in.

 An `actor` rather than a `@MainActor` class: connect, disconnect and clear are
 not reentrant and they race in a way that is very hard to see — a sign-out
 arriving mid-`connect` can leave the database connected under a JWT for a user
 who is no longer signed in, which uploads their local writes to the wrong
 account. Actor isolation makes the sequence a queue, and none of this work
 belongs on the main thread anyway.
 */
public actor SyncBootstrap {
    private let db: any PowerSyncDatabaseProtocol
    private let connector: SupabaseConnector
    private let auth: any AuthRepository

    /// The identity the current connection was opened for.
    ///
    /// Empty means "not connected". This is the whole state machine: every
    /// decision below is a comparison between this and the id the auth stream
    /// just produced.
    private var connectedUserId = ""
    private var following: Task<Void, Never>?

    public init(
        db: any PowerSyncDatabaseProtocol,
        connector: SupabaseConnector,
        auth: any AuthRepository
    ) {
        self.db = db
        self.connector = connector
        self.auth = auth
    }

    /// Begin following the session. Idempotent and safe to call once at launch.
    public func start() {
        guard following == nil else { return }
        following = Task { [weak self] in
            guard let self else { return }
            // The CURRENT session first. `authStateChanges` only reports
            // transitions, so a returning user with a stored session emits
            // nothing at launch and would never connect.
            await self.apply(self.auth.currentUserId ?? "")
            for await _ in self.auth.authState {
                await self.apply(self.auth.currentUserId ?? "")
            }
        }
    }

    /// Web's `forceSync()`: drop the connection and open a fresh one.
    public func forceSync() async {
        guard !connectedUserId.isEmpty else { return }
        try? await db.disconnect()
        await openConnection(userId: connectedUserId, clearFirst: false)
    }

    private func apply(_ userId: String) async {
        if userId.isEmpty {
            // Signed out. Drop the connection AND the local rows -- the next
            // person to use this device must not find them.
            guard !connectedUserId.isEmpty else { return }
            connectedUserId = ""
            do { try await db.disconnectAndClear() } catch {
                logDiagnostic(level: "error", scope: "sync", message: "disconnectAndClear failed: \(error)")
            }
            return
        }
        // Already connected as this person. Do NOT reconnect -- that would
        // re-download everything on every emission of the auth stream.
        guard userId != connectedUserId else { return }
        // A DIFFERENT person: clear the previous identity's rows first. A
        // same-id guest-to-registered transition never reaches here, which is
        // the point.
        await openConnection(userId: userId, clearFirst: !connectedUserId.isEmpty)
    }

    private func openConnection(userId: String, clearFirst: Bool) async {
        if clearFirst {
            do { try await db.disconnectAndClear() } catch {
                logDiagnostic(level: "error", scope: "sync", message: "clear before re-key failed: \(error)")
            }
        }
        connectedUserId = userId
        do {
            try await db.connect(connector: connector)
        } catch {
            // Leave `connectedUserId` set. PowerSync retries internally, and
            // clearing it here would make the next auth emission look like a
            // fresh sign-in and clear the user's local data.
            logDiagnostic(level: "error", scope: "sync", message: "connect failed: \(error)")
        }
    }
}

public extension Container {
    var syncBootstrap: Factory<SyncBootstrap> {
        self {
            SyncBootstrap(
                db: Container.shared.powerSyncDatabase(),
                connector: Container.shared.supabaseConnector(),
                auth: Container.shared.authRepository()
            )
        }.singleton
    }
}
