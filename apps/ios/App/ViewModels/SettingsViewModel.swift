import Foundation
import Domain
import Data
import Factory
import Observation
import Supabase
import PowerSync

/// Settings screen state + actions (task #47). See settings.md for the full
/// scope reasoning; mirrors apps/android/app/.../ui/SettingsViewModel.kt.

public struct SessionInfo: Sendable {
    public let email: String?
    public let isGuest: Bool
    public let username: String
    /// Days until a guest's data is deleted. Nil once registered.
    public let daysLeft: Int?
}

public struct EntitlementUi: Sendable {
    public let tier: String
    public let isPaid: Bool
}

public struct RepairFailure: Sendable, Identifiable {
    public let table: String
    public let id: String
    public let error: String
}

@MainActor
@Observable
class SettingsViewModel {
    @ObservationIgnored
    @Injected(\.prefsRepository) private var prefsRepo
    @ObservationIgnored
    @Injected(\.authRepository) private var authRepo
    @ObservationIgnored
    @Injected(\.repairRepository) private var repairRepo
    @ObservationIgnored
    @Injected(\.supabaseClient) private var client
    @ObservationIgnored
    @Injected(\.powerSyncDatabase) private var db

    // Notifications (existing)
    var notifPrefs: NotificationPrefs?

    // Account / session
    var session: SessionInfo?
    var usernameSaved = false

    // Plan & billing
    var entitlement = EntitlementUi(tier: "free", isPaid: false)

    // About you
    var profileGender = ""
    var profileCountry = ""
    private var profileExists = false
    var profileMsg: String?

    // Diagnostics
    var diagnosticsEntries: [LogEntry] = []
    var queueOps: [QueuedOp] = []
    var queueDepth: Int?
    var discardingStuck = false

    // Problems syncing
    var failedWrites: [FailedWriteItem] = []
    var problemsBusy: String?

    // Check for unsynced data
    var repairStage = "idle" // idle|scanning|found|clean|repairing|done|error
    var strandedRows: [StrandedRow] = []
    var repairUnchecked: [String] = []
    var repairUploaded = 0
    var repairFailed: [RepairFailure] = []
    var repairError: String?

    // Sync status
    var syncConnected = false
    var syncLastSyncedAt: String?

    // Delete account
    var deleting = false
    var deleteError: String?

    /// See GoalsViewModel.swift/InsightsViewModel.swift's identical helper --
    /// `??`'s RHS is an `@autoclosure`, so `currentUserId ?? (try? await
    /// ensureUser())` is invalid Swift; use an explicit if/else instead.
    private func resolveUserId() async -> String? {
        if let existing = authRepo.currentUserId { return existing }
        return try? await authRepo.ensureUser()
    }

    func start() async {
        await loadPrefs()
        await loadSession()
        await loadProfile()
        refreshDiagnostics()
        await refreshFailedWrites()
        await loadEntitlement()
    }

    private func loadEntitlement() async {
        // One-shot read is enough for Settings (unlike Insights, which needs
        // a live watch for its premium gate) -- take the first emission only.
        guard let stream = try? prefsRepo.watchEntitlement() else { return }
        // `AsyncThrowingStream` iteration itself throws, and this function is
        // `async` rather than `async throws` — so the do/catch is required, not
        // decorative. Offline keeps whatever tier was last known instead of
        // silently downgrading someone to free.
        do {
            for try await row in stream {
                guard let row else {
                    entitlement = EntitlementUi(tier: "free", isPaid: false)
                    return
                }
                let paid = isPaid(tier: row.tier, premiumTrialStartDate: row.premiumTrialStartDate, compTier: row.compTier, compUntil: row.compUntil, now: Date())
                entitlement = EntitlementUi(tier: row.tier ?? "free", isPaid: paid)
                return
            }
        } catch {
            /* offline — keep the last known tier */
        }
    }

