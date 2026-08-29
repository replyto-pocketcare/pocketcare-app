import CryptoKit
import Foundation
import Security

/**
 The Hybrid zero-trust envelope scheme — Swift side.

 Ported from `packages/core/crypto/src/index.ts` (the `@sanvya/crypto` package
 the files under web's `src/crypto` are built on) and pinned, primitive by
 primitive, by `tools/golden-vectors/vectors/security.json`. Those vectors
 were produced by
 RUNNING web's own WebCrypto calls, which is the only way to prove the thing
 that actually matters: an envelope written in a browser must open on a phone
 and vice versa. A cosmetic bug in this file is unreadable user data, not a
 misaligned label.

 WHY THIS IS IN Domain AND NOT Data. Everything below is deterministic and
 needs no app context — CryptoKit and `Security` are OS frameworks, not UIKit.
 Putting it here is what lets the vector runner execute it: the runner lives in
 this package's test target, and a primitive it cannot run is a primitive
 nobody has checked against web. The parts that genuinely need the platform —
 the Keychain, the database, the network — live in Data, where they belong.

 WHY PBKDF2 IS BUILT ON CryptoKit's HMAC RATHER THAN CommonCrypto. Two
 reasons, in order. It keeps this package to frameworks whose availability is
 not in question, and it puts BOTH ports on the same construction: Android
 hand-rolls RFC 8018 §5.2 too, because its stock `PBKDF2WithHmacSHA256`
 converts the passphrase to bytes with PKCS#5's 8-bit rule rather than UTF-8
 and would silently disagree with a browser on any non-ASCII passphrase. Two
 implementations of the same twelve lines, checked against the same
 browser-produced vectors, is a better guarantee than two different library
 calls that are each "probably" right.
 */

// MARK: - Parameters

// Every one of these is web's value; none may be inlined at a call site,
// because the day one of them drifts is the day the two platforms stop being
// able to read each other and nothing says so out loud.

/// The only envelope version that exists. `v1.<base64 iv>.<base64 ct+tag>`.
public let securityEnvelopeVersion = "v1"

/// Separator between an envelope's three fields (web: `envelope.split(".")`).
public let securityEnvelopeSeparator: Character = "."

/// OWASP 2023 guidance for PBKDF2-HMAC-SHA256, and web's `PBKDF2_ITERATIONS`.
public let securityPbkdf2Iterations = 210_000

/// AES-GCM 256 — the `length: 256` web asks `deriveKey` for.
public let securityKekLengthBytes = 32

/// `generateDek()` — "a fresh 256-bit data encryption key".
public let securityDekLengthBytes = 32

/// `newSalt()` — `randomBytes(16)`.
public let securitySaltLengthBytes = 16

/// `aesEncrypt()` — `randomBytes(12)`, the AES-GCM standard nonce size.
public let securityIvLengthBytes = 12

/// WebCrypto appends a 128-bit tag to the ciphertext and offers no way to
/// choose otherwise, so this is not a preference — it is the only value that
/// can read a browser-written envelope.
public let securityGcmTagLengthBytes = 16

/// `generateRecoveryCode()` — `randomBytes(20)`.
public let securityRecoveryCodeLengthBytes = 20

/// A dash after every fourth character, but never a trailing one.
public let securityRecoveryCodeGroupSize = 4

/// Web's alphabet, chosen for having no ambiguous glyphs (no I/L/O/0/1).
public let securityRecoveryCodeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

/// `SetupBox`'s `if (pass.length < 8)`.
public let securityMinPassphraseLength = 8

/// `issueSupportGrant(scope, 2)` — the support window the panel promises.
public let securityGrantTtlHours = 2

/// Milliseconds in an hour — web's `ttlHours * 3_600_000`.
public let securityMillisPerHour: Int64 = 3_600_000

/// The JWK curve name for the consent-signing keypair (WebCrypto: P-256).
public let securitySigningCurveJwk = "P-256"

/// Half a P-256 raw signature, and the width of the `x`/`y`/`d` JWK fields.
public let securityP256CoordinateBytes = 32

private let asn1Sequence: UInt8 = 0x30
private let asn1Integer: UInt8 = 0x02

