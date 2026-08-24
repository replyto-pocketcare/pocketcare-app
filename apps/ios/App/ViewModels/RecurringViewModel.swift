import Foundation
import Observation
import Factory
import Domain
import Data

/// Recurring payments & income — ported from apps/web/app/recurring/page.tsx.
/// Mirrors `apps/android/.../ui/recurring/RecurringViewModel.kt`.
///
/// Everything here is a MONTHLY equivalent so a weekly bill and a yearly
/// subscription are comparable. `monthlyEquivalent` is the shared, vector-tested
/// domain port — raw amounts are never summed across frequencies.
@Observable
@MainActor
public final class RecurringViewModel {
    @ObservationIgnored
    @Injected(\.recurringRepository) private var recurringRepository
    @ObservationIgnored
    @Injected(\.authRepository) private var authRepository

    /// One row of the "Due now" list.
    ///
    /// `amountFormatted` is nil when the item has no amount — web renders
    /// nothing rather than a zero, because an amount-less commitment is a
    /// reminder, not a figure.
    public struct DueUiModel: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let nextDue: String
        public let amountFormatted: String?
    }

    public var netMonthlyMinor: Int64 = 0
    public var incomeMonthlyMinor: Int64 = 0
    public var expenseMonthlyMinor: Int64 = 0
    public var incomeCount: Int = 0
    public var expenseCount: Int = 0
    public var due: [DueUiModel] = []

    private var itemsTask: Task<Void, Never>?
    private var dueTask: Task<Void, Never>?
    private var busy = false

    /// Today, captured once at construction rather than read per emission. A
    /// value recomputed on every upstream tick would silently change what
    /// "due" means mid-session; the screen is rebuilt on the next launch.
    private let todayIso = isoToday()

    public init() { start() }

    /// Idempotent — safe from every `.onAppear`. Both streams are live
    /// `db.watch()`es, so a write from anywhere shows up here without any
    /// dependence on SwiftUI appear/disappear timing (the staleness bug
    /// GoalsViewModel documents at length).
    public func start() {
        guard itemsTask == nil else { return }

        itemsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await items in try self.recurringRepository.watchActiveItems() {
                    self.apply(items: items)
                }
            } catch {}
        }

        dueTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try self.recurringRepository.watchDueItems(todayIso: self.todayIso) {
                    self.due = rows.map { item in
                        DueUiModel(
                            id: item.id,
                            name: item.name,
                            nextDue: item.nextDue,
                            amountFormatted: item.amount.map {
                                formatMoney($0, item.currency ?? baseCurrencyNow())
                            }
                        )
                    }
                }
            } catch {}
        }
    }

    private func apply(items: [RecurringRepository.Item]) {
        func monthly(_ direction: String) -> Int64 {
            items
                .filter { $0.direction == direction }
                .reduce(Int64(0)) { $0 + monthlyEquivalent($1.amount ?? 0, $1.frequency) }
        }

        let income = monthly("income")
        // The column stores 'expense'; web's UI calls the same thing a
        // "payment". Only the label differs.
        let expense = monthly("expense")

        incomeMonthlyMinor = income
        expenseMonthlyMinor = expense
        // Savings are deliberately EXCLUDED, not merely unlisted. A SIP is a
        // transfer between your own accounts: the money leaves the current
        // account but not your net worth, so counting it as an outflow would
        // understate what you actually have spare.
        netMonthlyMinor = income - expense
        incomeCount = items.filter { $0.direction == "income" }.count
        expenseCount = items.filter { $0.direction == "expense" }.count
    }

    /// Confirm a due occurrence: post the transaction and advance `next_due`.
    ///
    /// Guarded because both buttons mutate the same row and a double-tap would
    /// post twice — the engine's catch-up guard protects against missed
    /// occurrences, not against the user.
    public func record(id: String) {
        guard !busy else { return }
        busy = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false }
            guard let userId = self.authRepository.currentUserId
                ?? (try? await self.authRepository.ensureUser()) else { return }
            // Quiet on failure for now: there is no error surface on this
            // screen yet, and the row stays due, so the failure is visible as
            // "it is still in the list".
            try? await self.recurringRepository.postOnce(
                id: id, userId: userId, baseCurrency: baseCurrencyNow()
            )
        }
    }

    /// Advance past one occurrence without posting anything.
    public func skip(id: String) {
        guard !busy else { return }
        busy = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false }
            try? await self.recurringRepository.skipOnce(id: id)
        }
    }
}
