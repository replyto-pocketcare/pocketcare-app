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

    private func refreshOverviewSafely(userId: String) async {
        do { try await refreshOverview(userId: userId) } catch { errorMessage = error.localizedDescription }
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

        self.friends = ov.direct.map { bal in
            let isOwed = bal.net > 0
            return FriendEdgeUiModel(id: bal.userId, name: nameOf(bal.userId), net: bal.net, balanceFormatted: formatMoney(abs(bal.net), base), isOwed: isOwed)
        }.sorted { abs($0.net) > abs($1.net) }
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
