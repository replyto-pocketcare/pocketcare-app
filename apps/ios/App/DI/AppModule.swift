import Foundation
import Factory
import Data

@MainActor
public extension Container {
    var authViewModel: Factory<AuthViewModel> {
        self { MainActor.assumeIsolated { AuthViewModel(authRepository: self.authRepository()) } }.singleton
    }

    var dashboardViewModel: Factory<DashboardViewModel> {
        self { MainActor.assumeIsolated { DashboardViewModel(ledgerRepository: self.ledgerRepository()) } }
    }

    var transactionsViewModel: Factory<TransactionsViewModel> {
        self { MainActor.assumeIsolated { TransactionsViewModel(ledgerRepository: self.ledgerRepository()) } }
    }
}
