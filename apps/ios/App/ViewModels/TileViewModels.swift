import Foundation
import Observation
import Factory
import Domain
import Data

/**
 One view model per tile, not one for the dashboard.

 Web does the same — every tile in `tiles.tsx` runs its own `useQuery` — and it
 is what lets the catalog hold fourteen tiles cheaply: a tile the user has not
 enabled is never built, so its query never runs.

 Mirrors `apps/android/.../ui/dashboard/TileViewModels.kt`.
 */

/* ------------------------------ Recent ------------------------------ */

@Observable
@MainActor
final class RecentTileViewModel {
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository

    public private(set) var rows: [TransactionListItem] = []

    private var task: Task<Void, Never>?
    private var accountMap: [String: Account] = [:]
    private var categoryMap: [String: CategoryRow] = [:]
    private var labelNames: [String: [String]] = [:]
    private var latest: [TransactionRow] = []

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.watchTransactions() }
                group.addTask { await self.watchAccounts() }
                group.addTask { await self.watchCategories() }
                group.addTask { await self.watchLabels() }
            }
        }
    }

    private func watchTransactions() async {
        do {
            for try await rows in try ledgerRepository.watchRecentTransactions(limit: 24) {
                latest = rows
                rebuild()
            }
        } catch {}
    }

    private func watchAccounts() async {
        do {
            for try await rows in try ledgerRepository.watchAccounts(includeArchived: true) {
                accountMap = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
                rebuild()
            }
        } catch {}
    }

    private func watchCategories() async {
        do {
            for try await rows in try ledgerRepository.watchCategories() {
                categoryMap = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
                rebuild()
            }
        } catch {}
    }

    private func watchLabels() async {
        do {
            for try await map in try ledgerRepository.watchTransactionLabelNames() {
                labelNames = map
                rebuild()
            }
        } catch {}
    }

    /// Web reads 24 rows, collapses split siblings, then shows however many fit
    /// the tile — capped at 10. Native rows size to their content rather than
    /// being clipped to a measured height, so there is nothing to fit to: the
    /// cap IS the count. Ten was already web's ceiling and what a phone showed.
    private func rebuild() {
        rows = latest
            // Web filters `type != 'opening_balance'` in the query itself. An
            // opening balance is bookkeeping, not activity, and showing it as
            // the most recent thing you did is how a new account looks like a
            // deposit you do not remember making.
            .filter { $0.type != "opening_balance" }
            .prefix(10)
            .map {
                transactionListItem(
                    $0,
                    accountMap: accountMap,
                    categoryMap: categoryMap,
                    labels: labelNames[$0.id]
                )
            }
    }
}

/* ----------------------------- Spending ----------------------------- */

/// One category's share of this month's spending.
struct SpendSlice: Identifiable, Sendable {
    let id: String
    /// Nil for the uncategorised bucket — the VIEW names it, because i18n
    /// belongs where the string is rendered.
    let name: String?
    let totalMinor: Int64
    /// Share of the month's total, 0–100.
    let sharePct: Int
    /// Share of the LARGEST category, 0–100 — the bar's fill.
    let fillPct: Int
}

@Observable
@MainActor
final class SpendingTileViewModel {
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository

    public private(set) var totalMinor: Int64 = 0
    public private(set) var slices: [SpendSlice] = []
    public private(set) var hiddenCount = 0

    private var task: Task<Void, Never>?

    /// Web's `new Date(y, m, 1).toISOString()` — the first instant of this month.
    private var monthStartIso: String {
        let now = Date()
        var components = Calendar.current.dateComponents([.year, .month], from: now)
        components.day = 1
        let start = Calendar.current.date(from: components) ?? now
        return ISO8601DateFormatter().string(from: start)
    }

