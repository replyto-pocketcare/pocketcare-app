import Foundation
import Observation
import Factory
import Domain
import Data

@Observable
@MainActor
public final class InsightsViewModel {
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository

    public struct InsightUiModel: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let description: String
        public let highlightAmount: String?
        public let isPositive: Bool
    }

    public var insights: [InsightUiModel] = []
    public var thisMonthSpending: String = "₹0"
    public var lastMonthSpending: String = "₹0"

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
            let stream = try await ledgerRepository.watchAllTransactions()
            for try await transactions in stream {
                let now = Date()
                let calendar = Calendar.current
                
                let currentYear = calendar.component(.year, from: now)
                let currentMonth = calendar.component(.month, from: now)
                
                var thisMonthTotal: Int64 = 0
                var lastMonthTotal: Int64 = 0
                var diningTotal: Int64 = 0
                var hasSubscription = false
                
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                
                for tx in transactions {
                    if tx.type != "expense" { continue }
                    
                    guard let txDate = isoFormatter.date(from: tx.occurredAt) ?? ISO8601DateFormatter().date(from: tx.occurredAt) else { continue }
                    
                    let txYear = calendar.component(.year, from: txDate)
                    let txMonth = calendar.component(.month, from: txDate)
                    
                    if txYear == currentYear && txMonth == currentMonth {
                        thisMonthTotal += tx.amount
                        
                        if let desc = tx.description?.lowercased(), desc.contains("dining") || desc.contains("streamtv") {
                            if desc.contains("dining") { diningTotal += tx.amount }
                            if desc.contains("streamtv") { hasSubscription = true }
                        }
                        if let note = tx.note?.lowercased(), note.contains("food") {
                            diningTotal += tx.amount
                        }
                    } else if (txYear == currentYear && txMonth == currentMonth - 1) || (txYear == currentYear - 1 && currentMonth == 1 && txMonth == 12) {
                        lastMonthTotal += tx.amount
                    }
                }
                
                let thisD = Double(thisMonthTotal) / 100.0
                let lastD = Double(lastMonthTotal) / 100.0
                
                self.thisMonthSpending = numberFormatter.string(from: NSNumber(value: thisD)) ?? "₹0"
                self.lastMonthSpending = numberFormatter.string(from: NSNumber(value: lastD)) ?? "₹0"
                
                var newInsights: [InsightUiModel] = []
                
                if thisMonthTotal > lastMonthTotal && lastMonthTotal > 0 {
                    let pct = ((thisMonthTotal - lastMonthTotal) * 100) / lastMonthTotal
                    newInsights.append(InsightUiModel(
                        id: "1",
                        title: "Spending up this month",
                        description: "You've spent \(pct)% more than last month so far.",
                        highlightAmount: self.thisMonthSpending,
                        isPositive: false
                    ))
                } else if lastMonthTotal > 0 {
                    let pct = ((lastMonthTotal - thisMonthTotal) * 100) / lastMonthTotal
                    newInsights.append(InsightUiModel(
                        id: "1",
                        title: "Spending down this month",
                        description: "You've spent \(pct)% less than last month so far. Great job!",
                        highlightAmount: self.thisMonthSpending,
                        isPositive: true
                    ))
                } else {
                    newInsights.append(InsightUiModel(
                        id: "1",
                        title: "Welcome to Insights",
                        description: "Track your spending habits here as you use the app.",
                        highlightAmount: nil,
                        isPositive: true
                    ))
                }
                
                if diningTotal > 0 {
                    let dFmt = numberFormatter.string(from: NSNumber(value: Double(diningTotal) / 100.0))
                    newInsights.append(InsightUiModel(
                        id: "2",
                        title: "Food & Dining",
                        description: "Your total dining expenses this month.",
                        highlightAmount: dFmt,
                        isPositive: true
                    ))
                }
                
                if hasSubscription {
                    newInsights.append(InsightUiModel(
                        id: "3",
                        title: "Unusual Subscription",
                        description: "We noticed a recurring charge from 'StreamTV'.",
                        highlightAmount: "₹499",
                        isPositive: false
                    ))
                }
                
                self.insights = newInsights
            }
        } catch {
            print("Failed to observe insights: \(error)")
        }
    }
}
