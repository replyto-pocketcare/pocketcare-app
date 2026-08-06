import Foundation
import PowerSync

/// Loans (EMI) repository -- P3.11/P3.16 (task #27), read/write. Mirrors
/// apps/web/app/loans/page.tsx's `AddLoan.save()` and [id]/page.tsx's
/// `setManualPaid`/`setAmount`/`toggleAutoMark`/`EditLoan.save()` exactly,
/// and Android's LoansRepository.kt field-for-field. See
/// docs/mobile/screen-specs/loans.md for the full source-verification
/// notes.
///
/// Fixed this pass (2026-08-06): `tenure_months`/`emi_amount`/`start_date`/
/// `emis_paid`/`emi_due_day`/`rate_type` were all mapped as non-nullable
/// via non-optional cursor getters despite web's own `Loan` interface
/// treating every one of them as nullable -- a real crash risk, same bug
/// class already found and fixed in Budgets/Investments this engagement.
/// Also added `emi_payments`/`emi_amounts`/`funding_account_id`/
/// `alert_time_utc`, which the schema already had but this repository's
/// `Loan` struct was missing entirely.
public struct Loan: Identifiable, Sendable {
    public let id: String
    public let userId: String
    public let lender: String?
    public let principal: Int64
    public let currency: String
    public let interestRate: Double?
    public let tenureMonths: Int?
    public let emiAmount: Int64?
    public let startDate: String?
    public let emisPaid: Int?
    public let emiPayments: String?
    public let emiDueDay: Int?
    public let autoMarkPaid: Bool
    public let rateType: String?
    public let emiAmounts: String?
    public let fundingAccountId: String?
    public let alertTimeUtc: String?
}

public struct NewLoanInput: Sendable {
    public let lender: String
    public let currency: String
    public let principal: Int64
    public let emiAmount: Int64?
    public let interestRate: Double
    public let tenureMonths: Int?
    public let startDate: String?
    public let emiDueDay: Int?
    public let autoMarkPaid: Bool
    public let rateType: String
    public let fundingAccountId: String?
    public let alertTimeUtc: String

    public init(lender: String, currency: String, principal: Int64, emiAmount: Int64?, interestRate: Double, tenureMonths: Int?, startDate: String?, emiDueDay: Int?, autoMarkPaid: Bool, rateType: String, fundingAccountId: String?, alertTimeUtc: String) {
        self.lender = lender; self.currency = currency; self.principal = principal; self.emiAmount = emiAmount
        self.interestRate = interestRate; self.tenureMonths = tenureMonths; self.startDate = startDate
        self.emiDueDay = emiDueDay; self.autoMarkPaid = autoMarkPaid; self.rateType = rateType
        self.fundingAccountId = fundingAccountId; self.alertTimeUtc = alertTimeUtc
    }
}

public struct EditLoanInput: Sendable {
    public let lender: String?
    public let principal: Int64
    public let emiAmount: Int64?
    public let interestRate: Double
    public let tenureMonths: Int?
    public let startDate: String?
    public let emiDueDay: Int?
    public let rateType: String
    public let alertTimeUtc: String

