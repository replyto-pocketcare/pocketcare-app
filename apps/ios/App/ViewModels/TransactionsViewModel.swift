import Foundation
import Observation
import Factory
import PowerSync
import Data
import Domain

public struct TransactionListItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let tagsText: String
    public let accountName: String?
    public let amountFormatted: String
    public let isPositive: Bool
    /// True when this row stands for a whole split expense rather than one
    /// posting of it — the row shows a "Split" chip and the amount you paid.
    public let isSplit: Bool
    /// True when a receipt photo created this transaction — the row shows a
    /// "Scanned" chip. Web's `scannedIds.has(tx.id)`, from `receipt_scans`.
    public let isScanned: Bool
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
    /// `@Injected`, not a constructor argument, for the two dependencies added
    /// after this view model's wiring was written: the container already
    /// vends both, and widening `init` would have meant editing the DI module
    /// for a list that only reads from them.
    @ObservationIgnored @Injected(\.receiptsRepository) private var receiptsRepository
    @ObservationIgnored @Injected(\.powerSyncDatabase) private var db
    private var tasks: [Task<Void, Never>] = []

    public var items: [TransactionListItem] = []
    /// Show skeletons rather than "no matching transactions".
    ///
    /// Web's guard is `rows.length > 0 ? list : (rowsLoading || syncPending) ?
    /// skeletons : empty`, and the misleading half is the one that matters: for
    /// the first seconds of a returning user's first launch the local database
    /// is empty because the data is still downloading, and this list told them
    /// they had none.
    public private(set) var showSkeleton = true
    public var query: String = "" { didSet { recompute() } }
    public var typeFilter: String = "all" { didSet { recompute() } }

    private var allTxns: [TransactionRow] = []
    private var accountMap: [String: Account] = [:]
    private var categoryMap: [String: CategoryRow] = [:]
    private var labelNames: [String: [String]] = [:]
    private var splitInfo: [String: SplitInfo] = [:]
    /// Transactions a receipt photo created — the "Scanned" chip.
    ///
    /// Web's `useScannedTransactionIds()`, which neither phone ever called:
    /// `receipt_scans.transaction_id` was written on save and then never read
    /// back, so a scanned bill was indistinguishable from a hand-typed one.
    private var scannedIds: Set<String> = []
    /// False until the first ledger read lands — web's `isLoading` from
    /// `useQuery`. An empty list that has not been read yet is not an empty
    /// list.
    private var rowsLoaded = false
    private var syncPending = true

    public init(ledgerRepository: LedgerRepository) {
        self.ledgerRepository = ledgerRepository
    }

    public func start() {
        cancel()
        tasks.append(Task {
            do {
                for try await txns in try ledgerRepository.watchAllTransactions() {
                    self.allTxns = txns
                    self.rowsLoaded = true
                    self.recompute()
                }
            } catch {
                print("Error watching transactions: \(error)")
                // A stream that failed before its first yield is still an
                // answer -- we are not waiting any more. Without this the
                // skeleton shimmers for the life of the process.
                self.rowsLoaded = true
                self.recompute()
            }
        })
        tasks.append(Task {
            do {
                for try await ids in try receiptsRepository.watchScannedTransactionIds() {
                    self.scannedIds = ids
                    self.recompute()
                }
            } catch { print("Error watching scanned transaction ids: \(error)") }
        })
        tasks.append(Task { [weak self] in
            guard let self else { return }
            await awaitInitialSync(self.db)
            self.syncPending = false
            self.recompute()
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
        tasks.append(Task {
            do {
                for try await postings in try ledgerRepository.watchSplitPostings() {
                    self.splitInfo = splitInfoByTransaction(postings)
                    self.recompute()
                }
            } catch { print("Error watching split postings: \(error)") }
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

        // Collapse AFTER the cap, which is web's order: it queries with
        // `LIMIT 200` and collapses the page it got back. Collapsing first
        // would let a page of split siblings pull older rows into view and
        // make the list's length depend on how many splits it happened to
        // contain.
        //
        // This was missing until 2026-08-26. A split expense writes up to three
        // ledger rows, so this list showed one dinner as three lines with three
        // different amounts, where the browser has always shown one.
        let byId = Dictionary(uniqueKeysWithValues: filtered.map { ($0.id, $0) })
        let visible = collapseSplitRowIds(filtered.map(\.id), splitInfo)

        items = visible.compactMap { id in
            guard let txn = byId[id] else { return nil }
            return transactionListItem(
                txn,
                accountMap: accountMap,
                categoryMap: categoryMap,
                labels: labelNames[id],
                split: splitInfo[id],
                scanned: scannedIds.contains(id)
            )
        }
        showSkeleton = !rowsLoaded || syncPending
    }

}

/// Tries with-fractional-seconds first, falls back to the plain ISO8601
/// format -- matches the flexible-parse pattern already used in this file's
/// predecessor.
///
/// A fresh formatter is allocated per call rather than cached in a global
/// `let` -- a cached instance hit the same real Swift 6 build error already
/// documented in `Domain/Sources/Domain/SplitsInsights.swift`'s
/// `parseIsoMillis` ("not concurrency-safe because non-Sendable type
/// 'ISO8601DateFormatter' may have shared mutable state"). Same fix here for
/// the same reason: this can genuinely be called from concurrent Swift
/// Tasks, ISO8601DateFormatter's thread-safety for concurrent reads isn't
/// documented as guaranteed, and this isn't a hot loop (per-row transaction
/// formatting, not a tight numeric kernel) -- so allocating per call
/// sidesteps the question instead of asserting an unverified safety claim.
func parseOccurredAt(_ s: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: s) ?? ISO8601DateFormatter().date(from: s)
}
