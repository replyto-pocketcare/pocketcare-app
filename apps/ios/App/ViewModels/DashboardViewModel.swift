import Foundation
import Observation
import Data
import Domain

/// Net-worth hero content -- mirrors apps/web/app/page.tsx's NetWorthHero
/// exactly (see docs/mobile/screen-specs/dashboard.md), and Android's
/// NetWorthHeroState (DashboardViewModel.kt) added the same session.
public struct NetWorthHeroState: Sendable {
    public var net: Money = Money(amount: 0, currency: "INR")
    public var base: String = "INR"
    public var showAvailable: Bool = false
    public var deltaMinor: Int64 = 0
    public var hasTrend: Bool = false
    public var sparkline: [Float] = []
}

/// Dashboard's own minimal recent-activity row -- was relying on
/// TransactionsViewModel.swift's TransactionUiModel until that file was
/// rewritten (2026-08-05, real Transactions screens session) and dropped
/// that type in favor of the richer TransactionListItem. Given a local
/// definition here instead of adopting TransactionListItem directly: the
/// Dashboard "Recent Activity" section is itself explicitly out of scope /
/// deferred (tracked as P3.1c, the tile-catalog follow-up), so this keeps
/// the exact same placeholder-category behavior it already had rather than
/// pulling in real category/label logic as an unplanned scope change here.
public struct DashboardTxnRow: Identifiable, Sendable {
    public let id: String
    public let description: String
    public let amount: String
    public let date: String
    public let accountName: String
    public let categoryName: String
    public let isIncome: Bool
}

@Observable
@MainActor
public final class DashboardViewModel {
    private let ledgerRepository: LedgerRepository
    private var tasks: [Task<Void, Never>] = []

    public var netWorthFormatted: String = "₹0.00"
    public var assetsFormatted: String = "₹0.00"
    public var liabilitiesFormatted: String = "₹0.00"
    public var accounts: [AccountWithBalance] = []
    public var recentTransactions: [DashboardTxnRow] = []
    public var hero: NetWorthHeroState = NetWorthHeroState()

    /// Mirrors page.tsx's `showAvailable` local state (net-worth toggle).
    public func toggleShowAvailable() {
        hero.showAvailable.toggle()
        Task { await refreshSnapshots() }
    }

    private let formatter: NumberFormatter = {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "INR"
        fmt.maximumFractionDigits = 2
        fmt.locale = Locale(identifier: "en_IN")
        return fmt
    }()

    public init(ledgerRepository: LedgerRepository) {
        self.ledgerRepository = ledgerRepository
    }

    public func start() {
        cancel()
        
        // Initial fetch of snapshots
        Task { await refreshSnapshots() }

        // Watch for changes in transactions to refresh recent txns and snapshots
        let txnTask = Task {
            do {
                for try await txns in try ledgerRepository.watchRecentTransactions(limit: 10) {
                    await refreshRecentTransactions(txns: txns)
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
            async let netWorthTask = ledgerRepository.netWorth(base: "INR")
            async let balancesTask = ledgerRepository.accountBalances(includeArchived: false)
            async let monthlyTask = ledgerRepository.monthlyIncomeExpense()

            let nw = try await netWorthTask
            let bal = try await balancesTask
            let monthly = try await monthlyTask

            self.accounts = bal

            let assets = bal.filter { $0.balance.amount > 0 && $0.account.includeInNetWorth }
                .reduce(0) { $0 + $1.balance.amount }
            let liabilities = bal.filter { $0.balance.amount < 0 && $0.account.includeInNetWorth }
                .reduce(0) { $0 + $1.balance.amount }

            self.netWorthFormatted = formatAmount(nw.total.amount)
            self.assetsFormatted = formatAmount(assets)
            self.liabilitiesFormatted = formatAmount(abs(liabilities))

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
    
    private func refreshRecentTransactions(txns: [TransactionRow]) async {
        // We need account names for UI models. We'll use the current self.accounts cache
        // which might be slightly stale if the account hasn't loaded yet, but we just re-fetched it
        let accountMap = Dictionary(uniqueKeysWithValues: self.accounts.map { ($0.account.id, $0.account) })
        
        let now = Date()
        let calendar = Calendar.current
        
        let uiModels = txns.map { txn -> DashboardTxnRow in
            let isIncome = txn.type == "income"
            let sign = isIncome ? "+" : "-"
            let amt = Double(txn.amount) / 100.0
            
            let dateStr = txn.occurredAt
            let formatterDate = ISO8601DateFormatter()
            formatterDate.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let dateObj = formatterDate.date(from: dateStr) ?? (ISO8601DateFormatter().date(from: dateStr) ?? now)
            
            var dateDisplay = dateStr
            if calendar.isDateInToday(dateObj) {
                dateDisplay = "Today"
            } else if calendar.isDateInYesterday(dateObj) {
                dateDisplay = "Yesterday"
            } else {
                let df = DateFormatter()
                df.dateFormat = "dd MMM"
                dateDisplay = df.string(from: dateObj)
            }
            
            let formattedAmt = self.formatter.string(from: NSNumber(value: amt)) ?? "₹0.00"
            
            return DashboardTxnRow(
                id: txn.id,
                description: txn.description ?? txn.note ?? "Transaction",
                amount: "\(sign)\(formattedAmt.replacingOccurrences(of: "-", with: ""))",
                date: dateDisplay,
                accountName: accountMap[txn.accountId]?.name ?? "Unknown Account",
                categoryName: "General",
                isIncome: isIncome
            )
        }
        self.recentTransactions = uiModels
    }

    private func formatAmount(_ amountCents: Int64) -> String {
        let val = Double(amountCents) / 100.0
        return formatter.string(from: NSNumber(value: val)) ?? "₹0.00"
    }
}
