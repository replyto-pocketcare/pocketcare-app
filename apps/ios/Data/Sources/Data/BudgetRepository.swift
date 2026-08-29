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
    public let alertTimeUtc: String?

    public init(id: String, name: String?, period: String, startDate: String?, endDate: String?, limitAmount: Int64, currency: String, thresholdPct: Int, alertTimeUtc: String? = nil) {
        self.id = id
        self.name = name
        self.period = period
        self.startDate = startDate
        self.endDate = endDate
        self.limitAmount = limitAmount
        self.currency = currency
        self.thresholdPct = thresholdPct
        self.alertTimeUtc = alertTimeUtc
    }
}

/// ISO instant string at UTC midnight of [date] -- matches JS's
/// `new Date(...).toISOString()` format (always millisecond-precision),
/// which is what the real spec compares occurred_at against.
private func isoMidnight(_ date: Ymd) -> String {
    "\(date.description)T00:00:00.000Z"
}

/**
 One expense counted against a budget, joined for display -- web's `BudgetTxn`
 (packages/data/src/index.ts).
 */
public struct BudgetTxn: Sendable, Identifiable, Equatable {
    public let id: String
    public let occurredAt: String
    public let amount: Int64
    public let currency: String
    public let description: String?
    public let note: String?
    public let categoryName: String?
    public let accountName: String?

    public init(id: String, occurredAt: String, amount: Int64, currency: String, description: String?, note: String?, categoryName: String?, accountName: String?) {
        self.id = id
        self.occurredAt = occurredAt
        self.amount = amount
        self.currency = currency
        self.description = description
        self.note = note
        self.categoryName = categoryName
        self.accountName = accountName
    }
}

/// Per-day expense totals for a budget's window, plus the window itself.
public struct DailySpend: Sendable, Equatable {
    /// `YYYY-MM-DD` to minor units. Days with no spend are absent.
    public let totals: [String: Int64]
    public let startIso: String
    /// INCLUSIVE last day of the window.
    public let endIso: String

    public init(totals: [String: Int64], startIso: String, endIso: String) {
        self.totals = totals
        self.startIso = startIso
        self.endIso = endIso
    }
}

/// The shared WHERE clause plus its bound parameters and the window it covers.
/// `whereClause`, not `where`: the latter is a Swift keyword and would need
/// backticks at every use site.
private struct ScopedQuery {
    let whereClause: String
    let params: [Sendable?]
    let startIso: String
    let endIso: String
}

/**
 SQL predicate excluding money you FRONTED for other people from your own
 spending -- web's `notFrontedForOthers("t")`, verbatim.

 A file-scope constant rather than three copies inline: the whole point of web's
 version is that the same string backs every aggregate, so they cannot drift
 apart -- which is precisely how a budget total and its drill-down would come to
 disagree.
 */
private let notFrontedForOthers =
    "t.id NOT IN (SELECT transaction_id FROM expense_postings "
    + "WHERE role = 'lend' AND transaction_id IS NOT NULL AND deleted_at IS NULL)"

