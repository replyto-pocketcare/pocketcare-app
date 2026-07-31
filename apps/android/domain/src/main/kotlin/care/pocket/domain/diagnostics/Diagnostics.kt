package care.pocket.domain.diagnostics

import java.time.Instant
import java.time.ZoneOffset

// Ported from packages/core/diagnostics/src/index.ts (P1.6a). Support-log
// types and redaction. THE REDACTION IS THE POINT: this is a personal
// finance app, so a support log must never become a leak of someone's
// spending. Keeps what DIAGNOSES a problem (table names, operations, error
// codes, row ids, routes) and drops what merely describes a person's life
// (amounts, merchants, descriptions, emails, payment handles).
//
// This is the highest cross-engine-divergence-risk domain ported so far
// after receipts (P1.5): heavy \b-word-boundary regex, Unicode currency
// symbols (₹€£), and an order-sensitive multi-pass pipeline (secrets ->
// UUID-preservation -> code-protection -> amount-scrubbing) where each
// pass's output feeds the next. Every regex below is transcribed VERBATIM
// from the TS source, not re-derived, mirroring ReceiptsMoneyText.kt's
// established discipline for this same class of risk. \b/\w default to
// the same ASCII word/non-word classification in Kotlin's java.util.regex
// as JS's non-/u \b/\w -- verified via search earlier in this porting
// effort (P1.5) and unchanged here.

const val LOG_LEVEL_ERROR = "error"
const val LOG_LEVEL_WARN = "warn"
const val LOG_LEVEL_INFO = "info"

data class LogEntry(
    /** Epoch ms. */
    val at: Long,
    val level: String, // LOG_LEVEL_ERROR | LOG_LEVEL_WARN | LOG_LEVEL_INFO
    /** Where it came from: "sync", "console", "window", "app". */
    val scope: String,
    val message: String,
    /** Route the user was on, for reproducing. */
    val route: String? = null,
    /** Structured extras (already redacted). */
    val detail: DetailValue.Obj? = null,
)

/** Placeholder tokens -- deliberately obvious in a log so nothing looks real. */
object Redacted {
    const val AMOUNT = "[amount]"
    const val EMAIL = "[email]"
    const val VPA = "[upi-id]"
    const val TOKEN = "[token]"
    const val TEXT = "[text]"
}

/** Reused from Reconcile.kt's RowValue in spirit, but a fresh type: this
 * domain's dynamic "detail" object is a distinct concept (redacted support
 * log extras, not a DB row), and keeping the two separate avoids coupling
 * an unrelated future change in either domain to the other. */
sealed class DetailValue {
    object Null : DetailValue()
    data class Str(val value: String) : DetailValue()
    data class IntNum(val value: Long) : DetailValue()
    data class DoubleNum(val value: Double) : DetailValue()
    data class Bool(val value: Boolean) : DetailValue()
    data class Arr(val value: List<DetailValue>) : DetailValue()
    /** LinkedHashMap: JSON.stringify (used by formatLog's detail rendering)
     * is insertion-order-sensitive, unlike the vector comparator's
     * object-equality checks elsewhere in this porting effort -- so unlike
     * Reconcile.kt's RowValue.Obj (a plain Map is fine there), order must
     * be preserved here. No golden vector currently exercises a non-empty
     * detail through formatLog, but this is kept correct anyway per this
     * codebase's "unexercised branches stay reasonably faithful" standard. */
    data class Obj(val value: LinkedHashMap<String, DetailValue>) : DetailValue()
}

/**
 * Keys whose VALUES are never diagnostic and often personal. Matched
 * case-insensitively, on substring, so `merchant_name` and `raw_text` are
 * both caught.
 */
private val SENSITIVE_KEYS = listOf(
    "amount", "total", "subtotal", "balance", "price", "share_amount", "paid_amount",
    "description", "note", "merchant", "title", "name", "label",
    "email", "vpa", "handle", "upi",
    "raw_text", "parsed_json", "token", "key", "secret", "password", "authorization",
)

private fun isSensitiveKey(key: String): Boolean {
    val k = key.lowercase()
    return SENSITIVE_KEYS.any { k.contains(it) }
}

/**
 * Keys holding free-form prose. Their values get the full number-scrubbing
 * treatment, because a message can carry an amount anywhere in it.
 */
private val FREE_TEXT_KEYS = listOf("message", "msg", "error", "reason", "stack", "text", "body")

private fun isFreeTextKey(key: String): Boolean {
    val k = key.lowercase()
    return FREE_TEXT_KEYS.any { k == it || k.endsWith("_$it") }
}

/** Anything that looks like an id stays -- it's how we find the row. */
private val UUID_RE = Regex(
    "\\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\b",
    RegexOption.IGNORE_CASE,
)
private val UUID_RESTORE_RE = Regex(" UUID(\\d+) ")