    public init(lender: String?, principal: Int64, emiAmount: Int64?, interestRate: Double, tenureMonths: Int?, startDate: String?, emiDueDay: Int?, rateType: String, alertTimeUtc: String) {
        self.lender = lender; self.principal = principal; self.emiAmount = emiAmount; self.interestRate = interestRate
        self.tenureMonths = tenureMonths; self.startDate = startDate; self.emiDueDay = emiDueDay
        self.rateType = rateType; self.alertTimeUtc = alertTimeUtc
    }
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
            lender: try cursor.getStringOptional(name: "lender"),
            principal: (try cursor.getInt64Optional(name: "principal")) ?? 0,
            currency: try cursor.getString(name: "currency"),
            interestRate: try cursor.getDoubleOptional(name: "interest_rate"),
            tenureMonths: (try cursor.getInt64Optional(name: "tenure_months")).map { Int($0) },
            emiAmount: try cursor.getInt64Optional(name: "emi_amount"),
            startDate: try cursor.getStringOptional(name: "start_date"),
            emisPaid: (try cursor.getInt64Optional(name: "emis_paid")).map { Int($0) },
            emiPayments: try cursor.getStringOptional(name: "emi_payments"),
            emiDueDay: (try cursor.getInt64Optional(name: "emi_due_day")).map { Int($0) },
            autoMarkPaid: (try cursor.getBooleanOptional(name: "auto_mark_paid")) ?? false,
            rateType: try cursor.getStringOptional(name: "rate_type"),
            emiAmounts: try cursor.getStringOptional(name: "emi_amounts"),
            fundingAccountId: try cursor.getStringOptional(name: "funding_account_id"),
            alertTimeUtc: try cursor.getStringOptional(name: "alert_time_utc")
        )
    }

    public func watchLoans(userId: String) throws -> AsyncThrowingStream<[Loan], Error> {
        try db.watch(
            sql: "SELECT * FROM loans WHERE deleted_at IS NULL AND user_id = ? ORDER BY created_at",
            parameters: [userId],
            mapper: loanMapper
        )
    }

    public func watchLoan(id: String) throws -> AsyncThrowingStream<Loan?, Error> {
        let stream = try db.watch(
            sql: "SELECT * FROM loans WHERE id = ? AND deleted_at IS NULL",
            parameters: [id],
            mapper: loanMapper
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await rows in stream {
                        continuation.yield(rows.first)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Matches web's `AddLoan.save()`: `emis_paid` starts at 0.
    @discardableResult
    public func create(userId: String, input: NewLoanInput) async throws -> String {
        let id = newId()
        let ts = nowIso()
        try await db.execute(
            sql: """
                INSERT INTO loans
                 (id,user_id,lender,currency,principal,emi_amount,interest_rate,tenure_months,start_date,
                  emi_due_day,auto_mark_paid,rate_type,funding_account_id,emis_paid,alert_time_utc,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
            parameters: [
                id, userId, input.lender, input.currency, input.principal, input.emiAmount, input.interestRate,
                input.tenureMonths.map { Int64($0) }, input.startDate, input.emiDueDay.map { Int64($0) },
                input.autoMarkPaid ? 1 : 0, input.rateType, input.fundingAccountId, 0, input.alertTimeUtc, ts, ts,
            ]
        )
        return id
    }

    /// Matches web's `EditLoan.save()`: currency/funding-account/auto-mark
    /// are not editable here (funding account is only set via a mark-paid
    /// confirm, matching web's own `setLoanFundingAccount` call site).
    public func update(id: String, input: EditLoanInput) async throws {
        let ts = nowIso()
        try await db.execute(
            sql: """
                UPDATE loans SET lender = ?, principal = ?, emi_amount = ?, interest_rate = ?, tenure_months = ?,
                 start_date = ?, emi_due_day = ?, rate_type = ?, alert_time_utc = ?, updated_at = ?
                WHERE id = ?
                """,
            parameters: [
                input.lender, input.principal, input.emiAmount, input.interestRate,
                input.tenureMonths.map { Int64($0) }, input.startDate, input.emiDueDay.map { Int64($0) },
                input.rateType, input.alertTimeUtc, ts, id,
            ]
        )
    }

    public func delete(id: String) async throws {
        try await softDelete(db: db, table: "loans", id: id)
    }

    /// Matches web's `setManualPaid()`: rewrites the whole `emi_payments`
    /// JSON map and the legacy `emis_paid` count together.
    public func setManualPaid(id: String, emiPaymentsJson: String, emisPaidCount: Int) async throws {
        let ts = nowIso()
        try await db.execute(
            sql: "UPDATE loans SET emi_payments = ?, emis_paid = ?, updated_at = ? WHERE id = ?",
            parameters: [emiPaymentsJson, Int64(emisPaidCount), ts, id]
        )
    }

    /// Matches web's `setAmount()` (variable-rate month EMI).
    public func setEmiAmounts(id: String, emiAmountsJson: String) async throws {
        let ts = nowIso()
        try await db.execute(sql: "UPDATE loans SET emi_amounts = ?, updated_at = ? WHERE id = ?", parameters: [emiAmountsJson, ts, id])
    }

    /// Matches web's `toggleAutoMark()`.
    public func setAutoMarkPaid(id: String, enabled: Bool) async throws {
        let ts = nowIso()
        try await db.execute(sql: "UPDATE loans SET auto_mark_paid = ?, updated_at = ? WHERE id = ?", parameters: [enabled ? 1 : 0, ts, id])
    }

    /// Matches web's `setLoanFundingAccount()` -- remembered so the next
    /// EMI mark-paid defaults to the same account. Unlike web (which
    /// falls back to localStorage for pre-migration rows), this always
    /// writes the real `funding_account_id` column, present on both
    /// native schemas from day one.
    public func setFundingAccountId(id: String, accountId: String?) async throws {
        let ts = nowIso()
        try await db.execute(sql: "UPDATE loans SET funding_account_id = ?, updated_at = ? WHERE id = ?", parameters: [accountId, ts, id])
    }
}
