import Foundation
import PowerSync

/// Read/write facade over goals + goal_allocations, matching
/// apps/web/app/goals/page.tsx per docs/mobile/screen-specs/goals.md. Was
/// read-only (watchGoals/watchGoalAllocations only, no create/update/
/// delete/allocate) before this pass (2026-08-06, task #25), then briefly
/// switched to a one-shot list(userId)/listAllocations(userId) pair driven
/// by an explicit reload() (matching BudgetsViewModel's convention at the
/// time). That reload()-only approach turned out to be the root cause of a
/// real bug found 2026-08-06: since Add/Edit Goal are separate screens with
/// their own GoalsViewModel instance, saving there never called reload() on
/// the list screen's own (different) instance, so a new/edited goal didn't
/// appear until the whole Goals screen was torn down and recreated (e.g. by
/// navigating elsewhere and back). Fixed by adding real
/// watchGoals/watchAllocations (db.watch, same pattern as
/// InvestmentsRepository/LoansRepository) so the list is driven by a live
/// query against the actual table instead of a manually-triggered snapshot
/// -- see AUDIT_HISTORY.md's 2026-08-06 "list staleness" entry. Mirrors
/// Android's GoalsRepository.kt field-for-field.
public struct Goal: Identifiable, Sendable {
    public let id: String
    public let userId: String
    public let name: String
    public let targetAmount: Int64
    public let currency: String
    public let priority: Int64
    public let isEmergencyFund: Bool
    public let alertTimeUtc: String?
}

public struct GoalAllocation: Identifiable, Sendable {
    public let id: String
    public let userId: String
    public let goalId: String
    public let sourceAccountId: String
    public let amountBlocked: Int64
}