/** Run `fn` with UUIDs stashed out of harm's way, then restore them. */
private fun preservingUuids(input: String, fn: (String) -> String): String {
    val uuids = mutableListOf<String>()
    val masked = UUID_RE.replace(input) { m ->
        uuids.add(m.value)
        " UUID${uuids.size - 1} "
    }
    val transformed = fn(masked)
    return UUID_RESTORE_RE.replace(transformed) { m ->
        m.groupValues[1].toIntOrNull()?.let { uuids.getOrNull(it) } ?: ""
    }
}

private val BEARER_RE = Regex("\\bBearer\\s+[A-Za-z0-9._\\-]+", RegexOption.IGNORE_CASE)
private val EYJ_RE = Regex("\\beyJ[A-Za-z0-9._\\-]{20,}")
private val SECRET_PREFIX_RE = Regex("\\b(sk|pk|rzp|whsec)[-_][A-Za-z0-9_\\-]{8,}", RegexOption.IGNORE_CASE)
// Emails before VPAs -- an email is also `x@y` shaped.
private val EMAIL_RE = Regex("\\b[\\w.+-]+@[\\w-]+\\.[\\w.-]{2,}\\b")
private val VPA_LOOSE_RE = Regex("\\b[\\w.\\-]{2,}@[a-z]{2,}\\b", RegexOption.IGNORE_CASE)

/**
 * Strip credentials and contact details only. NEVER touches numbers.
 * Used for values under keys we already know aren't money, where guessing
 * from shape would destroy the diagnosis.
 */
fun redactSecrets(input: String): String {
    if (input.isEmpty()) return ""
    return preservingUuids(input) { s ->
        var out = s
        out = BEARER_RE.replace(out, "Bearer ${Redacted.TOKEN}")
        out = EYJ_RE.replace(out, Redacted.TOKEN)
        out = SECRET_PREFIX_RE.replace(out, Redacted.TOKEN)
        out = EMAIL_RE.replace(out, Redacted.EMAIL)
        out = VPA_LOOSE_RE.replace(out, Redacted.VPA)
        out
    }
}

private val CODE_RE = Regex(
    "((?:\"|')?\\bcode(?:\"|')?\\s*[:=]\\s*(?:\"|')?)([A-Za-z0-9]{2,10})",
    RegexOption.IGNORE_CASE,
)
private val CODE_RESTORE_RE = Regex(" CODE(\\d+) ")
private val SYMBOL_AMOUNT_RE = Regex(
    "(?:₹|Rs\\.?|INR|\\$|€|£)\\s*-?[\\d,]+(?:\\.\\d{1,2})?",
    RegexOption.IGNORE_CASE,
)
private val THOUSANDS_AMOUNT_RE = Regex("\\b-?\\d{1,3}(?:,\\d{2,3})+(?:\\.\\d{1,2})?\\b")
private val DECIMAL_AMOUNT_RE = Regex("\\b-?\\d+\\.\\d{1,2}\\b")
private val LONG_INT_AMOUNT_RE = Regex("\\b\\d{4,}\\b")

/**
 * Scrub a free-text string: secrets AND anything money-shaped. Used for
 * log MESSAGES, where there is no key to say what a number means, so we
 * assume the worst.
 */
fun redactText(input: String): String {
    if (input.isEmpty()) return ""
    return preservingUuids(redactSecrets(input)) { s ->
        var out = s
        // Protect SQLSTATE / error codes before the money passes run -- a
        // serialised PostgREST error arrives here as free text where the
        // 5-digit code is shape-identical to an amount.
        val codes = mutableListOf<String>()
        out = CODE_RE.replace(out) { m ->
            val lead = m.groupValues[1]
            val code = m.groupValues[2]
            codes.add(code)
            "$lead CODE${codes.size - 1} "
        }
        // Symbol-prefixed, or a bare number with a decimal or thousands group.
        out = SYMBOL_AMOUNT_RE.replace(out, Redacted.AMOUNT)
        out = THOUSANDS_AMOUNT_RE.replace(out, Redacted.AMOUNT)
        out = DECIMAL_AMOUNT_RE.replace(out, Redacted.AMOUNT)
        // Long bare integers are minor-unit amounts (1258784 = ₹12,587.84).
        out = LONG_INT_AMOUNT_RE.replace(out, Redacted.AMOUNT)
        CODE_RESTORE_RE.replace(out) { m ->
            m.groupValues[1].toIntOrNull()?.let { codes.getOrNull(it) } ?: ""
        }
    }
}

