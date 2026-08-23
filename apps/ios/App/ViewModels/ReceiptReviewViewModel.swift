import Foundation
import Observation
import Factory
import Data
import Domain

/// Real port of apps/web/app/receipts/review/page.tsx (task #62). See
/// docs/mobile/screen-specs/receipt-scan.md for the documented scope cut
/// (no category auto-suggest yet -- pairs with task #65; "Split this bill"
/// shown disabled -- pairs with task #63/64).
///
/// `@Injected` + plain `ReceiptReviewViewModel()` init, matching
/// GroupDetailViewModel/SplitsViewModel's convention. The scan id is passed
/// in via `load(_:)`, called from `.task(id: scanId)` in the view, matching
/// GroupDetailViewModel's established `select(_:)` convention. Each
/// `watch*` stream gets its own long-running `Task` in `tasks`, per
/// TransactionsViewModel's convention (not a one-shot "take the first
/// value" pattern).
@Observable
@MainActor
public final class ReceiptReviewViewModel {
    @Injected(\.receiptsRepository) private var receiptsRepository
    @Injected(\.ledgerRepository) private var ledgerRepository
    @Injected(\.authRepository) private var authRepository
    private var tasks: [Task<Void, Never>] = []
    private var scanId: String = ""

    public var draft: ReceiptDraft?
    public var accounts: [Account] = []
    public var categories: [CategoryRow] = []
    public var accountId: String?
    public var categoryId: String?
    public var loaded = false
    public var saving = false
    public var error: String?
    public var savedTransactionId: String?

    public init() {}

