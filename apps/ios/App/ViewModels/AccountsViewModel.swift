import Foundation
import Observation
import Factory
import Domain
import Data

@Observable
@MainActor
public final class AccountsViewModel {
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository

    public struct AccountUiModel: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let typeLabel: String
        public let balanceFormatted: String
        public let isNegative: Bool
    }

    public var accounts: [AccountUiModel] = []
    
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
        do {
            let stream = try ledgerRepository.watchAccounts(includeArchived: true)
            for try await _ in stream {
                let balances = try await ledgerRepository.accountBalances(includeArchived: true)
                self.accounts = balances.map { accountWithBalance in
                    let amt = Double(accountWithBalance.balance.amount) / 100.0
                    let formatted = self.numberFormatter.string(from: NSNumber(value: abs(amt))) ?? "₹0.00"
                    let sign = amt < 0 ? "-" : ""
                    
                    return AccountUiModel(
                        id: accountWithBalance.account.id,
                        name: accountWithBalance.account.name,
                        typeLabel: "\(accountWithBalance.account.type.capitalized) • \(accountWithBalance.account.currency)",
                        balanceFormatted: "\(sign)\(formatted)",
                        isNegative: amt < 0
                    )
                }
            }
        } catch {
            print("Failed to observe accounts: \(error)")
        }
    }
}