/**
 Stands in for the TS source's plain `new Error("bad envelope")`.

 One message for every way an envelope can fail to open — wrong version, wrong
 shape, bad base64, wrong key, tampered ciphertext — deliberately. Telling a
 caller WHICH of those happened tells an attacker the same thing, and no caller
 does anything different with the answer.
 */
public struct SecurityEnvelopeError: Error, CustomStringConvertible, Sendable {
    public init() {}
    public var description: String { "bad envelope" }
}

// MARK: - Base64 / base64url

/// Standard, padded base64 — what `btoa` produces and web stores.
public func securityBase64Encode(_ bytes: Data) -> String { bytes.base64EncodedString() }

/// Strict decode; a malformed body is a bad envelope, not a crash.
public func securityBase64Decode(_ text: String) throws -> Data {
    guard let data = Data(base64Encoded: text) else { throw SecurityEnvelopeError() }
    return data
}

/// JWKs are base64**url** (RFC 7515) and everything else here is base64.
/// Converting at the boundary keeps one decoder in the file rather than two.
public func base64UrlToBase64(_ input: String) -> String {
    let swapped = input.replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let remainder = swapped.count % 4
    return remainder == 0 ? swapped : swapped + String(repeating: "=", count: 4 - remainder)
}

/// The inverse: unpadded, URL-safe, as a JWK field must be written.
public func base64ToBase64Url(_ input: String) -> String {
    var trimmed = Substring(input)
    while trimmed.hasSuffix("=") { trimmed = trimmed.dropLast() }
    return String(trimmed).replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
}

private func base64UrlDecode(_ input: String) throws -> Data {
    try securityBase64Decode(base64UrlToBase64(input))
}

private func base64UrlEncode(_ bytes: Data) -> String {
    base64ToBase64Url(bytes.base64EncodedString())
}

// MARK: - Envelope shape

/// The two halves of a parsed envelope, still base64.
public struct SecurityEnvelope: Equatable, Sendable {
    public let ivBase64: String
    public let ctBase64: String

    public init(ivBase64: String, ctBase64: String) {
        self.ivBase64 = ivBase64
        self.ctBase64 = ctBase64
    }
}

/**
 True if a stored value looks like one of our ciphertext envelopes.

 Web's `isEncrypted`: a `startsWith` on the version prefix and nothing more.
 Deliberately loose — the point is to tell "the user typed this" from "we wrote
 this", cheaply, on every row of a list.
 */
public func isEncryptedEnvelope(_ value: String?) -> Bool {
    guard let value else { return false }
    return value.hasPrefix("\(securityEnvelopeVersion)\(securityEnvelopeSeparator)")
}

/// `v1.<iv>.<ct>`.
public func formatSecurityEnvelope(ivBase64: String, ctBase64: String) -> String {
    "\(securityEnvelopeVersion)\(securityEnvelopeSeparator)\(ivBase64)\(securityEnvelopeSeparator)\(ctBase64)"
}

/**
 Split an envelope, or nil if it is not one.

 Web throws here; this returns nil so the caller decides whether a non-envelope
 is an error (unwrapping a key) or simply plaintext to pass through (rendering
 a note). Exactly three parts: `v1.a.b.c` is rejected, because a stray
 separator means we are not looking at what we think.
 */
public func parseSecurityEnvelope(_ envelope: String?) -> SecurityEnvelope? {
    guard let envelope else { return nil }
    // `omittingEmptySubsequences: false` matters: web's `split(".")` keeps
    // empty fields, so `v1..` is three parts there and must be three here.
    let parts = envelope.split(
        separator: securityEnvelopeSeparator,
        omittingEmptySubsequences: false
    )
    guard parts.count == 3, parts[0] == securityEnvelopeVersion else { return nil }
    return SecurityEnvelope(ivBase64: String(parts[1]), ctBase64: String(parts[2]))
}

// MARK: - Key derivation

