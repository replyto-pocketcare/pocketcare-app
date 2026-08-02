import Foundation
import Observation
import Factory
import Domain
import Data
import Supabase

@Observable
@MainActor
public final class LoansViewModel {
    @ObservationIgnored
    @Injected(\.loansRepository) private var loansRepository
    
    @ObservationIgnored
    @Injected(\.supabaseClient) private var supabaseClient

    public struct LoanUiModel: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let totalAmount: String
        public let emiAmount: String
        public let remainingEmis: Int
        public let totalEmis: Int
        public let status: String
        public let nextDueDate: String
    }

    public var loans: [LoanUiModel] = []

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
            let stream = try await loansRepository.watchLoans(userId: userId)
            for try await dbLoans in stream {
                var uiLoans: [LoanUiModel] = []
                
                for loan in dbLoans {
                    let total = Double(loan.principal) / 100.0
                    let emi = Double(loan.emiAmount) / 100.0
                    
                    let remainingEmis = max(0, Int(loan.tenureMonths - loan.emisPaid))
                    
                    uiLoans.append(LoanUiModel(
                        id: loan.id,
                        name: loan.lender,
                        totalAmount: numberFormatter.string(from: NSNumber(value: total)) ?? "₹0",
                        emiAmount: numberFormatter.string(from: NSNumber(value: emi)) ?? "₹0",
                        remainingEmis: remainingEmis,
                        totalEmis: Int(loan.tenureMonths),
                        status: remainingEmis > 0 ? "Active" : "Closed",
                        nextDueDate: "Day \(loan.emiDueDay)" // Placeholder based on due day
                    ))
                }
                
                self.loans = uiLoans
            }
        } catch {
            print("Failed to observe loans: \(error)")
        }
    }
}
