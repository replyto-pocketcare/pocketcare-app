import Foundation
import Observation
import Factory
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

    public var visible: [AccountUiModel] = []
    public var archivedCount: Int = 0
    public var showArchived: Bool = false {
        didSet { recompute() }
    }

    private var all: [AccountUiModel] = []

    public init() {
        Task { await startObserving() }
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
            recompute()
        } catch {
            print("Failed to load account balances: \(error)")
        }
    }

    private func recompute() {
        archivedCount = all.filter(\.isArchived).count
        visible = showArchived ? all : all.filter { !$0.isArchived }
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
