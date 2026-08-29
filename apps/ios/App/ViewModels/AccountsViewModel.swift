import Foundation
import Observation
import Factory
import PowerSync
import Domain
import Data

/// Accounts list — ported from apps/web/app/accounts/page.tsx per
/// docs/mobile/screen-specs/accounts.md. Rewritten 2026-08-05: the previous
/// version only had id/name/typeLabel/balance -- missing color, archived
/// state + toggle, per-account net-worth toggle, all required by the real
/// screen. Mirrors Android's AccountsViewModel.kt.
@Observable
@MainActor
public final class AccountsViewModel {
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored
    @Injected(\.powerSyncDatabase) private var db

    public struct AccountUiModel: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let type: String
        public let currency: String
        public let color: String?
        public let balanceFormatted: String
        public let isArchived: Bool
        public let includeInNetWorth: Bool
    }

    /// One currency's share of net worth -- a row of the "Across currencies"
    /// card. `native` is the total in the currency the accounts are actually
    /// held in; `base` is that value converted to the user's base currency,
    /// which is the only thing the shares can be computed against.
    ///
    /// Deliberately NOT `Identifiable`: this type is nested inside a
    /// `@MainActor` class, so a computed `id` would infer main-actor isolation
    /// and could not satisfy the protocol's nonisolated requirement. The views
    /// key their `ForEach` on `currency` instead, which is unique by
    /// construction (the breakdown is grouped by it).
    public struct CurrencySliceUiModel: Equatable {
        public let currency: String
        public let nativeFormatted: String
        public let baseFormatted: String
        /// No "≈ base" line is drawn for the base currency itself -- it would
        /// restate the amount already shown. Matches web.
        public let isBase: Bool
        /// Share of the total, already rounded for display (web's `toFixed(0)`).
        public let sharePct: Int
        /// Share as a bar width. Clamped at zero because a net-negative
        /// currency would otherwise ask the bar for a negative width. Web
        /// clamps the same way, and only for the bar.
        public let barSharePct: Double
    }

    /// "Across currencies" -- where the money is held, converted to base. Nil
    /// for the single-currency case, which web renders as nothing at all.
    public struct CurrencyBreakdownUiModel: Equatable {
        public let base: String
        public let slices: [CurrencySliceUiModel]
        public let totalFormatted: String
    }

    public var visible: [AccountUiModel] = []
    public var archivedCount: Int = 0
    /// Nil until there is more than one currency to compare.
    public var breakdown: CurrencyBreakdownUiModel?
    /// Show card skeletons rather than "no accounts yet".
    ///
    /// Web's guard is `balances.length === 0 && (accountsLoading ||
    /// syncPending)`. The half that matters is `syncPending`: on a returning
    /// user's first launch the local database is empty because the accounts are
    /// still downloading, and this screen told them they had none — which for
    /// an accounts list reads as "your money is gone", not as "still loading".
    public private(set) var showSkeleton = true
    public var showArchived: Bool = false {
        didSet { recompute() }
    }

    private var all: [AccountUiModel] = []
    /// False until the first balance read lands — web's `useAccountsLoading()`.
    /// A list of no accounts that has not been read yet is not a list of no
    /// accounts.
    private var loaded = false
    private var syncPending = true

    public init() {
        Task { await startObserving() }
        Task { [weak self] in
            guard let self else { return }
            await awaitInitialSync(self.db)
            self.syncPending = false
            self.recompute()
        }
    }

    private func startObserving() async {
        do {
            let stream = try ledgerRepository.watchAccounts(includeArchived: true)
            for try await _ in stream {
                await reload()
            }
        } catch {
            print("Failed to observe accounts: \(error)")
        }
    }

    private func reload() async {
        do {
            let balances = try await ledgerRepository.accountBalances(includeArchived: true)
            // A failed rate read must not take the account list with it -- the
            // list needs no rates, only the breakdown does.
            let rates = try? await ledgerRepository.rates()
            breakdown = rates.flatMap { currencyBreakdown(balances, $0) }
            all = balances.map { acctWithBal in
                let acct = acctWithBal.account
                return AccountUiModel(
                    id: acct.id,
                    name: acct.name,
                    type: acct.type,
                    currency: acct.currency,
                    color: acct.color,
                    balanceFormatted: formatMoneyAware(acctWithBal.balance),
                    isArchived: acct.isArchived,
                    includeInNetWorth: acct.includeInNetWorth
                )
            }
            loaded = true
            recompute()
        } catch {
            print("Failed to load account balances: \(error)")
            // A read that threw is still an answer -- we are not waiting any
            // more. Leaving this false turns one failure into a permanent
            // skeleton.
            loaded = true
            recompute()
        }
    }

    /// Net worth split by the currency each account is held in -- the port of
    /// web's `useCurrencyBreakdown()` (apps/web/src/hooks.ts). Mirrors
    /// Android's `currencyBreakdown`.
    ///
    /// Two filters, both copied from web rather than invented: archived
    /// accounts are out because web builds this from `useAccountBalances()`
    /// with its default (non-archived) argument, and accounts excluded from net
    /// worth are out because the card is a breakdown OF net worth. This
    /// screen's own list shows archived accounts on request; this card
    /// deliberately does not follow it.
    ///
    /// Returns nil below two currencies: a single-currency user has nothing to
    /// compare, and web renders the section as nothing at all in that case.
    private func currencyBreakdown(_ balances: [AccountWithBalance], _ rates: RateLookup) -> CurrencyBreakdownUiModel? {
        let base = baseCurrencyNow()
        var order: [String] = []
        var byCurrency: [String: Int64] = [:]
        for ab in balances {
            guard !ab.account.isArchived, ab.account.includeInNetWorth else { continue }
            let currency = ab.balance.currency
            if byCurrency[currency] == nil { order.append(currency) }
            byCurrency[currency, default: 0] += ab.balance.amount
        }
        guard byCurrency.count >= 2 else { return nil }

        // `convert(money(...), to: base, rate:)`, never a bare multiply: the
        // two currencies can have different minor-unit scales (JPY 0, KWD 3),
        // and the domain helper is what knows that. `try?` because `convert`
        // rejects a non-positive rate, and a zero in `exchange_rates` would
        // otherwise take the whole accounts list down -- falling back to par is
        // what the rate lookup itself does for an unknown pair.
        let converted: [(currency: String, native: Int64, inBase: Int64)] = order
            .map { currency in
                let native = byCurrency[currency] ?? 0
                let inBase = currency == base
                    ? native
                    : ((try? convert(money(native, currency), to: base, rate: rates(currency, base)))?.amount ?? native)
                return (currency, native, inBase)
            }
            .sorted { abs($0.inBase) > abs($1.inBase) }
        let total = converted.reduce(Int64(0)) { $0 + $1.inBase }
        // The BAR divides by the sum of absolute values, not by the signed
        // total. Web divides by the signed one, and on a net-negative sheet --
        // or with one overdrawn currency against two positive ones -- that
        // yields negative shares and shares over 100%, which paint a segment
        // wider than the bar it sits in. Percentages of "how much of my money
        // is here" only mean anything against a magnitude.
        let magnitude = converted.reduce(Int64(0)) { $0 + abs($1.inBase) }

        return CurrencyBreakdownUiModel(
            base: base,
            slices: converted.map { entry in
                let share = magnitude != 0 ? (Double(abs(entry.inBase)) / Double(magnitude)) * 100.0 : 0.0
                return CurrencySliceUiModel(
                    currency: entry.currency,
                    nativeFormatted: formatMoney(entry.native, entry.currency),
                    baseFormatted: formatMoney(entry.inBase, base),
                    isBase: entry.currency == base,
                    sharePct: Int(share.rounded()),
                    barSharePct: min(100, max(0, share))
                )
            },
            totalFormatted: formatMoney(total, base)
        )
    }

    private func recompute() {
        archivedCount = all.filter(\.isArchived).count
        visible = showArchived ? all : all.filter { !$0.isArchived }
        showSkeleton = !loaded || syncPending
    }

    public func toggleShowArchived() {
        showArchived.toggle()
    }

    /// Matches accounts/page.tsx's toggleNw() exactly -- direct update, no
    /// confirmation.
    public func toggleIncludeInNetWorth(id: String, current: Bool) {
        Task {
            try? await ledgerRepository.updateAccount(id: id, values: ["include_in_net_worth": !current])
            await reload()
        }
    }

    public func setArchived(id: String, archived: Bool) {
        Task {
            try? await ledgerRepository.setAccountArchived(id: id, archived: archived)
            await reload()
        }
    }
}
