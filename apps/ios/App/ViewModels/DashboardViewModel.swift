import Foundation
import Observation
import Factory
import Data
import Domain
import PowerSync
import Supabase

/// Net-worth hero content -- mirrors apps/web/app/page.tsx's NetWorthHero
/// exactly (see docs/mobile/screen-specs/dashboard.md), and Android's
/// NetWorthHeroState (DashboardViewModel.kt) added the same session.
public struct NetWorthHeroState: Sendable {
    public var net: Money = Money(amount: 0, currency: FormOptions.defaultCurrency)
    public var base: String = FormOptions.defaultCurrency
    public var showAvailable: Bool = false
    public var deltaMinor: Int64 = 0
    public var hasTrend: Bool = false
    public var sparkline: [Float] = []
}

/// The four figures the wide-window KPI strip shows, all in MINOR units.
///
/// Derived here rather than in ``StatRow`` because the monthly income/expense
/// fold this screen already does for the hero's sparkline is the same fold web's
/// StatRow runs a second query for — one pass over the ledger, two consumers.
///
/// Mirrors Android's `DashboardStats` (DashboardViewModel.kt).
public struct DashboardStats: Sendable {
    public var netMinor: Int64 = 0
    public var currentIncomeMinor: Int64 = 0
    public var currentExpenseMinor: Int64 = 0
    public var previousIncomeMinor: Int64 = 0
    public var previousExpenseMinor: Int64 = 0
    public var base: String = FormOptions.defaultCurrency
}

@Observable
@MainActor
public final class DashboardViewModel {
    private let ledgerRepository: LedgerRepository
    /// Property-wrapper injection alongside the constructor-injected repository
    /// above -- the newer of this app's two Factory conventions (see
    /// DI/AppModule.swift's own note), used here so the registration in that
    /// file does not have to change shape for two reads that belong to this
    /// screen alone.
    @ObservationIgnored @Injected(\.supabaseClient) private var client
    @ObservationIgnored @Injected(\.powerSyncDatabase) private var db
    private var tasks: [Task<Void, Never>] = []

    public var accounts: [AccountWithBalance] = []
    public var hero: NetWorthHeroState = NetWorthHeroState()

    /// Only read at `.expanded` — see StatRow.swift for why iPhones skip the strip.
    public var stats: DashboardStats = DashboardStats()

    /// Who the greeting is addressed to -- page.tsx's
    /// `session?.username || session.email.split("@")[0]`. Empty when neither is
    /// known; the view supplies `dashboard.greetingFallback`, as web does.
    public var displayName: String = ""

    /// The local read has returned at least once. Web reads the equivalent off
    /// `useAccountsLoading()`; here it is simply "a snapshot has landed".
    public var accountsLoaded = false

    /// The FIRST sync from the server has not finished, so the local database
    /// may still be empty because the data is on its way. Together with
    /// `accountsLoaded` this is what stops the dashboard telling a returning
    /// user to add their first account while their accounts are downloading.
    public var syncPending = true

    /// Mirrors page.tsx's `showAvailable` local state (net-worth toggle).
    public func toggleShowAvailable() {
        hero.showAvailable.toggle()
        Task { await refreshSnapshots() }
    }

    public init(ledgerRepository: LedgerRepository) {
        self.ledgerRepository = ledgerRepository
    }