/// PBKDF2-HMAC-SHA256, RFC 8018 §5.2, over the UTF-8 bytes of the password.
///
/// See the file header for why this is not a library call.
public func pbkdf2HmacSha256(
    password: Data,
    salt: Data,
    iterations: Int,
    keyLengthBytes: Int
) -> Data {
    precondition(iterations > 0, "iterations must be positive")
    precondition(keyLengthBytes > 0, "keyLengthBytes must be positive")
    let key = SymmetricKey(data: password)
    // SHA256Digest.byteCount, not SHA256.byteCount: `byteCount` is declared on
    // the DIGEST type, and the hash function itself only carries
    // `blockByteCount`. The wrong one is a compile error, but a confident-
    // looking one.
    let hashLength = SHA256Digest.byteCount
    let blocks = (keyLengthBytes + hashLength - 1) / hashLength
    var derived = [UInt8]()
    derived.reserveCapacity(blocks * hashLength)
    for block in 1...blocks {
        var message = [UInt8](salt)
        // INT(i), big-endian, appended to the salt for the first HMAC only.
        message.append(UInt8((block >> 24) & 0xFF))
        message.append(UInt8((block >> 16) & 0xFF))
        message.append(UInt8((block >> 8) & 0xFF))
        message.append(UInt8(block & 0xFF))
        var u = [UInt8](HMAC<SHA256>.authenticationCode(for: message, using: key))
        var accumulator = u
        if iterations > 1 {
            for _ in 2...iterations {
                u = [UInt8](HMAC<SHA256>.authenticationCode(for: u, using: key))
                for i in 0..<accumulator.count { accumulator[i] ^= u[i] }
            }
        }
        derived.append(contentsOf: accumulator)
    }
    return Data(derived.prefix(keyLengthBytes))
}

/**
 The key-encryption key, from a passphrase or a recovery code.

 Web's `deriveKek`. `iterations` is a parameter for the same reason it is one
 there — so a future cost bump can read the value off the row it is unwrapping
 instead of guessing — but every call today passes the constant.
 */
public func deriveKek(
    passphrase: String,
    salt: Data,
    iterations: Int = securityPbkdf2Iterations
) -> Data {
    pbkdf2HmacSha256(
        password: Data(passphrase.utf8),
        salt: salt,
        iterations: iterations,
        keyLengthBytes: securityKekLengthBytes
    )
}

// MARK: - AES-GCM envelope

/// Cryptographically strong bytes. One source, so nothing reaches for `random`.
///
/// CryptoKit's key generator rather than `SecRandomCopyBytes`: it is the same
/// system CSPRNG, it cannot fail with a status code nobody checks, and it does
/// not drag an imported C global (`kSecRandomDefault`) into a package built
/// under Swift 6's strict concurrency. `bitCount` is always a multiple of
/// eight here, which is what `SymmetricKeySize` requires.
public func securityRandomBytes(_ count: Int) -> Data {
    let key = SymmetricKey(size: SymmetricKeySize(bitCount: count * 8))
    return key.withUnsafeBytes { Data($0) }
}

/// A fresh per-user PBKDF2 salt.
public func newSecuritySalt() -> Data { securityRandomBytes(securitySaltLengthBytes) }

/// A fresh 256-bit data encryption key.
public func generateDek() -> Data { securityRandomBytes(securityDekLengthBytes) }

/**
 Seal `plaintext` under `key` into an envelope.

 `iv` is injectable ONLY so the golden vectors can pin the output against a
 browser's; every production caller lets it default to fresh randomness. A
 reused nonce under the same key breaks GCM completely.
 */
public func aesGcmSeal(key: Data, plaintext: Data, iv: Data? = nil) throws -> String {
    let nonceBytes = iv ?? securityRandomBytes(securityIvLengthBytes)
    do {
        let sealed = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: key),
            nonce: AES.GCM.Nonce(data: nonceBytes)
        )
        // CryptoKit keeps ciphertext and tag apart; WebCrypto concatenates
        // them, and the concatenation is what is on the wire.
        let body = sealed.ciphertext + sealed.tag
        return formatSecurityEnvelope(
            ivBase64: securityBase64Encode(nonceBytes),
            ctBase64: securityBase64Encode(body)
        )
    } catch {
        throw SecurityEnvelopeError()
    }
}

/// Open an envelope, or throw `SecurityEnvelopeError`.
public func aesGcmOpen(key: Data, envelope: String) throws -> Data {
    guard let parsed = parseSecurityEnvelope(envelope) else { throw SecurityEnvelopeError() }
    let iv = try securityBase64Decode(parsed.ivBase64)
    let body = try securityBase64Decode(parsed.ctBase64)
    // An empty plaintext is a 16-byte body (tag only), so this is `>=`.
    guard body.count >= securityGcmTagLengthBytes else { throw SecurityEnvelopeError() }
    do {
        let split = body.count - securityGcmTagLengthBytes
        let sealed = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: iv),
            ciphertext: body.prefix(split),
            tag: body.suffix(securityGcmTagLengthBytes)
        )
        // Wrong key and tampered ciphertext are the same answer on purpose.
        return try AES.GCM.open(sealed, using: SymmetricKey(data: key))
    } catch {
        throw SecurityEnvelopeError()
    }
}

