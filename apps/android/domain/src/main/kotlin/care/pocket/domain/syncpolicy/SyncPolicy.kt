package care.pocket.domain.syncpolicy

// Ported from packages/core/sync-policy/src/index.ts (P1.6a). Classifies a
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
// via Python (`ord(ch)`) before writing this file, per the same
// verify-don't-transcribe-by-eye discipline the P1.6a reconcile control-byte
// discovery established. Plain printable Unicode text like this isn't at
// risk of the Read-tool misrendering that affected reconcile's literal
// control BYTES -- the risk here is purely transcription typos, not tool
// misdisplay -- but it's still verified rather than assumed.

const val FAILURE_CLASS_TRANSIENT = "transient"
const val FAILURE_CLASS_PERMANENT = "permanent"

data class FailureInput(
    /** HTTP status, when the transport gave us one. */
    val status: Int? = null,
    /** Postgres SQLSTATE from PostgREST. */
    val code: String? = null,
    val message: String? = null,
)

data class Classification(
    val cls: String, // FAILURE_CLASS_TRANSIENT | FAILURE_CLASS_PERMANENT
    /** Why, in terms a maintainer can act on. */
    val reason: String,
)

/**
 * Postgres SQLSTATEs that mean "this write is invalid", not "try again".
 * Deliberately a short allow-list of codes we understand.
 */
private val PERMANENT_PG_CODES = setOf(
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
)

/**
 * SQLSTATEs that look alarming but genuinely resolve on retry. Listed
 * explicitly so they can't be swept up by a broader rule later.
 */
private val TRANSIENT_PG_CODES = setOf(
    "40001", // serialization_failure
    "40P01", // deadlock_detected
    "53300", // too_many_connections
    "57014", // query_canceled
    "08006", // connection_failure
)

private val NETWORK_MESSAGE_RE = Regex("failed to fetch|network|timeout|aborted|offline|econn")
private val RLS_MESSAGE_RE = Regex("row-level security|violates .*policy")

/**
 * Classify one upload failure. Order is deliberate: an explicit SQLSTATE
 * beats an HTTP status, because PostgREST reports several genuinely
 * different conditions as 400.
 */
fun classifyFailure(input: FailureInput): Classification {
    val code = (input.code ?: "").trim()

    if (code.isNotEmpty() && TRANSIENT_PG_CODES.contains(code)) {
        return Classification(FAILURE_CLASS_TRANSIENT, "postgres $code resolves on retry")
    }
    if (code.isNotEmpty() && PERMANENT_PG_CODES.contains(code)) {
        return Classification(FAILURE_CLASS_PERMANENT, "postgres $code is a rejected write")
    }

    val status = input.status
    if (status != null) {
        // 408 timeout and 429 rate-limit are retryable despite being 4xx.
        if (status == 408 || status == 429) {
            return Classification(FAILURE_CLASS_TRANSIENT, "http $status is retryable")
        }
        // 401 is retryable: the token refreshes and the next attempt
        // succeeds. Quarantining a user's writes because a JWT expired
        // would be terrible.
        if (status == 401) {
            return Classification(FAILURE_CLASS_TRANSIENT, "http 401 — token refresh should fix it")
        }
        if (status in 400 until 500) {
            return Classification(FAILURE_CLASS_PERMANENT, "http $status — the server rejected this")
        }
        if (status >= 500) {
            return Classification(FAILURE_CLASS_TRANSIENT, "http $status — server-side, try again")
        }
    }

    val message = (input.message ?: "").lowercase()
    // Fetch failures surface as a TypeError with no status at all.
    if (NETWORK_MESSAGE_RE.containsMatchIn(message)) {
        return Classification(FAILURE_CLASS_TRANSIENT, "network error")
    }
    // RLS sometimes arrives as prose without a code.
    if (RLS_MESSAGE_RE.containsMatchIn(message)) {
        return Classification(FAILURE_CLASS_PERMANENT, "row-level security denial")
    }

    // Unknown: keep retrying. The recoverable mistake.
    return Classification(FAILURE_CLASS_TRANSIENT, "unrecognised failure — retrying is the safe default")
}

/** Attempts before a permanent failure is quarantined. */
const val MAX_PERMANENT_ATTEMPTS = 3

/**
 * Should this op be moved to the dead-letter queue? Even a
 * permanent-looking failure gets a few attempts: a foreign key can
 * genuinely resolve if the parent is a little way behind it in the same
 * queue, and a deploy racing a migration can produce a transient 42P01.
 */
fun shouldQuarantine(c: Classification, attempts: Int): Boolean =
    c.cls == FAILURE_CLASS_PERMANENT && attempts >= MAX_PERMANENT_ATTEMPTS

/** Exponential backoff with a ceiling, for transient retries. */
fun backoffMs(attempts: Int, base: Int = 1000, ceiling: Int = 60_000): Int {
    val exp = kotlin.math.max(0, attempts - 1)
    val scaled = base.toLong() * (1L shl exp) // base * 2**exp; Long to avoid Int overflow for large `attempts`
    return kotlin.math.min(ceiling.toLong(), scaled).toInt()
}

/**
 * Plain-language explanation for the recovery screen. Users see this, so
 * it says what happened and what they can do -- never `23503`. The
 * maintainer-facing detail is in the diagnostics log.
 */
fun explainForUser(input: FailureInput): String {
    val code = (input.code ?: "").trim()
    return when (code) {
        "23503" -> "It refers to something that no longer exists — the group or account it belonged to may have been deleted."
        "23505" -> "It looks like this was already saved once."
        "23514", "P0001" -> "Some of the numbers didn't add up, so the server wouldn't accept it."
        "42501" ->
            // Deliberately does NOT assert "you were removed from the group":
            // the same code is raised when the parent row (e.g. the group
            // itself) never reached the server, in which case the user is
            // still very much a member and telling them otherwise sends
            // them looking in the wrong place.
            "You don't have permission to save this yet. If it belongs to a group, try Settings → Check for unsynced data — the group itself may not have uploaded."
        "23502" -> "Something required was missing from it."
        else -> if (classifyFailure(input).cls == FAILURE_CLASS_PERMANENT) {
            "The server wouldn't accept it."
        } else {
            "It hasn't uploaded yet. We'll keep trying."
        }
    }
}
