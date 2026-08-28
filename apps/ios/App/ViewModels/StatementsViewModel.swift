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
///
/// The rows are `TransactionListItem`s — the same model Transactions, Search
/// and the dashboard's recent activity render, because web renders one
/// `<TransactionTile>` on all four. The one substitution is the right-hand
/// meta: web's Statements passes the TIME there rather than the date, because
/// the date is already the header of the group the row sits in.
@Observable
@MainActor
public final class StatementsViewModel {
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored
    @Injected(\.prefsRepository) private var prefsRepository

    /// One calendar day of the statement — web's `groupTxnsByDay`.
    ///
    /// The day is the LOCAL calendar day, not `occurred_at.slice(0, 10)`. Web
    /// slices the stored UTC timestamp, so east of Greenwich a 02:00 purchase
    /// is filed under yesterday's header while the row beside it prints
    /// "2:00 AM" — the header and its own rows disagree. The rows here read
    /// local (that is what `transactionListItem` already does), so the header
    /// does too.
    public struct DayGroup: Identifiable, Sendable {
        /// The local `yyyy-MM-dd`, which is also the group's identity.
        public let id: String
        public let label: String
        /// Day net, sign stripped — the view prepends + or − from `isPositive`.
        public let netFormatted: String
        public let isPositive: Bool
        public let items: [TransactionListItem]
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
    /// Web's third summary row — a plain count, not money.
    public private(set) var transactionCount = 0
    public private(set) var days: [DayGroup] = []

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
    private var accountsTask: Task<Void, Never>?
    private var categoriesTask: Task<Void, Never>?
    private var labelsTask: Task<Void, Never>?

    /// The last value of every stream the rows are built from.
    ///
    /// Four independent watches feed one derived list, so each of them stores
    /// what it saw and asks for a rebuild. Combining them into one stream is
    /// Android's shape because Kotlin has `combine`; Swift's `AsyncSequence`
    /// has no equivalent that keeps the latest of each, and hand-rolling one
    /// here would be a concurrency primitive living in a screen.
    private var rows: [TransactionRow] = []
    private var accountMap: [String: Account] = [:]
    private var categoryMap: [String: CategoryRow] = [:]
    private var labelNames: [String: [String]] = [:]

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
        startContext()
        restartRows()
    }

