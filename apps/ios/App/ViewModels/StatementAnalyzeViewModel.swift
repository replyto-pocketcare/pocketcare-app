import Foundation
import Observation
import Factory
import Domain
import Data

/// The statement analyzer — parse a bank or card export on the device, analyse
/// it, reconcile it against what is already recorded, and import what is
/// missing.
///
/// Ported from `apps/web/app/statements/analyze/page.tsx`. Every number on the
/// screen comes from Domain's `StatementCsv`/`StatementAnalysis`/
/// `StatementReconcile`, all vector-pinned; this holds the screen's state and
/// the four repository calls.
///
/// **Nothing leaves the device**, which is the claim web's header makes and the
/// reason the parse, the categorisation and the reconciliation all happen here
/// rather than behind an endpoint.
@MainActor
@Observable
public final class StatementAnalyzeViewModel {
    @ObservationIgnored @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored @Injected(\.recurringRepository) private var recurringRepository
    @ObservationIgnored @Injected(\.authRepository) private var authRepository

    // ---- picker state ----
    /// "bank" | "card".
    public var kind = "bank"
    public var accountId = ""
    public var accounts: [Account] = []
    /// A short label while a file is being read, or nil.
    public private(set) var busy: String?
    public private(set) var error: String?

    /// Surfaced by the view's file picker, which is the only place a read can
    /// fail before this type has anything to say.
    public func setError(_ message: String) { error = message }

    // ---- results ----
    public private(set) var parsed: ParsedStatement?
    public private(set) var reconciliation: Reconciliation?
    public private(set) var recordedCount = 0
    public private(set) var imported = false
    public private(set) var addedRecurring: Set<String> = []
    public var showAllTransactions = false

    private var tasks: [Task<Void, Never>] = []

    public init() {}

    public func start() {
        guard tasks.isEmpty else { return }
        tasks.append(Task { [weak self] in
            guard let self else { return }
            do {
                for try await list in try self.ledgerRepository.watchAccounts() { self.accounts = list }
            } catch { /* the analyzer works without an account; reconcile does not */ }
        })
    }

    public func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    public var accountName: String {
        accounts.first { $0.id == accountId }?.name ?? ""
    }

    public var currency: String {
        parsed?.currency ?? baseCurrencyNow()
    }

    /// Start over with a new file.
    public func reset() {
        parsed = nil
        reconciliation = nil
        imported = false
        addedRecurring = []
        showAllTransactions = false
        error = nil
    }

    // MARK: - Parse

    /// Parse a picked CSV, categorise its spends, and reconcile.
    ///
    /// `readFailMessage` and `parsingLabel` are passed in rather than read from
    /// `S` here for the usual reason — this type has no business holding the
    /// localisation surface — and because the same two strings are used by the
    /// view's error state.
    public func parse(text: String, parsingLabel: String, categorisingLabel: String, readFailMessage: String) {
        error = nil
        parsed = nil
        reconciliation = nil
        imported = false
        busy = parsingLabel

        Task { [weak self] in
            guard let self else { return }
            defer { self.busy = nil }
            let base = baseCurrencyNow()
            var statement = parseStatementCsv(text, currency: base, kind: self.kind)

            self.busy = categorisingLabel
            statement = await self.categorise(statement)
            self.parsed = statement

            await self.reconcileNow(statement)
            if statement.txns.isEmpty && statement.warnings.isEmpty {
                self.error = readFailMessage
            }
        }
    }

    /// On-device categorisation of the spends.
    ///
    /// The classifier is built ONCE and then run over every row in memory,
    /// which is the whole reason `BulkClassifier` exists — a per-row query would
    /// turn a 400-line statement into 400 round-trips against a database the UI
    /// is also reading. Web says the same in its own comment.
    ///
    /// Failure is swallowed: a statement that could not be categorised is still
    /// a statement worth showing, and web treats the categoriser as optional
    /// here for exactly that reason.
    private func categorise(_ statement: ParsedStatement) async -> ParsedStatement {
        guard !statement.txns.isEmpty else { return statement }
        var uid = authRepository.currentUserId
        if uid == nil { uid = try? await authRepository.ensureUser() }
        guard let userId = uid else { return statement }
        guard let categoryRows = try? await ledgerRepository.listCategories(),
              let rules = try? await ledgerRepository.listCategoryRules(userId: userId)
        else { return statement }

        let categories = categoryRows.map { CategoryData(id: $0.id, name: $0.name) }
        let nameById = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let classifier = BulkClassifier(rules: rules, categories: categories)

        let txns = statement.txns.map { txn -> StatementTxn in
            // Only spends. A salary credit is not a "Food & Dining" row just
            // because the payer's name happens to contain a seed keyword.
            guard txn.amount < 0, let id = classifier.classify(txn.description), let name = nameById[id] else {
                return txn
            }
            return StatementTxn(
                date: txn.date, description: txn.description, amount: txn.amount,
                balance: txn.balance, category: name, ref: txn.ref
            )
        }
        return ParsedStatement(
            kind: statement.kind, label: statement.label, currency: statement.currency,
            period: statement.period, openingBalance: statement.openingBalance,
            closingBalance: statement.closingBalance, txns: txns, card: statement.card,
            warnings: statement.warnings, mapping: statement.mapping
        )
    }

