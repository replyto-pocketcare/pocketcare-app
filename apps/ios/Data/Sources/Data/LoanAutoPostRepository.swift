import Foundation
import Domain
import PowerSync

/// Charge due EMIs to the account they are linked to — the port of
/// apps/web/src/loans/autoPost.ts. Mirrors
/// apps/android/data/.../repository/LoanAutoPostRepository.kt.
///
/// A loan can name the account its EMI is charged to, usually a credit card
/// (`loans.funding_account_id`). When an EMI's due date passes, this posts it
/// as an expense on that account, exactly as a bank adds the instalment to your
/// statement. That is what makes the EMI appear in the card's total due.
///
/// ## CHARGED and PAID are different, and this only does the first
///
/// - **charged** — the instalment is on the card. This file, on the due date.
/// - **paid** — you settled it. That happens when the card bill is settled, or
///   by hand in the EMI dialog.
///
/// `auto_mark_paid` therefore does **not** gate this. An EMI is owed whether or
/// not you have told the app you paid it.
///
/// ## Never post an EMI twice
///
/// - Dedupe is a lookup in the **synced ledger** for a transaction with exactly
///   `emiDescription`'s output on that account — not a local flag — so a second
///   device running the same catch-up finds the first device's row and skips.
///   That is why `emiDescription` is a shared function and not a literal.
/// - An actor-isolated flag stops two concurrent runs inside one process.
/// - Only EMIs whose due date has actually passed are considered, and each is
///   posted **at its own due date** so it lands in the right billing cycle.
/// - Manually-marked EMIs are skipped: that dialog already made the posting
///   decision (the user picked an account there, or chose not to record).
public actor LoanAutoPostRepository {
    private let db: PowerSyncDatabaseProtocol
    private let ledger: LedgerRepository

    /// Catching up more than a year of missed EMIs at once is a bug, not a feature.
    private static let maxPerLoan = 12

    /// Web uses a module-level `let running = false`, which is safe there only
    /// because the browser is single-threaded and the check and set cannot
    /// interleave. Two Swift tasks genuinely can, and the failure mode is the
    /// one thing this file exists to prevent: two runs racing past the same
    /// dedupe lookup before either has written its row. `actor` isolation makes
    /// the check-and-set atomic without a lock.
    private var isRunning = false

    public init(db: PowerSyncDatabaseProtocol, ledger: LedgerRepository) {
        self.db = db
        self.ledger = ledger
    }

    private struct LoanRow: Sendable {
        let id: String
        let lender: String?
        let currency: String?
        let emiAmount: Int64?
        let tenureMonths: Int?
        let startDate: String?
        let emiPayments: String?
        let emiAmounts: String?
        let emiDueDay: Int?
        let fundingAccountId: String?
    }

    private func parseMap(_ raw: String?) -> [String: Any]? {
        guard let raw, !raw.isEmpty, let data = raw.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// - Parameter asOfIso: today, as YYYY-MM-DD. A parameter rather than a
    ///   clock read for the same reason `Finance.swift` takes one: a function
    ///   that reads the clock cannot be tested against a fixed date.
    /// - Returns: how many EMIs were charged.
    @discardableResult
    public func run(userId: String, asOfIso: String) async throws -> Int {
        // Return immediately if a run is in flight, the way web's
        // `if (running) return 0` does -- NOT queue up and run the whole
        // catch-up again straight after.
        if isRunning { return 0 }
        isRunning = true
        defer { isRunning = false }

        let loans: [LoanRow] = try await db.getAll(
            // NOT gated on auto_mark_paid. A loan linked to an account posts its
            // EMI when the EMI falls due; that is what makes the charge appear
            // in the card's total due, which is the point of linking.
            sql: """
                SELECT id, lender, currency, emi_amount, tenure_months, start_date,
                       emi_payments, emi_amounts, emi_due_day, funding_account_id
                  FROM loans
                 WHERE deleted_at IS NULL AND funding_account_id IS NOT NULL
                """,
            parameters: [],
            mapper: { cursor in
                LoanRow(
                    id: try cursor.getString(name: "id"),
                    lender: try cursor.getStringOptional(name: "lender"),
                    currency: try cursor.getStringOptional(name: "currency"),
                    emiAmount: try cursor.getInt64Optional(name: "emi_amount"),
                    tenureMonths: (try cursor.getInt64Optional(name: "tenure_months")).map(Int.init),
                    startDate: try cursor.getStringOptional(name: "start_date"),
                    emiPayments: try cursor.getStringOptional(name: "emi_payments"),
                    emiAmounts: try cursor.getStringOptional(name: "emi_amounts"),
                    emiDueDay: (try cursor.getInt64Optional(name: "emi_due_day")).map(Int.init),
                    fundingAccountId: try cursor.getStringOptional(name: "funding_account_id")
                )
            }
        )

        var posted = 0
        for loan in loans {
            // Web falls back to a localStorage map for loans created before
            // migration 0047 added the column. There is no native equivalent and
            // there should not be one -- the column is the record, and a
            // per-device memory of it would post different EMIs on different
            // phones.
            guard let accountId = loan.fundingAccountId else { continue }

            // The account may have been deleted or archived since.
            let account: String? = try await db.getOptional(
                sql: "SELECT id FROM accounts WHERE id = ? AND deleted_at IS NULL AND IFNULL(is_archived, 0) = 0",
                parameters: [accountId],
                mapper: { cursor in try cursor.getString(name: "id") }
            )
            guard let account else { continue }

            let total = loan.tenureMonths ?? 0
            if total <= 0 { continue }

            let manualMap = parseMap(loan.emiPayments)
            let manual = manualMap?.keys.compactMap { Int($0) } ?? []

            // Every EMI whose due date has passed is CHARGED, regardless of
            // auto_mark_paid -- hence autoMark: true unconditionally. `manual`
            // is passed in even though every manual EMI is skipped below; web
            // does the same, and the result is identical either way, but
            // diverging from the source on "it makes no difference" grounds is
            // how a port acquires differences nobody can account for later.
            let due = effectivePaidEmis(
                manual: manual,
                totalEmis: total,
                autoMark: true,
                startIso: loan.startDate,
                dueDay: loan.emiDueDay,
                asOfIso: asOfIso
            )

            let manualSet = Set(manual)
            let amounts = parseMap(loan.emiAmounts)
            let currency = loan.currency ?? "INR"

            var done = 0
            for n in due.sorted() {
                if done >= Self.maxPerLoan { break }
                if manualSet.contains(n) { continue }

                let perEmi = (amounts?[String(n)] as? NSNumber)?.doubleValue
                let amountMinor = perEmi ?? loan.emiAmount.map(Double.init) ?? 0
                if !amountMinor.isFinite || amountMinor <= 0 { continue }

                let description = emiDescription(n, loan.lender)
                let existing: String? = try await db.getOptional(
                    sql: """
                        SELECT id FROM transactions
                         WHERE description = ? AND account_id = ? AND deleted_at IS NULL
                         LIMIT 1
                        """,
                    parameters: [description, account],
                    mapper: { cursor in try cursor.getString(name: "id") }
                )
                if existing != nil { continue }

                guard let dueDate = emiDueDate(loan.startDate, loan.emiDueDay, n) else { continue }
                do {
                    _ = try await ledger.createTransaction(
                        userId: userId,
                        accountId: account,
                        type: "expense",
                        amount: money(Int64(amountMinor.rounded()), currency),
                        // Noon UTC. Web builds this as `new Date("\(dueDate)T12:00:00")`,
                        // i.e. noon LOCAL, which lands on a different UTC instant
                        // per device -- two phones in different zones would stamp
                        // the same EMI differently. Noon UTC is what web's own
                        // recurring engine uses (`dueIso`), and it is stable
                        // everywhere. It also keeps the EMI in the right month
                        // and the right billing cycle.
                        occurredAt: "\(dueDate)T12:00:00.000Z",
                        description: description
                    )
                    posted += 1
                    done += 1
                } catch {
                    // e.g. an overdraft guard refusing the write. Leave it
                    // unposted and move to the next loan rather than stalling
                    // every other one.
                    break
                }
            }
        }
        return posted
    }
}