    private func loadPrefs() async {
        guard let userId = await resolveUserId() else { return }
        do {
            if let p = try await prefsRepo.getNotificationPrefs(userId: userId) {
                self.notifPrefs = p
            } else {
                let p = NotificationPrefs(user_id: userId)
                try await prefsRepo.updateNotificationPrefs(userId: userId, prefs: p)
                self.notifPrefs = p
            }
        } catch {
            print("Failed to load notif prefs: \(error)")
        }
    }

    func updatePref(keyPath: WritableKeyPath<NotificationPrefs, Int>, value: Bool) {
        guard var prefs = notifPrefs else { return }
        prefs[keyPath: keyPath] = value ? 1 : 0
        self.notifPrefs = prefs
        Task {
            guard let userId = await resolveUserId() else { return }
            try? await prefsRepo.updateNotificationPrefs(userId: userId, prefs: prefs)
        }
    }

    private func loadSession() async {
        guard let s = try? await client.auth.session else { session = nil; return }
        let user = s.user
        let guest = user.isAnonymous
        let username = user.userMetadata["username"]?.stringValue ?? ""
        let createdAtMs = Int64(user.createdAt.timeIntervalSince1970 * 1000)
        var daysLeft: Int? = nil
        if guest {
            let remainMs = createdAtMs + 3 * 86_400_000 - Int64(Date().timeIntervalSince1970 * 1000)
            daysLeft = max(0, Int(ceil(Double(remainMs) / 86_400_000.0)))
        }
        session = SessionInfo(email: user.email, isGuest: guest, username: username, daysLeft: daysLeft)
    }

    func saveUsername(_ name: String) {
        Task {
            do {
                try await client.auth.update(user: UserAttributes(data: ["username": .string(name)]))
                if let s = session { session = SessionInfo(email: s.email, isGuest: s.isGuest, username: name, daysLeft: s.daysLeft) }
                usernameSaved = true
            } catch {
                // Offline -- best effort, matches web's swallow-and-keep-local.
            }
        }
    }

    func clearUsernameSaved() { usernameSaved = false }

    func signOut() {
        Task { try? await authRepo.signOut() }
    }

    // MARK: - About you (profiles.gender / profiles.country)

    private func loadProfile() async {
        guard let userId = await resolveUserId() else { return }
        struct Row { let gender: String; let country: String }
        var result: Row?
        do {
            result = try await db.getOptional(
                sql: "SELECT gender, country FROM profiles WHERE id = ? LIMIT 1",
                parameters: [userId]
            ) { c in
                let gender = try c.getStringOptional(name: "gender") ?? ""
                let country = try c.getStringOptional(name: "country") ?? ""
                return Row(gender: gender, country: country)
            }
        } catch {
            result = nil // profiles row may not exist yet -- fine, save() will insert it
        }
        if let row = result {
            profileExists = true
            profileGender = row.gender
            profileCountry = row.country
        }
    }

    func saveProfile(gender: String, country: String) {
        Task {
            guard let userId = await resolveUserId() else { return }
            profileMsg = nil
            do {
                if profileExists {
                    try await updateRow(db: db, table: "profiles", id: userId, values: [
                        "gender": gender.isEmpty ? nil : gender,
                        "country": country.isEmpty ? nil : country,
                    ])
                } else {
                    try await insertRow(db: db, table: "profiles", userId: userId, values: [
                        "id": userId,
                        "gender": gender.isEmpty ? nil : gender,
                        "country": country.isEmpty ? nil : country,
                    ])
                    profileExists = true
                }
                profileGender = gender
                profileCountry = country
                profileMsg = "Saved."
            } catch {
                profileMsg = error.localizedDescription
            }
        }
    }

    // MARK: - Diagnostics