    /**
     Grouped in SQL now, not in Swift.

     It used to read every transaction of the month and group them here, which
     meant there was no subquery to hang web's `lend` exclusion on — so this
     tile, alone on the dashboard, counted money you had fronted for someone as
     your own spending. Moving the grouping into the query fixes the number and
     drops the in-memory pass at the same time.
     */
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try self.ledgerRepository.watchExpenseByCategorySince(self.monthStartIso) {
                    self.rebuild(rows)
                }
            } catch {}
        }
    }

    private func rebuild(_ rows: [NamedTotal]) {
        let total = rows.reduce(Int64(0)) { $0 + $1.total }
        let largest = rows.first?.total ?? 0
        // Web charts the top 7 and links the rest to Insights.
        let top = rows.prefix(7)

        totalMinor = total
        hiddenCount = max(0, rows.count - top.count)
        slices = top.enumerated().map { index, row in
            SpendSlice(
                id: row.name ?? "uncategorised-\(index)",
                name: (row.name?.isEmpty == false) ? row.name : nil,
                totalMinor: row.total,
                sharePct: total > 0 ? Int((row.total * 100) / total) : 0,
                // Web floors the fill at 3% so a tiny category still draws
                // something — a zero-width bar reads as a rendering bug.
                fillPct: largest > 0 ? max(3, Int((row.total * 100) / largest)) : 0
            )
        }
    }
}

/* ----------------------------- Upcoming ----------------------------- */

struct UpcomingRow: Identifiable, Sendable {
    let id: String
    let name: String
    let dueIso: String
    let amountMinor: Int64?
    let currency: String?
}

@Observable
@MainActor
final class UpcomingTileViewModel {
    @ObservationIgnored
    @Injected(\.recurringRepository) private var recurringRepository

    public private(set) var rows: [UpcomingRow] = []

    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await items in try self.recurringRepository.watchActiveItems() {
                    self.rows = items
                        // Savings are excluded here for the same reason they
                        // are excluded from the Recurring screen's totals: a
                        // SIP is a transfer between your own accounts, so
                        // listing it as an upcoming payment overstates what is
                        // leaving.
                        .filter { $0.direction != "saving" }
                        .sorted { $0.nextDue < $1.nextDue }
                        .prefix(5)
                        .map { UpcomingRow(id: $0.id, name: $0.name, dueIso: $0.nextDue, amountMinor: $0.amount, currency: $0.currency) }
                }
            } catch {}
        }
    }
}

/* ------------------------------ Budgets ----------------------------- */

struct BudgetMini: Identifiable, Sendable {
    let id: String
    let label: String
    let spentMinor: Int64
    let limitMinor: Int64
    let currency: String
    let pct: Double
    let overLimit: Bool
    let atOrOverThreshold: Bool
}

@Observable
@MainActor
final class BudgetsTileViewModel {
    @ObservationIgnored
    @Injected(\.budgetRepository) private var budgetRepository

    public private(set) var rows: [BudgetMini] = []

    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await budgets in try self.budgetRepository.watchBudgets() {
                    // Web takes six and shows however many fit; native rows
                    // size to their content, so six IS the count.
                    var built: [BudgetMini] = []
                    for budget in budgets.prefix(6) {
                        // spentThisPeriod is an async call per budget — the
                        // same N+1 web does in BudgetMini's useEffect. Six
                        // rows, and the alternative is a bespoke aggregate
                        // query that would then have to agree with the
                        // repository's own period maths.
                        let spent = (try? await self.budgetRepository.spentThisPeriod(budget: budget))
                            ?? Money(amount: 0, currency: budget.currency)
                        let limit = Money(amount: budget.limitAmount, currency: budget.currency)
                        guard let progress = try? budgetProgress(limit, spent, Double(budget.thresholdPct)) else { continue }
                        built.append(BudgetMini(
                            id: budget.id,
                            label: (budget.name?.isEmpty == false ? budget.name! : budget.period),
                            spentMinor: spent.amount,
                            limitMinor: limit.amount,
                            currency: budget.currency,
                            // pct is infinite for a zero limit; the bar clamps,
                            // but infinity through a clamp stays infinite, so
                            // it is pinned here instead.
                            pct: progress.pct.isFinite ? progress.pct : 100,
                            overLimit: progress.overLimit,
                            atOrOverThreshold: progress.atOrOverThreshold
                        ))
                    }
                    self.rows = built
                }
            } catch {}
        }
    }
}

/* ------------------------------- Goals ------------------------------ */

struct GoalMini: Identifiable, Sendable {
    let id: String
    let name: String
    let isEmergencyFund: Bool
    let savedMinor: Int64
    let targetMinor: Int64
    let currency: String
    let pct: Double
}

@Observable
@MainActor
final class GoalsTileViewModel {
    @ObservationIgnored
    @Injected(\.goalsRepository) private var goalsRepository
    @ObservationIgnored
    @Injected(\.authRepository) private var authRepository

    public private(set) var rows: [GoalMini] = []