/** Keep the SHAPE of a redacted value -- null vs missing vs present matters. */
private fun redactedPlaceholderFor(value: DetailValue): DetailValue = when (value) {
    is DetailValue.Null -> value
    is DetailValue.IntNum, is DetailValue.DoubleNum -> DetailValue.Str(Redacted.AMOUNT)
    else -> DetailValue.Str(Redacted.TEXT)
}

/**
 * Scrub a structured object. Key-based rather than value-based wherever
 * possible: knowing that `share_amount` was present is diagnostic, knowing
 * it was ₹4,284.90 is not.
 */
fun redactDetail(input: DetailValue, depth: Int = 0): DetailValue {
    if (input is DetailValue.Null) return input
    if (depth > 4) return DetailValue.Str("[deep]")

    return when (input) {
        is DetailValue.Null -> input // unreachable (handled above); kept for `when` exhaustiveness
        is DetailValue.Str -> DetailValue.Str(redactSecrets(input.value))
        is DetailValue.IntNum, is DetailValue.Bool, is DetailValue.DoubleNum -> input
        is DetailValue.Arr -> {
            // Cap arrays: a 200-row upload batch is noise, its length is the signal.
            val capped = input.value.take(10).map { redactDetail(it, depth + 1) }
            if (input.value.size > 10) {
                DetailValue.Arr(capped + DetailValue.Str("…+${input.value.size - 10} more"))
            } else {
                DetailValue.Arr(capped)
            }
        }
        is DetailValue.Obj -> {
            val out = LinkedHashMap<String, DetailValue>()
            for ((k, v) in input.value) {
                out[k] = when {
                    isSensitiveKey(k) -> redactedPlaceholderFor(v)
                    isFreeTextKey(k) && v is DetailValue.Str -> DetailValue.Str(redactText(v.value))
                    else -> redactDetail(v, depth + 1)
                }
            }
            DetailValue.Obj(out)
        }
    }
}

/** Build a fully-scrubbed entry. The only supported way to create one. */
fun makeEntry(
    level: String,
    scope: String,
    message: String,
    route: String? = null,
    detail: DetailValue.Obj? = null,
    at: Long? = null,
): LogEntry {
    return LogEntry(
        at = at ?: System.currentTimeMillis(),
        level = level,
        scope = scope,
        // Cap length: a stack trace or a giant JSON blob crowds out everything else.
        message = redactText(message).take(500),
        route = if (!route.isNullOrEmpty()) route else null,
        detail = detail?.let { redactDetail(it) as DetailValue.Obj },
    )
}

/** Minimal JSON.stringify equivalent for a detail object -- NOT exercised
 * by any golden vector (both formatLog vectors carry no detail), but kept
 * insertion-order-faithful (LinkedHashMap) since formatLog's output is
 * compared as an exact string, unlike the object-keyed comparisons used
 * everywhere else in this porting effort. */
private fun jsonStringify(v: DetailValue): String = when (v) {
    is DetailValue.Null -> "null"
    is DetailValue.Bool -> if (v.value) "true" else "false"
    is DetailValue.IntNum -> v.value.toString()
    is DetailValue.DoubleNum -> v.value.toString()
    is DetailValue.Str -> "\"" + v.value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
    is DetailValue.Arr -> v.value.joinToString(",", "[", "]") { jsonStringify(it) }
    is DetailValue.Obj -> v.value.entries.joinToString(",", "{", "}") { (k, vv) -> "\"$k\":${jsonStringify(vv)}" }
}

private fun hhmmssUtc(epochMs: Long): String {
    val t = Instant.ofEpochMilli(epochMs).atZone(ZoneOffset.UTC)
    return "%02d:%02d:%02d".format(t.hour, t.minute, t.second)
}

/**
 * Render the log as plain text for copy/share. Plain text on purpose: it
 * survives being pasted into WhatsApp, an email or a GitHub issue, which
 * is how it will actually reach us.
 */
fun formatLog(entries: List<LogEntry>, context: Map<String, String?> = emptyMap()): String {
    val head = context.entries.joinToString("\n") { (k, v) -> "$k: ${v ?: "—"}" }

    val body = if (entries.isEmpty()) {
        "(no events captured)"
    } else {
        entries.joinToString("\n") { e ->
            val time = hhmmssUtc(e.at)
            val detail = if (e.detail != null && e.detail.value.isNotEmpty()) " ${jsonStringify(e.detail)}" else ""
            val route = if (!e.route.isNullOrEmpty()) " (${e.route})" else ""
            val levelPadded = e.level.uppercase().padEnd(5)
            "$time $levelPadded [${e.scope}]$route ${e.message}$detail"
        }
    }

    return "PocketCare diagnostics\n$head\n\n--- events (newest last, ${entries.size}) ---\n$body"
}
