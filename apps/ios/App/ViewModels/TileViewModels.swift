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
    let name: String
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
    private var categoryMap: [String: CategoryRow] = [:]
    private var transactions: [TransactionRow] = []

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.watchTransactions() }
                group.addTask { await self.watchCategories() }
            }
        }
    }

    /// Web's `new Date(y, m, 1).toISOString()` — the first instant of this month.
    private var monthStartIso: String {
        let now = Date()
        var components = Calendar.current.dateComponents([.year, .month], from: now)
        components.day = 1
        let start = Calendar.current.date(from: components) ?? now
        return ISO8601DateFormatter().string(from: start)
    }

    private func watchTransactions() async {
        do {
            // Open-ended: the repository's query is `occurred_at < ?`, so a
            // sentinel far in the future includes anything dated later today.
            // Web's query has no upper bound at all; inventing a second
            // unbounded repository method for one caller would be worse than a
            // sentinel that is obviously one.
            for try await rows in try ledgerRepository.watchTransactionsInRange(
                startIso: monthStartIso,
                endIso: "9999-12-31T00:00:00Z"
            ) {
                transactions = rows
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

    private func rebuild() {
        // NOTE: web's query also excludes transactions with a `lend` expense
        // posting — money you fronted for someone is not your spending. That
        // exclusion is NOT applied here, because no native repository exposes
        // expense_postings yet. Recorded in ABSENT-BY-DECISION.md rather than
        // left to be discovered as a number that disagrees with the browser.
        let expenses = transactions.filter { $0.type == "expense" }
        let grouped = Dictionary(grouping: expenses, by: { $0.categoryId })
            .map { key, rows in (key, rows.reduce(Int64(0)) { $0 + $1.amount }) }
            .sorted { $0.1 > $1.1 }

        let total = grouped.reduce(Int64(0)) { $0 + $1.1 }
        let largest = grouped.first?.1 ?? 0
        // Web charts the top 7 and links the rest to Insights.
        let top = grouped.prefix(7)

        totalMinor = total
        hiddenCount = max(0, grouped.count - top.count)
        slices = top.map { categoryId, amount in
            SpendSlice(
                id: categoryId ?? "uncategorised",
                name: categoryId.flatMap { categoryMap[$0]?.name } ?? S.Transactions.uncategorised,
                totalMinor: amount,
                sharePct: total > 0 ? Int((amount * 100) / total) : 0,
                // Web floors the fill at 3% so a tiny category still draws
                // something — a zero-width bar reads as a rendering bug.
                fillPct: largest > 0 ? max(3, Int((amount * 100) / largest)) : 0
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

    /// `friendBalances` is a ONE-SHOT read on iOS, not a stream — see
    /// SplitsRepository's REACTIVITY NOTE: every derived balance view is a
    /// snapshot here because `AsyncThrowingStream` has no `combine`. So this
    /// re-reads it whenever the connections watch fires, which is the same
    /// pattern SplitsViewModel already uses. **Android's repository combines
    /// two watches and is genuinely reactive**, which makes this one of the
    /// few real behavioural asymmetries left; recorded in
    /// ABSENT-BY-DECISION.md rather than hidden behind a matching signature.
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            guard let userId = await self.resolveUserId() else { return }
            do {
                for try await connections in try self.splitsRepository.watchConnections(userId: userId) {
                    await self.refresh(userId: userId, connections: connections)
                }
            } catch {}
        }
    }

    private func refresh(userId: String, connections: [UserProfile]) async {
        guard let balances = try? await splitsRepository.friendBalances(userId: userId) else { return }
        let namesById = Dictionary(uniqueKeysWithValues: connections.map { ($0.id, $0.name) })
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
