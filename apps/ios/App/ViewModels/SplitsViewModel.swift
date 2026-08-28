import Foundation
import Observation
import Factory
import Domain
import Data
import Supabase

/// Real port of apps/web/app/friends/page.tsx's hub (task #30). See
/// docs/mobile/screen-specs/splits.md. Replaces the previous version's
/// `"Friend" // Placeholder` name bug -- names are now resolved via a real
/// connections join, matching web's `profiles.get(id)?.name ?? "Someone"`.
///
/// Multi-Task watch pattern (each `watch*` stream its own long-running
/// Task, recomputing shared UI state on every emission) matches
/// TransactionsViewModel's established convention -- deliberately NOT a
/// one-shot "take the first value" extraction, since abandoning an
/// AsyncThrowingStream early mid-loop is unverified behavior against this
/// project's PowerSync SDK version and no other ViewModel in this codebase
/// does it.
@Observable
@MainActor
public final class SplitsViewModel {
    @ObservationIgnored
    @Injected(\.splitsRepository) private var splitsRepository

    @ObservationIgnored
    @Injected(\.authRepository) private var authRepository

    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository

    public struct SplitGroupUiModel: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let kind: String
        public let memberCount: Int
        public let dateRange: String?
        public let net: Int64
        public let netBalanceFormatted: String
        public let isOwed: Bool
    }

    public struct FriendEdgeUiModel: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let net: Int64
        public let balanceFormatted: String
        public let isOwed: Bool
    }

    public struct OverviewUiModel: Equatable {
        public let netPositionFormatted: String
        public let netPositive: Bool
        public let owedFormatted: String
        public let oweFormatted: String
    }

    public var groups: [SplitGroupUiModel] = []
    public var friends: [FriendEdgeUiModel] = []
    public var overview: OverviewUiModel?
    public var connections: [UserProfile] = []
    public var loaded = false
    public var errorMessage: String?

    // ---- friend insights ----

    /// Behavioural patterns across the groups you share — who covers the most,
    /// who always ends up owing, who settles fastest.
    ///
    /// `friendInsights()` has been on both repositories since P2.5 with zero
    /// callers: the ranking was computed, thresholded, returned and thrown
    /// away. `pickFriendInsights` in Domain does the actual choosing under its
    /// own vectors, including the evidence thresholds that stop it asserting a
    /// pattern from one dinner.
    public var insights: [FriendInsight] = []

    // ---- person detail ----

    /// The itemised ledger behind one person's balance, across every group.
    ///
    /// `personLedger()` has been on both repositories since P2.5 with zero
    /// callers, so the Friends screen could tell you THAT you owed someone and
    /// not one line of WHY — unless the whole balance happened to sit in a
    /// single group you could open.
    public var personLines: [PersonLine] = []
    public var personLinesFor: String?

    public func loadPersonLedger(_ otherUserId: String) {
        guard let uid = userId, personLinesFor != otherUserId else { return }
        personLinesFor = otherUserId
        personLines = []
        Task {
            do {
                personLines = try await splitsRepository.personLedger(userId: uid, otherId: otherUserId).lines
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func clearPersonLedger() {
        personLinesFor = nil
        personLines = []
    }

    // ---- pending settlements ----

    /// Payments someone says they made to you, waiting on your confirmation.
    ///
    /// Web renders this above the Friends list on /friends. It is the payee's
    /// half of settle-up and it had no native UI at all — both repositories
    /// have had `confirmSettlement` and `disputeSettlement` since P2.5 with
    /// zero callers, so a UPI settlement raised on a phone stayed pending
    /// until somebody opened the browser.
    public var pending: [PendingSettlement] = []

    /// Real accounts the deposit could land in — web's own picker query.
    public var accounts: [Account] = []

    /// The settlement currently being confirmed or disputed, by id.
    public var busySettlementId: String?

    private var namesById: [String: String] = [:]
    private var userId: String?
    private var tasks: [Task<Void, Never>] = []

    public init() {
        Task { await start() }
    }

    private func resolveUserId() async -> String? {
        if let existing = authRepository.currentUserId { return existing }
        return try? await authRepository.ensureUser()
    }

    private func start() async {
        guard let userId = await resolveUserId() else { loaded = true; return }
        self.userId = userId

        tasks.append(Task {
            do {
                for try await conns in try splitsRepository.watchConnections(userId: userId) {
                    self.connections = conns
                    self.namesById = Dictionary(uniqueKeysWithValues: conns.map { ($0.id, $0.name) })
                    await self.refreshOverviewSafely(userId: userId)
                }
            } catch { self.errorMessage = error.localizedDescription }
        })

        tasks.append(Task {
            do {
                for try await list in try self.splitsRepository.watchPendingSettlements(userId: userId) {
                    self.pending = list
                }
            } catch { self.pending = [] }
        })

        tasks.append(Task {
            do {
                // Web's picker query: real, unarchived, non-investment. A
                // deposit cannot land in a demat account.
                for try await list in try self.ledgerRepository.watchAccounts(includeArchived: false) {
                    self.accounts = list.filter { !FormOptions.isInvestmentAccount($0.type) }
                }
            } catch { self.accounts = [] }
        })

        tasks.append(Task {
            do {
                let stream = try splitsRepository.watchGroups(includeDirect: false)
                for try await _ in stream {
                    await self.refreshOverviewSafely(userId: userId)
                    self.loaded = true
                }
            } catch {
                self.errorMessage = error.localizedDescription
                self.loaded = true
            }
        })
    }

    public func nameOfUser(_ id: String) -> String { namesById[id] ?? S.Payments.someone }

    /// "Yes, it arrived" / "Didn't arrive".
    ///
    /// Note what dispute does NOT do: it does not unwind the payer's ledger
    /// entry. The ledger is append-only and if their money really left, that is
    /// still true. What changes is that the settlement stops counting toward
    /// the balance between you — web's own comment, and the reason the two
    /// actions are not symmetric.
    public func confirmArrived(_ settlement: PendingSettlement, accountId: String?) {
        act(settlement.id) { uid in
            try await self.splitsRepository.confirmSettlement(userId: uid, settlement: settlement, accountId: accountId)
        }
    }

    public func markDidNotArrive(_ settlement: PendingSettlement) {
        act(settlement.id) { uid in
            try await self.splitsRepository.disputeSettlement(userId: uid, settlementId: settlement.id)
        }
    }

    private func act(_ settlementId: String, _ block: @escaping (String) async throws -> Void) {
        guard let uid = userId, busySettlementId == nil else { return }
        busySettlementId = settlementId
        Task {
            do {
                try await block(uid)
            } catch {
                errorMessage = error.localizedDescription
            }
            busySettlementId = nil
        }
    }

    private func refreshOverviewSafely(userId: String) async {
        do { try await refreshOverview(userId: userId) } catch { errorMessage = error.localizedDescription }
        insights = (try? await splitsRepository.friendInsights(userId: userId).insights) ?? []
    }

    private func nameOf(_ id: String) -> String { namesById[id] ?? S.Groups.someone }

    private func refreshOverview(userId: String) async throws {
        let ov = try await splitsRepository.splitOverview(userId: userId)

        // These three roll up across groups, so they are reported in the user's
        // BASE currency — not INR, which is what was hardcoded here. The
        // per-group rows below already used `g.group.currency` correctly, which
        // is what made the inconsistency easy to miss.
        let base = baseCurrencyNow()

        self.overview = OverviewUiModel(
            netPositionFormatted: (ov.netPosition >= 0 ? "+" : "\u{2212}") + formatMoney(abs(ov.netPosition), base),
            netPositive: ov.netPosition >= 0,
            owedFormatted: formatMoney(ov.owed, base),
            oweFormatted: formatMoney(ov.owe, base)
        )

        self.groups = ov.groups.map { g in
            let isOwed = g.net > 0
            let text: String
            if g.net == 0 { text = S.Groups.settledTitle }
            else if isOwed { text = "You are owed \(formatMoney(g.net, g.group.currency))" }
            else { text = "You owe \(formatMoney(-g.net, g.group.currency))" }
            return SplitGroupUiModel(id: g.group.id, name: g.group.name, kind: g.group.kind, memberCount: g.peopleCount, dateRange: g.group.startDate, net: g.net, netBalanceFormatted: text, isOwed: isOwed)
        }

        // Across the WHOLE ledger, not `ov.direct` alone.
        //
        // `direct` holds only the 1:1 groups. Every balance that lives inside a
        // real group — a trip, a flat, anything with a name — is in
        // `GroupOverview.perUser`, which was computed, returned, and never
        // read. Somebody who owed you from a trip did not appear in Friends at
        // all, so the debt was invisible outside that one group's screen.
        //
        // The rollup itself is Domain's under 25 vectors, including the
        // first-appearance ordering web gets from spreading a JS Map.
        let directNets = ov.direct.map { PersonNet(userId: $0.userId, net: $0.net) }
        let nets = friendNets(
            groupPerUser: ov.groups.map { g in g.perUser.map { PersonNet(userId: $0.userId, net: $0.net) } },
            direct: directNets
        )
        // Everyone you share a group with, INCLUDING the people you are square
        // with — a Friends directory that lists only debts is a debt list.
        self.friends = everyoneYouShareWith(
            groupMemberIds: ov.groups.map(\.memberIds),
            direct: directNets,
            nets: nets,
            names: namesById
        ).map { person in
            FriendEdgeUiModel(
                id: person.userId,
                name: nameOf(person.userId),
                net: person.net,
                balanceFormatted: formatMoney(abs(person.net), base),
                isOwed: person.net > 0
            )
        }
    }

    /// The signed-in user id, resolving it if this is the first call.
    private func currentOrResolvedUserId() async -> String? {
        if let userId { return userId }
        return await resolveUserId()
    }

    public func createGroup(name: String, kind: String, currency: String, memberIds: [String]) async -> String? {
        // Not `userId ?? (await resolveUserId())`: `??`'s right side is an
        // autoclosure, and an autoclosure cannot be async.
        guard !name.isEmpty, let userId = await currentOrResolvedUserId() else { return nil }
        do {
            return try await splitsRepository.createGroup(userId: userId, name: name, kind: kind, currency: currency, memberUserIds: memberIds)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Friends aren't groups in the UI, but ARE one underneath (a hidden
    /// `is_direct` group per pair) -- tapping a friend reuses
    /// GroupDetailView against that hidden group rather than a second,
    /// near-duplicate "person ledger" screen.
    public func openOrCreateDirectGroup(otherUserId: String, currency: String) async -> String? {
        guard let userId = await currentOrResolvedUserId() else { return nil }
        do {
            return try await splitsRepository.getOrCreateDirectGroup(userId: userId, otherUserId: otherUserId, otherName: nameOf(otherUserId), currency: currency)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
