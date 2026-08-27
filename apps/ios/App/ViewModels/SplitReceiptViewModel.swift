import Foundation
import Observation
import Factory
import Domain
import Data

/// One line's assignment as the screen holds it: who is on it, how it divides,
/// and the raw text each person typed.
///
/// The text is kept RAW, not parsed, for the same reason web does: a
/// half-entered "12." must survive a re-render, and parsing on every keystroke
/// would delete the character the user is in the middle of typing.
struct SplitLineState: Equatable {
    var mode: String
    var members: [String]
    /// userId -> raw input string. Its meaning depends on `mode`.
    var weights: [String: String]
}

/// Per-item split assignment — "who had what".
///
/// Ported from `apps/web/app/receipts/split/page.tsx`. All of the arithmetic
/// lives in Domain's `SplitAssign.swift` and `allocateReceipt`; this holds the
/// screen's state and nothing else.
@MainActor
@Observable
public final class SplitReceiptViewModel {
    @ObservationIgnored @Injected(\.receiptsRepository) private var receiptsRepository
    @ObservationIgnored @Injected(\.splitsRepository) private var splitsRepository
    @ObservationIgnored @Injected(\.authRepository) private var authRepository

    public private(set) var draft: ReceiptDraft?
    public private(set) var group: SplitGroup?
    public private(set) var memberIds: [String] = []
    public private(set) var loaded = false
    public var saving = false
    public var error: String?
    /// Set once the split is written, so the view can leave.
    public private(set) var savedExpenseId: String?

    private(set) var state: [String: SplitLineState] = [:]
    private var profileNames: [String: String] = [:]
    private var me: String = ""

    private var scanId = ""
    private var groupId = ""
    private var accountId = ""
    private var categoryId = ""

    public init() {}

    public func load(scanId: String, groupId: String, accountId: String, categoryId: String) async {
        guard !loaded else { return }
        self.scanId = scanId
        self.groupId = groupId
        self.accountId = accountId
        self.categoryId = categoryId

        if let existing = authRepository.currentUserId {
            me = existing
        } else {
            me = (try? await authRepository.ensureUser()) ?? ""
        }

        if let row = try? await receiptsRepository.get(scanId: scanId), let parsed = row.parsedJson {
            // A scan whose JSON will not parse is not an empty scan: the screen
            // says so rather than showing an empty bill you could "save".
            draft = ReceiptDraftJson.decode(parsed)
            if draft == nil { error = S.Receipts.splitCorrupt }
        }

        group = try? await splitsRepository.getGroup(groupId: groupId)
        if let ids = try? await firstValue(splitsRepository.watchGroupMemberIds(groupId: groupId)) {
            memberIds = ids
        }
        if let profiles = try? await firstValue(splitsRepository.watchConnections(userId: me)) {
            profileNames = Dictionary(profiles.map { ($0.id, $0.name) }, uniquingKeysWith: { _, last in last })
        }

        seed()
        loaded = true
    }

    /// Seed every line with "everyone, split the obvious way" so the screen is
    /// usable immediately and the user only edits the exceptions.
    private func seed() {
        guard let draft, !memberIds.isEmpty, state.isEmpty else { return }
        for line in draft.lines {
            state[line.id] = SplitLineState(
                mode: isCharge(line.kind) ? "proportional" : "equal",
                members: memberIds,
                weights: [:]
            )
        }
    }

    // MARK: - Derived

    var digits: Int { receiptDigits(draft?.currency ?? baseCurrencyNow()) }
    var currency: String { draft?.currency ?? baseCurrencyNow() }

    public func name(of id: String) -> String {
        if id == me { return S.Receipts.splitYou }
        return profileNames[id] ?? S.Receipts.splitSomeone
    }

    func lineState(_ lineId: String) -> SplitLineState? { state[lineId] }

    /// Build Domain's assignment structures from the UI state.
    var assignments: [LineAssignment] {
        guard let draft else { return [] }
        return draft.lines.map { line in
            guard let s = state[line.id] else {
                return LineAssignment(lineId: line.id, mode: "equal", shares: [])
            }
            return LineAssignment(
                lineId: line.id,
                mode: s.mode,
                shares: s.members.map { uid in
                    ShareInput(
                        userId: uid,
                        weight: lineWeight(mode: s.mode, raw: s.weights[uid], lineAmount: line.amount, digits: digits)
                    )
                }
            )
        }
    }

    /// Live allocation. A failure here is a validation message, not a crash.
    var allocation: Result<AllocationResult, Error>? {
        guard let draft, !draft.lines.isEmpty else { return nil }
        do { return .success(try allocateReceipt(draft.lines, assignments)) } catch { return .failure(error) }
    }

    func problem(for line: ReceiptLine) -> LineProblem? {
        guard let s = state[line.id] else { return .needsSomeone }
        return validateSplitLine(line: line, mode: s.mode, members: s.members, weights: s.weights, digits: digits)
    }

    var hasLineProblem: Bool {
        guard let draft else { return true }
        return draft.lines.contains { problem(for: $0) != nil }
    }

    var canSave: Bool {
        guard draft != nil, !saving, !accountId.isEmpty, !hasLineProblem else { return false }
        if case .success = allocation { return true }
        return false
    }

    // MARK: - Edits

    func setMode(_ lineId: String, _ mode: String) {
        guard var s = state[lineId] else { return }
        s.mode = mode
        // Weights are mode-specific: "50" means 50% in one mode and ₹0.50 in
        // another, so carrying them across would silently change the split.
        s.weights = [:]
        state[lineId] = s
    }

    func setWeight(_ lineId: String, _ userId: String, _ raw: String) {
        guard var s = state[lineId] else { return }
        s.weights[userId] = raw
        state[lineId] = s
    }

    func toggleMember(_ lineId: String, _ userId: String) {
        guard var s = state[lineId] else { return }
        let has = s.members.contains(userId)
        // A line must belong to somebody — refuse to empty the last one.
        if has && s.members.count == 1 { return }
        s.members = has ? s.members.filter { $0 != userId } : s.members + [userId]
        state[lineId] = s
    }

    func applyToAll(_ members: [String]) {
        for (id, s) in state {
            state[id] = SplitLineState(mode: s.mode, members: members, weights: [:])
        }
    }

    var everyone: [String] { memberIds }
    var onlyMe: [String] { [me] }

    // MARK: - Save

    func save() {
        guard let draft, case .success(let alloc)? = allocation, !saving else { return }
        saving = true
        error = nil
        let input = SplitsRepository.ItemizedSplitInput(
            groupId: groupId,
            draft: draft,
            assignments: assignments,
            // The scanner flow assumes you paid the whole bill; multi-payer
            // stays in the richer add-transaction editor. Web says the same.
            payers: [PayerInput(userId: me, paid: alloc.total, accountId: accountId)],
            categoryId: categoryId.isEmpty ? nil : categoryId,
            occurredAt: draft.occurredAt ?? String(nowIso().prefix(10))
        )
        Task { [weak self] in
            guard let self else { return }
            do {
                let expenseId = try await self.splitsRepository.createSplitExpenseItemized(userId: self.me, input: input)
                try? await self.receiptsRepository.linkScan(scanId: self.scanId, expenseId: expenseId)
                self.savedExpenseId = expenseId
            } catch {
                self.error = error.localizedDescription
                self.saving = false
            }
        }
    }
}

/// First element of a watch, used where the screen needs a snapshot rather than
/// a subscription — the members of a group do not change while you are
/// assigning its bill.
private func firstValue<T: Sendable>(_ stream: AsyncThrowingStream<T, Error>) async throws -> T? {
    for try await value in stream { return value }
    return nil
}
