import Foundation
import Domain
import PowerSync
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

/// One row of `payment_handle_disclosures` — who fetched your UPI ID, and when.
///
/// `viewerName` is nil when neither profile table knows this viewer, so the
/// VIEW can name them in the user's language rather than this layer hardcoding
/// "Someone" (the same rule `LedgerRepository`'s split-banner participants
/// follow).
public struct HandleDisclosure: Sendable, Identifiable {
    public let id: String
    public let viewerUserId: String
    public let createdAtIso: String
    public let viewerName: String?

    public init(id: String, viewerUserId: String, createdAtIso: String, viewerName: String?) {
        self.id = id
        self.viewerUserId = viewerUserId
        self.createdAtIso = createdAtIso
        self.viewerName = viewerName
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
    let hint: String?
    let ok: Bool?
    let error: String?
    let code: String?
}

/// One `payment_handles` row, as the owner may read it.
///
/// Snake-cased to match the columns, the same way `NotificationPrefs` is: the
/// PostgREST decoder does no key conversion, and a `CodingKeys` block for two
/// fields would be more ceremony than the names it renames.
private struct MyHandleRow: Decodable {
    let handle_hint: String?
    let deleted_at: String?
}

public final class UpiRepository: @unchecked Sendable {
    private let client: SupabaseClient
    private let db: PowerSyncDatabaseProtocol
    private let defaults: UserDefaults
    /// The signed-in user, read on every call rather than captured once — the
    /// same shape `SecurityRepository` and `RepairRepository` already take.
    private let getUserId: @Sendable () -> String?

    public init(
        client: SupabaseClient,
        db: PowerSyncDatabaseProtocol,
        defaults: UserDefaults = .standard,
        getUserId: @escaping @Sendable () -> String?
    ) {
        self.client = client
        self.db = db
        self.defaults = defaults
        self.getUserId = getUserId
    }

    /**
     The masked hint, and ONLY the masked hint.

     Web keeps this in `localStorage` under `pc_upi_hint`; the same key is used
     here so the two clients mean the same thing by it. The real VPA is
     deliberately never persisted on a device — see the file comment. This
     exists so the Settings panel can say "you have one" while offline instead
     of showing an empty form to someone who already saved a handle.

     Was an in-memory field until this pass, which on a phone is close to no
     cache at all: iOS terminates a backgrounded app routinely, and every such
     termination put the panel back to "add a UPI ID".
     */
    public func getCachedHint() -> String? {
        defaults.string(forKey: Self.hintKey)
    }