    public func load(_ scanId: String) async {
        if self.scanId == scanId, loaded { return }
        self.scanId = scanId
        tasks.forEach { $0.cancel() }
        tasks = []

        do {
            let row = try await receiptsRepository.get(scanId: scanId)
            if let json = row?.parsedJson, let d = ReceiptDraftJson.decode(json) {
                draft = d
            } else {
                error = "We couldn't reopen this scan. Please scan it again."
            }
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true

        tasks.append(Task { [weak self] in
            guard let self else { return }
            do {
                for try await list in try self.ledgerRepository.watchAccounts() {
                    self.accounts = list
                    if self.accountId == nil, let first = list.first { self.accountId = first.id }
                }
            } catch { print("Error watching accounts: \(error)") }
        })
        tasks.append(Task { [weak self] in
            guard let self else { return }
            do {
                for try await list in try self.ledgerRepository.watchCategories() {
                    self.categories = list.filter { $0.kind != "income" }
                }
            } catch { print("Error watching categories: \(error)") }
        })
    }

    public func reconcileResult() -> ReconcileResult? {
        draft.map { reconcile($0) }
    }

    public func subtotalsResult() -> Subtotals? {
        draft.map { subtotals($0.lines) }
    }

    private func patch(_ fn: (ReceiptDraft) -> ReceiptDraft) {
        if let d = draft { draft = fn(d) }
    }

    public func setMerchant(_ value: String) { patch { ReceiptDraft(merchant: value, occurredAt: $0.occurredAt, currency: $0.currency, lines: $0.lines, total: $0.total, confidence: $0.confidence, engine: $0.engine, rawText: $0.rawText) } }
    public func setOccurredAt(_ value: String) { patch { ReceiptDraft(merchant: $0.merchant, occurredAt: value, currency: $0.currency, lines: $0.lines, total: $0.total, confidence: $0.confidence, engine: $0.engine, rawText: $0.rawText) } }
    public func setTotal(_ minor: Int64?) { patch { ReceiptDraft(merchant: $0.merchant, occurredAt: $0.occurredAt, currency: $0.currency, lines: $0.lines, total: minor, confidence: $0.confidence, engine: $0.engine, rawText: $0.rawText) } }

    public func updateLine(_ lineId: String, _ fn: (ReceiptLine) -> ReceiptLine) {
        patch { d in
            let lines = d.lines.map { $0.id == lineId ? fn($0) : $0 }
            return ReceiptDraft(merchant: d.merchant, occurredAt: d.occurredAt, currency: d.currency, lines: lines, total: d.total, confidence: d.confidence, engine: d.engine, rawText: d.rawText)
        }
    }

    public func removeLine(_ lineId: String) {
        patch { d in
            ReceiptDraft(merchant: d.merchant, occurredAt: d.occurredAt, currency: d.currency, lines: d.lines.filter { $0.id != lineId }, total: d.total, confidence: d.confidence, engine: d.engine, rawText: d.rawText)
        }
    }

    public func addLine(_ kind: String) {
        patch { d in
            let line = ReceiptLine(id: "new-\(Int(Date().timeIntervalSince1970 * 1000))", kind: kind, description: "", quantity: nil, unit: nil, unitPrice: nil, amount: 0, confidence: 100)
            return ReceiptDraft(merchant: d.merchant, occurredAt: d.occurredAt, currency: d.currency, lines: d.lines + [line], total: d.total, confidence: d.confidence, engine: d.engine, rawText: d.rawText)
        }
    }

    /// One-tap fix: "Add {delta} as a line".
    public func addDifferenceAsLine() {
        patch { balanceWithLine($0, "fix-\(Int(Date().timeIntervalSince1970 * 1000))", "Unmatched") }
    }

    /// One-tap fix: "Use {computed} as the total".
    public func useComputedTotal() {
        patch { adoptComputedTotal($0) }
    }

    public func saveAsTransaction() {
        guard let draft, let stated = reconcile(draft).stated, let accId = accountId, let userId = authRepository.currentUserId else { return }
        saving = true
        error = nil
        Task {
            do {
                let s = subtotals(draft.lines)
                try await receiptsRepository.updateScanDraft(scanId: scanId, input: UpdateScanDraftInput(
                    engine: draft.engine, merchant: draft.merchant, occurredAt: draft.occurredAt, currency: draft.currency,
                    subtotal: s.items, tax: s.tax, serviceCharge: s.serviceCharge, tip: s.tip, discount: s.discount,
                    total: draft.total, confidence: Int64(draft.confidence), parsedJson: ReceiptDraftJson.encode(draft)
                ))
                let cur = draft.currency
                let tx = try await ledgerRepository.createTransaction(
                    userId: userId,
                    accountId: accId,
                    type: "expense",
                    amount: money(stated, cur),
                    occurredAt: draft.occurredAt ?? ISO8601DateFormatter().string(from: Date()),
                    categoryId: categoryId,
                    description: draft.merchant,
                    // Breakdown must sum EXACTLY to the transaction amount --
                    // reconciliation already proved it does, mirrors web's
                    // `describeItem` (fold qty/unit into the description
                    // since transaction_items has no qty column).
                    items: draft.lines.map { line in
                        TransactionItemInput(description: Self.describeItem(line.description, line.quantity, line.unit), amount: money(line.amount, cur))
                    }
                )
                try await receiptsRepository.linkScan(scanId: scanId, transactionId: tx.id, expenseId: nil)
                savedTransactionId = tx.id
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }

    private static func describeItem(_ description: String, _ quantity: Int64?, _ unit: String?) -> String {
        let name = description.trimmingCharacters(in: .whitespaces).isEmpty ? "Item" : description.trimmingCharacters(in: .whitespaces)
        guard let quantity else { return name }
        let q = Double(quantity) / 1000.0
        let qtyText: String
        if q == q.rounded(.towardZero), q.truncatingRemainder(dividingBy: 1) == 0 {
            qtyText = String(Int(q))
        } else {
            qtyText = String(format: "%.3f", q).trimmingCharacters(in: CharacterSet(charactersIn: "0")).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        if let unit { return "\(name) (\(qtyText) \(unit))" }
        return "\(name) × \(qtyText)"
    }
}
