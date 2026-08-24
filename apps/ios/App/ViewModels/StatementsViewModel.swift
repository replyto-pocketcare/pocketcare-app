import Foundation
import Observation
import Factory
import Domain
import Data

/// Statements — ported from apps/web/app/statements/page.tsx.
/// Mirrors `apps/android/.../ui/statements/StatementsViewModel.kt`.
///
/// **The view this replaces was a completely different, invented feature** — a
/// searchable list of "July 2026" / "2025 Annual Statement" cards, with a
/// premium padlock on the annual one. No such documents exist anywhere in this
/// product; there is no statement-generation feature to list. Web's Statements
/// is a *date-ranged* view of real transactions with an income/expense summary,
/// behind the paid gate. Android had no screen at all, which was at least
/// honest about it.
@Observable
@MainActor
public final class StatementsViewModel {
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored
    @Injected(\.prefsRepository) private var prefsRepository

    public struct TxUiModel: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let occurredOn: String
        public let amountFormatted: String
        public let isIncome: Bool
    }

    public private(set) var isPaid = false
    /// False until the entitlement row has actually been read once.
    ///
    /// The view shows neither the statement nor the upsell while this is false.
    /// Defaulting `isPaid` to false and rendering immediately would flash
    /// "Go Premium" at a paying user on every cold start, before the local
    /// entitlement row has been read — a small thing that reads as being asked
    /// to pay twice.
    public private(set) var entitlementKnown = false

    public private(set) var incomeFormatted = ""
    public private(set) var expenseFormatted = ""
    public private(set) var netFormatted = ""
    public private(set) var netIsPositive = true
    public private(set) var transactions: [TxUiModel] = []

    /// Defaults to this calendar month so far, exactly as web does.
    ///
    /// Named `startDate`/`endDate` rather than `start`/`end` because `start()`
    /// is the observation entry point every view model here has, and a stored
    /// property cannot share a name with a method.
    public var startDate: String {
        didSet {
            // Web drags the far end along rather than rejecting the input,
            // which is the kinder behaviour: the user is mid-thought, not
            // making a mistake. Assigning `endDate` re-enters its own didSet
            // and restarts the query there, so this returns early to avoid
            // starting the same watch twice.
            if startDate > endDate { endDate = startDate; return }
            restartRows()
        }
    }

    public var endDate: String {
        didSet {
            if endDate < startDate { endDate = startDate; return }
            restartRows()
        }
    }

    private var entitlementTask: Task<Void, Never>?
    private var rowsTask: Task<Void, Never>?

    public init() {
        let today = isoToday()
        // "2026-08-24" -> "2026-08-01". prefix(8) keeps "YYYY-MM-".
        self.startDate = String(today.prefix(8)) + "01"
        self.endDate = today
        start()
    }

    public func start() {
        guard entitlementTask == nil else { return }
        entitlementTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await row in try self.prefsRepository.watchEntitlement() {
                    self.isPaid = Domain.isPaid(
                        tier: row?.tier,
                        premiumTrialStartDate: row?.premiumTrialStartDate,
                        compTier: row?.compTier,
                        compUntil: row?.compUntil,
                        now: Date()
                    )
                    self.entitlementKnown = true
                }
            } catch {
                // Offline or unreadable: keep the gate CLOSED rather than
                // guessing it open, and leave `entitlementKnown` false so the
                // view shows nothing instead of the upsell.
            }
        }
        restartRows()
    }

    private func restartRows() {
        rowsTask?.cancel()
        let from = startDate
        // `end` advanced one whole day, matching web: occurred_at is a
        // timestamp, so `< end` on the bare date would drop everything that
        // happened after midnight on the final day.
        guard let to = nextDayIso(endDate) else { return }
        rowsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try self.ledgerRepository.watchTransactionsInRange(
                    startIso: "\(from)T00:00:00.000Z",
                    endIso: "\(to)T00:00:00.000Z"
                ) {
                    self.apply(rows)
                }
            } catch {}
        }
    }

    private func apply(_ rows: [TransactionRow]) {
        let base = baseCurrencyNow()
        let income = rows.filter { $0.type == "income" }.reduce(Int64(0)) { $0 + $1.amount }
        let expense = rows.filter { $0.type == "expense" }.reduce(Int64(0)) { $0 + $1.amount }
        let net = income - expense

        incomeFormatted = formatMoney(income, base)
        expenseFormatted = formatMoney(expense, base)
        netFormatted = formatMoney(abs(net), base)
        netIsPositive = net >= 0
        transactions = rows.map { t in
            TxUiModel(
                id: t.id,
                // Web's TransactionTile falls back through description then
                // note; an untitled row shows blank rather than as an invented
                // label.
                title: t.description?.isEmpty == false ? t.description!
                    : (t.note?.isEmpty == false ? t.note! : ""),
                occurredOn: String(t.occurredAt.prefix(10)),
                amountFormatted: formatMoney(t.amount, t.currency),
                isIncome: t.type == "income"
            )
        }
    }

    /// One day after a YYYY-MM-DD date, in UTC. Nil only if the input is not a date.
    private func nextDayIso(_ iso: String) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]; components.month = parts[1]; components.day = parts[2]
        guard let date = calendar.date(from: components),
              let next = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
        let out = calendar.dateComponents([.year, .month, .day], from: next)
        return String(format: "%04d-%02d-%02d", out.year ?? 0, out.month ?? 1, out.day ?? 1)
    }
}
