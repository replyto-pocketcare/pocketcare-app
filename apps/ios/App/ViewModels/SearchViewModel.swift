import Foundation
import Observation
import Factory
import Data
import Domain

/// Search — ported from apps/web/app/search/page.tsx.
///
/// The filter itself is `Domain.searchTransactions`, vector-tested against a
/// reference implementation of web's `useMemo`. This view model's whole job is
/// to keep the six live queries that feed it and to turn the surviving rows
/// into the SAME `TransactionListItem` the Transactions list and the dashboard
/// tile render — web renders the same `<TransactionTile>` on all three, and a
/// third row builder here is the re-inlining the component inventory exists to
/// prevent.
///
/// Mirrors apps/android/.../ui/search/SearchViewModel.kt.
@Observable
@MainActor
final class SearchViewModel {
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository

    /// Mutating any field re-runs the filter — `didSet` fires for an in-place
    /// mutation of a struct property, which is what `criteria.query = "…"` is.
    var criteria = SearchCriteria() { didSet { recompute() } }
    var showFilters = false

    /// The account picker's options, in the order the repository returns them.
    private(set) var accounts: [Account] = []
    private(set) var items: [TransactionListItem] = []
    /// Web counts the FILTERED rows, before collapse — so two postings of one
    /// split expense count as two here and render as one row below. Copied
    /// deliberately: the count answers "how much matched", not "how many rows".
    private(set) var resultCount = 0

    private var tasks: [Task<Void, Never>] = []
    private var allTxns: [TransactionRow] = []
    private var accountMap: [String: Account] = [:]
    private var categoryMap: [String: CategoryRow] = [:]
    private var labelNames: [String: [String]] = [:]
    private var methodLabels: [String: String] = [:]
    private var splitInfo: [String: SplitInfo] = [:]

    var activeFilters: Int { activeFilterCount(criteria) }

    func clearFilters() {
        criteria = SearchCriteria(query: criteria.query)
    }

    /**
     Apply a deep link's filters — once.

     Web guards its prefill effect with a `prefilled` flag for a reason: the
     effect re-runs whenever `params` changes identity, and re-applying would
     wipe whatever the user had typed since arriving. The flag lives here rather
     than in the view because a view model outlives the redraws a `@State` in a
     recreated view does not.
     */
    func applyPrefill(_ prefill: SearchPrefill) {
        guard !prefilled else { return }
        prefilled = true
        criteria = prefill.criteria
        if prefill.showFilters { showFilters = true }
    }

    private var prefilled = false

    func start() {
        cancel()
        tasks.append(Task {
            do {
                for try await txns in try ledgerRepository.watchSearchTransactions() {
                    self.allTxns = txns
                    self.recompute()
                }
            } catch { print("Error watching search transactions: \(error)") }
        })
        tasks.append(Task {
            do {
                for try await accounts in try ledgerRepository.watchAccounts(includeArchived: true) {
                    self.accounts = accounts
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
                // The repository returns one row per (account type, method)
                // pairing, so the same method arrives several times. Only the
                // id → label mapping is wanted here, and it is the same in
                // every pairing.
                for try await methods in try ledgerRepository.watchPaymentMethods() {
                    self.methodLabels = Dictionary(methods.map { ($0.id, $0.label) }) { first, _ in first }
                    self.recompute()
                }
            } catch { print("Error watching payment methods: \(error)") }
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

    func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private func recompute() {
        let rows = allTxns.map { txn -> SearchRow in
            let account = accountMap[txn.accountId]
            return SearchRow(
                id: txn.id,
                type: txn.type,
                accountId: txn.accountId,
                toAccountId: txn.toAccountId,
                occurredAt: txn.occurredAt,
                amountMinor: txn.amount,
                currency: txn.currency,
                labels: labelNames[txn.id]?.joined(separator: ", "),
                note: txn.note,
                description: txn.description,
                methodLabel: txn.paymentMethod.flatMap { methodLabels[$0] },
                categoryName: txn.categoryId.flatMap { categoryMap[$0]?.name },
                accountName: account?.name,
                accountType: account?.type
            )
        }

        let matched = searchTransactions(rows, criteria)
        resultCount = matched.count

        let byId = Dictionary(uniqueKeysWithValues: allTxns.map { ($0.id, $0) })
        items = collapseSplitRowIds(matched.map(\.id), splitInfo).compactMap { id in
            guard let txn = byId[id] else { return nil }
            return transactionListItem(
                txn,
                accountMap: accountMap,
                categoryMap: categoryMap,
                labels: labelNames[id],
                split: splitInfo[id]
            )
        }
    }
}