    private var task: Task<Void, Never>?
    private var goals: [Goal] = []
    private var allocations: [GoalAllocation] = []

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            guard let userId = await self.resolveUserId() else { return }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.watchGoals(userId) }
                group.addTask { await self.watchAllocations(userId) }
            }
        }
    }

    private func watchGoals(_ userId: String) async {
        do {
            // `await try`, not `try`: GoalsRepository is an `actor` on iOS
            // (LedgerRepository is a class), so reaching it hops actors.
            // GoalsViewModel already calls it this way.
            for try await rows in try await goalsRepository.watchGoals(userId: userId) {
                goals = rows
                rebuild()
            }
        } catch {}
    }

    private func watchAllocations(_ userId: String) async {
        do {
            for try await rows in try await goalsRepository.watchAllocations(userId: userId) {
                allocations = rows
                rebuild()
            }
        } catch {}
    }

    private func rebuild() {
        var savedByGoal: [String: Int64] = [:]
        for allocation in allocations {
            savedByGoal[allocation.goalId, default: 0] += allocation.amountBlocked
        }
        // Web orders emergency funds first, then by priority, and takes six.
        // The repository already returns that order.
        rows = goals.prefix(6).map { goal in
            let saved = savedByGoal[goal.id] ?? 0
            return GoalMini(
                id: goal.id,
                name: goal.name,
                isEmergencyFund: goal.isEmergencyFund,
                savedMinor: saved,
                targetMinor: goal.targetAmount,
                currency: goal.currency,
                pct: goal.targetAmount > 0
                    ? min(100, (Double(saved) / Double(goal.targetAmount)) * 100)
                    : 0
            )
        }
    }

    /// Spelled out, not `currentUserId ?? (try? await ensureUser())` — `??`'s
    /// right side is an `@autoclosure` and cannot contain an `await`. The
    /// parity job greps for that exact mistake because it has reached CI more
    /// than once; it caught this file too.
    private func resolveUserId() async -> String? {
        if let existing = authRepository.currentUserId { return existing }
        return try? await authRepository.ensureUser()
    }

}

/* ------------------------------ Splits ------------------------------ */

struct FriendBalanceRow: Identifiable, Sendable {
    let id: String
    let name: String
    let netMinor: Int64
}

@Observable
@MainActor
final class SplitsTileViewModel {
    @ObservationIgnored
    @Injected(\.splitsRepository) private var splitsRepository
    @ObservationIgnored
    @Injected(\.authRepository) private var authRepository

    public private(set) var owedMinor: Int64 = 0
    public private(set) var oweMinor: Int64 = 0
    public private(set) var rows: [FriendBalanceRow] = []
    public private(set) var hiddenCount = 0

    private var task: Task<Void, Never>?
    private var balances: [FriendBalance] = []
    private var namesById: [String: String] = [:]

    /// Two watches, both live. `watchFriendBalances` was a one-shot snapshot on
    /// iOS until `combineLatest` existed (Streams.swift, 2026-08-26) — Android
    /// had been reactive here all along.
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            guard let userId = await self.resolveUserId() else { return }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.watchNames(userId) }
                group.addTask { await self.watchBalances(userId) }
            }
        }
    }

    private func watchNames(_ userId: String) async {
        do {
            for try await connections in try splitsRepository.watchConnections(userId: userId) {
                namesById = Dictionary(uniqueKeysWithValues: connections.map { ($0.id, $0.name) })
                rebuild()
            }
        } catch {}
    }

    private func watchBalances(_ userId: String) async {
        do {
            for try await rows in try splitsRepository.watchFriendBalances(userId: userId) {
                balances = rows
                rebuild()
            }
        } catch {}
    }

    private func rebuild() {
        // Ranked by SIZE of the balance, not by sign — web sorts on abs(net),
        // so the person you owe most and the person who owes you most both
        // surface.
        let ranked = balances.filter { $0.net != 0 }.sorted { abs($0.net) > abs($1.net) }
        let top = ranked.prefix(8)

        owedMinor = balances.reduce(Int64(0)) { $0 + max(0, $1.net) }
        oweMinor = balances.reduce(Int64(0)) { $0 + max(0, -$1.net) }
        hiddenCount = max(0, ranked.count - top.count)
        rows = top.map {
            // An empty name rather than an invented "Someone", which would look
            // like a real person you owe money to.
            FriendBalanceRow(id: $0.userId, name: namesById[$0.userId] ?? "", netMinor: $0.net)
        }
    }

    /// Spelled out, not `currentUserId ?? (try? await ensureUser())` — `??`'s
    /// right side is an `@autoclosure` and cannot contain an `await`. The
    /// parity job greps for that exact mistake because it has reached CI more
    /// than once; it caught this file too.
    private func resolveUserId() async -> String? {
        if let existing = authRepository.currentUserId { return existing }
        return try? await authRepository.ensureUser()
    }

}