/// Wrap the DEK under a KEK. Web's `wrapDek`.
public func wrapDek(dek: Data, kek: Data) throws -> String {
    try aesGcmSeal(key: kek, plaintext: dek)
}

/// Unwrap the DEK. Throws on a wrong passphrase or a tampered row.
public func unwrapDek(wrapped: String, kek: Data) throws -> Data {
    try aesGcmOpen(key: kek, envelope: wrapped)
}

/// Encrypt one field value for storage. Web's `encryptField`.
public func encryptField(_ plaintext: String, dek: Data) throws -> String {
    try aesGcmSeal(key: dek, plaintext: Data(plaintext.utf8))
}

/// Decrypt one stored field value. Web's `decryptField`.
public func decryptField(_ envelope: String, dek: Data) throws -> String {
    let bytes = try aesGcmOpen(key: dek, envelope: envelope)
    guard let text = String(data: bytes, encoding: .utf8) else { throw SecurityEnvelopeError() }
    return text
}

// MARK: - Recovery code

/**
 Web's `generateRecoveryCode` encoding, separated from its randomness.

 The modulo is biased (256 is not a multiple of 31) and that is web's encoding,
 not a mistake to fix here: a phone and a browser have to produce codes from
 the same alphabet, and 20 bytes of entropy squeezed into a slightly
 non-uniform 31-symbol code is still ~98 bits. Changing it would make the two
 sides disagree about nothing useful.
 */
public func recoveryCodeFromBytes(_ raw: Data) -> String {
    let bytes = [UInt8](raw)
    var out = ""
    for (i, byte) in bytes.enumerated() {
        out.append(securityRecoveryCodeAlphabet[Int(byte) % securityRecoveryCodeAlphabet.count])
        if (i + 1) % securityRecoveryCodeGroupSize == 0 && i < bytes.count - 1 { out.append("-") }
    }
    return out
}

/// A fresh one-time recovery code. Shown once, never stored in the clear.
public func generateRecoveryCode() -> String {
    recoveryCodeFromBytes(securityRandomBytes(securityRecoveryCodeLengthBytes))
}

/**
 What a typed recovery code becomes before it is fed to the KDF.

 Web's `unlockWithRecovery` does `code.trim().toUpperCase()` and nothing
 else — the dashes are part of the derived string, so they cannot be stripped
 here however tempting that looks.
 */
public func normalizeRecoveryCode(_ input: String) -> String {
    input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
}

// MARK: - Panel state

/// Web's `CryptoStatus`. String-valued so the vectors can pin it.
public enum SecurityStatus {
    public static let loading = "loading"
    public static let unset = "unset"
    public static let locked = "locked"
    public static let unlocked = "unlocked"
}

/**
 Web's `status()`: nil means "we have not looked yet", which is a different
 thing from "there are no keys" and must not render as the setup form.
 */
public func securityStatus(hasKeys: Bool?, unlocked: Bool) -> String {
    guard let hasKeys else { return SecurityStatus.loading }
    if !hasKeys { return SecurityStatus.unset }
    return unlocked ? SecurityStatus.unlocked : SecurityStatus.locked
}

/// i18n keys for the two setup-form refusals, or nil when the form is fine.
public enum SecuritySetupError {
    public static let tooShort = "setupTooShort"
    public static let mismatch = "setupMismatch"
}

/**
 Web's `SetupBox.go()` guard, in the order it runs there: length first, so a
 user who typed a short passphrase twice is told the useful thing.
 */
public func passphraseSetupErrorKey(passphrase: String, confirm: String) -> String? {
    if passphrase.count < securityMinPassphraseLength { return SecuritySetupError.tooShort }
    if passphrase != confirm { return SecuritySetupError.mismatch }
    return nil
}

// MARK: - Support grants

/// Web's `Date.now() + ttlHours * 3_600_000`.
public func grantExpiryMillis(nowMs: Int64, ttlHours: Int) -> Int64 {
    nowMs + Int64(ttlHours) * securityMillisPerHour
}

