import Foundation
import Observation
import Factory
import Domain
import Data
import Supabase

/// Real port of apps/web/app/cards/page.tsx (task #29), replacing a fake
/// predecessor: hardcoded "Bank • Visa" network label, a fake "Day N" due
/// string instead of real billing-cycle math, a random alternating
/// gradient instead of the account's own color, no settle-up flow at all
/// (the "Pay Bill" button in the old CreditCardsView.swift was a literal
/// no-op `Button(action: {})`), no covered-EMI confirm, no editable
/// statement/due-day/limit/last4 form. See
/// docs/mobile/screen-specs/credit-cards.md and Android's
/// CreditCardsViewModel.kt (same session) for the mirrored implementation.
public struct SettleSourceOption: Identifiable, Sendable {
    public let id: String
    public let name: String
}

public struct CreditCardUiModel: Identifiable, Sendable {
    public let id: String // == accountId
    public let accountName: String
    public let accountColorHex: String?
    public let currency: String
    public let last4: String?
    public let owed: Int64
    public let owedFormatted: String
    public let creditLimit: Int64?
    public let creditLimitFormatted: String?
    public let availableCreditFormatted: String?
    public let hasCycle: Bool
    public let statementDay: Int
    public let dueDay: Int
    public let statementDateIso: String?
    public let payByIso: String?
    public let dueThisCycle: Int64?
    public let dueThisCycleFormatted: String?
    /// True when this card's statement due date has moved past the current
    /// cycle -- `dueThisCycle` is then 0 and `pendingDueFormatted` is what
    /// actually rolled forward. Mirrors Android's CreditCardUiModel.
    public let rolledToNext: Bool
    public let pendingDueFormatted: String?
    /// Seed text for the "amount due" input, in MAJOR units and unformatted.
    ///
    /// Web seeds its input with `String(toMajor(money(pending_due, ccy)))`; the
    /// same value has to reach the field here or a save that did not touch it
    /// would write null over the user's amount. A formatted string could not
    /// serve -- it carries a currency symbol, grouping and the privacy mask, so
    /// it is not something the user can type back.
    public let pendingDueMajorText: String
    /// Seed text for the "credit limit" input -- same reasoning as
    /// `pendingDueMajorText`.
    public let creditLimitMajorText: String
    public let newSpend: Int64
    public let newSpendFormatted: String?
    /// Charges behind the balance. Only the COUNT is carried here -- the rows
    /// themselves are read on demand when the user opens the list, so the view
    /// still knows whether to offer it.
    public let chargeCount: Int
}

/// One row of the "View transactions" list. `description` stays optional so the
/// view applies the localised fallback -- the same split already used for
/// `holderName`.
public struct CardChargeUiModel: Identifiable, Sendable {
    public let id: String
    public let description: String?
    public let amountFormatted: String
    public let occurredAtIso: String
}

/// The open "View transactions" list: the charges behind one card's balance
/// plus their running total, which is web's `chargesTotal`.
public struct CardChargesUiModel: Sendable {
    public let accountId: String
    public let rows: [CardChargeUiModel]
    public let totalFormatted: String
}

@Observable
@MainActor
public final class CreditCardsViewModel {
    @ObservationIgnored @Injected(\.creditCardRepository) private var creditCardRepository
    @ObservationIgnored @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored @Injected(\.loansRepository) private var loansRepository
    @ObservationIgnored @Injected(\.authRepository) private var authRepository
    @ObservationIgnored @Injected(\.supabaseClient) private var supabaseClient

    public var cards: [CreditCardUiModel] = []
    public var sources: [SettleSourceOption] = []
    public var loaded: Bool = false
    /// Covered EMIs from the most recent settle() -- non-empty triggers the
    /// "Mark N EMI(s) paid?" confirm sheet.
    public var coveredEmis: [CoveredEmi] = []
    /// The open "View transactions" list, or nil when it is closed. Held on the
    /// view model rather than in per-panel `@State` so the rows survive the
    /// list behind the modal re-rendering.
    public var charges: CardChargesUiModel?
    /// The signed-in user's display name, for the name printed on the card
    /// face. Web reads `session.username` and falls back to the `cardHolder`
    /// string only when it is blank, so this stays the RAW name and the view
    /// applies the fallback. Read once -- the name only changes from Settings.
    public var holderName: String = ""
    private var settledAt: String = ""

    private var tasks: [Task<Void, Never>] = []
    private var latestDetails: [CreditCardDetails] = []

    public init() { start() }

