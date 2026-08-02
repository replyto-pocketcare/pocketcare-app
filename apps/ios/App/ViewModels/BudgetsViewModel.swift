import Foundation
import Observation
import Factory
import Domain
import Data

@Observable
@MainActor
public final class BudgetsViewModel {
    @ObservationIgnored
    @Injected(\.budgetRepository) private var budgetRepository

    public struct BudgetUiModel: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let period: String
        public let spentFormatted: String
        public let limitFormatted: String
        public let progress: Float
        public let categories: [String]
    }

    public var budgets: [BudgetUiModel] = []

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
        do {
            let list = try await budgetRepository.list()
            var uis: [BudgetUiModel] = []
            let now = Date()
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let ymd = Ymd(
                year: calendar.component(.year, from: now),
                month: calendar.component(.month, from: now),
                day: calendar.component(.day, from: now)
            )
            
            for budgetLike in list {
                let spent = try await budgetRepository.spentThisPeriod(budget: budgetLike, asOf: ymd)
                
                let spentAmt = Double(spent.amount) / 100.0
                let limitAmt = Double(budgetLike.limitAmount) / 100.0
                let progress = limitAmt > 0 ? Float(spentAmt / limitAmt) : 0
                
                let spentFormatted = numberFormatter.string(from: NSNumber(value: spentAmt)) ?? "₹0"
                let limitFormatted = numberFormatter.string(from: NSNumber(value: limitAmt)) ?? "₹0"
                
                uis.append(BudgetUiModel(
                    id: budgetLike.id,
                    name: budgetLike.name ?? "Untitled Budget",
                    period: budgetLike.period,
                    spentFormatted: spentFormatted,
                    limitFormatted: limitFormatted,
                    progress: progress,
                    categories: ["All"]
                ))
            }
            
            self.budgets = uis
        } catch {
            print("Failed to load budgets: \(error)")
        }
    }
}
