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

    // Task #62's ReceiptCaptureViewModel/ReceiptReviewViewModel are NOT
    // registered here -- they follow GroupDetailViewModel/SplitsViewModel's
    // newer convention instead (`@Injected(\.xRepository)` property wrapper
    // + a plain `ViewModel()` init at the call site), not this file's older
    // constructor-injection-via-Factory pattern. See those two files.
}