/* -------------------- By category / by label ------------------- */

/// One horizontal bar. `name` is nil for the uncategorised bucket — the view
/// names it, because i18n belongs where the string is rendered.
struct NamedTotalRow: Identifiable, Sendable {
    let id: String
    let name: String?
    let totalMinor: Int64
}

@Observable
@MainActor
final class ByCategoryTileViewModel {
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository

    public private(set) var rows: [NamedTotalRow] = []
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try self.ledgerRepository.watchExpenseByCategory() {
                    self.rows = rows.enumerated().map {
                        NamedTotalRow(id: $0.element.name ?? "uncategorised-\($0.offset)", name: $0.element.name, totalMinor: $0.element.total)
                    }
                }
            } catch {}
        }
    }
}

@Observable
@MainActor
final class ByLabelTileViewModel {
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository

    public private(set) var rows: [NamedTotalRow] = []
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try self.ledgerRepository.watchExpenseByLabel() {
                    self.rows = rows.enumerated().map {
                        NamedTotalRow(id: $0.element.name ?? "label-\($0.offset)", name: $0.element.name, totalMinor: $0.element.total)
                    }
                }
            } catch {}
        }
    }
}

/* ---------------------- This month vs last --------------------- */

@Observable
@MainActor
final class MonthCompareTileViewModel {
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository

    public private(set) var lastIncomeMinor: Int64 = 0
    public private(set) var lastExpenseMinor: Int64 = 0
    public private(set) var thisIncomeMinor: Int64 = 0
    public private(set) var thisExpenseMinor: Int64 = 0

    var isEmpty: Bool {
        lastIncomeMinor == 0 && lastExpenseMinor == 0 && thisIncomeMinor == 0 && thisExpenseMinor == 0
    }

    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try self.ledgerRepository.watchMonthlyIncomeExpense() {
                    self.apply(rows)
                }
            } catch {}
        }
    }

    private func apply(_ rows: [MonthlyIncomeExpense]) {
        // Local months, matching web's `new Date().getMonth()`. The query groups
        // on strftime('%Y-%m', occurred_at), which SQLite evaluates in UTC — so
        // a transaction in the first hours of a month can land in the previous
        // bucket for a user east of UTC. That is web's behaviour too, bug
        // included, and fixing it here alone would make the two disagree.
        let calendar = Calendar.current
        let now = Date()
        let thisYm = Self.ym(now, calendar)
        let lastYm = Self.ym(calendar.date(byAdding: .month, value: -1, to: now) ?? now, calendar)
        func total(_ ym: String, _ type: String) -> Int64 {
            rows.first { $0.yearMonth == ym && $0.type == type }?.total ?? 0
        }
        lastIncomeMinor = total(lastYm, "income")
        lastExpenseMinor = total(lastYm, "expense")
        thisIncomeMinor = total(thisYm, "income")
        thisExpenseMinor = total(thisYm, "expense")
    }

    private static func ym(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}

/* ---------------------------- Trends --------------------------- */

@Observable
@MainActor
final class TrendsTileViewModel {
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository

    public private(set) var period: TrendPeriod = .oneMonth
    public private(set) var buckets: [TrendBucket] = []
    public private(set) var totalMinor: Int64 = 0

    private var task: Task<Void, Never>?

    func start() { restart() }

    /// Changing the period swaps the QUERY rather than filtering a wider one in
    /// memory — a year of daily rows is not something to hold just because the
    /// user might pick "1y".
    func setPeriod(_ next: TrendPeriod) {
        guard next != period else { return }
        period = next
        restart()
    }

    private func restart() {
        task?.cancel()
        let period = self.period
        task = Task { [weak self] in
            guard let self else { return }
            let todayIso = Self.todayIso()
            let since = Self.sinceIso(period: period, todayIso: todayIso)
            do {
                for try await daily in try self.ledgerRepository.watchDailyExpenseSince(since) {
                    self.buckets = buildTrend(daily, period: period, todayIso: todayIso)
                    self.totalMinor = daily.values.reduce(0, +)
                }
            } catch {}
        }
    }

