import Foundation
import Domain
import Supabase

// Read facade and helper methods for UPI payment handles (P2.5, extended
// task #30 for Splits settle-up: fetchCounterpartyHandle).
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

/// Mirrors web's HandleError: [code] is machine-readable so the UI can
/// offer the right next step -- "no_handle" | "no_group" | "no_balance" |
/// "rate_limited" (per handles.ts's own doc comment on fetchCounterpartyHandle).
public struct UpiHandleError: Error, Sendable {
    public let message: String
    public let code: String?
}

private struct PaymentHandleResponse: Decodable {
    let vpa: String?
    let displayName: String?
    let error: String?
    let code: String?
}

public final class UpiRepository: @unchecked Sendable {
    private var cachedHint: String?
    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

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
        return Domain.isValidVpa(vpa)
    }

    public func createPaymentUrl(
        payeeVpa: String,
        payeeName: String?,
        amountMinor: Int64,
        currency: String = "INR",
        transactionRef: String? = nil,
        note: String? = nil
    ) throws -> String {
        let params = IntentParams(
            vpa: payeeVpa,
            name: payeeName ?? "Sanvya",
            amountMinor: Double(amountMinor),
            note: note,
            ref: transactionRef,
            currency: currency
        )
        return try buildIntentUrl(params).url
    }

    /// Fetch someone's UPI ID in order to pay them (task #30, Splits
    /// settle-up). Straight port of fetchCounterpartyHandle() in
    /// handles.ts. NEVER cached (the [cachedHint] above is for the
    /// CALLER's own handle only -- a different, pre-existing concept).
    ///
    /// This is genuinely new mobile networking surface -- nothing under
    /// apps/ios called `client.functions` before this pass. Verified
    /// against the real FunctionsClient.swift/Types.swift source: on a
    /// non-2xx response, the SDK throws `FunctionsError.httpError(code:data:)`
    /// where `data` is the raw response body, decoded here the same way
    /// web's own `edgeFnMessage()` unwraps the equivalent opaque top-level
    /// error. A 2xx response can ALSO carry `{error, code}` in its body
    /// (the edge function's own "no handle" case) -- checked after a
    /// successful decode too, matching handles.ts's `if (res.error) throw`.
    public func fetchCounterpartyHandle(counterpartyId: String) async throws -> UpiPaymentHandle {
        do {
            let res: PaymentHandleResponse = try await client.functions.invoke(
                "payment-handle",
                options: FunctionInvokeOptions(body: ["action": "get", "counterpartyId": counterpartyId])
            )
            if let err = res.error {
                throw UpiHandleError(message: err, code: res.code)
            }
            guard let vpa = res.vpa else {
                throw UpiHandleError(message: "They haven't added a UPI ID yet.", code: "no_handle")
            }
            return UpiPaymentHandle(vpa: vpa, displayName: res.displayName)
        } catch let error as UpiHandleError {
            throw error
        } catch let error as FunctionsError {
            if case let .httpError(_, data) = error, let parsed = try? JSONDecoder().decode(PaymentHandleResponse.self, from: data) {
                throw UpiHandleError(message: parsed.error ?? "Couldn't reach the payments service.", code: parsed.code)
            }
            throw UpiHandleError(message: error.localizedDescription, code: nil)
        } catch {
            throw UpiHandleError(message: "Couldn't reach the payments service. Check your connection.", code: nil)
        }
    }
}
