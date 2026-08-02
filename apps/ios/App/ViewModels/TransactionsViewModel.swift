import Foundation
import Observation
import Data

public struct TransactionUiModel: Identifiable, Sendable {
    public let id: String
    public let description: String
    public let amount: String
    public let date: String
    public let accountName: String
    public let categoryName: String
    public let isIncome: Bool

    public init(id: String, description: String, amount: String, date: String, accountName: String, categoryName: String, isIncome: Bool) {
        self.id = id
        self.description = description
        self.amount = amount
        self.date = date
        self.accountName = accountName
        self.categoryName = categoryName
        self.isIncome = isIncome
    }
}

@Observable
@MainActor
public final class TransactionsViewModel {
    private let ledgerRepository: LedgerRepository
    private var tasks: [Task<Void, Never>] = []

    public var allTransactions: [TransactionUiModel] = []
    
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
        
        let task = Task {
            do {
                // watchAllTransactions combines with a single fetch of accounts
                for try await txns in try ledgerRepository.watchAllTransactions() {
                    await refreshTransactions(txns: txns)
                }
            } catch {
                print("Error watching all transactions: \(error)")
            }
        }
        
        tasks.append(task)
    }

    public func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private func refreshTransactions(txns: [TransactionRow]) async {
        do {
            let accounts = try await ledgerRepository.accountBalances(includeArchived: true)
            let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.account.id, $0.account) })
            
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
            self.allTransactions = uiModels
        } catch {
            print("Error refreshing transactions: \(error)")
        }
    }
}