    /// Deliberately minimal -- see SettingsViewModel.kt's identical doc
    /// comment on refreshDiagnostics for why only `.connected`/`.lastSyncedAt`
    /// are read off `db.currentStatus`.
    func refreshDiagnostics() {
        diagnosticsEntries = currentDiagnosticsEntries()
        let status = db.currentStatus
        syncConnected = status.connected
        syncLastSyncedAt = status.lastSyncedAt.map { ISO8601DateFormatter().string(from: $0) }

        Task {
            do {
                queueDepth = try await db.getOptional(sql: "SELECT COUNT(*) AS n FROM ps_crud", parameters: []) { c in
                    Int(try c.getInt64(index: 0))
                }
            } catch {
                queueDepth = nil
            }
            let failingTable = failingTableFrom(diagnosticsEntries)
            queueOps = await inspectQueue(db: db, failingTable: failingTable)
        }
    }

    func diagnosticsShareText() -> String {
        let errors = diagnosticsEntries.filter { $0.level == "error" }.count
        let context: [(key: String, value: String?)] = [
            ("queuedWrites", queueDepth.map { String($0) } ?? "unknown"),
            ("queue", summarizeQueue(queueOps)),
            ("errorsLogged", String(errors)),
        ]
        return diagnosticsReport(context: context)
    }

    func discardStuck() {
        let stuck = queueOps.filter { $0.orphaned }
        guard !stuck.isEmpty else { return }
        Task {
            discardingStuck = true
            _ = await discardOps(db: db, ids: stuck.map { $0.id })
            refreshDiagnostics()
            discardingStuck = false
        }
    }

    // MARK: - Problems syncing

    func refreshFailedWrites() async {
        failedWrites = (try? await repairRepo.listFailedWrites()) ?? []
    }

    func retryFailedWrite(_ item: FailedWriteItem) {
        Task {
            problemsBusy = item.id
            _ = await repairRepo.retryFailedWrite(item)
            problemsBusy = nil
            await refreshFailedWrites()
        }
    }

    func retryAllFailedWrites() {
        Task {
            problemsBusy = "all"
            for item in failedWrites { _ = await repairRepo.retryFailedWrite(item) }
            problemsBusy = nil
            await refreshFailedWrites()
        }
    }

    func discardFailedWrite(_ item: FailedWriteItem) {
        Task {
            problemsBusy = item.id
            await repairRepo.discardFailedWrite(item)
            problemsBusy = nil
            await refreshFailedWrites()
        }
    }

    func exportFailedWritesJson(_ items: [FailedWriteItem]? = nil) -> String {
        repairRepo.exportFailedWritesJson(items: items ?? failedWrites)
    }

    // MARK: - Check for unsynced data

    func scanForStranded() {
        Task {
            repairStage = "scanning"
            repairError = nil
            let res = await repairRepo.scanForStranded()
            strandedRows = res.stranded
            repairUnchecked = res.unchecked
            repairStage = res.stranded.isEmpty ? "clean" : "found"
        }
    }

    func repairStrandedNow() {
        Task {
            repairStage = "repairing"
            let (uploaded, failed) = await repairRepo.repairStranded(strandedRows)
            repairUploaded = uploaded
            repairFailed = failed.map { RepairFailure(table: $0.table, id: $0.id, error: $0.error) }
            repairStage = "done"
        }
    }

    func resetRepair() {
        repairStage = "idle"
        strandedRows = []
        repairUnchecked = []
        repairFailed = []
        repairUploaded = 0
        repairError = nil
    }

    func exportStrandedJson() -> String { repairRepo.exportStrandedJson(rows: strandedRows) }

    // MARK: - Delete account

    /// The RPC lives in the `pocketcare` schema -- see RepairRepository.swift
    /// and DeleteAccount's Android equivalent's identical doc comment for why
    /// (matches SupabaseConnector's DB_SCHEMA, NOT the `sanvya` schema used
    /// elsewhere in this codebase's own naming).
    func deleteAccount() {
        Task {
            deleting = true
            deleteError = nil
            do {
                try await client.schema("pocketcare").rpc("delete_user_account", params: ["orphan_records": false]).execute()
                do {
                    try await db.disconnectAndClear()
                } catch {
                    // best-effort local clear; sign-out proceeds regardless
                }
                try await authRepo.signOut()
            } catch {
                deleteError = error.localizedDescription
            }
            deleting = false
        }
    }
}
