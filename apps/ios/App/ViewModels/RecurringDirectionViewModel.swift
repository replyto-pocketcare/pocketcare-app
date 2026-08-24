import Foundation
import Observation
import Factory
import Domain
import Data

/// One side of the recurring picture: Income or Expense.
///
/// **The slug is the USER-facing word**, pinned here and nowhere else, exactly
/// as web pins it in its own `SLUGS` table.
///
/// There is no `saving` case. A recurring saving is a SIP and belongs to the
/// holding it funds — created and stopped in Investments, not here.
public enum RecurringDirectionSlug: String, CaseIterable, Sendable {
    case income
    case expense

    /// The value stored in `recurring_items.direction`.
    var dbDirection: String { rawValue }

    static func from(_ slug: String?) -> RecurringDirectionSlug? {
        guard let slug else { return nil }
        return RecurringDirectionSlug(rawValue: slug.lowercased())
    }
}

/// Mirrors `apps/android/.../ui/recurring/RecurringDirectionViewModel.kt`.
@Observable
@MainActor
public final class RecurringDirectionViewModel {
    @ObservationIgnored
    @Injected(\.recurringRepository) private var recurringRepository
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored
    @Injected(\.authRepository) private var authRepository

    public struct CategorySlice: Identifiable, Equatable, Sendable {
        public let id: String
        /// Empty when `isUncategorised`; the view supplies the localised label.
        ///
        /// Web hardcodes the English "Uncategorised" in `summarise()`. A view
        /// model has no business holding localised strings, so the flag crosses
        /// the boundary and `S.Cashflow.noCategory` is resolved in the view.
        public let name: String
        public let isUncategorised: Bool
        /// 0...100, already rounded — the view does no arithmetic.
        public let sharePct: Int
    }

    public struct ItemUiModel: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let subtitle: String
        public let amountFormatted: String
    }

    public private(set) var monthlyFormatted = ""
    public private(set) var categories: [CategorySlice] = []
    public private(set) var items: [ItemUiModel] = []

    private let slug: RecurringDirectionSlug
    private var itemsTask: Task<Void, Never>?
    private var categoriesTask: Task<Void, Never>?
    private var latestItems: [RecurringRepository.Item] = []
    private var categoryNames: [String: String] = [:]
    private var busy = false

    /// Group key for items with no category. Never a real category id.
    private static let uncategorised = "uncategorised"

    public init(slug: RecurringDirectionSlug) {
        self.slug = slug
        start()
    }

    public func start() {
        guard itemsTask == nil else { return }
        itemsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try self.recurringRepository.watchActiveItems() {
                    self.latestItems = rows
                    self.rebuild()
                }
            } catch {}
        }
        categoriesTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await cats in try self.ledgerRepository.watchCategories() {
                    self.categoryNames = Dictionary(
                        cats.map { ($0.id, $0.name) },
                        uniquingKeysWith: { first, _ in first }
                    )
                    self.rebuild()
                }
            } catch {}
        }
    }

    private func rebuild() {
        let base = baseCurrencyNow()
        let mine = latestItems.filter { $0.direction == slug.dbDirection }

        // Monthly equivalents throughout -- never sum raw amounts across
        // frequencies. Same vector-tested helper the summary card uses.
        var perMonth: [String: Int64] = [:]
        for item in mine {
            perMonth[item.id] = monthlyEquivalent(item.amount ?? 0, item.frequency)
        }
        let monthly = perMonth.values.reduce(Int64(0), +)
        monthlyFormatted = formatMoney(monthly, base)

        var byCategory: [String: Int64] = [:]
        for item in mine {
            let key = item.categoryId ?? Self.uncategorised
            byCategory[key, default: 0] += perMonth[item.id] ?? 0
        }
        categories = byCategory
            .sorted { $0.value > $1.value }
            .map { key, amount in
                CategorySlice(
                    id: key,
                    name: key == Self.uncategorised ? "" : (categoryNames[key] ?? ""),
                    isUncategorised: key == Self.uncategorised,
                    // A zero total means no shares rather than a division by zero.
                    sharePct: monthly > 0 ? Int((Double(amount) * 100.0 / Double(monthly)).rounded()) : 0
                )
            }

        items = mine.map { item in
            var parts = [item.frequency]
            if let categoryId = item.categoryId, let name = categoryNames[categoryId], !name.isEmpty {
                parts.append(name)
            }
            if !item.nextDue.isEmpty { parts.append(item.nextDue) }
            return ItemUiModel(
                id: item.id,
                name: item.name,
                subtitle: parts.joined(separator: " · "),
                amountFormatted: formatMoney(item.amount ?? 0, item.currency ?? base)
            )
        }
    }

    /// Post one occurrence now and advance.
    public func recordNow(id: String) {
        guard !busy else { return }
        busy = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false }
            guard let userId = await self.resolveUserId() else { return }
            try? await self.recurringRepository.postOnce(
                id: id, userId: userId, baseCurrency: baseCurrencyNow()
            )
        }
    }

    /// Stop the commitment. Soft delete — see `RecurringRepository.remove`.
    public func remove(id: String) {
        guard !busy else { return }
        busy = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false }
            try? await self.recurringRepository.remove(id: id)
        }
    }

    /// Spelled out, not `currentUserId ?? (try? await ensureUser())` — `??`'s
    /// right side is an `@autoclosure` and cannot contain an `await`.
    private func resolveUserId() async -> String? {
        if let existing = authRepository.currentUserId { return existing }
        return try? await authRepository.ensureUser()
    }
}