public actor GoalsRepository {
    private let db: PowerSyncDatabaseProtocol

    public init(db: PowerSyncDatabaseProtocol) {
        self.db = db
    }

    private func goalMapper(cursor: SqlCursor) throws -> Goal {
        Goal(
            id: try cursor.getString(name: "id"),
            userId: try cursor.getString(name: "user_id"),
            name: try cursor.getString(name: "name"),
            targetAmount: try cursor.getInt64(name: "target_amount"),
            currency: try cursor.getString(name: "currency"),
            priority: try cursor.getInt64(name: "priority"),
            isEmergencyFund: (try cursor.getBooleanOptional(name: "is_emergency_fund")) ?? false,
            alertTimeUtc: try cursor.getStringOptional(name: "alert_time_utc")
        )
    }

    private func allocationMapper(cursor: SqlCursor) throws -> GoalAllocation {
        GoalAllocation(
            id: try cursor.getString(name: "id"),
            userId: try cursor.getString(name: "user_id"),
            goalId: try cursor.getString(name: "goal_id"),
            sourceAccountId: try cursor.getString(name: "source_account_id"),
            amountBlocked: try cursor.getInt64(name: "amount_blocked")
        )
    }

    /// Matches web's `ORDER BY is_emergency_fund DESC, priority` (EF goal
    /// always first). Construction is inlined in the trailing closure
    /// (rather than calling the actor-isolated `goalMapper` via `self.`)
    /// matching BudgetRepository.swift's `list()` -- the only
    /// confirmed-working `db.getAll` call shape in this package; `getAll`
    /// takes a trailing closure, not a labeled `mapper:` (unlike `db.watch`,
    /// which does and is fine calling a bare actor-isolated method
    /// reference, see `LoansRepository.swift`'s `watchLoans`/this file's
    /// `watchGoals` below -- kept deliberately separate from `getAll`'s
    /// closure shape rather than unifying them, since that's untested).
    public func list(userId: String) async throws -> [Goal] {
        try await db.getAll(
            sql: "SELECT * FROM goals WHERE deleted_at IS NULL AND user_id = ? ORDER BY is_emergency_fund DESC, priority",
            parameters: [userId]
        ) { cursor in
            Goal(
                id: try cursor.getString(name: "id"),
                userId: try cursor.getString(name: "user_id"),
                name: try cursor.getString(name: "name"),
                targetAmount: try cursor.getInt64(name: "target_amount"),
                currency: try cursor.getString(name: "currency"),
                priority: try cursor.getInt64(name: "priority"),
                isEmergencyFund: (try cursor.getBooleanOptional(name: "is_emergency_fund")) ?? false,
                alertTimeUtc: try cursor.getStringOptional(name: "alert_time_utc")
            )
        }
    }

    /// All of the user's allocations in one query -- web does the same
    /// (a single goal_allocations query, saved(goalId) filters+reduces
    /// client-side).
    public func listAllocations(userId: String) async throws -> [GoalAllocation] {
        try await db.getAll(
            sql: "SELECT * FROM goal_allocations WHERE deleted_at IS NULL AND user_id = ?",
            parameters: [userId]
        ) { cursor in
            GoalAllocation(
                id: try cursor.getString(name: "id"),
                userId: try cursor.getString(name: "user_id"),
                goalId: try cursor.getString(name: "goal_id"),
                sourceAccountId: try cursor.getString(name: "source_account_id"),
                amountBlocked: try cursor.getInt64(name: "amount_blocked")
            )
        }
    }

    /// Live version of [list] -- re-emits on any local write to `goals`,
    /// regardless of which repository/ViewModel instance performed it.
    /// Added 2026-08-06 to fix list staleness (see the type doc comment).
    public func watchGoals(userId: String) throws -> AsyncThrowingStream<[Goal], Error> {
        try db.watch(
            sql: "SELECT * FROM goals WHERE deleted_at IS NULL AND user_id = ? ORDER BY is_emergency_fund DESC, priority",
            parameters: [userId],
            mapper: goalMapper
        )
    }

    /// Live version of [listAllocations]. Added 2026-08-06 to fix list
    /// staleness (see [watchGoals]).
    public func watchAllocations(userId: String) throws -> AsyncThrowingStream<[GoalAllocation], Error> {
        try db.watch(
            sql: "SELECT * FROM goal_allocations WHERE deleted_at IS NULL AND user_id = ?",
            parameters: [userId],
            mapper: allocationMapper
        )
    }

    /// Matches web's addGoal(): priority = caller-supplied (current goal
    /// count, append-to-end).
    @discardableResult
    public func create(userId: String, name: String, targetAmount: Int64, currency: String, isEmergencyFund: Bool, priority: Int64, alertTimeUtc: String) async throws -> String {
        let id = newId()
        let ts = nowIso()
        try await db.execute(
            sql: """
                INSERT INTO goals
                (id,user_id,name,target_amount,currency,is_emergency_fund,priority,alert_time_utc,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?)
                """,
            parameters: [id, userId, name, targetAmount, currency, isEmergencyFund ? 1 : 0, priority, alertTimeUtc, ts, ts]
        )
        return id
    }

    /// Matches web's saveEdit(): name, target_amount, alert_time_utc only
    /// -- currency, is_emergency_fund, and priority are not editable after
    /// creation.
    public func update(id: String, name: String, targetAmount: Int64, alertTimeUtc: String) async throws {
        let ts = nowIso()
        try await db.execute(
            sql: "UPDATE goals SET name = ?, target_amount = ?, alert_time_utc = ?, updated_at = ? WHERE id = ?",
            parameters: [name, targetAmount, alertTimeUtc, ts, id]
        )
    }

    /// Soft-deletes the goal row only -- matches web's
    /// `softDelete("goals", goal.id)` exactly, no cascade to its
    /// allocations (see the screen spec's data section for why that's an
    /// accepted, pre-existing asymmetry).
    public func delete(id: String) async throws {
        try await softDelete(db: db, table: "goals", id: id)
    }

    /// Matches web's allocate(): caller is responsible for capping
    /// [amountBlocked] at the goal's remaining amount before calling this
    /// (mirrors web's own client-side `Math.min(..., remaining)` cap).
    public func createAllocation(userId: String, goalId: String, sourceAccountId: String, amountBlocked: Int64) async throws {
        let ts = nowIso()
        try await db.execute(
            sql: """
                INSERT INTO goal_allocations
                (id,user_id,goal_id,source_account_id,amount_blocked,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?)
                """,
            parameters: [newId(), userId, goalId, sourceAccountId, amountBlocked, ts, ts]
        )
    }
}