/**
 The exact bytes the user signs to authorise a support grant.

 Web signs `canonical({ userId, grantId, exp, scope })` — sorted keys, so the
 signature is deterministic. Built by hand rather than through a serializer
 because a serializer that decides its own key order is precisely the thing
 this function exists to prevent. Sorted here means: exp, grantId, scope,
 userId.
 */
public func canonicalGrantJson(userId: String, grantId: String, exp: Int64, scope: String) -> String {
    "{\"exp\":\(exp),\"grantId\":\(jsonString(grantId)),\"scope\":\(jsonString(scope)),\"userId\":\(jsonString(userId))}"
}

/// `JSON.stringify` for a string, restricted to what a UUID/scope can contain
/// plus the escapes JSON requires. Not a general serializer — the two call
/// sites pass a UUID and one of two fixed words.
private func jsonString(_ value: String) -> String {
    var out = "\""
    for ch in value.unicodeScalars {
        switch ch {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        default:
            if ch.value < 0x20 {
                out += String(format: "\\u%04x", ch.value)
            } else {
                out.unicodeScalars.append(ch)
            }
        }
    }
    return out + "\""
}

/// A user's ECDSA consent-signing keypair, as the two JWK documents web stores.
public struct SigningKeypairJwk: Sendable {
    public let publicJwkJson: String
    public let privateJwkJson: String

    public init(publicJwkJson: String, privateJwkJson: String) {
        self.publicJwkJson = publicJwkJson
        self.privateJwkJson = privateJwkJson
    }
}

/**
 Generate the consent-signing keypair, as `generateSigningKeypair()` does.

 The public JWK goes to the server so support can verify a grant; the private
 JWK is encrypted under the DEK before it goes anywhere. Emitting the same
 field set WebCrypto's `exportKey("jwk", …)` does matters: this row is read
 back by the browser, and by the headless support-admin script, both of which
 feed it straight to `importKey("jwk", …)`.
 */
public func generateSigningKeypair() -> SigningKeypairJwk {
    let key = P256.Signing.PrivateKey()
    // CryptoKit's public `rawRepresentation` is the uncompressed point WITHOUT
    // the 0x04 prefix — exactly x‖y, 32 bytes each.
    let point = key.publicKey.rawRepresentation
    let x = base64UrlEncode(point.prefix(securityP256CoordinateBytes))
    let y = base64UrlEncode(point.suffix(securityP256CoordinateBytes))
    let d = base64UrlEncode(key.rawRepresentation)
    return SigningKeypairJwk(
        publicJwkJson: "{\"crv\":\"\(securitySigningCurveJwk)\",\"ext\":true,\"key_ops\":[\"verify\"],\"kty\":\"EC\",\"x\":\"\(x)\",\"y\":\"\(y)\"}",
        privateJwkJson: "{\"crv\":\"\(securitySigningCurveJwk)\",\"d\":\"\(d)\",\"ext\":true,\"key_ops\":[\"sign\"],\"kty\":\"EC\",\"x\":\"\(x)\",\"y\":\"\(y)\"}"
    )
}

/**
 DER (`SEQUENCE { INTEGER r, INTEGER s }`) to the raw `r ‖ s` WebCrypto uses.

 CryptoKit already hands back the raw form, so this platform does not need it
 to sign — Android does, because JCE emits DER and WebCrypto's `verify`
 (which is what support's admin tool runs) accepts nothing but raw. A DER
 converter only one platform runs is a DER converter only one platform has ever
 checked, so both register it against the same vector.
 */
public func ecdsaDerToRawSignature(_ der: Data) throws -> Data {
    let bytes = [UInt8](der)
    var index = 0
    func next() throws -> UInt8 {
        guard index < bytes.count else { throw SecurityEnvelopeError() }
        defer { index += 1 }
        return bytes[index]
    }
    func readLength() throws -> Int {
        let first = try next()
        if first < 0x80 { return Int(first) }
        let count = Int(first & 0x7F)
        guard count > 0, count <= 4 else { throw SecurityEnvelopeError() }
        var value = 0
        // `try` may not sit to the right of a non-assignment operator in
        // Swift, so the byte is read into a local first.
        for _ in 0..<count {
            let byte = try next()
            value = (value << 8) | Int(byte)
        }
        guard value <= bytes.count else { throw SecurityEnvelopeError() }
        return value
    }
    func readInteger() throws -> [UInt8] {
        guard try next() == asn1Integer else { throw SecurityEnvelopeError() }
        let length = try readLength()
        guard index + length <= bytes.count else { throw SecurityEnvelopeError() }
        let raw = Array(bytes[index..<(index + length)])
        index += length
        return fixedWidth(raw, securityP256CoordinateBytes)
    }
    guard try next() == asn1Sequence else { throw SecurityEnvelopeError() }
    _ = try readLength()
    let r = try readInteger()
    let s = try readInteger()
    return Data(r + s)
}

