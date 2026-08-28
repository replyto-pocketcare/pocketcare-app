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

    public var visible: [AccountUiModel] = []
    public var archivedCount: Int = 0
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
