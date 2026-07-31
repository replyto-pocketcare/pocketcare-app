package care.pocket.domain.upi

// Ported from packages/core/upi/src/index.ts (P1.6a). Building UPI Intent
// deep links for peer-to-peer settle-up. UPI is India-only; every entry
// point below refuses anything else. PocketCare never touches the money --
// this only builds a `upi://pay?...` URL and hands it to a third-party app.

/** UPI is India-only. Every entry point refuses anything else. */
const val UPI_CURRENCY = "INR"

/** Minor-unit digits for INR. UPI always wants two decimal places. */
private const val MINOR_DIGITS = 2

class UpiError(message: String) : Exception(message)

// ---------------------------------------------------------------------------
// VPA (Virtual Payment Address)
// ---------------------------------------------------------------------------

/**
 * `name@handle`, per NPCI's linking spec. Intentionally permissive on the
 * handle side -- validates SHAPE, not the specific PSP.
 */
private val VPA_RE = Regex("^[a-z0-9](?:[a-z0-9._-]{0,60}[a-z0-9])?@[a-z][a-z0-9.-]{1,63}$", RegexOption.IGNORE_CASE)

fun isValidVpa(value: String): Boolean {
    val v = value.trim()
    if (v.length < 3 || v.length > 128) return false
    // A double dot or a leading/trailing dot in either part is always wrong.
    if (v.contains("..")) return false
    val parts = v.split("@")
    val name = parts.getOrNull(0)
    val handle = parts.getOrNull(1)
    if (name.isNullOrEmpty() || handle.isNullOrEmpty()) return false
    if (parts.size != 2) return false
    if (handle.startsWith(".") || handle.endsWith(".")) return false
    return VPA_RE.matches(v)
}

fun normalizeVpa(value: String): String = value.trim().lowercase()

/**
 * `akhilesh@okhdfcbank` -> `akh••••@okhdfcbank`. Lets us show which handle
 * is saved without either screen becoming a place to harvest full VPAs.
 */
fun maskVpa(value: String): String {
    val v = value.trim()
    val at = v.lastIndexOf('@')
    if (at <= 0) return "••••"
    val name = v.substring(0, at)
    val handle = v.substring(at)
    if (name.length <= 3) return "${name.getOrNull(0) ?: ""}••••$handle"
    return "${name.substring(0, 3)}••••$handle"
}

// ---------------------------------------------------------------------------
// Amounts
// ---------------------------------------------------------------------------

/**
 * Integer minor units -> the decimal string UPI expects ("430.00"). Takes a
 * Double (not Long), mirroring the TS source's plain `number` parameter --
 * so a non-integer input (e.g. 12.5) is a real, testable failure mode
 * rather than something the type system rules out before this function
 * ever sees it.
 */
fun formatAmount(minor: Double): String {
    if (minor != kotlin.math.floor(minor) || minor.isNaN() || minor.isInfinite()) {
        throw UpiError("Amount must be integer minor units, got ${formatJsNumber(minor)}")
    }
    if (minor <= 0) throw UpiError("Amount must be greater than zero")
    // Dead code in the TS source too: by this point minor > 0 always holds
    // (the <= 0 branch above already threw), so `sign` can never actually
    // be "-". Ported faithfully anyway rather than "improving" on the
    // original's (harmless) redundancy.
    val sign = if (minor < 0) "-" else ""
    val abs = kotlin.math.abs(minor).toLong()
    val scale = 100L // 10 ** MINOR_DIGITS
    val whole = abs / scale
    val frac = (abs % scale).toString().padStart(MINOR_DIGITS, '0')
    return "$sign$whole.$frac"
}

/** Mirrors JS's `${n}` template-literal coercion for a plain number, only
 * for the error-message case (12.5 -> "12.5"). Not a general-purpose
 * Number-to-string formatter -- Kotlin's Double.toString() already agrees
 * with JS here for every value this function is ever called with (a
 * non-integer minor-unit amount from a vector or real input). */
private fun formatJsNumber(n: Double): String {
    if (n == kotlin.math.floor(n) && !n.isInfinite()) return n.toLong().toString()
    return n.toString()
}

