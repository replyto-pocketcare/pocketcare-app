import Foundation
import Observation
import Data
import Domain

/// Net-worth hero content -- mirrors apps/web/app/page.tsx's NetWorthHero
/// exactly (see docs/mobile/screen-specs/dashboard.md), and Android's
/// NetWorthHeroState (DashboardViewModel.kt) added the same session.
public struct NetWorthHeroState: Sendable {
    public var net: Money = Money(amount: 0, currency: FormOptions.defaultCurrency)
    public var base: String = FormOptions.defaultCurrency
    public var showAvailable: Bool = false
    public var deltaMinor: Int64 = 0
    public var hasTrend: Bool = false
    public var sparkline: [Float] = []
}

@Observable
@MainActor
public final class DashboardViewModel {
    private let ledgerRepository: LedgerRepository
    private var tasks: [Task<Void, Never>] = []

    public var accounts: [AccountWithBalance] = []
    public var hero: NetWorthHeroState = NetWorthHeroState()

    /// Mirrors page.tsx's `showAvailable` local state (net-worth toggle).
    public func toggleShowAvailable() {
        hero.showAvailable.toggle()
        Task { await refreshSnapshots() }
    }

    public init(ledgerRepository: LedgerRepository) {
        self.ledgerRepository = ledgerRepository
    }

    public func start() {
        cancel()

        // Initial fetch of snapshots
        Task { await refreshSnapshots() }

        // Watch for changes in transactions to trigger a snapshot refresh
        // (net worth / sparkline / delta all derive from transaction data).
        // No longer maps rows into a Dashboard-local recent-activity list --
        // that section was removed 2026-08-06 (Akhilesh: "we already have
        // recent transactions section that would must have come when we
        // copied all the widgets and the layout from web" -- it was an
        // iOS-only invention with no counterpart in web or Android, not a
        // real ported feature). watchRecentTransactions is reused here
        // purely as a change signal; a real Transactions list belongs to
        // TransactionsViewModel.swift, not Dashboard.
        let txnTask = Task {
            do {
                for try await _ in try ledgerRepository.watchRecentTransactions(limit: 10) {
                    await refreshSnapshots()
                }
            } catch {
                print("Error watching recent transactions: \(error)")
            }
        }

        // Watch for changes in accounts to refresh snapshots
        let acctTask = Task {
            do {
                for try await _ in try ledgerRepository.watchAccounts(includeArchived: false) {
                    await refreshSnapshots()
                }
            } catch {
                print("Error watching accounts: \(error)")
            }
        }
        
        tasks = [txnTask, acctTask]
    }

    public func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private func refreshSnapshots() async {
        do {
            async let netWorthTask = ledgerRepository.netWorth(base: baseCurrencyNow())
            async let balancesTask = ledgerRepository.accountBalances(includeArchived: false)
            async let monthlyTask = ledgerRepository.monthlyIncomeExpense()

            let nw = try await netWorthTask
            let bal = try await balancesTask
            let monthly = try await monthlyTask

            self.accounts = bal

            // ---- Hero sparkline/delta -- matches page.tsx's NetWorthHero
            // exactly (same algorithm as Android's DashboardViewModel.kt,
            // ported the same session): fold (year-month, type) rows into
            // per-month (inc, exp), last 8 months, delta = last month's
            // (inc - exp), sparkline = cumulative running sum of (inc-exp)/100.
            var byMonth: [String: (inc: Int64, exp: Int64)] = [:]
            var order: [String] = []
            for row in monthly {
                if byMonth[row.yearMonth] == nil { order.append(row.yearMonth) }
                var entry = byMonth[row.yearMonth] ?? (0, 0)
                if row.type == "income" { entry.inc = row.total } else { entry.exp = row.total }
                byMonth[row.yearMonth] = entry
            }
            let months = order.suffix(8).map { ($0, byMonth[$0]!) }
            let deltaMinor: Int64 = months.last.map { $0.1.inc - $0.1.exp } ?? 0
            var acc: Float = 0
            let sparkline: [Float] = months.map { (_, v) in
                acc += Float(v.inc - v.exp) / 100
                return acc
            }

            self.hero.net = self.hero.showAvailable ? nw.available : nw.total
            self.hero.base = nw.base
            self.hero.deltaMinor = deltaMinor
            self.hero.hasTrend = !months.isEmpty
            self.hero.sparkline = sparkline
        } catch {
            print("Error refreshing snapshots: \(error)")
        }
    }
}
