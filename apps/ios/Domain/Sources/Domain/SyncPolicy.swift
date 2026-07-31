import Foundation

// Ported from packages/core/sync-policy/src/index.ts (P1.6b). Mirrors
// apps/android/domain/.../syncpolicy/SyncPolicy.kt (P1.6a). Classifies a
// PowerSync upload-queue failure as transient (keep retrying forever) or
// permanent (quarantine after a few attempts) -- PowerSync retries the
// queue IN ORDER, so a permanent failure left unclassified head-of-line
// blocks every unrelated write behind it. Default to transient: an
// unknown failure keeps retrying (recoverable), not quarantined (which
// would silently drop good data on a network blip).
//
// Two message strings below (`explainForUser`'s 42501 and 23503 cases)
// contain a literal U+2014 EM DASH ("—") and, in the 42501 case, a literal
// U+2192 RIGHTWARDS ARROW ("→") -- transcribed character-for-character
// from the TS source and cross-checked against the raw vector JSON bytes
// via Python (`ord(ch)`) before writing this file, mirroring
// SyncPolicy.kt's identical verification.

public let FAILURE_CLASS_TRANSIENT = "transient"
public let FAILURE_CLASS_PERMANENT = "permanent"

public struct FailureInput: Sendable {
    /// HTTP status, when the transport gave us one.
    public let status: Int?
    /// Postgres SQLSTATE from PostgREST.
    public let code: String?
    public let message: String?

    public init(status: Int? = nil, code: String? = nil, message: String? = nil) {
        self.status = status
        self.code = code
        self.message = message
    }
}

public struct Classification: Sendable {
    public let cls: String // FAILURE_CLASS_TRANSIENT | FAILURE_CLASS_PERMANENT
    /// Why, in terms a maintainer can act on.
    public let reason: String

    public init(cls: String, reason: String) {
        self.cls = cls
        self.reason = reason
    }
}

/// Postgres SQLSTATEs that mean "this write is invalid", not "try again".
/// Deliberately a short allow-list of codes we understand.
private let PERMANENT_PG_CODES: Set<String> = [
    "23502", // not_null_violation
    "23503", // foreign_key_violation   <- the orphaned-child case
    "23505", // unique_violation
    "23514", // check_violation
    "22001", // string_data_right_truncation
    "22003", // numeric_value_out_of_range
    "22P02", // invalid_text_representation
    "42501", // insufficient_privilege  <- RLS denial
    "42703", // undefined_column
    "42P01", // undefined_table
    "P0001", // raise_exception (our own triggers)
]

/// SQLSTATEs that look alarming but genuinely resolve on retry. Listed
/// explicitly so they can't be swept up by a broader rule later.
private let TRANSIENT_PG_CODES: Set<String> = [
    "40001", // serialization_failure
    "40P01", // deadlock_detected
    "53300", // too_many_connections
    "57014", // query_canceled
    "08006", // connection_failure
]

private let NETWORK_MESSAGE_RE = rx("failed to fetch|network|timeout|aborted|offline|econn")
private let RLS_MESSAGE_RE = rx("row-level security|violates .*policy")

