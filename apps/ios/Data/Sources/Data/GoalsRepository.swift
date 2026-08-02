import Foundation
import PowerSync

public struct Goal: Identifiable, Sendable {
    public let id: String
    public let userId: String
    public let name: String
    public let targetAmount: Int64
    public let currency: String
    public let priority: Int64
    public let isEmergencyFund: Bool
    public let targetDate: String?
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
            targetDate: try cursor.getStringOptional(name: "target_date")
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

    public func watchGoals(userId: String) throws -> AsyncThrowingStream<[Goal], Error> {
        try db.watch(
            sql: "SELECT * FROM goals WHERE deleted_at IS NULL AND user_id = ? ORDER BY priority ASC, created_at DESC",
            parameters: [userId],
            mapper: goalMapper
        )
    }

    public func watchGoalAllocations(goalId: String) throws -> AsyncThrowingStream<[GoalAllocation], Error> {
        try db.watch(
            sql: "SELECT * FROM goal_allocations WHERE deleted_at IS NULL AND goal_id = ?",
            parameters: [goalId],
            mapper: allocationMapper
        )
    }
}