/// One day BEFORE `ymd`, carrying month/year -- the mirror of `nextDay`, needed
/// to turn an exclusive window end back into the inclusive last day a chart
/// axis draws.
private func previousDay(_ ymd: Ymd) -> Ymd {
    if ymd.day > 1 {
        return Ymd(year: ymd.year, month: ymd.month, day: ymd.day - 1)
    }
    if ymd.month > 1 {
        return Ymd(year: ymd.year, month: ymd.month - 1, day: daysInMonth(ymd.year, ymd.month - 1))
    }
    return Ymd(year: ymd.year - 1, month: 12, day: 31)
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

    private func budgetMapper(_ cursor: SqlCursor) throws -> BudgetLike {
        BudgetLike(
            id: try cursor.getString(name: "id"),
            name: try cursor.getStringOptional(name: "name"),
            period: try cursor.getString(name: "period"),
            startDate: try cursor.getStringOptional(name: "start_date"),
            endDate: try cursor.getStringOptional(name: "end_date"),
            limitAmount: try cursor.getInt64(name: "limit_amount"),
            currency: try cursor.getString(name: "currency"),
            thresholdPct: Int(try cursor.getInt64(name: "threshold_pct")),
            alertTimeUtc: try cursor.getStringOptional(name: "alert_time_utc")
        )
    }

    public func list() async throws -> [BudgetLike] {
        try await db.getAll(
            sql: """
                SELECT id, name, period, start_date, end_date, limit_amount, currency, threshold_pct, alert_time_utc
                FROM budgets WHERE deleted_at IS NULL ORDER BY created_at DESC
                """,
            parameters: []
        ) { cursor in try self.budgetMapper(cursor) }
    }

    /// Live version of [list] -- re-emits on any local write to `budgets`,
    /// regardless of which repository/ViewModel instance performed it.
    /// Added 2026-08-06 to fix a list-staleness bug: the list screen used
    /// to only refresh via an explicit `reload()` call from `.onAppear`,
    /// which doesn't reliably re-fire across a `.sheet(...)` presentation/
    /// dismissal in SwiftUI -- see AUDIT_HISTORY.md's 2026-08-06 entry.
    public func watchBudgets() throws -> AsyncThrowingStream<[BudgetLike], Error> {
        try db.watch(
            sql: """
                SELECT id, name, period, start_date, end_date, limit_amount, currency, threshold_pct, alert_time_utc
                FROM budgets WHERE deleted_at IS NULL ORDER BY created_at DESC
                """,
            parameters: [],
            mapper: budgetMapper
        )
    }

    // ---- writes ----
    // Matches apps/web/app/budgets/page.tsx's addBudget()/saveEdit()/
    // writeBudgetScope()/resolveLabelIds() exactly: budgets rows use the
    // create/update/soft-delete shape established by LedgerRepository's
    // createAccount()/updateAccount()/deleteAccount() (explicit raw SQL,
    // newId()/nowIso(), userId passed in by the caller -- no repository here
    // holds its own AuthRepository reference, matching every other
    // repository in this package); the category/label scope is a
    // delete-then-reinsert of both junction tables per write, same as web
    // (PowerSync's incremental per-row upload queue means this can't be a
    // single cross-table constraint -- CLAUDE.md golden rule: "never write a
    // cross-row constraint on a synced table").

    /// Creates a budget row. [startDate]/[endDate] are both non-nil for a
    /// custom-dated budget, both nil for a recurring one -- matches web's
    /// `timeMode === "custom" ? start || null : null` exactly (never a mix).
    @discardableResult
    public func create(
        userId: String,
        name: String?,
        period: String,
        startDate: String?,
        endDate: String?,
        limitAmount: Int64,
        currency: String,
        thresholdPct: Int,
        alertTimeUtc: String
    ) async throws -> String {
        let id = newId()
        let ts = nowIso()
        try await db.execute(
            sql: """
                INSERT INTO budgets
                (id,user_id,name,period,start_date,end_date,limit_amount,currency,threshold_pct,alert_time_utc,rollover,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
            parameters: [id, userId, name, period, startDate, endDate, limitAmount, currency, thresholdPct, alertTimeUtc, 0, ts, ts]
        )
        return id
    }

    /// Updates a budget's editable fields. Matches web's saveEdit(): name,
    /// limit_amount, period, threshold_pct, alert_time_utc only -- currency,
    /// start_date/end_date are NOT editable after creation (web's edit form
    /// has no currency picker; the period chips are hidden entirely for a
    /// custom-dated budget, per dashboard.md's port notes -- callers must
    /// not pass a changed [period] for a custom-dated budget).
    public func update(
        id: String,
        name: String?,
        limitAmount: Int64,
        period: String,
        thresholdPct: Int,
        alertTimeUtc: String
    ) async throws {
        let ts = nowIso()
        try await db.execute(
            sql: """
                UPDATE budgets SET name = ?, limit_amount = ?, period = ?, threshold_pct = ?, alert_time_utc = ?, updated_at = ?
                WHERE id = ?
                """,
            parameters: [name, limitAmount, period, thresholdPct, alertTimeUtc, ts, id]
        )
    }

    public func delete(id: String) async throws {
        try await softDelete(db: db, table: "budgets", id: id)
    }

    /// All (budget_id, category_id) pairs across every budget, reactive --
    /// added 2026-08-06 for Insights' budgets aggregation (task #28), which
    /// needs every budget's scoped categories up front rather than one
    /// categoryIds(id) call per budget. Mirrors Android's
    /// BudgetRepository.kt watchBudgetCategories() added the same session.
    public func watchBudgetCategories() throws -> AsyncThrowingStream<[(budgetId: String, categoryId: String)], Error> {
        try db.watch(
            sql: "SELECT budget_id, category_id FROM budget_categories",
            parameters: []
        ) { cursor in
            (budgetId: try cursor.getString(name: "budget_id"), categoryId: try cursor.getString(name: "category_id"))
        }
    }

    public func categoryIds(budgetId: String) async throws -> [String] {
        try await db.getAll(
            sql: "SELECT category_id FROM budget_categories WHERE budget_id = ?",
            parameters: [budgetId]
        ) { cursor in try cursor.getString(name: "category_id") }
    }

    public func labelNames(budgetId: String) async throws -> [String] {
        try await db.getAll(
            sql: "SELECT l.name AS name FROM budget_labels bl JOIN labels l ON l.id = bl.label_id WHERE bl.budget_id = ?",
            parameters: [budgetId]
        ) { cursor in try cursor.getString(name: "name") }
    }

    /// Rewrites a budget's category/label scope via the junction tables --
    /// delete-then-reinsert, matching web's writeBudgetScope() exactly.
    /// [labelNames] are find-or-created by name (case-insensitive dedupe),
    /// matching web's resolveLabelIds().
    public func writeScope(userId: String, budgetId: String, categoryIds: [String], labelNames: [String]) async throws {
        try await db.execute(sql: "DELETE FROM budget_categories WHERE budget_id = ?", parameters: [budgetId])
        try await db.execute(sql: "DELETE FROM budget_labels WHERE budget_id = ?", parameters: [budgetId])
        for cid in Set(categoryIds) {
            try await db.execute(
                sql: "INSERT INTO budget_categories (id,user_id,budget_id,category_id) VALUES (?,?,?,?)",
                parameters: [newId(), userId, budgetId, cid]
            )
        }
        let labelIds = try await resolveLabelIds(userId: userId, names: labelNames)
        for lid in labelIds {
            try await db.execute(
                sql: "INSERT INTO budget_labels (id,user_id,budget_id,label_id) VALUES (?,?,?,?)",
                parameters: [newId(), userId, budgetId, lid]
            )
        }
    }

    /// Find-or-create label rows by name, returning their ids -- matches
    /// web's resolveLabelIds() exactly (case-insensitive dedupe within the
    /// call, trims whitespace, skips blanks).
    private func resolveLabelIds(userId: String, names: [String]) async throws -> [String] {
        var ids: [String] = []
        var seen: Set<String> = []
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seen.contains(name.lowercased()) else { continue }
            seen.insert(name.lowercased())
            if let found = try await db.getOptional(
                sql: "SELECT id FROM labels WHERE user_id = ? AND name = ? AND deleted_at IS NULL",
                parameters: [userId, name]
            ) { cursor in try cursor.getString(name: "id") } {
                ids.append(found)
            } else {
                let id = newId()
                let ts = nowIso()
                try await db.execute(
                    sql: "INSERT INTO labels (id,user_id,name,color,created_at,updated_at) VALUES (?,?,?,?,?,?)",
                    parameters: [id, userId, name, nil, ts, ts]
                )
                ids.append(id)
            }
        }
        return ids
    }

    /**
     The WHERE clause every "what counts against this budget" read shares.

     Mirrors packages/data/src/powersync-repositories.ts's private
     `scopeClause` exactly, and exists for the reason its own comment gives: a
     second hand-written query for the drill-down list or the chart would be a
     standing invitation for the two to disagree, and a list that does not add
     up to the figure above it is worse than no list at all -- it makes the user
     doubt the number rather than the screen.

     `asOf` is a UTC calendar day (already truncated by the caller, matching
     this port's established periodBounds() convention).
     */
    private func scopeClause(budget: BudgetLike, asOf: Ymd) async throws -> ScopedQuery {
        let start: Ymd
        let endExclusive: Ymd
        let endInclusive: Ymd
        if let s = budget.startDate, let e = budget.endDate {
            start = parseYmd(s)
            endInclusive = parseYmd(e)
            // Make end inclusive of the whole end day.
            endExclusive = nextDay(endInclusive)
        } else {
            let window = periodBounds(budget.period, asOf)
            start = window.start
            endExclusive = window.endExclusive
            // INCLUSIVE, for the chart's axis: the query boundary is exclusive
            // because SQLite compares timestamps, but a chart draws days.
            endInclusive = previousDay(window.endExclusive)
        }

        var whereClauses = [
            "t.type = 'expense'",
            "t.deleted_at IS NULL",
            // Money FRONTED for other people is not your spending. A split
            // books the part you covered for others as an ordinary expense on
            // your account, which is right for the ledger and wrong for every
            // "what did I spend" aggregate -- buying a friend a phone on your
            // card would blow the month's budget. Web excludes it here
            // (packages/data's `notFrontedForOthers`); this port did not, so
            // the same budget read differently in the browser and on the phone.
            // Same SQL LedgerRepository's own expense aggregates use.
            notFrontedForOthers,
            "t.occurred_at >= ?",
            "t.occurred_at < ?",
            "t.currency = ?",
        ]
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
        // No categories/labels selected -> overall (all expenses in the window).
        if !ors.isEmpty { whereClauses.append("(\(ors.joined(separator: " OR ")))") }

        return ScopedQuery(
            whereClause: whereClauses.joined(separator: " AND "),
            params: params,
            startIso: start.description,
            endIso: endInclusive.description
        )
    }

    /// Sum of expenses in the budget's window, honoring its category/label
    /// scope. `asOf` defaults to today at UTC, matching Android's
    /// `asOf: LocalDate = LocalDate.now(ZoneOffset.UTC)`. Before that default
    /// existed every caller passed its own idea of "today", and one of them
    /// was a `private` helper inside a view model.
    public func spentThisPeriod(budget: BudgetLike, asOf: Ymd = todayYmd()) async throws -> Money {
        let scope = try await scopeClause(budget: budget, asOf: asOf)
        let total: Int64 = try await db.getOptional(
            sql: "SELECT COALESCE(SUM(t.amount), 0) AS total FROM transactions t WHERE \(scope.whereClause)",
            parameters: scope.params
        ) { cursor in try cursor.getInt64(name: "total") } ?? 0
        return money(total, budget.currency)
    }

    /**
     The individual expenses behind `spentThisPeriod`, newest first -- same
     scope, same window, so the rows always sum to the total.

     Mirrors web's `transactionsThisPeriod`, which backs apps/web/src/budgets/
     SpentBreakdown.tsx. Added here 2026-08-29: tapping the "spent" figure
     opened nothing on either native app.
     */
    public func transactionsThisPeriod(budget: BudgetLike, asOf: Ymd = todayYmd()) async throws -> [BudgetTxn] {
        let scope = try await scopeClause(budget: budget, asOf: asOf)
        return try await db.getAll(
            sql: """
                SELECT t.id AS id, t.occurred_at AS occurred_at, t.amount AS amount, t.currency AS currency,
                       t.description AS description, t.note AS note,
                       c.name AS category_name, a.name AS account_name
                  FROM transactions t
                  LEFT JOIN categories c ON c.id = t.category_id
                  LEFT JOIN accounts a ON a.id = t.account_id
                 WHERE \(scope.whereClause)
                 ORDER BY t.occurred_at DESC, t.created_at DESC
                """,
            parameters: scope.params
        ) { cursor in
            BudgetTxn(
                id: try cursor.getString(name: "id"),
                occurredAt: try cursor.getString(name: "occurred_at"),
                amount: try cursor.getInt64(name: "amount"),
                currency: try cursor.getString(name: "currency"),
                description: try cursor.getStringOptional(name: "description"),
                note: try cursor.getStringOptional(name: "note"),
                categoryName: try cursor.getStringOptional(name: "category_name"),
                accountName: try cursor.getStringOptional(name: "account_name")
            )
        }
    }

    /**
     Per-day totals for the budget's window, keyed `YYYY-MM-DD` -- the input to
     Domain's `cumulativeSpendSeries`, which draws the spend-vs-limit curve.

     Deliberately the SAME scope clause as `spentThisPeriod`, where web's own
     chart runs a looser hand-written query of its own (no currency filter, no
     fronted-for-others exclusion, scope re-implemented in JS over the rows).
     Web's chart can therefore finish above the "spent" figure printed directly
     beneath it. That is a defect, not a design, and reproducing it would mean
     shipping a chart that visibly contradicts its own card.

     Also returns the window it used, so the caller never has to re-derive the
     axis from a second copy of the period arithmetic.
     */
    public func dailySpendThisPeriod(budget: BudgetLike, asOf: Ymd = todayYmd()) async throws -> DailySpend {
        let scope = try await scopeClause(budget: budget, asOf: asOf)
        let rows = try await db.getAll(
            sql: """
                SELECT date(t.occurred_at) AS d, COALESCE(SUM(t.amount), 0) AS total
                  FROM transactions t
                 WHERE \(scope.whereClause)
                 GROUP BY date(t.occurred_at)
                """,
            parameters: scope.params
        ) { cursor in
            (day: try cursor.getString(name: "d"), total: try cursor.getInt64(name: "total"))
        }
        var totals: [String: Int64] = [:]
        for row in rows { totals[row.day] = row.total }
        return DailySpend(totals: totals, startIso: scope.startIso, endIso: scope.endIso)
    }
}
