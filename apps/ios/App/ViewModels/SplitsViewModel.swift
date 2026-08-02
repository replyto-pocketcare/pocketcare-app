import Foundation
import Observation
import Factory
import Domain
import Data
import Supabase

@Observable
@MainActor
public final class SplitsViewModel {
    @ObservationIgnored
    @Injected(\.splitsRepository) private var splitsRepository
    
    @ObservationIgnored
    @Injected(\.supabaseClient) private var supabaseClient

    public struct SplitGroupUiModel: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let kind: String
        public let memberCount: Int
        public let dateRange: String?
        public let netBalanceFormatted: String
        public let isOwed: Bool
    }

    public struct FriendEdgeUiModel: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let vpa: String?
        public let balanceFormatted: String
        public let isOwed: Bool
    }

    public var groups: [SplitGroupUiModel] = []
    public var friends: [FriendEdgeUiModel] = []

    private var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "INR"
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    public init() {
        Task {
            await startObserving()
        }
    }

    private func startObserving() async {
        guard let userId = try? await supabaseClient.auth.session.user.id.uuidString else {
            return
        }

        do {
            // First fetch the overview to populate immediately
            try await refreshOverview(userId: userId)
            
            // Watch for changes on groups, triggering a refresh
            let stream = try await splitsRepository.watchGroups(includeDirect: false)
            for try await _ in stream {
                try await refreshOverview(userId: userId)
            }
        } catch {
            print("Failed to observe splits: \(error)")
        }
    }
    
    private func refreshOverview(userId: String) async throws {
        let overview = try await splitsRepository.splitOverview(userId: userId)
        
        self.groups = overview.groups.map { grpOverview in
            let isOwed = grpOverview.net > 0
            let amt = Double(abs(grpOverview.net)) / 100.0
            let formatted = self.numberFormatter.string(from: NSNumber(value: amt)) ?? "₹0.00"
            let netStr = grpOverview.net == 0 ? "Settled up" : (isOwed ? "You are owed \(formatted)" : "You owe \(formatted)")
            
            return SplitGroupUiModel(
                id: grpOverview.group.id,
                name: grpOverview.group.name,
                kind: grpOverview.group.kind,
                memberCount: grpOverview.peopleCount,
                dateRange: grpOverview.group.startDate,
                netBalanceFormatted: netStr,
                isOwed: isOwed
            )
        }
        
        self.friends = overview.direct.map { bal in
            let isOwed = bal.net > 0
            let amt = Double(abs(bal.net)) / 100.0
            let formatted = self.numberFormatter.string(from: NSNumber(value: amt)) ?? "₹0.00"
            let netStr = isOwed ? "Owes you \(formatted)" : "You owe \(formatted)"
            
            return FriendEdgeUiModel(
                id: bal.userId,
                name: "Friend", // Placeholder
                vpa: nil,
                balanceFormatted: netStr,
                isOwed: isOwed
            )
        }
    }
}