    // MARK: - Reconcile

    public func accountChanged() {
        guard let statement = parsed else { return }
        Task { [weak self] in await self?.reconcileNow(statement) }
    }

    private func reconcileNow(_ statement: ParsedStatement) async {
        guard !accountId.isEmpty, let from = statement.period.from, let to = statement.period.to else {
            reconciliation = nil
            recordedCount = 0
            return
        }
        // The window is padded on the `to` end by the reconciler's own day
        // window, matching web's `addDays(to, 4)`: a row dated the last day of
        // the statement can legitimately match one recorded four days later.
        let paddedTo = addDaysIso(to, reconcileDayWindow) ?? to
        guard let recorded = try? await ledgerRepository.listRecordedForReconcile(
            accountId: accountId, fromIso: from, toIso: paddedTo
        ) else { return }
        recordedCount = recorded.count
        reconciliation = reconcileStatement(statement.txns, recorded)
    }

    // MARK: - Actions

    /// Import everything in the statement that is not already recorded.
    public func importMissing() {
        guard let rec = reconciliation, !accountName.isEmpty, !rec.missingOnPlatform.isEmpty else { return }
        let name = accountName
        let cur = currency
        Task { [weak self] in
            guard let self else { return }
            var uid = self.authRepository.currentUserId
            if uid == nil { uid = try? await self.authRepository.ensureUser() }
            guard let userId = uid else { return }
            let rows = rec.missingOnPlatform.map { t in
                CanonRow(
                    // Midday, not midnight: an occurred_at of 00:00 lands on the
                    // previous day for every user west of UTC once SQLite reads
                    // it back. Web picks the same hour for the same reason.
                    date: "\(t.date)T12:00:00",
                    type: t.amount < 0 ? "expense" : "income",
                    amount: abs(toMajor(money(t.amount, cur))),
                    currency: cur,
                    account: name,
                    category: t.category,
                    description: t.description
                )
            }
            // skipDuplicates: false — the reconciler has ALREADY established
            // that none of these is recorded, and a second, weaker dedupe here
            // would silently drop two genuinely identical coffees on the same
            // day. Web passes the same flag.
            _ = try? await self.ledgerRepository.importTransactions(
                userId: userId, rows: rows, baseCurrency: baseCurrencyNow(),
                nowIso: nowIso(), skipDuplicates: false
            )
            self.imported = true
        }
    }

    /// Turn a detected pattern into a real recurring commitment.
    public func addRecurring(_ candidate: RecurringCandidate) {
        guard !addedRecurring.contains(candidate.key) else { return }
        let cur = currency
        let accId = accountId.isEmpty ? nil : accountId
        Task { [weak self] in
            guard let self else { return }
            var uid = self.authRepository.currentUserId
            if uid == nil { uid = try? await self.authRepository.ensureUser() }
            guard let userId = uid else { return }
            let frequency: String
            switch candidate.cadence {
            case "weekly": frequency = "weekly"
            case "yearly": frequency = "yearly"
            default: frequency = "monthly"
            }
            _ = try? await self.recurringRepository.create(userId: userId, input: RecurringRepository.Input(
                direction: "payment",
                // 40 characters, web's cap. A bank narration is often the whole
                // POS dump and would make the recurring list unreadable.
                name: String(candidate.label.prefix(40)),
                amountMinor: candidate.amount,
                currency: cur,
                accountId: accId,
                frequency: frequency,
                firstDue: String(nowIso().prefix(10)),
                autoPost: false
            ))
            self.addedRecurring.insert(candidate.key)
        }
    }
}
