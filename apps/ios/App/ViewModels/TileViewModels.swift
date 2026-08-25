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
