import Foundation

// Ported from packages/core/upi/src/index.ts (P1.6b). Mirrors
// apps/android/domain/.../upi/Upi.kt (P1.6a). Building UPI Intent deep
// links for peer-to-peer settle-up. UPI is India-only; every entry point
// below refuses anything else. Sanvya never touches the money -- this
// only builds a `upi://pay?...` URL and hands it to a third-party app.

/// UPI is India-only. Every entry point refuses anything else.
public let UPI_CURRENCY = "INR"

/// Minor-unit digits for INR. UPI always wants two decimal places.
private let UPI_MINOR_DIGITS = 2

public struct UpiError: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ message: String) { self.description = message }
}

// ---------------------------------------------------------------------------
// VPA (Virtual Payment Address)
// ---------------------------------------------------------------------------

/// `name@handle`, per NPCI's linking spec. Intentionally permissive on the
/// handle side -- validates SHAPE, not the specific PSP.
private let VPA_RE = rx("^[a-z0-9](?:[a-z0-9._-]{0,60}[a-z0-9])?@[a-z][a-z0-9.-]{1,63}$", [.caseInsensitive])

public func isValidVpa(_ value: String) -> Bool {
    let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if v.count < 3 || v.count > 128 { return false }
    // A double dot or a leading/trailing dot in either part is always wrong.
    if v.contains("..") { return false }
    let parts = v.components(separatedBy: "@")
    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
    let handle = parts[1]
    if handle.hasPrefix(".") || handle.hasSuffix(".") { return false }
    return fullMatch(VPA_RE, v)
}

/// NSRegularExpression has no single-call "whole string matches" the way
/// JS's `RegExp.test` on an already `^...$`-anchored pattern does --
/// `matchesAnywhere` alone would accept a pattern that matches a substring
/// even without `$`, so this additionally checks the match spans the full
/// string, matching the pattern's own `^...$` anchoring intent exactly.
private func fullMatch(_ re: NSRegularExpression, _ s: String) -> Bool {
    let range = NSRange(s.startIndex..<s.endIndex, in: s)
    guard let m = re.firstMatch(in: s, range: range) else { return false }
    return m.range == range
}