/// Classify one upload failure. Order is deliberate: an explicit SQLSTATE
/// beats an HTTP status, because PostgREST reports several genuinely
/// different conditions as 400.
public func classifyFailure(_ input: FailureInput) -> Classification {
    let code = (input.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    if !code.isEmpty && TRANSIENT_PG_CODES.contains(code) {
        return Classification(cls: FAILURE_CLASS_TRANSIENT, reason: "postgres \(code) resolves on retry")
    }
    if !code.isEmpty && PERMANENT_PG_CODES.contains(code) {
        return Classification(cls: FAILURE_CLASS_PERMANENT, reason: "postgres \(code) is a rejected write")
    }

    if let status = input.status {
        // 408 timeout and 429 rate-limit are retryable despite being 4xx.
        if status == 408 || status == 429 {
            return Classification(cls: FAILURE_CLASS_TRANSIENT, reason: "http \(status) is retryable")
        }
        // 401 is retryable: the token refreshes and the next attempt
        // succeeds. Quarantining a user's writes because a JWT expired
        // would be terrible.
        if status == 401 {
            return Classification(cls: FAILURE_CLASS_TRANSIENT, reason: "http 401 — token refresh should fix it")
        }
        if status >= 400 && status < 500 {
            return Classification(cls: FAILURE_CLASS_PERMANENT, reason: "http \(status) — the server rejected this")
        }
        if status >= 500 {
            return Classification(cls: FAILURE_CLASS_TRANSIENT, reason: "http \(status) — server-side, try again")
        }
    }

    let message = (input.message ?? "").lowercased()
    // Fetch failures surface as a TypeError with no status at all.
    if NETWORK_MESSAGE_RE.matchesAnywhere(message) {
        return Classification(cls: FAILURE_CLASS_TRANSIENT, reason: "network error")
    }
    // RLS sometimes arrives as prose without a code.
    if RLS_MESSAGE_RE.matchesAnywhere(message) {
        return Classification(cls: FAILURE_CLASS_PERMANENT, reason: "row-level security denial")
    }

    // Unknown: keep retrying. The recoverable mistake.
    return Classification(cls: FAILURE_CLASS_TRANSIENT, reason: "unrecognised failure — retrying is the safe default")
}

/// Attempts before a permanent failure is quarantined.
public let MAX_PERMANENT_ATTEMPTS = 3

/// Should this op be moved to the dead-letter queue? Even a
/// permanent-looking failure gets a few attempts: a foreign key can
/// genuinely resolve if the parent is a little way behind it in the same
/// queue, and a deploy racing a migration can produce a transient 42P01.
public func shouldQuarantine(_ c: Classification, _ attempts: Int) -> Bool {
    c.cls == FAILURE_CLASS_PERMANENT && attempts >= MAX_PERMANENT_ATTEMPTS
}

/// Exponential backoff with a ceiling, for transient retries. Int64
/// throughout (not Int) to avoid overflow for a large `attempts`, mirroring
/// SyncPolicy.kt's Long-based computation -- `base * 2**(attempts-1)` grows
/// fast, and this is only ever clamped down to `ceiling` afterward anyway.
public func backoffMs(_ attempts: Int, base: Int = 1000, ceiling: Int = 60_000) -> Int {
    let exp = max(0, attempts - 1)
    let scaled = Int64(base) * (Int64(1) << Int64(min(exp, 62))) // cap the shift so it can't trap on huge `attempts`
    return Int(min(Int64(ceiling), scaled))
}

/// Plain-language explanation for the recovery screen. Users see this, so
/// it says what happened and what they can do -- never `23503`. The
/// maintainer-facing detail is in the diagnostics log.
public func explainForUser(_ input: FailureInput) -> String {
    let code = (input.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    switch code {
    case "23503":
        return "It refers to something that no longer exists — the group or account it belonged to may have been deleted."
    case "23505":
        return "It looks like this was already saved once."
    case "23514", "P0001":
        return "Some of the numbers didn't add up, so the server wouldn't accept it."
    case "42501":
        // Deliberately does NOT assert "you were removed from the group":
        // the same code is raised when the parent row (e.g. the group
        // itself) never reached the server, in which case the user is
        // still very much a member and telling them otherwise sends them
        // looking in the wrong place.
        return "You don't have permission to save this yet. If it belongs to a group, try Settings → Check for unsynced data — the group itself may not have uploaded."
    case "23502":
        return "Something required was missing from it."
    default:
        return classifyFailure(input).cls == FAILURE_CLASS_PERMANENT
            ? "The server wouldn't accept it."
            : "It hasn't uploaded yet. We'll keep trying."
    }
}
