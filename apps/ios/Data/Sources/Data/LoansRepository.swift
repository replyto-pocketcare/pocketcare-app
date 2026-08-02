import Foundation
import PowerSync

public struct Loan: Identifiable, Sendable {
    public let id: String
    public let userId: String
    public let lender: String
    public let principal: Int64
    public let currency: String
    public let interestRate: Double
    public let tenureMonths: Int64
    public let emiAmount: Int64
    public let startDate: String
    public let emisPaid: Int64
    public let emiDueDay: Int64
    public let autoMarkPaid: Bool
    public let rateType: String
}

public actor LoansRepository {
    private let db: PowerSyncDatabaseProtocol

    public init(db: PowerSyncDatabaseProtocol) {
        self.db = db
    }

    private func loanMapper(cursor: SqlCursor) throws -> Loan {
        Loan(
            id: try cursor.getString(name: "id"),
            userId: try cursor.getString(name: "user_id"),
            lender: try cursor.getString(name: "lender"),
            principal: try cursor.getInt64(name: "principal"),
            currency: try cursor.getString(name: "currency"),
            interestRate: try cursor.getDouble(name: "interest_rate"),
            tenureMonths: try cursor.getInt64(name: "tenure_months"),
            emiAmount: try cursor.getInt64(name: "emi_amount"),
            startDate: try cursor.getString(name: "start_date"),
            emisPaid: try cursor.getInt64(name: "emis_paid"),
            emiDueDay: try cursor.getInt64(name: "emi_due_day"),
            autoMarkPaid: (try cursor.getBooleanOptional(name: "auto_mark_paid")) ?? false,
            rateType: try cursor.getString(name: "rate_type")
        )
    }

    public func watchLoans(userId: String) throws -> AsyncThrowingStream<[Loan], Error> {
        try db.watch(
            sql: "SELECT * FROM loans WHERE deleted_at IS NULL AND user_id = ? ORDER BY created_at DESC",
            parameters: [userId],
            mapper: loanMapper
        )
    }
}
