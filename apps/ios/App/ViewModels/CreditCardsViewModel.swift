import Foundation
import Observation
import Factory
import Domain
import Data
import SwiftUI

@Observable
@MainActor
public final class CreditCardsViewModel {
    @ObservationIgnored
    @Injected(\.creditCardRepository) private var creditCardRepository
    
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository

    public struct CreditCardUiModel: Identifiable, Equatable {
        public let id: String
        public let cardName: String
        public let bankNetwork: String
        public let last4: String
        public let outstandingFormatted: String
        public let availableLimitFormatted: String
        public let dueDate: String
        public let gradientColors: [Color]
    }

    public var cards: [CreditCardUiModel] = []

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
            let stream = try ledgerRepository.watchAccounts(includeArchived: false)
            for try await _ in stream {
                let balances = try await ledgerRepository.accountBalances(includeArchived: false)
                let creditCards = balances.filter { $0.account.type.lowercased() == "creditcard" || $0.account.type.lowercased() == "credit_card" }
                
                var newCards: [CreditCardUiModel] = []
                for (index, accountWithBalance) in creditCards.enumerated() {
                    let details = try? await creditCardRepository.getDetails(accountId: accountWithBalance.account.id)
                    let outstandingAmt = Double(accountWithBalance.balance.amount) / 100.0
                    let limitAmt = Double(details?.creditLimit ?? 0) / 100.0
                    
                    let avail = max(0, limitAmt - abs(outstandingAmt))
                    
                    let colors: [Color]
                    if index % 2 == 0 {
                        colors = [Color(red: 44/255, green: 62/255, blue: 80/255), Color(red: 26/255, green: 37/255, blue: 47/255)] // Blueish dark
                    } else {
                        colors = [Color(red: 216/255, green: 111/255, blue: 83/255), Color(red: 122/255, green: 62/255, blue: 41/255)] // Terracotta
                    }
                    
                    let outFormatted = numberFormatter.string(from: NSNumber(value: abs(outstandingAmt))) ?? "₹0.00"
                    let availFormatted = numberFormatter.string(from: NSNumber(value: avail)) ?? "₹0.00"
                    
                    newCards.append(CreditCardUiModel(
                        id: accountWithBalance.account.id,
                        cardName: accountWithBalance.account.name,
                        bankNetwork: "Bank • Visa",
                        last4: details?.cardLast4 ?? "****",
                        outstandingFormatted: outFormatted,
                        availableLimitFormatted: availFormatted,
                        dueDate: "Day \(details?.dueDay ?? 0)",
                        gradientColors: colors
                    ))
                }
                
                self.cards = newCards
            }
        } catch {
            print("Failed to observe credit cards: \(error)")
        }
    }
}
