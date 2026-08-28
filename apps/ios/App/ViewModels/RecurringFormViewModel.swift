import Foundation
import Observation
import Factory
import Domain
import Data

/// Create / edit a recurring income or payment.
///
/// Ported from `apps/web/src/cashflow/RecurringModal.tsx`. Mirrors
/// `apps/android/.../ui/recurring/RecurringFormViewModel.kt`.
///
/// **Recurring SAVINGS are not created here**, matching web: a SIP is a
/// transfer into an investment account and is set up in Investments, next to
/// the holding it funds. The engine still posts `saving` items — this form just
/// isn't how they are born.
@Observable
@MainActor
public final class RecurringFormViewModel {
    @ObservationIgnored
    @Injected(\.recurringRepository) private var recurringRepository
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored
    @Injected(\.authRepository) private var authRepository

    public struct PickerOption: Identifiable, Equatable, Sendable {
        public let id: String
        public let label: String
    }

    public private(set) var accounts: [PickerOption] = []
    public private(set) var categories: [PickerOption] = []
    public private(set) var busy = false
    public private(set) var error: String?

    // Form fields.
    public var name = ""
    public var amount = ""
    public var accountId: String?
    public var categoryId: String?
    public var frequency = "monthly"
    public var firstDue = isoToday()
    /// "HH:MM" in the DEVICE's zone. Converted to UTC once, at save.
    ///
    /// `utcToLocalTime(nil)` rather than a literal "09:00": web's
    /// `utcToLocalTime(edit?.alert_time_utc)` returns the same default for a row
    /// that has none, and routing through the one helper keeps the default in a
    /// single place instead of two that can drift.
    public var alertTimeLocal = utcToLocalTime(nil)
    public var autoPost = false

    public let slug: RecurringDirectionSlug
    public let editingId: String?
    private var accountsTask: Task<Void, Never>?
    private var categoriesTask: Task<Void, Never>?
    private var itemTask: Task<Void, Never>?
    private var prefilled = false

    /// Web's `FREQS`, which is the same list as the generated
    /// `FormOptions.periods`. Referenced rather than retyped so it cannot drift
    /// from the catalogue.
    public static var frequencies: [String] { FormOptions.periods }

    public init(slug: RecurringDirectionSlug, editingId: String? = nil) {
        self.slug = slug
        self.editingId = editingId
        start()
    }

    public func start() {
        guard accountsTask == nil else { return }

        accountsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try self.ledgerRepository.watchAccounts(includeArchived: false) {
                    // Real spending accounts only. Web filters with
                    // isInvestmentAccount for the same reason: a recurring
                    // payment cannot come out of a holding, and offering one
                    // produces a row the engine then fails to post.
                    self.accounts = rows
                        .filter { !FormOptions.isInvestmentAccount($0.type) }
                        .map { PickerOption(id: $0.id, label: $0.name) }
                    if self.editingId == nil, self.accountId == nil {
                        self.accountId = self.accounts.first?.id
                    }
                }
            } catch {}
        }

        categoriesTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try self.ledgerRepository.watchCategories() {
                    // Expense categories only — web filters `c.kind === "expense"`.
                    // The picker only shows for a payment, and an income
                    // category in it would write a row that no expense
                    // breakdown can then read.
                    self.categories = rows
                        .filter { $0.kind == "expense" }
                        .map { PickerOption(id: $0.id, label: $0.name) }
                }
            } catch {}
        }

        guard let editingId else { return }
        itemTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await items in try self.recurringRepository.watchActiveItems() {
                    // Fill once. Re-running on every emission would overwrite
                    // what the user is typing each time the watch re-fires.
                    guard !self.prefilled, let item = items.first(where: { $0.id == editingId })
                    else { continue }
                    self.prefilled = true
                    self.name = item.name
                    self.amount = item.amount.map { Self.majorText($0, baseCurrencyNow()) } ?? ""
                    self.accountId = item.accountId
                    self.categoryId = item.categoryId
                    self.frequency = item.frequency
                    self.firstDue = item.nextDue
                    // Stored UTC, shown local -- web's
                    // `utcToLocalTime(edit?.alert_time_utc)`.
                    self.alertTimeLocal = utcToLocalTime(item.alertTimeUtc)
                    self.autoPost = item.autoPost
                }
            } catch {}
        }
    }

    public var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && Double(amount) != nil
            && !(accountId ?? "").isEmpty
    }

    public func save(onSaved: @escaping () -> Void) {
        guard !busy, canSave, let major = Double(amount), let accountId else { return }
        busy = true
        error = nil
        let currency = baseCurrencyNow()
        let isPayment = slug == .expense

        Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false }
            let input = RecurringRepository.Input(
                direction: isPayment ? "expense" : "income",
                name: self.name,
                // fromMajor, not `* 100`. Web hardcodes the ×100 here and is
                // wrong for JPY (no minor units) and BHD (three) — fromMajor
                // asks minorUnits(currency), which is golden rule 1.
                amountMinor: fromMajor(major, currency).amount,
                currency: currency,
                accountId: accountId,
                // Web attaches a category to payments only; an income category
                // would show up in expense breakdowns.
                categoryId: isPayment ? self.categoryId : nil,
                frequency: self.frequency,
                firstDue: self.firstDue,
                autoPost: self.autoPost,
                // Was hardcoded null, which is what made every recurring item
                // silently unremindable: the engine reads this column to decide
                // WHEN to nudge, and a null is "never". Converted here, once,
                // at the boundary -- the same helper every other alert-carrying
                // form in this app (budgets, goals, loans) uses.
                alertTimeUtc: localToUtcTime(self.alertTimeLocal)
            )
            do {
                if let editingId = self.editingId {
                    try await self.recurringRepository.update(id: editingId, input: input)
                } else {
                    // Not `?: return`. A bare return is the silent no-op this
                    // audit has already found four times: the button clears its
                    // busy state and nothing was written. `ensureUser()` throws,
                    // so a genuine failure lands in the catch below and the user
                    // sees it.
                    let userId = try await self.resolveUserId()
                    try await self.recurringRepository.create(userId: userId, input: input)
                }
                onSaved()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Minor units back to an editable major-unit string, for the edit prefill.
    /// `minorUnits(currency)` rather than a hardcoded 100, same as the save path.
    private static func majorText(_ minor: Int64, _ currency: String) -> String {
        let units = minorUnits(currency)
        if units == 0 { return String(minor) }
        return String(Double(minor) / pow(10.0, Double(units)))
    }

    /// Spelled out, not `currentUserId ?? (try await ensureUser())` — `??`'s
    /// right side is an `@autoclosure` and cannot contain an `await`.
    private func resolveUserId() async throws -> String {
        if let existing = authRepository.currentUserId { return existing }
        return try await authRepository.ensureUser()
    }
}
