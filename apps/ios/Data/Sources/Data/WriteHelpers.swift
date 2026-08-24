import Foundation
import PowerSync

// Generic synced-row write helpers (P2.5).
//
// Swift mirror of apps/web/src/write.ts's insertRow/updateRow/softDelete,
// which auto-fill id/created_at/updated_at (and user_id, with the same
// shared-ledger-table exception). Every domain repository builds its writes
// on top of these three functions rather than hand-rolling INSERT/UPDATE SQL
// per table, matching the web app's own stated convention (CLAUDE.md
// "Conventions": "write with write.ts helpers (insertRow/updateRow/
// softDelete) -- they auto-fill id/user_id/timestamps"). Mirrors
// apps/android/data/.../repository/WriteHelpers.kt exactly.
//
// [userId] is an explicit parameter here, not read from a magic global store
// the way write.ts reads it via getUserId() from a reactive auth context --
// Phase 2 (this file) is data-layer only, with no UI/auth-state layer built
// yet (that's Phase 3+), so repositories take the caller's current user id
// explicitly rather than assuming a not-yet-designed global source of truth.

/// Tables scoped by group_id, not user_id, and with no user_id column at all
/// -- adding one would make the INSERT fail. Identical list to write.ts's.
private let sharedLedgerTables: Set<String> = [
    "split_groups", "expenses", "expense_items", "settlements",
    "split_invitations", "connections", "profiles",
]

/// Lowercase, matching web and Android. See Ids.swift for why that matters.
public func newId() -> String { UUID().canonicalString }

public func nowIso() -> String { ISO8601DateFormatter().string(from: Date()) }

/// Insert a row into a synced table, filling id/created_at/updated_at.
/// [userId] is added automatically unless [values] already has a "user_id"
/// key or [table] is a shared-ledger table.
@discardableResult
public func insertRow(
    db: PowerSyncDatabaseProtocol,
    table: String,
    userId: String,
    values: [String: Sendable?]
) async throws -> String {
    let id = newId()
    let ts = nowIso()
    var row: [String: Sendable?] = [:]
    row["id"] = id
    row["created_at"] = ts
    row["updated_at"] = ts
    for (k, v) in values { row[k] = v }
    if values["user_id"] == nil && !sharedLedgerTables.contains(table) {
        row["user_id"] = userId
    }
    let keys = Array(row.keys)
    let placeholders = keys.map { _ in "?" }.joined(separator: ",")
    try await db.execute(
        sql: "INSERT INTO \(table) (\(keys.joined(separator: ","))) VALUES (\(placeholders))",
        parameters: keys.map { row[$0] ?? nil }
    )
    return id
}

/// Update columns on a synced row by id (sets updated_at automatically).
public func updateRow(
    db: PowerSyncDatabaseProtocol,
    table: String,
    id: String,
    values: [String: Sendable?]
) async throws {
    if values.isEmpty { return }
    let keys = Array(values.keys)
    let sets = (keys.map { "\($0) = ?" } + ["updated_at = ?"]).joined(separator: ", ")
    var params: [Sendable?] = keys.map { values[$0] ?? nil }
    params.append(nowIso())
    params.append(id)
    try await db.execute(sql: "UPDATE \(table) SET \(sets) WHERE id = ?", parameters: params)
}

/// Soft-delete a row (sets deleted_at) so the change syncs.
public func softDelete(db: PowerSyncDatabaseProtocol, table: String, id: String) async throws {
    let ts = nowIso()
    try await db.execute(
        sql: "UPDATE \(table) SET deleted_at = ?, updated_at = ? WHERE id = ?",
        parameters: [ts, ts, id]
    )
}
