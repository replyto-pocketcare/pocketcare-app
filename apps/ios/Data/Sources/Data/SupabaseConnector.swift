import Foundation

// SupabaseConnector — bridges PowerSync to Supabase on iOS.
//
// Ported from packages/db/src/connector.ts (P2.2b).
// Mirrors apps/android/data/.../sync/SupabaseConnector.kt (P2.2a).
//
// - fetchCredentials: gives PowerSync the current Supabase JWT.
// - uploadData: flushes the local write queue to Postgres, preserving order.
//
// Financial-safety note: writes are applied in queue order and retried on
// failure; because the ledger is append-only and server-authoritative,
// replays are safe (no in-place money mutation).
//
// Coalescing: consecutive ops sharing the same table + op type are batched
// into a single PostgREST request (array upsert / id IN (...) delete). This
// turns a bulk import of N transactions into a handful of requests while
// preserving queue ordering (FK ordering like account-before-txn untouched).
// PATCH always stays per-row: two updates to the same table can touch
// different columns and must not be merged.

import PowerSync
import Supabase

/// Postgres schema that holds all PocketCare tables.
public let DB_SCHEMA = "pocketcare"

// MARK: - SyncDiagnostic

/// Optional sink for structured sync failures.
///
/// A module-level hook rather than an init parameter, so this package stays
/// free of any dependency on the app's diagnostics layer. The app opts in by
/// calling setSyncDiagnosticSink at startup.
public struct SyncDiagnostic: Sendable {
    public let table: String
    public let op: String
    public let rows: Int
    public let code: String?
    public let message: String?
    public let cls: String?
    public let attempts: Int?
    public let quarantined: Bool?
}

// Swift 6: nonisolated(unsafe) for a simple nullable callback.
nonisolated(unsafe) private var diagnosticSink: (@Sendable (SyncDiagnostic) -> Void)? = nil

public func setSyncDiagnosticSink(_ fn: (@Sendable (SyncDiagnostic) -> Void)?) {
    diagnosticSink = fn
}

// MARK: - FaultInjection

/// FAULT INJECTION — dev only.
///
/// Makes unreachable paths reachable (e.g. an RLS denial you can't produce
/// on demand). Matches connector.ts's fault injection semantics exactly.
public struct FaultInjection: Sendable {
    /// Unqualified table name, or "*" for everything.
    public let table: String
    /// SQLSTATE to report, e.g. "42501" (RLS) or "23503" (foreign key).
    public let code: String
    public let message: String?
    public let status: Int?

    public init(table: String, code: String, message: String? = nil, status: Int? = nil) {
        self.table = table
        self.code = code
        self.message = message
        self.status = status
    }
}

nonisolated(unsafe) private var fault: FaultInjection? = nil

public func setFaultInjection(_ f: FaultInjection?) { fault = f }
public func getFaultInjection() -> FaultInjection? { fault }

private func injectedErrorFor(table: String) -> FailureDetails? {
    guard let f = fault else { return nil }
    let bare = table.contains(".") ? String(table.split(separator: ".").last ?? Substring(table)) : table
    guard f.table == "*" || f.table == bare else { return nil }
    return FailureDetails(
        code: f.code,
        message: f.message ?? "injected fault (\(f.code)) for \(bare)",
        status: f.status
    )
}

// MARK: - SupabaseConnector

/// Keys bumped this session (in-memory; cleared on success).
nonisolated(unsafe) private var bumped = Set<String>()

private func reportSyncDiagnostic(_ d: SyncDiagnostic) {
    // Diagnostics must never make a sync failure worse than it already is.
    diagnosticSink?(d)
}

/// Convert a PowerSync CrudEntry to a CrudOpSummary for quarantine tracking.
private func toOpSummary(_ entry: CrudEntry) -> CrudOpSummary {
    CrudOpSummary(
        // entry.clientId is a non-optional Int64 in the real SDK (confirmed via
        // PowerSync Swift's DocC index and CrudEntry.swift source: `let clientId:
        // Int64`, no `?`) — unlike Kotlin's nullable clientId, so there's nothing
        // to .map over. Widens implicitly to CrudOpSummary.clientId's Int64? field.
        clientId: entry.clientId,
        table: entry.table,
        op: entry.op.rawValue,
        id: entry.id,
        // opDataTyped, not opData: CrudEntry.opData (confirmed via the real
        // CrudEntry.swift source) is a *deprecated, stringified* accessor —
        // `[String: String?]?` — that turns every value, including money minor
        // units, into a string for backwards compatibility. opDataTyped
        // (`[String: JsonValue]?`) is the real typed data. Using opData here
        // would put stringified numbers into the dead-letter record.
        payloadJson: encodePayload(entry.opDataTyped?.mapValues { anyValue(from: $0) })
    )
}

/// Extract FailureDetails from any thrown error.
private func extractFailure(_ error: Error) -> FailureDetails {
    // supabase-swift wraps PostgREST errors; we extract what we can.
    let msg = error.localizedDescription
    // PostgREST errors often include "code" in their userInfo or message.
    // Without a concrete type match, surface what's available.
    return FailureDetails(code: nil, message: msg, status: nil)
}

public final class SupabaseConnector: PowerSyncBackendConnectorProtocol, @unchecked Sendable {
    private let client: SupabaseClient
    private let powerSyncUrl: String
    private let schema: String

    public init(
        client: SupabaseClient,
        powerSyncUrl: String,
        schema: String = DB_SCHEMA
    ) {
        self.client = client
        self.powerSyncUrl = powerSyncUrl
        self.schema = schema
    }