/// Left-pad (or drop a leading DER sign byte) to the fixed field width.
private func fixedWidth(_ value: [UInt8], _ width: Int) -> [UInt8] {
    if value.count == width { return value }
    if value.count > width { return Array(value.suffix(width)) }
    return [UInt8](repeating: 0, count: width - value.count) + value
}

/// Sign a consent grant with the user's ECDSA private JWK, WebCrypto-style.
///
/// CryptoKit's `signature(for:)` on a P-256 signing key hashes with SHA-256,
/// which is what web's `{ name: "ECDSA", hash: "SHA-256" }` asks for.
public func signGrant(canonicalPayload: String, privateJwkD: String) throws -> Data {
    let d = try base64UrlDecode(privateJwkD)
    do {
        let key = try P256.Signing.PrivateKey(rawRepresentation: d)
        return try key.signature(for: Data(canonicalPayload.utf8)).rawRepresentation
    } catch {
        throw SecurityEnvelopeError()
    }
}

private func derLength(_ length: Int) -> [UInt8] {
    if length < 0x80 { return [UInt8(length)] }
    if length < 0x100 { return [0x81, UInt8(length)] }
    return [0x82, UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]
}

private func derInteger(_ value: [UInt8]) -> [UInt8] {
    var start = 0
    while start < value.count - 1 && value[start] == 0 { start += 1 }
    var body = Array(value[start...])
    // A leading high bit would read as a negative INTEGER; DER prepends 0x00.
    if let first = body.first, first & 0x80 != 0 { body = [0] + body }
    return [asn1Integer] + derLength(body.count) + body
}

/**
 PKCS#1 `RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }`.

 `SecKeyCreateWithData` accepts this and nothing else for an RSA public key —
 an X.509 SubjectPublicKeyInfo wrapper is rejected with an opaque
 `errSecParam`. Android does not need the DER at all (its `RSAPublicKeySpec`
 takes the two integers), but it builds and registers the same function so both
 sides check it against one vector.
 */
public func rsaPublicKeyDer(modulusB64Url: String, exponentB64Url: String) throws -> Data {
    let modulus = derInteger([UInt8](try base64UrlDecode(modulusB64Url)))
    let exponent = derInteger([UInt8](try base64UrlDecode(exponentB64Url)))
    let body = modulus + exponent
    return Data([asn1Sequence] + derLength(body.count) + body)
}

/**
 Re-wrap the DEK for the SUPPORT public key. Web's `wrapDekForSupport`.

 Takes the JWK's two integers rather than the JWK document: parsing JSON is the
 caller's job, and the caller in Data already has a parser.
 */
public func wrapDekForSupport(dek: Data, modulusB64Url: String, exponentB64Url: String) throws -> String {
    let der = try rsaPublicKeyDer(modulusB64Url: modulusB64Url, exponentB64Url: exponentB64Url)
    let modulusBytes = try base64UrlDecode(modulusB64Url)
    let attributes: [CFString: Any] = [
        kSecAttrKeyType: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass: kSecAttrKeyClassPublic,
        // Taken from the modulus rather than hard-coded to 3072: the support
        // keypair can be rotated, and a size that disagrees with the key is a
        // rejection with no useful message.
        kSecAttrKeySizeInBits: NSNumber(value: modulusBytes.count * 8),
    ]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error) else {
        throw SecurityEnvelopeError()
    }
    guard let ciphertext = SecKeyCreateEncryptedData(
        key,
        .rsaEncryptionOAEPSHA256,
        dek as CFData,
        &error
    ) else {
        throw SecurityEnvelopeError()
    }
    return securityBase64Encode(ciphertext as Data)
}
