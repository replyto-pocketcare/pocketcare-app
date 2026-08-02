import Foundation
import Observation
import Factory
import Domain
import Data
import Supabase

@Observable
@MainActor
public final class InvestmentsViewModel {
    @ObservationIgnored
    @Injected(\.investmentsRepository) private var investmentsRepository
    
    @ObservationIgnored
    @Injected(\.supabaseClient) private var supabaseClient

    public struct HoldingUiModel: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let symbolExchange: String
        public let assetClass: String
        public let quantity: String
        public let currentValueFormatted: String
        public let returnFormatted: String
        public let isPositiveReturn: Bool
    }

    public var holdings: [HoldingUiModel] = []
    public var totalValueFormatted: String = "₹0"
    public var totalReturnFormatted: String = "+₹0 (0%)"
    public var isTotalReturnPositive: Bool = true

    private var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "INR"
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private var percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 1
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
            let stream = try await investmentsRepository.watchHoldings(userId: userId)
            for try await dbHoldings in stream {
                var totalCost = 0.0
                var totalValue = 0.0
                var uiHoldings: [HoldingUiModel] = []
                
                for holding in dbHoldings {
                    let qty = holding.quantity
                    let avgCost = Double(holding.avgCost) / 100.0
                    let curVal = Double(holding.currentValue ?? holding.avgCost) / 100.0
                    
                    let costBasis = qty * avgCost
                    let valueBasis = qty * curVal
                    
                    totalCost += costBasis
                    totalValue += valueBasis
                    
                    let retAmt = valueBasis - costBasis
                    let retPct = costBasis > 0 ? retAmt / costBasis : 0.0
                    let isPos = retAmt >= 0
                    
                    let sign = isPos ? "+" : ""
                    let retStr = "\(sign)\(percentFormatter.string(from: NSNumber(value: retPct)) ?? "0%")"
                    
                    uiHoldings.append(HoldingUiModel(
                        id: holding.id,
                        name: holding.name ?? holding.symbol,
                        symbolExchange: "\(holding.symbol) • \(holding.exchange)",
                        assetClass: holding.assetClass ?? holding.instrumentType,
                        quantity: "\(holding.quantity) shares",
                        currentValueFormatted: numberFormatter.string(from: NSNumber(value: valueBasis)) ?? "₹0",
                        returnFormatted: retStr,
                        isPositiveReturn: isPos
                    ))
                }
                
                self.holdings = uiHoldings
                self.totalValueFormatted = numberFormatter.string(from: NSNumber(value: totalValue)) ?? "₹0"
                
                let totRetAmt = totalValue - totalCost
                let totRetPct = totalCost > 0 ? totRetAmt / totalCost : 0.0
                let isPosRet = totRetAmt >= 0
                self.isTotalReturnPositive = isPosRet
                
                let signRet = isPosRet ? "+" : ""
                let retSign2 = isPosRet ? "▲" : "▼"
                let retFormattedAmt = numberFormatter.string(from: NSNumber(value: abs(totRetAmt))) ?? "₹0"
                self.totalReturnFormatted = "\(retSign2) \(signRet)\(retFormattedAmt) (\(signRet)\(percentFormatter.string(from: NSNumber(value: totRetPct)) ?? "0%"))"
            }
        } catch {
            print("Failed to observe investments: \(error)")
        }
    }
}