    public func fetchCredentials() async throws -> PowerSyncCredentials? {
        guard let session = try? await client.auth.session else { return nil }
        return PowerSyncCredentials(
            endpoint: powerSyncUrl,
            token: session.accessToken
        )
    }

    public func uploadData(database: PowerSyncDatabaseProtocol) async throws {
        guard let batch = try await database.getCrudBatch() else { return }

        let ops = batch.crud
        var i = 0

        while i < ops.count {
            let op = ops[i]
            let rel = client.schema(schema).from(op.table)

            // Extend the run while the next op targets the same table + op type.
            // PATCH stays per-row (different columns may be touched).
            var j = i + 1
            while j < ops.count
                && ops[j].table == op.table
                && ops[j].op == op.op
                && op.op != .patch
            {
                j += 1
            }
            let run = Array(ops[i..<j])

            // Fault injection short-circuits before any real network call.
            let injected = injectedErrorFor(table: "\(schema).\(op.table)")
            var failure: FailureDetails? = injected

            if failure == nil {
                do {
                    switch op.op {
                    case .put:
                        // opDataTyped (not opData) — see the comment on toOpSummary:
                        // opData stringifies every value, which would upload money
                        // minor-unit columns as JSON strings instead of integers.
                        var rows: [[String: AnyJSON]] = run.map { entry in
                            var row: [String: AnyJSON] = [:]
                            if let d = entry.opDataTyped {
                                for (k, v) in d { row[k] = anyJSON(from: v) }
                            }
                            row["id"] = .string(entry.id)
                            return row
                        }
                        try await rel.upsert(rows).execute()
                    case .delete:
                        let ids = run.map { $0.id }
                        try await rel.delete().in("id", value: ids).execute()
                    case .patch:
                        var data: [String: AnyJSON] = [:]
                        if let d = op.opDataTyped {
                            for (k, v) in d { data[k] = anyJSON(from: v) }
                        }
                        try await rel.update(data).eq("id", value: op.id).execute()
                    @unknown default:
                        break
                    }
                } catch {
                    failure = extractFailure(error)
                }
            }

            if let failure {
                let summaries = run.map { toOpSummary($0) }
                let verdict = await handleUploadFailure(
                    db: database,
                    run: summaries,
                    failure: failure,
                    onBump: { k in bumped.insert(k) }
                )

                print("[PocketCare sync] upload failed for \(schema).\(op.table) "
                    + "(\(op.op.rawValue), \(run.count) row(s), attempt \(verdict.attempts), "
                    + "\(verdict.classification.cls))"
                    + (verdict.quarantined ? " — moved to Problems syncing" : ""))

                reportSyncDiagnostic(SyncDiagnostic(
                    table: "\(schema).\(op.table)",
                    op: op.op.rawValue,
                    rows: run.count,
                    code: failure.code,
                    message: failure.message,
                    cls: verdict.classification.cls,
                    attempts: verdict.attempts,
                    quarantined: verdict.quarantined
                ))

                if verdict.quarantined {
                    i = j
                    continue
                }
                throw NSError(domain: "PocketCareSync", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: failure.message ?? "Upload failed"])
            }

            // Succeeded — clear retry counters for this run.
            for entry in run {
                let key = opKey(table: entry.table, op: entry.op.rawValue, rowId: entry.id)
                if bumped.remove(key) != nil {
                    await clearAttempts(db: database, key: key)
                }
            }
            i = j
        }

        try await batch.complete()
    }
}

// MARK: - JsonValue → AnyJSON / Any conversion
//
// PowerSync's CrudEntry exposes typed op data as `opDataTyped: JsonParam?`
// (JsonParam = [String: JsonValue]), confirmed via the real source at the
// pinned commit (Sources/PowerSync/Protocol/db/JsonParam.swift). JsonValue
// has its own `toValue() -> Any?`, but that method is NOT `public` in the
// SDK — it's internal to the PowerSync module and inaccessible here — so we
// need our own converters. Two are needed because they target different
// destination types: AnyJSON for supabase-swift's PostgREST builder, and
// plain Any? for Quarantine.swift's encodePayload (JSONSerialization-based).

/// Convert a PowerSync JsonValue into supabase-swift's AnyJSON, preserving the
/// real type (Int/Double/Bool/String/null/array/object) instead of stringifying.
///
/// supabase-swift's real AnyJSON cases (confirmed via source at the pinned
/// commit, Sources/Helpers/AnyJSON/AnyJSON.swift): .null, .bool(Bool),
/// .integer(Int), .double(Double), .string(String), .object(JSONObject),
/// .array(JSONArray). There is no .number or .boolean case — those were
/// guesses, not the real API.
private func anyJSON(from value: JsonValue) -> AnyJSON {
    switch value {
    case .null: return .null
    case .string(let s): return .string(s)
    case .int(let n): return .integer(n)
    case .double(let d): return .double(d)
    case .bool(let b): return .bool(b)
    case .array(let arr): return .array(arr.map { anyJSON(from: $0) })
    case .object(let obj): return .object(obj.mapValues { anyJSON(from: $0) })
    }
}

/// Convert a PowerSync JsonValue into a plain Swift value, for encodePayload's
/// `[String: Any?]?` input (the quarantine dead-letter record).
private func anyValue(from value: JsonValue) -> Any? {
    switch value {
    case .null: return nil
    case .string(let s): return s
    case .int(let n): return n
    case .double(let d): return d
    case .bool(let b): return b
    case .array(let arr): return arr.map { anyValue(from: $0) as Any }
    case .object(let obj): return obj.mapValues { anyValue(from: $0) as Any }
    }
}
