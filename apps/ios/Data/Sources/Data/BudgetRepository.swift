import Foundation
import PowerSync
import Domain

// Read facade over budgets (P2.5). Mirrors
// packages/data/src/powersync-repositories.ts's PowerSyncBudgetRepository
// exactly. Mirrors apps/android/data/.../repository/BudgetRepository.kt.
//
// Table columns confirmed against PocketCareSchema.swift (budgets,
// budget_categories, budget_labels) and supabase/migrations/0001_init.sql.

public struct BudgetLike: Sendable {
    public let id: String
    public let name: String?
    public let period: String
    public let startDate: String?
    public let endDate: String?
    public let limitAmount: Int64
    public let currency: String
    public let thresholdPct: Int

    public init(id: String, name: String?, period: String, startDate: String?, endDate: String?, limitAmount: Int64, currency: String, thresholdPct: Int) {
        self.id = id
        self.name = name
        self.period = period
        self.startDate = startDate
        self.endDate = endDate
        self.limitAmount = limitAmount
        self.currency = currency
        self.thresholdPct = thresholdPct
    }
}

/// ISO instant string at UTC midnight of [date] -- matches JS's
/// `new Date(...).toISOString()` format (always millisecond-precision),
/// which is what the real spec compares occurred_at against.
private func isoMidnight(_ date: Ymd) -> String {
    "\(date.description)T00:00:00.000Z"
}

/// Parse a "yyyy-MM-dd" string (as stored in the start_date/end_date
/// columns) into a Ymd. Pure integer parsing, no Foundation Calendar/Date --
/// same rationale as Domain's Budget.swift (Calendar's `date(byAdding:)` has
/// real reports of silently reverting to the device's local time zone unless
/// airtight about UTC).
private func parseYmd(_ s: String) -> Ymd {
    let parts = s.split(separator: "-")
    return Ymd(year: Int(parts[0]) ?? 1970, month: Int(parts[1]) ?? 1, day: Int(parts[2]) ?? 1)
}

private func isLeapYear(_ y: Int) -> Bool {
    (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

private func daysInMonth(_ y: Int, _ m: Int) -> Int {
    switch m {
    case 1, 3, 5, 7, 8, 10, 12: return 31
    case 4, 6, 9, 11: return 30
    case 2: return isLeapYear(y) ? 29 : 28
    default: return 30
    }
}

/// Add exactly one day to a Ymd, carrying month/year -- this repository only
/// ever needs "+1 day" (to make an inclusive end_date exclusive), so a full
/// general-purpose day-adder (like Domain's private addDaysYmd, which isn't
/// visible across the module boundary anyway) isn't needed.
private func nextDay(_ ymd: Ymd) -> Ymd {
    if ymd.day < daysInMonth(ymd.year, ymd.month) {
        return Ymd(year: ymd.year, month: ymd.month, day: ymd.day + 1)
    }
    if ymd.month < 12 {
        return Ymd(year: ymd.year, month: ymd.month + 1, day: 1)
    }
    return Ymd(year: ymd.year + 1, month: 1, day: 1)
}

public final class BudgetRepository: @unchecked Sendable {
    private let db: PowerSyncDatabaseProtocol

    public init(db: PowerSyncDatabaseProtocol) {
        self.db = db
    }

    public func list() async throws -> [BudgetLike] {
        try await db.getAll(
            sql: "SELECT id, name, period, start_date, end_date, limit_amount, currency, threshold_pct FROM budgets WHERE deleted_at IS NULL",
            parameters: []
        ) { cursor in
            BudgetLike(
                id: try cursor.getString(name: "id"),
                name: try cursor.getStringOptional(name: "name"),
                period: try cursor.getString(name: "period"),
                startDate: try cursor.getStringOptional(name: "start_date"),
                endDate: try cursor.getStringOptional(name: "end_date"),
                limitAmount: try cursor.getInt64(name: "limit_amount"),
                currency: try cursor.getString(name: "currency"),
                thresholdPct: Int(try cursor.getInt64(name: "threshold_pct"))
            )
        }
    }

    /// Sum of expenses in the budget's window, honoring its category/label
    /// scope. [asOf] is a UTC calendar day (already truncated by the
    /// caller, matching this port's established periodBounds() convention).
    public func spentThisPeriod(budget: BudgetLike, asOf: Ymd) async throws -> Money {
        let start: Ymd
        let endExclusive: Ymd
        if let s = budget.startDate, let e = budget.endDate {
            start = parseYmd(s)
            // Make end inclusive of the whole end day.
            endExclusive = nextDay(parseYmd(e))
        } else {
            let window = periodBounds(budget.period, asOf)
            start = window.start
            endExclusive = window.endExclusive
        }

        var whereClauses = ["t.type = 'expense'", "t.deleted_at IS NULL", "t.occurred_at >= ?", "t.occurred_at < ?", "t.currency = ?"]
        var params: [Sendable?] = [isoMidnight(start), isoMidnight(endExclusive), budget.currency]

        let catIds = try await db.getAll(sql: "SELECT category_id FROM budget_categories WHERE budget_id = ?", parameters: [budget.id]) { cursor in
            try cursor.getString(name: "category_id")
        }
        let labelIds = try await db.getAll(sql: "SELECT label_id FROM budget_labels WHERE budget_id = ?", parameters: [budget.id]) { cursor in
            try cursor.getString(name: "label_id")
        }

        var ors: [String] = []
        if !catIds.isEmpty {
            ors.append("t.category_id IN (\(catIds.map { _ in "?" }.joined(separator: ",")))")
            params.append(contentsOf: catIds)
        }
        if !labelIds.isEmpty {
            ors.append("EXISTS (SELECT 1 FROM transaction_labels tl WHERE tl.transaction_id = t.id AND tl.label_id IN (\(labelIds.map { _ in "?" }.joined(separator: ","))))")
            params.append(contentsOf: labelIds)
        }
        if !ors.isEmpty { whereClauses.append("(\(ors.joined(separator: " OR ")))") }

        let total: Int64 = try await db.getOptional(
            sql: "SELECT COALESCE(SUM(t.amount), 0) AS total FROM transactions t WHERE \(whereClauses.joined(separator: " AND "))",
            parameters: params
        ) { cursor in try cursor.getInt64(name: "total") } ?? 0
        return money(total, budget.currency)
    }
}
