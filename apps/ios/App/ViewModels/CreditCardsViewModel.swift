import Foundation
import Observation
import Factory
import Domain
import Data

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
    public let pendingDueFormatted: String?
    public let newSpend: Int64
    public let newSpendFormatted: String?
}

@Observable
@MainActor
public final class CreditCardsViewModel {
    @ObservationIgnored @Injected(\.creditCardRepository) private var creditCardRepository
    @ObservationIgnored @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored @Injected(\.loansRepository) private var loansRepository
    @ObservationIgnored @Injected(\.authRepository) private var authRepository

    public var cards: [CreditCardUiModel] = []
    public var sources: [SettleSourceOption] = []
    public var loaded: Bool = false
    /// Covered EMIs from the most recent settle() -- non-empty triggers the
    /// "Mark N EMI(s) paid?" confirm sheet.
    public var coveredEmis: [CoveredEmi] = []
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
        tasks = [accountsTask, detailsTask]
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

            guard let detail else {
                newCards.append(CreditCardUiModel(
                    id: ab.account.id, accountName: ab.account.name, accountColorHex: ab.account.color,
                    currency: currency, last4: nil, owed: owed, owedFormatted: formatMoneyGeneric(owed, currency),
                    creditLimit: nil, creditLimitFormatted: nil, availableCreditFormatted: nil,
                    hasCycle: false, statementDay: 1, dueDay: 20, statementDateIso: nil, payByIso: nil,
                    dueThisCycle: nil, dueThisCycleFormatted: nil, pendingDueFormatted: nil,
                    newSpend: 0, newSpendFormatted: nil
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
                pendingDueFormatted: detail.pendingDue.map { formatMoneyGeneric($0, currency) },
                newSpend: newSpend, newSpendFormatted: newSpend > 0 ? formatMoneyGeneric(newSpend, currency) : nil
            ))
        }
        cards = newCards
        loaded = true
    }

    /// Matches web's `saveCycle()`: statement/due day clamped 1-28, limit
    /// and typed due-amount go through `upsertDetails`/`setCycleDetails`
    /// (the latter recomputes `due_on` from the possibly-new cycle so
    /// "pay by" stays correct).
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

/// A fresh NumberFormatter per call, not cached -- matches this codebase's
/// established non-Sendable-Foundation-formatter rule.
private func formatMoneyGeneric(_ minor: Int64, _ currency: String) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = currency
    f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: Double(minor) / 100.0)) ?? "\(currency) \(Double(minor) / 100.0)"
}