    public func start() {
        cancel()

        // Initial fetch of snapshots
        Task { await refreshSnapshots() }

        // Read once, not watched: the name on the greeting comes off the auth
        // session, which changes only by signing in or out -- and either of
        // those replaces this whole screen.
        let nameTask = Task { [weak self] in
            guard let self else { return }
            guard let session = try? await self.client.auth.session else { return }
            let username = session.user.userMetadata["username"]?.stringValue ?? ""
            let email = session.user.email ?? ""
            let localPart = email.split(separator: "@").first.map { String($0) } ?? ""
            // Web's precedence exactly: username, else the local part of the
            // email, else nothing.
            self.displayName = username.isEmpty ? localPart : username
        }

        // The shared gate, not a private copy of the poll: Transactions,
        // Accounts and this screen showing different answers to "has the data
        // arrived?" would be worse than any one of the answers. See
        // Components/InitialSyncGate.swift for why it polls at all.
        let syncTask = Task { [weak self] in
            guard let self else { return }
            await awaitInitialSync(self.db)
            if Task.isCancelled { return }
            self.syncPending = false
        }

        // Watch for changes in transactions to trigger a snapshot refresh
        // (net worth / sparkline / delta all derive from transaction data).
        // No longer maps rows into a Dashboard-local recent-activity list --
        // that section was removed 2026-08-06 (Akhilesh: "we already have
        // recent transactions section that would must have come when we
        // copied all the widgets and the layout from web" -- it was an
        // iOS-only invention with no counterpart in web or Android, not a
        // real ported feature). watchRecentTransactions is reused here
        // purely as a change signal; a real Transactions list belongs to
        // TransactionsViewModel.swift, not Dashboard.
        let txnTask = Task {
            do {
                for try await _ in try ledgerRepository.watchRecentTransactions(limit: 10) {
                    await refreshSnapshots()
                }
            } catch {
                print("Error watching recent transactions: \(error)")
            }
        }

        // Watch for changes in accounts to refresh snapshots
        let acctTask = Task {
            do {
                for try await _ in try ledgerRepository.watchAccounts(includeArchived: false) {
                    await refreshSnapshots()
                }
            } catch {
                print("Error watching accounts: \(error)")
            }
        }
        
        tasks = [txnTask, acctTask, nameTask, syncTask]
    }

    public func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private func refreshSnapshots() async {
        do {
            async let netWorthTask = ledgerRepository.netWorth(base: baseCurrencyNow())
            async let balancesTask = ledgerRepository.accountBalances(includeArchived: false)
            async let monthlyTask = ledgerRepository.monthlyIncomeExpense()

            let nw = try await netWorthTask
            let bal = try await balancesTask
            let monthly = try await monthlyTask

            self.accounts = bal

            // ---- Hero sparkline/delta -- matches page.tsx's NetWorthHero
            // exactly (same algorithm as Android's DashboardViewModel.kt,
            // ported the same session): fold (year-month, type) rows into
            // per-month (inc, exp), last 8 months, delta = last month's
            // (inc - exp), sparkline = cumulative running sum of (inc-exp)/100.
            var byMonth: [String: (inc: Int64, exp: Int64)] = [:]
            var order: [String] = []
            for row in monthly {
                if byMonth[row.yearMonth] == nil { order.append(row.yearMonth) }
                var entry = byMonth[row.yearMonth] ?? (0, 0)
                if row.type == "income" { entry.inc = row.total } else { entry.exp = row.total }
                byMonth[row.yearMonth] = entry
            }
            let months = order.suffix(8).map { ($0, byMonth[$0]!) }
            let deltaMinor: Int64 = months.last.map { $0.1.inc - $0.1.exp } ?? 0
            var acc: Float = 0
            // `majorScale`, not `/ 100`: the sparkline is drawn in MAJOR units
            // and a zero-decimal currency was being plotted at a hundredth of
            // its real height.
            let sparkScale = Float(majorScale(baseCurrencyNow()))
            let sparkline: [Float] = months.map { (_, v) in
                acc += Float(v.inc - v.exp) / sparkScale
                return acc
            }

            // The KPI strip's four figures, off the SAME fold as the
            // sparkline. Web's StatRow re-runs the identical GROUP BY in its own
            // component; the one thing the port does differently is not paying
            // for it twice.
            let current = months.last?.1 ?? (inc: 0, exp: 0)
            let previous = months.count >= 2 ? months[months.count - 2].1 : (inc: 0, exp: 0)

            self.hero.net = self.hero.showAvailable ? nw.available : nw.total
            self.hero.base = nw.base
            self.hero.deltaMinor = deltaMinor
            self.hero.hasTrend = !months.isEmpty
            self.hero.sparkline = sparkline
            self.stats = DashboardStats(
                netMinor: self.hero.net.amount,
                currentIncomeMinor: current.inc,
                currentExpenseMinor: current.exp,
                previousIncomeMinor: previous.inc,
                previousExpenseMinor: previous.exp,
                base: nw.base
            )
            // Set LAST, after every field it gates, so a half-built hero is
            // never shown as a finished one.
            self.accountsLoaded = true
        } catch {
            print("Error refreshing snapshots: \(error)")
            // Also set on FAILURE, and this is the important half. The flag
            // only ever answers "is the skeleton still the honest thing to
            // show?", and after a read that threw it is not: we are not
            // waiting for anything any more. Leaving it false turns one failed
            // read into a placeholder that shimmers for the life of the
            // process. The error is reported by the error surface, not by
            // withholding the screen.
            self.accountsLoaded = true
        }
    }
}
