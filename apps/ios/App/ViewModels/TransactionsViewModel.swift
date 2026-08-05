import Foundation
import Observation
import Data

public struct TransactionListItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let tagsText: String
    public let accountName: String?
    public let amountFormatted: String
    public let isPositive: Bool
    public let dateFormatted: String
    public let avatarLetter: String
}

/// Type filter chips -- matches transactions/page.tsx's TYPES exactly.
let txTypeFilters = ["all", "income", "expense", "transfer"]

/// Transactions list — rewritten 2026-08-05 per
/// docs/mobile/screen-specs/transactions.md. Previous version had a
/// hardcoded "General" category placeholder, no label tags, no type=transfer
/// filter tab, and TransactionsView.swift never linked a row to an edit
/// screen (none existed). Constructor-injected via Container.shared
/// .transactionsViewModel() (AppModule.swift) -- unchanged wiring, only the
/// body is new.
@Observable
@MainActor
public final class TransactionsViewModel {
    private let ledgerRepository: LedgerRepository
    private var tasks: [Task<Void, Never>] = []

    public var items: [TransactionListItem] = []
    public var query: String = "" { didSet { recompute() } }
    public var typeFilter: String = "all" { didSet { recompute() } }

    private var allTxns: [TransactionRow] = []
    private var accountMap: [String: Account] = [:]
    private var categoryMap: [String: CategoryRow] = [:]
    private var labelNames: [String: [String]] = [:]

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
        tasks.append(Task {
            do {
                for try await txns in try ledgerRepository.watchAllTransactions() {
                    self.allTxns = txns
                    self.recompute()
                }
            } catch { print("Error watching transactions: \(error)") }
        })
        tasks.append(Task {
            do {
                for try await accounts in try ledgerRepository.watchAccounts(includeArchived: true) {
                    self.accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
                    self.recompute()
                }
            } catch { print("Error watching accounts: \(error)") }
        })
        tasks.append(Task {
            do {
                for try await cats in try ledgerRepository.watchCategories() {
                    self.categoryMap = Dictionary(uniqueKeysWithValues: cats.map { ($0.id, $0) })
                    self.recompute()
                }
            } catch { print("Error watching categories: \(error)") }
        })
        tasks.append(Task {
            do {
                for try await names in try ledgerRepository.watchTransactionLabelNames() {
                    self.labelNames = names
                    self.recompute()
                }
            } catch { print("Error watching transaction labels: \(error)") }
        })
    }

    public func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    /// Matches transactions/page.tsx's query: excludes opening_balance rows,
    /// filters by note/label search text and type, newest first, capped at
    /// 200.
    private func recompute() {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = allTxns
            .filter { $0.type != "opening_balance" }
            .filter { typeFilter == "all" || $0.type == typeFilter }
            .filter { txn in
                guard !needle.isEmpty else { return true }
                let noteHit = (txn.note?.lowercased().contains(needle)) ?? false
                let labelHit = (labelNames[txn.id] ?? []).contains { $0.lowercased().contains(needle) }
                return noteHit || labelHit
            }
            .sorted { $0.occurredAt > $1.occurredAt }
            .prefix(200)

        items = filtered.map { toListItem($0) }
    }

    private func toListItem(_ txn: TransactionRow) -> TransactionListItem {
        let categoryName = txn.categoryId.flatMap { categoryMap[$0]?.name } ?? "Uncategorised"
        let labels = labelNames[txn.id]
        let labelsCsv = labels?.joined(separator: ", ")
        var raw = (txn.description ?? labelsCsv ?? categoryName).trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { raw = txn.type }
        let title = merchantTitle(raw)
        let subtitle = raw != title ? raw : ""
        let tags = txTags(categoryName, labels)
        let tagsText = tags.map(\.text).joined(separator: "  ·  ")
        let account = accountMap[txn.accountId]

        let sign = txn.type == "expense" ? "\u{2212}" : (txn.type == "income" ? "+" : "")
        let amt = Double(txn.amount) / 100.0
        let formatted = formatter.string(from: NSNumber(value: amt)) ?? "₹0.00"

        let dateFormatted: String
        if let date = parseOccurredAt(txn.occurredAt) {
            if Calendar.current.isDateInToday(date) {
                dateFormatted = "Today"
            } else if Calendar.current.isDateInYesterday(date) {
                dateFormatted = "Yesterday"
            } else {
                let df = DateFormatter()
                df.dateFormat = "MMM d"
                dateFormatted = df.string(from: date)
            }
        } else {
            dateFormatted = String(txn.occurredAt.prefix(10))
        }

        return TransactionListItem(
            id: txn.id,
            title: title,
            subtitle: subtitle,
            tagsText: tagsText,
            accountName: account?.name,
            amountFormatted: "\(sign)\(formatted)",
            isPositive: txn.type == "income",
            dateFormatted: dateFormatted,
            avatarLetter: String((title.first ?? "•")).uppercased()
        )
    }
}

/// Tries with-fractional-seconds first, falls back to the plain ISO8601
/// format -- matches the flexible-parse pattern already used in this file's
/// predecessor.
private let fractionalIsoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

func parseOccurredAt(_ s: String) -> Date? {
    fractionalIsoFormatter.date(from: s) ?? ISO8601DateFormatter().date(from: s)
}