// ---------------------------------------------------------------------------
// Reference
// ---------------------------------------------------------------------------

/** Our own transaction reference, passed as `tr=`. */
private const val REF_ALPHABET = "ABCDEFGHIJKLMNPQRSTUVWXYZ123456789" // no O/0 confusion

/**
 * Mulberry32 PRNG, ported bit-for-bit from export.ts's `seeded()` helper
 * (used to make golden vectors for `newPaymentRef` deterministic in place
 * of `Math.random`). Kept entirely in UInt (32-bit unsigned) space: the JS
 * source only ever uses `>>>` (never signed `>>`), and `+`/`*`/`^`/`|` are
 * bit-identical whether interpreted as signed or unsigned under wraparound
 * -- so there is no sign/bitPattern juggling needed the way a naive Int32
 * port would require. Verified against both `newPaymentRef` golden vectors
 * (seed=42 -> "PCVQ4XFSJW5R", seed=1 -> "PCWAS98JVZP9") via direct Node
 * execution before writing this port.
 */
private class Mulberry32(seed: Int) {
    private var a: UInt = seed.toUInt()

    fun next(): Double {
        a += 0x6d2b79f5u
        var t: UInt = (a xor (a shr 15)) * (a or 1u)
        t = (t + ((t xor (t shr 7)) * (t or 61u))) xor t
        return (t xor (t shr 14)).toDouble() / 4294967296.0
    }
}

/** Deterministic seeded random source for tests -- exposed so
 * upi/UpiVectors.kt can build the same PRNG export.ts used, matching the
 * vectors byte-for-byte. */
fun seededRandom(seed: Int): () -> Double {
    val rng = Mulberry32(seed)
    return { rng.next() }
}

fun newPaymentRef(random: () -> Double = { kotlin.random.Random.nextDouble() }): String {
    val out = StringBuilder("PC")
    repeat(10) {
        val idx = kotlin.math.floor(random() * REF_ALPHABET.length).toInt()
        out.append(REF_ALPHABET.getOrNull(idx) ?: 'X')
    }
    return out.toString()
}

private val REF_RE = Regex("^[A-Za-z0-9]{1,35}$")

fun isValidRef(ref: String): Boolean = REF_RE.matches(ref)

// ---------------------------------------------------------------------------
// Intent URL
// ---------------------------------------------------------------------------

data class IntentParams(
    /** Payee VPA. */
    val vpa: String,
    /** Payee display name, shown in the UPI app. */
    val name: String,
    /** Amount in integer minor units (paise). */
    val amountMinor: Double,
    /** Free-text note shown to both parties. */
    val note: String? = null,
    /** Our reference; generated by `newPaymentRef()` if omitted. */
    val ref: String? = null,
    val currency: String? = null,
)

private val SANITIZE_STRIP_RE = Regex("[&?#=%]")
private val SANITIZE_WHITESPACE_RE = Regex("\\s+")

/**
 * UPI notes are short and punctuation-hostile. Strip anything that could
 * break a PSP's parser rather than trusting percent-encoding to save us.
 */
private fun sanitizeNote(note: String): String =
    note.replace(SANITIZE_STRIP_RE, " ").replace(SANITIZE_WHITESPACE_RE, " ").trim().take(50)

private fun sanitizeName(name: String): String {
    val cleaned = name.replace(SANITIZE_STRIP_RE, " ").replace(SANITIZE_WHITESPACE_RE, " ").trim().take(50)
    return cleaned.ifEmpty { "PocketCare" }
}

data class BuiltIntent(
    val url: String,
    /** The reference actually used, to store on the settlement. */
    val ref: String,
)

/** encodeURIComponent, ported by hand: JS's unreserved set is
 * `A-Za-z0-9-_.!~*'()`, which does not match java.net.URLEncoder (form
 * encoding: spaces become "+", and the unreserved set differs), so that
 * standard-library shortcut can't be used here. Iterates by Unicode code
 * point (not UTF-16 char) so a supplementary-plane character is UTF-8
 * percent-encoded as one unit rather than as two broken surrogate halves --
 * an edge case with no vector coverage (every tested string is BMP), kept
 * correct anyway since it costs nothing here. */
