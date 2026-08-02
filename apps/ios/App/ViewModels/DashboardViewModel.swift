import Foundation
import Observation
import Data

@Observable
@MainActor
public final class DashboardViewModel {
    private let ledgerRepository: LedgerRepository
    private var tasks: [Task<Void, Never>] = []

    public var netWorthFormatted: String = "₹0.00"
    public var assetsFormatted: String = "₹0.00"
    public var liabilitiesFormatted: String = "₹0.00"
    public var accounts: [AccountWithBalance] = []
    public var recentTransactions: [TransactionUiModel] = []

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
            
            let nw = try await netWorthTask
            let bal = try await balancesTask
            
            self.accounts = bal

            let assets = bal.filter { $0.balance.amount > 0 && $0.account.includeInNetWorth }
                .reduce(0) { $0 + $1.balance.amount }
            let liabilities = bal.filter { $0.balance.amount < 0 && $0.account.includeInNetWorth }
                .reduce(0) { $0 + $1.balance.amount }

            self.netWorthFormatted = formatAmount(nw.total.amount)
            self.assetsFormatted = formatAmount(assets)
            self.liabilitiesFormatted = formatAmount(abs(liabilities))
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
        
        let uiModels = txns.map { txn -> TransactionUiModel in
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
            
            return TransactionUiModel(
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