    private static func days(_ period: TrendPeriod) -> Int {
        switch period {
        case .threeDays: return 3
        case .oneWeek: return 7
        case .oneMonth: return 28
        case .oneYear: return 365
        }
    }

    private static func calendarUTC() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func todayIso() -> String {
        let c = calendarUTC().dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func sinceIso(period: TrendPeriod, todayIso: String) -> String {
        let calendar = calendarUTC()
        let parts = todayIso.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        components.year = parts.first
        components.month = parts.count > 1 ? parts[1] : 1
        components.day = parts.count > 2 ? parts[2] : 1
        let today = calendar.date(from: components) ?? Date()
        let start = calendar.date(byAdding: .day, value: -(days(period) - 1), to: today) ?? today
        let c = calendar.dateComponents([.year, .month, .day], from: start)
        return String(format: "%04d-%02d-%02dT00:00:00", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/* ------------------- Cashflow / net trend ---------------------- */

@Observable
@MainActor
final class CashflowTileViewModel {
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository

    public private(set) var months: [CashflowMonth] = []
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try self.ledgerRepository.watchMonthlyCashflow() {
                    self.months = monthlyCashflow(rows.map { ($0.yearMonth, $0.type, $0.total) })
                }
            } catch {}
        }
    }
}

/* ------------------------ Subscriptions ------------------------ */

struct SubscriptionRow: Identifiable, Sendable {
    let id: String
    let name: String
    let dueIso: String
    let amountMinor: Int64?
    let currency: String?
}

@Observable
@MainActor
final class SubscriptionsTileViewModel {
    @ObservationIgnored
    @Injected(\.recurringRepository) private var recurringRepository

    public private(set) var monthlyMinor: Int64 = 0
    public private(set) var rows: [SubscriptionRow] = []
    public private(set) var hiddenCount = 0

    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await items in try self.recurringRepository.watchSubscriptions() {
                    // Everything normalised to a MONTHLY equivalent so a yearly
                    // plan and a monthly one are comparable — the same
                    // vector-tested monthlyEquivalent the Recurring screen uses.
                    self.monthlyMinor = items.reduce(Int64(0)) {
                        $0 + monthlyEquivalent($1.amount ?? 0, $1.frequency)
                    }
                    let renewing = items.filter { !$0.nextDue.isEmpty }
                    let top = renewing.prefix(8)
                    self.hiddenCount = max(0, renewing.count - top.count)
                    self.rows = top.map {
                        SubscriptionRow(id: $0.id, name: $0.name, dueIso: $0.nextDue, amountMinor: $0.amount, currency: $0.currency)
                    }
                }
            } catch {}
        }
    }
}

/* ----------------------- Across currencies --------------------- */

struct CurrencySlice: Identifiable, Sendable {
    let id: String
    let currency: String
    let nativeMinor: Int64
    let baseMinor: Int64
    let sharePct: Int
}

@Observable
@MainActor
final class CurrenciesTileViewModel {
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository

    public private(set) var slices: [CurrencySlice] = []
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        let repository = ledgerRepository
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let combined = combineLatest(
                    try repository.watchAccountBalances(),
                    try repository.watchRates()
                )
                for try await (balances, rates) in combined {
                    self.rebuild(balances, rates)
                }
            } catch {}
        }
    }

    private func rebuild(_ balances: [AccountWithBalance], _ rates: RateLookup) {
        let base = baseCurrencyNow()
        var native: [String: Int64] = [:]
        for row in balances {
            native[row.balance.currency, default: 0] += row.balance.amount
        }
        var inBase: [String: Int64] = [:]
        for (currency, amount) in native {
            inBase[currency] = Int64((Double(amount) * rates(currency, base)).rounded())
        }
        let total = inBase.values.reduce(Int64(0), +)
        slices = native.keys
            .sorted { (inBase[$0] ?? 0) > (inBase[$1] ?? 0) }
            .map { currency in
                let baseAmount = inBase[currency] ?? 0
                return CurrencySlice(
                    id: currency,
                    currency: currency,
                    nativeMinor: native[currency] ?? 0,
                    baseMinor: baseAmount,
                    sharePct: total != 0 ? Int((baseAmount * 100) / total) : 0
                )
            }
    }
}