private fun encodeUriComponent(s: String): String {
    val unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
    val sb = StringBuilder()
    var i = 0
    while (i < s.length) {
        val cp = s.codePointAt(i)
        val chars = Character.toChars(cp)
        val piece = String(chars)
        if (cp < 128 && unreserved.indexOf(cp.toChar()) >= 0) {
            sb.append(piece)
        } else {
            for (b in piece.toByteArray(Charsets.UTF_8)) {
                sb.append('%').append("%02X".format(b.toInt() and 0xFF))
            }
        }
        i += Character.charCount(cp)
    }
    return sb.toString()
}

/**
 * Build a `upi://pay?…` Intent URL. Only the parameters NPCI defines are
 * emitted, in the conventional order: `pa` payee address, `pn` payee name,
 * `am` amount, `cu` currency, `tr` reference, `tn` note.
 */
fun buildIntentUrl(params: IntentParams): BuiltIntent {
    val currency = params.currency ?: UPI_CURRENCY
    if (currency != UPI_CURRENCY) {
        throw UpiError("UPI only supports $UPI_CURRENCY, got $currency")
    }

    val vpa = normalizeVpa(params.vpa)
    if (!isValidVpa(vpa)) throw UpiError("Not a valid UPI ID: ${params.vpa}")

    val ref = params.ref ?: newPaymentRef()
    if (!isValidRef(ref)) throw UpiError("Invalid payment reference: $ref")

    val amount = formatAmount(params.amountMinor)

    // Built by hand rather than a form-encoder: that would encode spaces as
    // "+", which several UPI apps render literally in the note.
    val parts = mutableListOf(
        "pa=${encodeUriComponent(vpa)}",
        "pn=${encodeUriComponent(sanitizeName(params.name))}",
        "am=$amount",
        "cu=$currency",
        "tr=${encodeUriComponent(ref)}",
    )
    val note = if (!params.note.isNullOrEmpty()) sanitizeNote(params.note) else ""
    if (note.isNotEmpty()) parts.add("tn=${encodeUriComponent(note)}")

    return BuiltIntent(url = "upi://pay?${parts.joinToString("&")}", ref = ref)
}

/** The same string, for rendering as a QR the payer scans on desktop.
 * Identical payload by design: one code path. */
fun buildQrPayload(params: IntentParams): BuiltIntent = buildIntentUrl(params)

/** Whether to offer UPI at all for this balance. */
fun canPayViaUpi(currency: String, amountMinor: Double, hasHandle: Boolean): Boolean =
    currency == UPI_CURRENCY && amountMinor > 0 && hasHandle

// ---------------------------------------------------------------------------
// Reading a UPI target: a typed VPA, or a QR someone else produced.
// ---------------------------------------------------------------------------

/**
 * What a scanned QR / typed string resolved to.
 *
 * SECURITY: every field here is ATTACKER-CONTROLLED (see the TS source's
 * doc comment for the full rationale) -- `name` is an unverified claim,
 * `amountMinor` is a suggestion for an editable field, and nothing here may
 * be auto-submitted.
 */
data class UpiTarget(
    val vpa: String,
    /** Name claimed by the code. Not verified. */
    val name: String? = null,
    /** Suggested amount in minor units, when the code carried one. */
    val amountMinor: Long? = null,
    val note: String? = null,
)

/** Why a scanned/typed string couldn't be used: "empty" | "not_upi" |
 * "emvco" | "bad_vpa" | "unsupported_currency". Plain String (not a Kotlin
 * enum) since it only ever round-trips to/from a JSON string field. */
typealias UpiParseFailure = String

data class UpiParseResult(
    val ok: Boolean,
    val target: UpiTarget? = null,
    val reason: UpiParseFailure? = null,
)

/** UPI-intent query params also appear under app-specific schemes. */
private val UPI_SCHEMES = listOf("upi:", "tez:", "phonepe:", "paytmmp:", "bhim:", "gpay:")

private val EMVCO_PREFIX_RE = Regex("^000201")
private val EMVCO_BODY_RE = Regex("^[0-9A-Za-z.\\-\\s]+$")