    public func start() {
        guard tasks.isEmpty else { return }
        let accountsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try self.ledgerRepository.watchAccounts(includeArchived: false)
                for try await _ in stream { await self.rebuild() }
            } catch { print("CreditCards: failed to watch accounts: \(error)") }
        }
        let detailsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try self.creditCardRepository.watchAllDetails()
                for try await details in stream {
                    self.latestDetails = details
                    await self.rebuild()
                }
            } catch { print("CreditCards: failed to watch details: \(error)") }
        }
        let holderTask = Task { [weak self] in
            guard let self else { return }
            // Signed-out / offline reads throw; an empty name just falls back
            // to the "Card Holder" label, so this must not take the screen down.
            guard let session = try? await self.supabaseClient.auth.session else { return }
            let name = session.user.userMetadata["username"]?.stringValue ?? ""
            self.holderName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        tasks = [accountsTask, detailsTask, holderTask]
    }

    public func cancel() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    private func rebuild() async {
        guard let balances = try? await ledgerRepository.accountBalances(includeArchived: false) else { return }
        let cardBalances = balances.filter { $0.account.type.lowercased() == "credit_card" }
        sources = balances
            .filter { $0.account.type.lowercased() != "credit_card" }
            .map { SettleSourceOption(id: $0.account.id, name: $0.account.name) }

        var detailsById: [String: CreditCardDetails] = [:]
        for d in latestDetails { detailsById[d.accountId] = d }
        let today = todayYmd()

        // Not `.map` -- building this per-card list needs an `await` (the
        // cycle-spend read) inside the loop, and Swift's stdlib `Array.map`
        // has no async variant.
        var newCards: [CreditCardUiModel] = []
        for ab in cardBalances {
            let detail = detailsById[ab.account.id]
            let owed = abs(ab.balance.amount)
            let currency = ab.account.currency
            // Hoisted out of the initialiser calls below: it is read on both
            // branches, and an `await` buried in an argument list is the kind
            // of line a reader has to parse twice.
            let chargeCount = (try? await creditCardRepository.chargeCount(accountId: ab.account.id)) ?? 0

            guard let detail else {
                newCards.append(CreditCardUiModel(
                    id: ab.account.id, accountName: ab.account.name, accountColorHex: ab.account.color,
                    currency: currency, last4: nil, owed: owed, owedFormatted: formatMoneyGeneric(owed, currency),
                    creditLimit: nil, creditLimitFormatted: nil, availableCreditFormatted: nil,
                    hasCycle: false, statementDay: 1, dueDay: 20, statementDateIso: nil, payByIso: nil,
                    dueThisCycle: nil, dueThisCycleFormatted: nil, rolledToNext: false,
                    pendingDueFormatted: nil,
                    pendingDueMajorText: "", creditLimitMajorText: "",
                    newSpend: 0, newSpendFormatted: nil,
                    chargeCount: chargeCount
                ))
                continue
            }

            let cycle = billingCycle(detail.statementDay, detail.dueDay, today)
            let newSpend = (try? await creditCardRepository.cycleSpend(accountId: ab.account.id, cycleStartIso: "\(cycle.cycleStart)T00:00:00.000Z")) ?? 0
            let dueOnYmd = detail.dueOn.flatMap { parseYmdLocal($0) } ?? cycle.dueDate
            let rolledToNext = detail.pendingDue != nil && dueOnYmd > cycle.dueDate
            let dueThisCycle: Int64? = detail.pendingDue == nil ? nil : (rolledToNext ? 0 : detail.pendingDue)
            let availableCredit = detail.creditLimit.map { max(0, $0 - owed) }

            newCards.append(CreditCardUiModel(
                id: ab.account.id, accountName: ab.account.name, accountColorHex: ab.account.color,
                currency: currency, last4: detail.cardLast4, owed: owed, owedFormatted: formatMoneyGeneric(owed, currency),
                creditLimit: detail.creditLimit, creditLimitFormatted: detail.creditLimit.map { formatMoneyGeneric($0, currency) },
                availableCreditFormatted: availableCredit.map { formatMoneyGeneric($0, currency) },
                hasCycle: true, statementDay: detail.statementDay, dueDay: detail.dueDay,
                statementDateIso: "\(cycle.statementDate)", payByIso: "\(dueOnYmd)",
                dueThisCycle: dueThisCycle, dueThisCycleFormatted: dueThisCycle.map { formatMoneyGeneric($0, currency) },
                rolledToNext: rolledToNext,
                pendingDueFormatted: detail.pendingDue.map { formatMoneyGeneric($0, currency) },
                // `formatMajorPlain`, not `formatMoney`: these two are typed
                // back into number fields, so no symbol, no grouping and no
                // privacy mask -- and the scale still comes from the currency,
                // not from 100.
                pendingDueMajorText: detail.pendingDue.map { formatMajorPlain($0, currency: currency) } ?? "",
                creditLimitMajorText: detail.creditLimit.map { formatMajorPlain($0, currency: currency) } ?? "",
                newSpend: newSpend, newSpendFormatted: newSpend > 0 ? formatMoneyGeneric(newSpend, currency) : nil,
                chargeCount: chargeCount
            ))
        }
        cards = newCards
        loaded = true
    }

    /// Matches web's `saveCycle()`: statement/due day clamped 1-28, limit and
    /// typed due-amount go through `upsertDetails`/`setCycleDetails` (the
    /// latter recomputes `due_on` from the possibly-new cycle so "pay by"
    /// stays correct).
    ///
    /// **Every nullable column this touches is a full overwrite, not a patch.**
    /// `upsertDetails` writes `credit_limit` and `card_last4`;
    /// `setCycleDetails` writes `pending_due` and `due_on`. So whatever the
    /// form holds IS the new row, and the view's contract is that the form was
    /// seeded from the stored detail before the user ever saw it -- see
    /// `seedFromCard()` in CreditCardsView.swift. `due_on` is the one column
    /// that can never go nil: it is recomputed from the cycle on every save.
    ///
    /// A blank amount-due field therefore still means "unset this", which is
    /// web's behaviour and the only way a user can clear a statement amount.
    /// `existingCreditLimit` keeps web's asymmetry: the limit falls back rather
    /// than clearing, because web's `saveCycle` does the same.
    public func saveCycle(
        accountId: String, currency: String, statementDayText: String, dueDayText: String,
        creditLimitMajorText: String, dueAmountMajorText: String, last4: String, existingCreditLimit: Int64?
    ) async -> String? {
        guard let userId = authRepository.currentUserId else { return "Couldn't determine the current user." }
        let sDay = min(28, max(1, Int(statementDayText) ?? 1))
        let dDay = min(28, max(1, Int(dueDayText) ?? 20))
        let creditLimit = Double(creditLimitMajorText).map { fromMajor($0, currency).amount } ?? existingCreditLimit
        let pendingDue = Double(dueAmountMajorText).map { fromMajor($0, currency).amount }
        do {
            try await creditCardRepository.upsertDetails(
                userId: userId,
                details: CreditCardDetails(
                    accountId: accountId, statementDay: sDay, dueDay: dDay, creditLimit: creditLimit,
                    cardLast4: String(last4.suffix(4)).isEmpty ? nil : String(last4.suffix(4))
                )
            )
            let cycle = billingCycle(sDay, dDay, todayYmd())
            try await creditCardRepository.setCycleDetails(accountId: accountId, pendingDue: pendingDue, dueOnIso: "\(cycle.dueDate)")
            return nil
        } catch {
            return "Couldn't save card details: \(error.localizedDescription)"
        }
    }

    /// Settle the bill, then check whether the payment covers any EMIs
    /// charged to this card -- if so, populate `coveredEmis` so the screen
    /// can ask before marking anything (never auto-marks).
    public func settle(cardAccountId: String, currency: String, fromAccountId: String, amountMajorText: String) async -> String? {
        guard let userId = authRepository.currentUserId else { return "Couldn't determine the current user." }
        guard let amountMajor = Double(amountMajorText), amountMajor > 0 else { return "Enter an amount." }
        let money = fromMajor(amountMajor, currency)
        let whenIso = ISO8601DateFormatter().string(from: Date())
        do {
            try await creditCardRepository.settle(userId: userId, fromAccountId: fromAccountId, cardAccountId: cardAccountId, amount: money, occurredAt: whenIso)
            let covered = try await loansRepository.findCoveredEmis(cardAccountId: cardAccountId, amountMinor: money.amount)
            if !covered.isEmpty {
                settledAt = whenIso
                coveredEmis = covered
            }
            return nil
        } catch {
            return "Couldn't settle: \(error.localizedDescription)"
        }
    }

    /// Load the charges behind `accountId`'s balance and open the list.
    ///
    /// The running total is the sum of the rows actually listed, exactly as
    /// web's `chargesTotal` is -- both are capped at `cardChargesLimit`, so a
    /// card with more charges than that shows the same total on both clients.
    public func openCharges(accountId: String, currency: String) {
        Task { [weak self] in
            guard let self else { return }
            let rows = (try? await self.creditCardRepository.charges(accountId: accountId)) ?? []
            let total = rows.reduce(Int64(0)) { $0 + $1.amount }
            self.charges = CardChargesUiModel(
                accountId: accountId,
                rows: rows.map {
                    CardChargeUiModel(
                        id: $0.id,
                        description: $0.description,
                        amountFormatted: formatMoneyGeneric($0.amount, currency),
                        occurredAtIso: $0.occurredAt
                    )
                },
                totalFormatted: formatMoneyGeneric(total, currency)
            )
        }
    }

    public func closeCharges() {
        charges = nil
    }

    public func confirmMarkEmisPaid() {
        guard !coveredEmis.isEmpty else { return }
        let covered = coveredEmis
        let when = settledAt
        Task { [weak self] in
            guard let self else { return }
            try? await self.loansRepository.markEmisPaid(covered: covered, paidOnIso: when)
            self.coveredEmis = []
        }
    }

    public func skipMarkEmisPaid() {
        coveredEmis = []
    }
}

private func todayYmd() -> Ymd {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = Date()
    return Ymd(
        year: calendar.component(.year, from: now),
        month: calendar.component(.month, from: now),
        day: calendar.component(.day, from: now)
    )
}

private func parseYmdLocal(_ iso: String) -> Ymd? {
    let s = String(iso.prefix(10))
    let parts = s.split(separator: "-")
    guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
    return Ymd(year: y, month: m, day: d)
}

private func formatMoneyGeneric(_ minor: Int64, _ currency: String) -> String {
    formatMoney(minor, currency)
}