    /// The three range-independent watches the row model needs: accounts for
    /// the account line, categories for the category tag, labels for the rest.
    /// One task each, matching every other view model here — nudging a date
    /// restarts only `rowsTask`, never these.
    private func startContext() {
        guard accountsTask == nil else { return }

        accountsTask = Task { [weak self] in
            guard let self else { return }
            do {
                // includeArchived: an archived account still names the row that
                // was posted to it. Hiding the name would not un-spend the
                // money.
                for try await list in try self.ledgerRepository.watchAccounts(includeArchived: true) {
                    // `uniquingKeysWith` rather than `uniqueKeysWithValues`:
                    // the latter TRAPS on a duplicate id, and a screen is not
                    // the place to crash over a row the sync layer let through.
                    self.accountMap = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
                    self.rebuild()
                }
            } catch {}
        }

        categoriesTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await list in try self.ledgerRepository.watchCategories() {
                    self.categoryMap = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
                    self.rebuild()
                }
            } catch {}
        }

        labelsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await map in try self.ledgerRepository.watchTransactionLabelNames() {
                    self.labelNames = map
                    self.rebuild()
                }
            } catch {}
        }
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
                    self.rows = rows
                    self.rebuild()
                }
            } catch {}
        }
    }

    private func rebuild() {
        let base = baseCurrencyNow()
        let income = rows.filter { $0.type == "income" }.reduce(Int64(0)) { $0 + $1.amount }
        let expense = rows.filter { $0.type == "expense" }.reduce(Int64(0)) { $0 + $1.amount }
        let net = income - expense

        incomeFormatted = formatMoney(income, base)
        expenseFormatted = formatMoney(expense, base)
        netFormatted = formatMoney(abs(net), base)
        netIsPositive = net >= 0
        transactionCount = rows.count

        let grouped = Dictionary(grouping: rows) { Self.localDay($0.occurredAt) }
        // Newest day first, and newest row first inside it — web's
        // `.sort((a, b) => b[0].localeCompare(a[0]))` and the same on the rows.
        days = grouped.keys.sorted(by: >).map { day in
            let items = (grouped[day] ?? []).sorted { $0.occurredAt > $1.occurredAt }
            let dayNet = items.reduce(Int64(0)) { total, row in
                switch row.type {
                case "income": return total + row.amount
                case "expense": return total - row.amount
                default: return total
                }
            }
            return DayGroup(
                id: day,
                label: Self.dayLabel(day),
                netFormatted: formatMoney(abs(dayNet), base),
                isPositive: dayNet >= 0,
                items: items.map { row in
                    let built = transactionListItem(
                        row,
                        accountMap: accountMap,
                        categoryMap: categoryMap,
                        labels: labelNames[row.id]
                    )
                    // Web's Statements passes a TIME as the row's meta, not a
                    // date: the date is the header this row already sits under,
                    // and repeating it on every line says nothing. The rest of
                    // the model is the shared builder's, untouched.
                    return TransactionListItem(
                        id: built.id,
                        title: built.title,
                        subtitle: built.subtitle,
                        tagsText: built.tagsText,
                        accountName: built.accountName,
                        amountFormatted: built.amountFormatted,
                        isPositive: built.isPositive,
                        isSplit: built.isSplit,
                        // Always false here. Web draws the "Scanned" pill on
                        // the Transactions list and nowhere else, and this
                        // screen has no `receipt_scans` watch to answer it
                        // from -- see `transactionListItem`'s `scanned`
                        // parameter.
                        isScanned: false,
                        dateFormatted: Self.timeLabel(row.occurredAt),
                        avatarLetter: built.avatarLetter
                    )
                }
            )
        }
    }

    /// The statement, as plain text, for `ShareLink`.
    ///
    /// Web prints the page; a phone has no printer dialog, so the same intent —
    /// get this statement out of the app — becomes a share. Every figure in it
    /// is already through `formatMoney`, so the hide-amounts privacy toggle
    /// applies to what leaves the app exactly as it does on screen.
    public var shareText: String {
        var out = [
            S.Statements.statementName,
            "\(shortDateLabel(startDate)) – \(shortDateLabel(endDate))",
            "",
            "\(S.Statements.income): \(incomeFormatted)",
            "\(S.Statements.expenses): \(expenseFormatted)",
            "\(S.Statements.transactions): \(transactionCount)",
            "\(S.Statements.netForPeriod): \(netIsPositive ? "+" : "\u{2212}")\(netFormatted)",
        ]
        for day in days {
            out.append("")
            out.append("\(day.label)  \(day.isPositive ? "+" : "\u{2212}")\(day.netFormatted)")
            for item in day.items {
                out.append("  \(item.title)  \(item.dateFormatted)  \(item.amountFormatted)")
            }
        }
        return out.joined(separator: "\n")
    }

    /// The local calendar day a timestamp fell on, as `yyyy-MM-dd`.
    ///
    /// Falls back to the stored date part when the string is not a timestamp
    /// this can parse — the same defensive shape `transactionListItem` uses,
    /// because a row that cannot be parsed still has to land in some group.
    private static func localDay(_ occurredAt: String) -> String {
        guard let date = parseOccurredAt(occurredAt) else { return String(occurredAt.prefix(10)) }
        return IsoDay.string(from: date)
    }

    /// Today / Yesterday / "23 Aug 26" — web's `groupTxnsByDay` labels.
    ///
    /// Resolved here rather than handed to the view as a flag, which is where
    /// Android puts it: Swift's generated accessors read the bundle with no
    /// context, so a view model naming a string costs nothing, while Kotlin's
    /// need a `Resources` a view model must not hold. `transactionListItem`
    /// already splits the same way on the same line.
    private static func dayLabel(_ day: String) -> String {
        if day == IsoDay.today() { return S.Statements.today }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        if let yesterday, day == IsoDay.string(from: yesterday) { return S.Statements.yesterday }
        // Web's `{ day: "numeric", month: "short", year: "2-digit" }`.
        return isoLabel(day, "d MMM yy")
    }

    /// "2:30 PM" — web's `toLocaleTimeString(undefined, { hour: "numeric",
    /// minute: "2-digit" })`. `.short` rather than a format string: whether the
    /// clock is 12- or 24-hour is a locale fact, and a pattern picks one for
    /// everybody.
    private static func timeLabel(_ occurredAt: String) -> String {
        guard let date = parseOccurredAt(occurredAt) else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