/** EMVCo/Bharat QR starts with payload-format-indicator "000201". */
private fun looksEmvco(s: String): Boolean =
    EMVCO_PREFIX_RE.containsMatchIn(s) && EMVCO_BODY_RE.matches(s.take(32))

private val AMOUNT_MAJOR_RE = Regex("^\\d{1,9}(\\.\\d{1,2})?$")

/**
 * Parse major-unit money text ("1234.50") into minor units, strictly.
 * Rejects negatives, non-finite values, >2dp, and absurd magnitudes.
 */
private fun parseAmountMajor(raw: String): Long? {
    val s = raw.trim()
    if (s.isEmpty() || !AMOUNT_MAJOR_RE.matches(s)) return null
    val minor = Math.round(s.toDouble() * 100)
    if (minor <= 0) return null
    return minor
}

/** decodeURIComponent, approximated via Java's URLDecoder: not a
 * byte-for-byte match to the JS spec's malformed-sequence detection (no
 * golden vector exercises the catch/fallback branch this feeds), but
 * agrees on every well-formed input, which is all the vectors test. */
private fun decodeUriComponentOrNull(s: String): String? = try {
    java.net.URLDecoder.decode(s, "UTF-8")
} catch (e: IllegalArgumentException) {
    null
}

/**
 * Turn a typed UPI ID or a scanned QR payload into a payable target.
 * Accepts a bare VPA and the UPI intent URL that virtually every Indian
 * payment QR encodes, including app-specific scheme variants.
 */
fun parseUpiTarget(input: String?): UpiParseResult {
    val raw = (input ?: "").trim()
    if (raw.isEmpty()) return UpiParseResult(ok = false, reason = "empty")

    // EMVCo first: a Bharat QR payload contains no "://" or "?", so it
    // would otherwise fall into the bare-VPA branch and be reported as a
    // malformed UPI ID -- true but useless, when we can name what it is.
    if (looksEmvco(raw)) return UpiParseResult(ok = false, reason = "emvco")

    // Bare VPA, the typed case.
    if (!raw.contains("://") && !raw.contains("?")) {
        val vpa = normalizeVpa(raw)
        return if (isValidVpa(vpa)) UpiParseResult(ok = true, target = UpiTarget(vpa = vpa))
        else UpiParseResult(ok = false, reason = "bad_vpa")
    }

    val lower = raw.lowercase()
    val scheme = UPI_SCHEMES.firstOrNull { lower.startsWith(it) }
    if (scheme == null) return UpiParseResult(ok = false, reason = "not_upi")

    // Parse by hand rather than a URL parser: custom schemes aren't
    // consistently parsed across engines, and only the query string matters.
    val qIndex = raw.indexOf('?')
    if (qIndex == -1) return UpiParseResult(ok = false, reason = "not_upi")
    val q = raw.substring(qIndex + 1)

    val params = LinkedHashMap<String, String>()
    for (pair in q.split("&")) {
        val eq = pair.indexOf('=')
        if (eq <= 0) continue
        val k = pair.substring(0, eq).lowercase()
        if (params.containsKey(k)) continue // first wins; a duplicated `pa` is a spoof attempt
        val valueRaw = pair.substring(eq + 1)
        val plusReplaced = valueRaw.replace("+", " ")
        params[k] = decodeUriComponentOrNull(plusReplaced) ?: valueRaw
    }

    val cu = params["cu"]
    if (cu != null && cu.uppercase() != UPI_CURRENCY) return UpiParseResult(ok = false, reason = "unsupported_currency")

    val vpa = normalizeVpa(params["pa"] ?: "")
    if (vpa.isEmpty()) return UpiParseResult(ok = false, reason = "not_upi")
    if (!isValidVpa(vpa)) return UpiParseResult(ok = false, reason = "bad_vpa")

    val amountMinor = parseAmountMajor(params["am"] ?: "")
    val name = (params["pn"] ?: "").trim().ifEmpty { null }
    val note = (params["tn"] ?: "").trim().ifEmpty { null }

    return UpiParseResult(ok = true, target = UpiTarget(vpa = vpa, name = name, amountMinor = amountMinor, note = note))
}
