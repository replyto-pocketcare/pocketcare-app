import Foundation

// Ported from packages/core/reconcile/src/index.ts (P1.6b). Mirrors
// apps/android/domain/.../reconcile/Reconcile.kt (P1.6a). Deterministic
// checksums for detecting sync drift between the local SQLite DB and the
// remote Supabase source of truth (BigInt FNV-1a in the TS source).
//
// CRITICAL, easy-to-miss fact caught only by inspecting the TS source's raw
// BYTES (not its Read-tool-rendered text, which silently displayed these as
// an empty string and a plain space): `canonical()`'s field-pair join
// separator is the literal control character U+0001 (SOH), and
// `serialize()`'s null/undefined placeholder is the literal control
// character U+0000 (NUL) -- NOT "" and " " as a cursory read suggests.
// Verified by running the REAL TS module against the real golden vectors
// via `node --experimental-strip-types` and cross-checking hex output
// byte-for-byte, then re-confirmed against the (once-fixed) Kotlin port
// with an independent Python re-implementation before writing this file --
// see Reconcile.kt's header for the fuller story. Written here using
// explicit Unicode scalar literals (`"\u{0000}"` / `"\u{0001}"`) rather
// than pasted literal bytes, so the control characters survive verbatim
// through any future re-save of this file by a tool that might otherwise
// normalize an embedded control byte.

/// Minimal dynamic value type for a Row's field values -- Row is a fully
/// dynamic `Record<string, unknown>` in the TS source, so (unlike every
/// other domain ported so far) there is no fixed Swift struct to model it
/// as; this is the smallest type that can round-trip what the golden
/// vectors actually exercise (string/integer/boolean/null) plus the
/// unexercised-but-real object/array/non-integer-number cases.
public enum RowValue: Sendable {
    case null
    case str(String)
    case intNum(Int64)
    case doubleNum(Double)
    case bool(Bool)
    case obj([String: RowValue])
    case arr([RowValue])
}

public typealias Row = [String: RowValue]

public struct ChecksumOptions: Sendable {
    public let ignore: [String]
    public init(ignore: [String] = []) { self.ignore = ignore }
}

// UInt64 throughout: FNV's `& MASK` (MASK = 2^64-1) in the TS source is a
// no-op mask against BigInt arithmetic that's really just "truncate to 64
// bits" -- UInt64 already wraps silently at 64 bits on overflow (using the
// `&*`/`&+` wrapping operators below), matching that truncation exactly
// with no explicit mask needed.
// NOTE: this is NOT the textbook FNV-1a 64-bit offset basis
// (14695981039346656037 / 0xcbf29ce484222325) -- it's the literal decimal
// constant the TS source actually uses (one digit short of the textbook
// value). Verified independently in Python against the real golden
// vectors before writing this file: the textbook offset produces
// "ce0272827b113c20" for the {id:"r1",amount:100,note:"a"} vector, which
// does NOT match the expected "4586515961447bde"; this constant does.
// Matches Reconcile.kt's FNV_OFFSET exactly.
private let FNV_OFFSET: UInt64 = 1469598103934665603
private let FNV_PRIME: UInt64 = 1099511628211

private func fnv1a(_ str: String) -> UInt64 {
    var h = FNV_OFFSET
    // .utf16, not .unicodeScalars or Character iteration: JS strings (and
    // Kotlin's Char) iterate by UTF-16 code unit, and the vectors' fields
    // are all plain ASCII, so this only matters for future non-ASCII input
    // -- kept faithful to the source's iteration granularity regardless.
    for c in str.utf16 {
        h ^= UInt64(c)
        h = h &* FNV_PRIME
    }
    return h
}

/// Minimal JSON.stringify equivalent, only reachable via RowValue.obj/arr --
/// NOT exercised by any golden vector (every tested row's values are
/// string/number/null). Kept reasonably faithful (quoted+escaped strings,
/// bare numbers/booleans/null) rather than perfected, since there is
/// nothing to verify it against.
private func jsonStringify(_ v: RowValue) -> String {
    switch v {
    case .null: return "null"
    case .bool(let b): return b ? "true" : "false"
    case .intNum(let n): return String(n)
    case .doubleNum(let n): return String(n)
    case .str(let s):
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    case .arr(let items):
        return "[" + items.map(jsonStringify).joined(separator: ",") + "]"
    case .obj(let fields):
        return "{" + fields.map { k, vv in "\"\(k)\":\(jsonStringify(vv))" }.joined(separator: ",") + "}"
    }
}