    public func rememberHint(_ hint: String?) {
        if let hint {
            defaults.set(hint, forKey: Self.hintKey)
        } else {
            defaults.removeObject(forKey: Self.hintKey)
        }
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

    /**
     One call to the `payment-handle` Edge Function, unwrapped the way web's own
     `callFn()` + `edgeFnMessage()` pair unwraps it.

     This is genuinely new mobile networking surface — nothing under apps/ios
     called `client.functions` before this repository. Verified against the real
     FunctionsClient.swift/Types.swift source: on a non-2xx response the SDK
     throws `FunctionsError.httpError(code:data:)` where `data` is the raw
     response body, decoded here the same way web's own `edgeFnMessage()`
     unwraps the equivalent opaque top-level error. A 2xx response can ALSO
     carry `{error, code}` in its body — the function always answers HTTP 200
     with the payload in the body, its `json()` helper says so — which is
     checked after a successful decode too, matching handles.ts's
     `if (res.error) throw`.
     */
    private func callFn(_ body: [String: String]) async throws -> PaymentHandleResponse {
        do {
            let res: PaymentHandleResponse = try await client.functions.invoke(
                "payment-handle",
                options: FunctionInvokeOptions(body: body)
            )
            if let err = res.error {
                throw UpiHandleError(message: err, code: res.code)
            }
            return res
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

    /**
     The masked hint for your OWN handle, or nil if you haven't added one.

     Read directly from the table rather than through the Edge Function, exactly
     as web's `getMyPaymentHandle()` does: the owner RLS policy already permits
     it, and `handle_hint` is masked by construction — `akh****@okhdfcbank` — so
     nothing secret crosses the wire. The ciphertext in `handle_enc` stays
     useless to the client either way, since only the function holds the key.

     Schema-qualified, per golden rule #3 — a bare `from()` resolves to `public`
     and 404s.

     `deleted_at` is filtered in Swift rather than with a PostgREST is-null
     operator: there is no verified supabase-swift spelling of that filter
     anywhere in this module, the row set here is at most one per user, and
     reading the column costs nothing while guessing an API costs a CI round
     trip.

     Offline — or with the 0041 migration not yet applied — this falls back to
     the cached hint rather than claiming they have no UPI ID. Telling someone
     their saved details are gone because the network blinked is worse than
     showing a stale mask; web's comment says the same.
     */
    public func getMyPaymentHandle() async -> String? {
        guard let userId = getUserId() else { return getCachedHint() }
        let rows: [MyHandleRow]
        do {
            rows = try await client.schema(Self.schema)
                .from(Self.paymentHandlesTable)
                .select("handle_hint,deleted_at")
                .eq("user_id", value: userId)
                .execute()
                .value
        } catch {
            return getCachedHint()
        }
        let hint = rows.first(where: { $0.deleted_at == nil })?.handle_hint
        rememberHint(hint)
        return hint
    }

    /**
     Save (or replace) your own UPI ID. Returns the masked hint to show.

     Rejected for guests server-side too — a DB trigger, plus the function's own
     `guest_not_allowed` — so the panel's guest branch is a courtesy and not the
     control.
     */
    public func savePaymentHandle(vpa: String, displayName: String? = nil) async throws -> String {
        var body = ["action": "set", "vpa": vpa]
        if let displayName, !displayName.isEmpty {
            body["displayName"] = displayName
        }
        let res = try await callFn(body)
        let hint = res.hint ?? maskVpa(vpa)
        rememberHint(hint)
        return hint
    }

    /// Remove your UPI ID. Existing disclosures stay in the audit trail.
    public func forgetPaymentHandle() async throws {
        _ = try await callFn(["action": "forget"])
        rememberHint(nil)
    }

    /**
     Who has fetched your UPI ID, newest first. Your own audit trail.

     `payment_handle_disclosures` IS synced (unlike `payment_handles`), so this
     reads from local SQLite like everything else and works offline — web's
     `useHandleDisclosures()` makes the same point in its own comment.

     Web resolves the viewer's name through a separate `useUserProfiles()` map;
     the join is done in SQL here because there is no equivalent hook to combine
     with, and it is the same union: `public_profiles` for co-members you can
     see, `profiles` for yourself.
     */
    public func watchDisclosures() throws -> AsyncThrowingStream<[HandleDisclosure], Error> {
        try db.watch(
            sql: """
            SELECT d.id AS id, d.viewer_user_id AS viewer_user_id, d.created_at AS created_at,
                   COALESCE(pub.display_name, own.display_name) AS display_name,
                   COALESCE(pub.email, own.email) AS email
              FROM payment_handle_disclosures d
              LEFT JOIN public_profiles pub ON pub.id = d.viewer_user_id
              LEFT JOIN profiles own ON own.id = d.viewer_user_id
             ORDER BY d.created_at DESC
             LIMIT 50
            """,
            parameters: [],
            mapper: { cursor in
                let name = try cursor.getStringOptional(name: "display_name")
                let email = try cursor.getStringOptional(name: "email")
                let fallback = email?.split(separator: "@").first.map(String.init)
                return HandleDisclosure(
                    id: try cursor.getString(name: "id"),
                    viewerUserId: try cursor.getString(name: "viewer_user_id"),
                    createdAtIso: try cursor.getString(name: "created_at"),
                    viewerName: (name?.isEmpty == false) ? name : fallback
                )
            }
        )
    }

    /**
     Fetch someone's UPI ID in order to pay them (task #30, Splits settle-up).
     Straight port of `fetchCounterpartyHandle()` in handles.ts. NEVER cached
     (`getCachedHint`/`rememberHint` above hold the CALLER's own masked hint
     only — a different concept; a counterparty's VPA is held in memory for one
     settle-up interaction and dropped).
     */
    public func fetchCounterpartyHandle(counterpartyId: String) async throws -> UpiPaymentHandle {
        let res = try await callFn(["action": "get", "counterpartyId": counterpartyId])
        guard let vpa = res.vpa else {
            throw UpiHandleError(message: "They haven't added a UPI ID yet.", code: "no_handle")
        }
        return UpiPaymentHandle(vpa: vpa, displayName: res.displayName)
    }

    /**
     The schema is `pocketcare`, not `sanvya`: the product was renamed but
     `0001_init.sql` created — and every migration since has used — the
     `pocketcare` schema. Golden rule 3 in PROJECT_REFERENCE.md.
     */
    private static let schema = "pocketcare"
    private static let paymentHandlesTable = "payment_handles"
    /// Web's localStorage key, verbatim.
    private static let hintKey = "pc_upi_hint"
}
