import Foundation
import Observation
import Factory
import Domain
import Data
import Supabase

@Observable
@MainActor
public final class GoalsViewModel {
    @ObservationIgnored
    @Injected(\.goalsRepository) private var goalsRepository
    
    @ObservationIgnored
    @Injected(\.supabaseClient) private var supabaseClient

    public struct GoalUiModel: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let currentFormatted: String
        public let targetFormatted: String
        public let targetDate: String
        public let progress: Float
    }
    
    public struct CashflowUiModel: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let amountFormatted: String
        public let expectedDate: String
        public let isIncome: Bool
        public let status: String
    }

    public var goals: [GoalUiModel] = []
    public var cashflows: [CashflowUiModel] = [] // Kept empty or dummy for now since Cashflow repo isn't ported

    private var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "INR"
        formatter.maximumFractionDigits = 0
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
            let stream = try await goalsRepository.watchGoals(userId: userId)
            for try await dbGoals in stream {
                var uiGoals: [GoalUiModel] = []
                
                for goal in dbGoals {
                    var savedAmount: Int64 = 0
                    if let stream = try? await goalsRepository.watchGoalAllocations(goalId: goal.id) {
                        for try await allocations in stream {
                            savedAmount = allocations.reduce(0) { $0 + $1.amountBlocked }
                            break // Only get the first set to compute current state
                        }
                    }
                    
                    let savedD = Double(savedAmount) / 100.0
                    let targetD = Double(goal.targetAmount) / 100.0
                    let progress = targetD > 0 ? Float(savedD / targetD) : 0
                    
                    uiGoals.append(GoalUiModel(
                        id: goal.id,
                        name: goal.name,
                        currentFormatted: numberFormatter.string(from: NSNumber(value: savedD)) ?? "₹0",
                        targetFormatted: numberFormatter.string(from: NSNumber(value: targetD)) ?? "₹0",
                        targetDate: goal.targetDate ?? "No date",
                        progress: progress
                    ))
                }
                
                self.goals = uiGoals
            }
        } catch {
            print("Failed to observe goals: \(error)")
        }
    }
}