// U+0000 (NUL) -- a literal control character, not a space. See this
// file's header comment for why.
private let NULL_PLACEHOLDER = "\u{0000}"

/// Mirrors the TS source's `serialize()`. The number/non-integer branch
/// (`toPrecision(15)`) has no vector coverage either -- Swift's
/// `String(Double)` is used as a reasonable stand-in, not a verified
/// byte-exact match to JS's toPrecision.
private func serialize(_ v: RowValue) -> String {
    switch v {
    case .null: return NULL_PLACEHOLDER
    case .intNum(let n): return String(n)
    case .doubleNum(let n): return String(n)
    case .bool(let b): return b ? "1" : "0"
    case .obj, .arr: return jsonStringify(v)
    case .str(let s): return s
    }
}

// U+0001 (SOH) field-pair separator -- see this file's header comment.
private let FIELD_SEPARATOR = "\u{0001}"

/// Canonical, order-stable serialization of one row (keys sorted, ignores applied).
private func canonical(_ row: Row, _ ignore: Set<String>) -> String {
    let keys = row.keys.filter { !ignore.contains($0) }.sorted()
    return keys.map { k in "\(k)=\(serialize(row[k]!))" }.joined(separator: FIELD_SEPARATOR)
}

private func hex16(_ n: UInt64) -> String {
    var s = String(n, radix: 16)
    while s.count < 16 { s = "0" + s }
    return s
}

/// Per-row checksum (hex). Two rows with the same non-ignored fields match.
public func rowChecksum(_ row: Row, _ opts: ChecksumOptions = ChecksumOptions()) -> String {
    hex16(fnv1a(canonical(row, Set(opts.ignore))))
}

/// Order-independent checksum of a whole table/set. Rows are folded by XOR
/// of their per-row hashes, so shuffling rows does not change the result
/// and the cost is O(n). Row count is mixed in to catch duplicate/missing rows.
public func checksum(_ rows: [Row], _ opts: ChecksumOptions = ChecksumOptions()) -> String {
    let ignore = Set(opts.ignore)
    var acc: UInt64 = 0
    for r in rows { acc ^= fnv1a(canonical(r, ignore)) }
    acc ^= UInt64(rows.count) &* FNV_PRIME
    return hex16(acc)
}

public struct DriftReport: Sendable {
    public let inSync: Bool
    /// ids present locally but missing remotely (unsynced or dropped).
    public let missingRemote: [String]
    /// ids present remotely but missing locally (not yet pulled).
    public let missingLocal: [String]
    /// ids present on both sides but with differing content.
    public let mismatched: [String]
}

/// Row's `id` field, required to be a string per the TS source's `Row` type.
private func rowId(_ row: Row) -> String {
    guard case let .str(v)? = row["id"] else {
        fatalError("Row.id must be a string")
    }
    return v
}

/// Compare a local snapshot to a remote snapshot and report drift by id and
/// by per-row checksum. `inSync` is true only when all three drift lists
/// are empty.
public func reconcile(_ local: [Row], _ remote: [Row], _ opts: ChecksumOptions = ChecksumOptions()) -> DriftReport {
    var l: [String: String] = [:]
    for r in local { l[rowId(r)] = rowChecksum(r, opts) }
    var remoteMap: [String: String] = [:]
    for r in remote { remoteMap[rowId(r)] = rowChecksum(r, opts) }

    var missingRemote: [String] = []
    var missingLocal: [String] = []
    var mismatched: [String] = []

    for (id, hash) in l {
        if let rh = remoteMap[id] {
            if rh != hash { mismatched.append(id) }
        } else {
            missingRemote.append(id)
        }
    }
    for id in remoteMap.keys where l[id] == nil { missingLocal.append(id) }

    missingRemote.sort(); missingLocal.sort(); mismatched.sort()
    return DriftReport(
        inSync: missingRemote.isEmpty && missingLocal.isEmpty && mismatched.isEmpty,
        missingRemote: missingRemote,
        missingLocal: missingLocal,
        mismatched: mismatched
    )
}