public func normalizeVpa(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

/// `akhilesh@okhdfcbank` -> `akh••••@okhdfcbank`. Lets us show which handle
/// is saved without either screen becoming a place to harvest full VPAs.
public func maskVpa(_ value: String) -> String {
    let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let atIndex = v.lastIndex(of: "@"), v.distance(from: v.startIndex, to: atIndex) > 0 else {
        return "••••"
    }
    let name = String(v[v.startIndex..<atIndex])
    let handle = String(v[atIndex...])
    if name.count <= 3 {
        return "\(name.first.map(String.init) ?? "")••••\(handle)"
    }
    return "\(name.prefix(3))••••\(handle)"
}

// ---------------------------------------------------------------------------
// Amounts
// ---------------------------------------------------------------------------

/// Integer minor units -> the decimal string UPI expects ("430.00"). Takes
/// a Double (not Int64), mirroring the TS source's plain `number`
/// parameter -- so a non-integer input (e.g. 12.5) is a real, testable
/// failure mode rather than something the type system rules out before
/// this function ever sees it.
public func formatAmount(_ minor: Double) throws -> String {
    if minor != minor.rounded(.towardZero) || minor.isNaN || minor.isInfinite {
        throw UpiError("Amount must be integer minor units, got \(formatJsNumber(minor))")
    }
    if minor <= 0 { throw UpiError("Amount must be greater than zero") }
    // Dead code in the TS source too: by this point minor > 0 always holds
    // (the <= 0 branch above already threw), so `sign` can never actually
    // be "-". Ported faithfully anyway rather than "improving" on the
    // original's (harmless) redundancy.
    let sign = minor < 0 ? "-" : ""
    let abs = Int64(minor.magnitude)
    let scale: Int64 = 100 // 10 ** MINOR_DIGITS
    let whole = abs / scale
    var frac = String(abs % scale)
    while frac.count < UPI_MINOR_DIGITS { frac = "0" + frac }
    return "\(sign)\(whole).\(frac)"
}

/// Mirrors JS's `${n}` template-literal coercion for a plain number, only
/// for the error-message case (12.5 -> "12.5"). Not a general-purpose
/// Number-to-string formatter -- every value this is ever called with (a
/// non-integer minor-unit amount from a vector or real input) formats
/// identically to JS via Swift's own Double description here.
private func formatJsNumber(_ n: Double) -> String {
    if n == n.rounded(.towardZero) && !n.isInfinite {
        return String(Int64(n))
    }
    return String(n)
}

// ---------------------------------------------------------------------------
// Reference
// ---------------------------------------------------------------------------

/// Our own transaction reference, passed as `tr=`.
private let REF_ALPHABET = Array("ABCDEFGHIJKLMNPQRSTUVWXYZ123456789") // no O/0 confusion

/// Mulberry32 PRNG, ported bit-for-bit from export.ts's `seeded()` helper
/// (used to make golden vectors for `newPaymentRef` deterministic in place
/// of `Math.random`). Kept entirely in UInt32 space: the JS source only
/// ever uses `>>>` (never signed `>>`), and `+`/`*`/`^`/`|` are
/// bit-identical whether interpreted as signed or unsigned under
/// wraparound -- so there is no sign/bitPattern juggling needed the way a
/// naive Int32 port would require. Verified against both `newPaymentRef`
/// golden vectors (seed=42 -> "PCVQ4XFSJW5R", seed=1 -> "PCWAS98JVZP9")
/// via direct Node execution before writing this port. Matches
/// Reconcile... no -- matches Upi.kt's Mulberry32 exactly.
private final class Mulberry32 {
    private var a: UInt32
    init(seed: Int32) { self.a = UInt32(bitPattern: seed) }

    func next() -> Double {
        a = a &+ 0x6d2b79f5
        var t: UInt32 = (a ^ (a >> 15)) &* (a | 1)
        t = (t &+ ((t ^ (t >> 7)) &* (t | 61))) ^ t
        return Double(t ^ (t >> 14)) / 4294967296.0
    }
}

/// Deterministic seeded random source for tests -- exposed so
/// UpiVectors.swift can build the same PRNG export.ts used, matching the
/// vectors byte-for-byte.
public func seededRandom(_ seed: Int32) -> () -> Double {
    let rng = Mulberry32(seed: seed)
    return { rng.next() }
}

public func newPaymentRef(_ random: () -> Double = { Double.random(in: 0..<1) }) -> String {
    var out = "PC"
    for _ in 0..<10 {
        let idx = Int((random() * Double(REF_ALPHABET.count)).rounded(.down))
        out.append(idx >= 0 && idx < REF_ALPHABET.count ? REF_ALPHABET[idx] : "X")
    }
    return out
}

private let REF_RE = rx("^[A-Za-z0-9]{1,35}$")

public func isValidRef(_ ref: String) -> Bool {
    fullMatch(REF_RE, ref)
}

// ---------------------------------------------------------------------------
// Intent URL
// ---------------------------------------------------------------------------

public struct IntentParams: Sendable {
    /// Payee VPA.
    public let vpa: String
    /// Payee display name, shown in the UPI app.
    public let name: String
    /// Amount in integer minor units (paise).
    public let amountMinor: Double
    /// Free-text note shown to both parties.
    public let note: String?
    /// Our reference; generated by `newPaymentRef()` if omitted.
    public let ref: String?
    public let currency: String?

    public init(vpa: String, name: String, amountMinor: Double, note: String? = nil, ref: String? = nil, currency: String? = nil) {
        self.vpa = vpa
        self.name = name
        self.amountMinor = amountMinor
        self.note = note
        self.ref = ref
        self.currency = currency
    }
}

private let SANITIZE_STRIP_RE = rx("[&?#=%]")
private let SANITIZE_WHITESPACE_RE = rx("\\s+")

/// UPI notes are short and punctuation-hostile. Strip anything that could
/// break a PSP's parser rather than trusting percent-encoding to save us.
private func sanitizeNote(_ note: String) -> String {
    var s = SANITIZE_STRIP_RE.replacingAllMatches(in: note, with: " ")
    s = SANITIZE_WHITESPACE_RE.replacingAllMatches(in: s, with: " ")
    s = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return String(s.prefix(50))
}

private func sanitizeName(_ name: String) -> String {
    var s = SANITIZE_STRIP_RE.replacingAllMatches(in: name, with: " ")
    s = SANITIZE_WHITESPACE_RE.replacingAllMatches(in: s, with: " ")
    s = s.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleaned = String(s.prefix(50))
    return cleaned.isEmpty ? "Sanvya" : cleaned
}

public struct BuiltIntent: Sendable {
    public let url: String
    /// The reference actually used, to store on the settlement.
    public let ref: String
}

/// encodeURIComponent, ported by hand: JS's unreserved set is
/// `A-Za-z0-9-_.!~*'()`, which does not match Swift's
/// `addingPercentEncoding(withAllowedCharacters:)` presets (`.urlQueryAllowed`
/// etc. allow a different, larger set), so that shortcut can't be used
/// here. Iterates `.unicodeScalars` (full Unicode scalar values, not
/// UTF-16 code units), so a supplementary-plane character is UTF-8
/// percent-encoded as one correct unit -- an edge case with no vector
/// coverage (every tested string is BMP), kept correct anyway since it
/// costs nothing here.
private let URI_UNRESERVED = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")

private func encodeUriComponent(_ s: String) -> String {
    var out = ""
    for scalar in s.unicodeScalars {
        if URI_UNRESERVED.contains(scalar) {
            out.unicodeScalars.append(scalar)
        } else {
            for byte in String(scalar).utf8 {
                out += String(format: "%%%02X", byte)
            }
        }
    }
    return out
}

/// Build a `upi://pay?…` Intent URL. Only the parameters NPCI defines are
/// emitted, in the conventional order: `pa` payee address, `pn` payee
/// name, `am` amount, `cu` currency, `tr` reference, `tn` note.
public func buildIntentUrl(_ params: IntentParams) throws -> BuiltIntent {
    let currency = params.currency ?? UPI_CURRENCY
    if currency != UPI_CURRENCY {
        throw UpiError("UPI only supports \(UPI_CURRENCY), got \(currency)")
    }

    let vpa = normalizeVpa(params.vpa)
    if !isValidVpa(vpa) { throw UpiError("Not a valid UPI ID: \(params.vpa)") }

    let ref = params.ref ?? newPaymentRef()
    if !isValidRef(ref) { throw UpiError("Invalid payment reference: \(ref)") }

    let amount = try formatAmount(params.amountMinor)

    // Built by hand rather than a form-encoder: that would encode spaces
    // as "+", which several UPI apps render literally in the note.
    var parts = [
        "pa=\(encodeUriComponent(vpa))",
        "pn=\(encodeUriComponent(sanitizeName(params.name)))",
        "am=\(amount)",
        "cu=\(currency)",
        "tr=\(encodeUriComponent(ref))",
    ]
    let note = (params.note?.isEmpty == false) ? sanitizeNote(params.note!) : ""
    if !note.isEmpty { parts.append("tn=\(encodeUriComponent(note))") }

    return BuiltIntent(url: "upi://pay?\(parts.joined(separator: "&"))", ref: ref)
}

/// The same string, for rendering as a QR the payer scans on desktop.
/// Identical payload by design: one code path.
public func buildQrPayload(_ params: IntentParams) throws -> BuiltIntent {
    try buildIntentUrl(params)
}

/// Whether to offer UPI at all for this balance.
public func canPayViaUpi(currency: String, amountMinor: Double, hasHandle: Bool) -> Bool {
    currency == UPI_CURRENCY && amountMinor > 0 && hasHandle
}

// ---------------------------------------------------------------------------
// Reading a UPI target: a typed VPA, or a QR someone else produced.
// ---------------------------------------------------------------------------

/// What a scanned QR / typed string resolved to.
///
/// SECURITY: every field here is ATTACKER-CONTROLLED (see the TS source's
/// doc comment for the full rationale) -- `name` is an unverified claim,
/// `amountMinor` is a suggestion for an editable field, and nothing here
/// may be auto-submitted.
public struct UpiTarget: Sendable {
    public let vpa: String
    /// Name claimed by the code. Not verified.
    public let name: String?
    /// Suggested amount in minor units, when the code carried one.
    public let amountMinor: Int64?
    public let note: String?
}

/// Why a scanned/typed string couldn't be used: "empty" | "not_upi" |
/// "emvco" | "bad_vpa" | "unsupported_currency". Plain String (not a
/// Swift enum) since it only ever round-trips to/from a JSON string field.
public typealias UpiParseFailure = String

public struct UpiParseResult: Sendable {
    public let ok: Bool
    public let target: UpiTarget?
    public let reason: UpiParseFailure?
}

/// UPI-intent query params also appear under app-specific schemes.
private let UPI_SCHEMES = ["upi:", "tez:", "phonepe:", "paytmmp:", "bhim:", "gpay:"]

private let EMVCO_PREFIX_RE = rx("^000201")
private let EMVCO_BODY_RE = rx("^[0-9A-Za-z.\\-\\s]+$")

/// EMVCo/Bharat QR starts with payload-format-indicator "000201".
private func looksEmvco(_ s: String) -> Bool {
    EMVCO_PREFIX_RE.matchesAnywhere(s) && fullMatch(EMVCO_BODY_RE, String(s.prefix(32)))
}

private let AMOUNT_MAJOR_RE = rx("^\\d{1,9}(\\.\\d{1,2})?$")

/// Parse major-unit money text ("1234.50") into minor units, strictly.
/// Rejects negatives, non-finite values, >2dp, and absurd magnitudes.
private func parseAmountMajor(_ raw: String) -> Int64? {
    let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty || !fullMatch(AMOUNT_MAJOR_RE, s) { return nil }
    guard let d = Double(s) else { return nil }
    let minor = (d * 100).rounded()
    if !minor.isFinite || minor <= 0 { return nil }
    return Int64(minor)
}

/// decodeURIComponent, approximated via `removingPercentEncoding`: not a
/// byte-for-byte match to the JS spec's malformed-sequence detection (no
/// golden vector exercises the catch/fallback branch this feeds), but
/// agrees on every well-formed input, which is all the vectors test.
/// `removingPercentEncoding` returns nil on malformed input, which is
/// used here exactly like the TS source's try/catch fallback.
private func decodeUriComponentOrNull(_ s: String) -> String? {
    s.removingPercentEncoding
}

/// Turn a typed UPI ID or a scanned QR payload into a payable target.
/// Accepts a bare VPA and the UPI intent URL that virtually every Indian
/// payment QR encodes, including app-specific scheme variants.
public func parseUpiTarget(_ input: String?) -> UpiParseResult {
    let raw = (input ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.isEmpty { return UpiParseResult(ok: false, target: nil, reason: "empty") }

    // EMVCo first: a Bharat QR payload contains no "://" or "?", so it
    // would otherwise fall into the bare-VPA branch and be reported as a
    // malformed UPI ID -- true but useless, when we can name what it is.
    if looksEmvco(raw) { return UpiParseResult(ok: false, target: nil, reason: "emvco") }

    // Bare VPA, the typed case.
    if !raw.contains("://") && !raw.contains("?") {
        let vpa = normalizeVpa(raw)
        return isValidVpa(vpa)
            ? UpiParseResult(ok: true, target: UpiTarget(vpa: vpa, name: nil, amountMinor: nil, note: nil), reason: nil)
            : UpiParseResult(ok: false, target: nil, reason: "bad_vpa")
    }

    let lower = raw.lowercased()
    guard UPI_SCHEMES.contains(where: { lower.hasPrefix($0) }) else {
        return UpiParseResult(ok: false, target: nil, reason: "not_upi")
    }

    // Parse by hand rather than a URL parser: custom schemes aren't
    // consistently parsed across engines, and only the query string matters.
    guard let qIndex = raw.firstIndex(of: "?") else {
        return UpiParseResult(ok: false, target: nil, reason: "not_upi")
    }
    let q = String(raw[raw.index(after: qIndex)...])

    var params: [String: String] = [:]
    for pair in q.components(separatedBy: "&") {
        guard let eqIndex = pair.firstIndex(of: "="), pair.distance(from: pair.startIndex, to: eqIndex) > 0 else { continue }
        let k = String(pair[pair.startIndex..<eqIndex]).lowercased()
        if params[k] != nil { continue } // first wins; a duplicated `pa` is a spoof attempt
        let valueRaw = String(pair[pair.index(after: eqIndex)...])
        let plusReplaced = valueRaw.replacingOccurrences(of: "+", with: " ")
        params[k] = decodeUriComponentOrNull(plusReplaced) ?? valueRaw
    }

    if let cu = params["cu"], cu.uppercased() != UPI_CURRENCY {
        return UpiParseResult(ok: false, target: nil, reason: "unsupported_currency")
    }

    let vpa = normalizeVpa(params["pa"] ?? "")
    if vpa.isEmpty { return UpiParseResult(ok: false, target: nil, reason: "not_upi") }
    if !isValidVpa(vpa) { return UpiParseResult(ok: false, target: nil, reason: "bad_vpa") }

    let amountMinor = parseAmountMajor(params["am"] ?? "")
    let name = (params["pn"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let note = (params["tn"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    return UpiParseResult(
        ok: true,
        target: UpiTarget(
            vpa: vpa,
            name: name.isEmpty ? nil : name,
            amountMinor: amountMinor,
            note: note.isEmpty ? nil : note
        ),
        reason: nil
    )
}
