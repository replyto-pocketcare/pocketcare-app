import Foundation
import Domain

// Read facade and helper methods for UPI payment handles (P2.5).
// Mirrors apps/web/src/payments/handles.ts.
// Mirrors apps/android/data/.../repository/UpiRepository.kt.

public struct UpiPaymentHandle: Sendable {
    public let vpa: String
    public let displayName: String?

    public init(vpa: String, displayName: String?) {
        self.vpa = vpa
        self.displayName = displayName
    }
}

public final class UpiRepository: @unchecked Sendable {
    private var cachedHint: String?

    public init() {}

    public func getCachedHint() -> String? {
        return cachedHint
    }

    public func rememberHint(_ hint: String?) {
        self.cachedHint = hint
    }

    public func maskHandle(_ vpa: String) -> String {
        return maskVpa(vpa)
    }

    public func isValidVpa(_ vpa: String) -> Bool {
        return validateVpa(vpa)
    }

    public func createPaymentUrl(
        payeeVpa: String,
        payeeName: String?,
        amountMinor: Int64,
        currency: String = "INR",
        transactionRef: String? = nil,
        note: String? = nil
    ) -> String {
        return buildUpiUrl(
            payeeVpa: payeeVpa,
            payeeName: payeeName,
            amountMinor: amountMinor,
            currency: currency,
            transactionRef: transactionRef,
            note: note
        )
    }
}
