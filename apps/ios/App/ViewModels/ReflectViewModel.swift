import Foundation
import Observation
import Factory
import Data

/// Reflect — ported from apps/web/app/reflect/page.tsx.
///
/// A card stack over untagged expenses: swipe left for "need", right for
/// "greed". Judging writes `transactions.intent`; skipping writes nothing and
/// only hides the card for this visit.
///
/// **The history is what makes Undo work, and it is deliberately local.** Web
/// keeps the same list in component state: an undone judgement re-clears
/// `intent`, which brings the row back into the query naturally, and an undone
/// *skip* just stops hiding it. Persisting the history would mean a second
/// source of truth for something the ledger already records.
///
/// Mirrors apps/android/.../ui/reflect/ReflectViewModel.kt.
@Observable
@MainActor
final class ReflectViewModel {
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository

    enum Action: Equatable, Sendable { case skip, judge }

    /// One thing the user did this visit. A struct rather than a tuple so it
    /// is `Sendable` on its own and can cross into the write task without the
    /// compiler having to infer it.
    struct Step: Equatable, Sendable {
        let id: String
        let action: Action
    }

    private(set) var queue: [LedgerRepository.IntentQueueRow] = []
    private(set) var isLoading = true
    private(set) var history: [Step] = []

    private var task: Task<Void, Never>?

    /// What the stack actually shows: the live query minus anything this visit
    /// has already dealt with. A judged row leaves the query on its own once
    /// the write lands, but not before the next emission — so it is filtered
    /// here too, or the card would flick back for a frame.
    var visible: [LedgerRepository.IntentQueueRow] {
        let handled = Set(history.map(\.id))
        return queue.filter { !handled.contains($0.id) }
    }

    var canUndo: Bool { !history.isEmpty }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try self.ledgerRepository.watchIntentQueue() {
                    self.queue = rows
                    self.isLoading = false
                }
            } catch {
                self.isLoading = false
                print("Error watching intent queue: \(error)")
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func judge(_ id: String, intent: String) {
        history.append(Step(id: id, action: .judge))
        Task { [weak self] in
            try? await self?.ledgerRepository.setIntent(id: id, intent: intent)
        }
    }

    func skip(_ id: String) {
        history.append(Step(id: id, action: .skip))
    }

    func undo() {
        guard let last = history.popLast() else { return }
        guard last.action == .judge else { return }
        let id = last.id
        Task { [weak self] in
            try? await self?.ledgerRepository.setIntent(id: id, intent: nil)
        }
    }
}
