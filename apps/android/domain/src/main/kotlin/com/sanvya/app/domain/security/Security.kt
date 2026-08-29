package com.sanvya.app.domain.security

import java.io.ByteArrayOutputStream
import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.SecureRandom
import java.security.Signature
import java.security.interfaces.ECPrivateKey
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPrivateKeySpec
import java.security.spec.MGF1ParameterSpec
import java.security.spec.RSAPublicKeySpec
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource
import javax.crypto.spec.SecretKeySpec

/**
 * The Hybrid zero-trust envelope scheme — Kotlin side.
 *
 * Ported from `packages/core/crypto/src/index.ts` (the `@sanvya/crypto`
 * package the files under web's `src/crypto` are built on) and pinned,
 * primitive by primitive, by
 * `tools/golden-vectors/vectors/security.json`. Those vectors
 * were produced by RUNNING web's own WebCrypto calls, which is the only way
 * to prove the thing that actually matters here: an envelope written in a
 * browser must open on a phone and vice versa. A cosmetic bug in this file is
 * unreadable user data, not a misaligned label.
 *
 * WHY THIS IS IN :domain AND NOT :data. Everything below is deterministic and
 * platform-independent — `javax.crypto` is JDK API, present on Android since
 * forever, and needs no Android SDK type. Putting it here is what lets the
 * vector runner execute it: the runner lives in this module's test source set,
 * and a primitive it cannot run is a primitive nobody has checked against web.
 * The parts that genuinely need the platform — the Keystore, the database, the
 * network — live in :data, which is where they belong.
 *
 * WHY PBKDF2 IS HAND-ROLLED OVER `Mac` RATHER THAN `SecretKeyFactory`.
 * `PBKDF2WithHmacSHA256` takes a `PBEKeySpec(char[])` and the provider decides
 * how those chars become bytes. Android's historical answer for the PBKDF2
 * families is the PKCS#5 8-bit conversion (the low byte of each char), NOT
 * UTF-8 — so a passphrase with any non-ASCII character would derive a
 * different key on the phone than in the browser, and the user would be told
 * their correct passphrase is wrong. Feeding UTF-8 bytes into HMAC-SHA256
 * ourselves removes the provider's opinion from the equation. The construction
 * is RFC 8018 §5.2 verbatim, and the `deriveKekHex` vectors (one of them a
 * deliberately non-ASCII passphrase) are what prove it agrees with WebCrypto.
 */

// ---------------------------------------------------------------------------
// Parameters. Every one of these is web's value; none may be inlined at a call
// site, because the day one of them drifts is the day the two platforms stop
// being able to read each other and nothing says so out loud.
// ---------------------------------------------------------------------------

/** The only envelope version that exists. `v1.<base64 iv>.<base64 ct+tag>`. */
const val SECURITY_ENVELOPE_VERSION: String = "v1"

/** Separator between an envelope's three fields (web: `envelope.split(".")`). */
const val SECURITY_ENVELOPE_SEPARATOR: Char = '.'

/** OWASP 2023 guidance for PBKDF2-HMAC-SHA256, and web's `PBKDF2_ITERATIONS`. */
const val SECURITY_PBKDF2_ITERATIONS: Int = 210_000

/** AES-GCM 256 — the `length: 256` web asks `deriveKey` for. */
const val SECURITY_KEK_LENGTH_BYTES: Int = 32

/** `generateDek()` — "a fresh 256-bit data encryption key". */
const val SECURITY_DEK_LENGTH_BYTES: Int = 32

/** `newSalt()` — `randomBytes(16)`. */
const val SECURITY_SALT_LENGTH_BYTES: Int = 16

/** `aesEncrypt()` — `randomBytes(12)`, the AES-GCM standard nonce size. */
const val SECURITY_IV_LENGTH_BYTES: Int = 12

/**
 * WebCrypto appends a 128-bit tag to the ciphertext and offers no way to
 * choose otherwise, so this is not a preference — it is the only value that
 * can read a browser-written envelope.
 */
const val SECURITY_GCM_TAG_LENGTH_BITS: Int = 128

/** `generateRecoveryCode()` — `randomBytes(20)`. */
const val SECURITY_RECOVERY_CODE_LENGTH_BYTES: Int = 20

/** A dash after every fourth character, but never a trailing one. */
const val SECURITY_RECOVERY_CODE_GROUP_SIZE: Int = 4

/** Web's alphabet, chosen for having no ambiguous glyphs (no I/L/O/0/1). */
const val SECURITY_RECOVERY_CODE_ALPHABET: String = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

/** `SetupBox`'s `if (pass.length < 8)`. */
const val SECURITY_MIN_PASSPHRASE_LENGTH: Int = 8

/** `issueSupportGrant(scope, 2)` — the support window the panel promises. */
const val SECURITY_GRANT_TTL_HOURS: Int = 2

/** Milliseconds in an hour — web's `ttlHours * 3_600_000`. */
const val SECURITY_MILLIS_PER_HOUR: Long = 3_600_000L

/** `generateSigningKeypair()` — ECDSA P-256, the consent-grant signing curve. */
const val SECURITY_SIGNING_CURVE: String = "secp256r1"

/** The JWK name for [SECURITY_SIGNING_CURVE]; the two must not drift apart. */
const val SECURITY_SIGNING_CURVE_JWK: String = "P-256"

/** Half a P-256 raw signature, and the width of the `x`/`y`/`d` JWK fields. */
const val SECURITY_P256_COORDINATE_BYTES: Int = 32

private const val HMAC_ALGORITHM = "HmacSHA256"
private const val AES_ALGORITHM = "AES"
private const val AES_GCM_TRANSFORMATION = "AES/GCM/NoPadding"
private const val EC_ALGORITHM = "EC"
private const val RSA_ALGORITHM = "RSA"
private const val ECDSA_SIGNATURE_ALGORITHM = "SHA256withECDSA"

/**
 * RSA-OAEP with SHA-256 for BOTH the label hash and MGF1.
 *
 * The JCE default for `OAEPPadding` is MGF1-**SHA-1**, and it does not warn:
 * you get a ciphertext support's WebCrypto-based admin tool cannot open, with
 * no error until the day somebody actually needs the grant. The parameters are
 * therefore always passed explicitly — see [wrapDekForSupport].
 */
private const val RSA_OAEP_TRANSFORMATION = "RSA/ECB/OAEPPadding"
private const val OAEP_DIGEST = "SHA-256"
private const val OAEP_MGF = "MGF1"

private const val ASN1_SEQUENCE: Int = 0x30
private const val ASN1_INTEGER: Int = 0x02

/**
 * Stands in for the TS source's plain `new Error("bad envelope")`.
 *
 * One message for every way an envelope can fail to open — wrong version,
 * wrong shape, bad base64, wrong key, tampered ciphertext — deliberately.
 * Telling a caller WHICH of those happened tells an attacker the same thing,
 * and no caller does anything different with the answer.
 */
class SecurityEnvelopeError(override val message: String) : Exception(message)

private const val BAD_ENVELOPE = "bad envelope"

// ---------------------------------------------------------------------------
// Base64 / base64url
// ---------------------------------------------------------------------------

/** Standard, padded base64 — what `btoa` produces and web stores. */
fun securityBase64Encode(bytes: ByteArray): String = Base64.getEncoder().encodeToString(bytes)

/** Strict decode; a malformed body is a bad envelope, not a crash. */
fun securityBase64Decode(text: String): ByteArray = try {
    Base64.getDecoder().decode(text)
} catch (_: IllegalArgumentException) {
    throw SecurityEnvelopeError(BAD_ENVELOPE)
}

/**
 * JWKs are base64**url** (RFC 7515) and everything else here is base64.
 * Converting at the boundary keeps one decoder in the file rather than two.
 */
fun base64UrlToBase64(input: String): String {
    val swapped = input.replace('-', '+').replace('_', '/')
    val remainder = swapped.length % 4
    return if (remainder == 0) swapped else swapped + "=".repeat(4 - remainder)
}

/** The inverse: unpadded, URL-safe, as a JWK field must be written. */
fun base64ToBase64Url(input: String): String =
    input.trimEnd('=').replace('+', '-').replace('/', '_')

private fun base64UrlDecode(input: String): ByteArray =
    Base64.getDecoder().decode(base64UrlToBase64(input))

private fun base64UrlEncode(bytes: ByteArray): String =
    base64ToBase64Url(Base64.getEncoder().encodeToString(bytes))

// ---------------------------------------------------------------------------
// Envelope shape (pure string work — the part the vectors care most about)
// ---------------------------------------------------------------------------

/** The two halves of a parsed envelope, still base64. */
data class SecurityEnvelope(val ivBase64: String, val ctBase64: String)

/**
 * True if a stored value looks like one of our ciphertext envelopes.
 *
 * Web's `isEncrypted`: a `startsWith` on the version prefix and nothing more.
 * Deliberately loose — the point is to tell "the user typed this" from "we
 * wrote this", cheaply, on every row of a list.
 */
fun isEncryptedEnvelope(value: String?): Boolean =
    value != null && value.startsWith("$SECURITY_ENVELOPE_VERSION$SECURITY_ENVELOPE_SEPARATOR")

/** `v1.<iv>.<ct>`. */
fun formatSecurityEnvelope(ivBase64: String, ctBase64: String): String =
    "$SECURITY_ENVELOPE_VERSION$SECURITY_ENVELOPE_SEPARATOR$ivBase64$SECURITY_ENVELOPE_SEPARATOR$ctBase64"

/**
 * Split an envelope, or null if it is not one.
 *
 * Web throws here; this returns null so the caller decides whether a
 * non-envelope is an error (unwrapping a key) or simply plaintext to pass
 * through (rendering a note). Exactly three parts: `v1.a.b.c` is rejected,
 * because a stray separator means we are not looking at what we think.
 */
fun parseSecurityEnvelope(envelope: String?): SecurityEnvelope? {
    if (envelope == null) return null
    val parts = envelope.split(SECURITY_ENVELOPE_SEPARATOR)
    if (parts.size != 3) return null
    if (parts[0] != SECURITY_ENVELOPE_VERSION) return null
    return SecurityEnvelope(ivBase64 = parts[1], ctBase64 = parts[2])
}

// ---------------------------------------------------------------------------
// Key derivation
// ---------------------------------------------------------------------------

/**
 * PBKDF2-HMAC-SHA256, RFC 8018 §5.2, over the UTF-8 bytes of [password].
 *
 * See the file header for why this is not `SecretKeyFactory`.
 */
fun pbkdf2HmacSha256(
    password: ByteArray,
    salt: ByteArray,
    iterations: Int,
    keyLengthBytes: Int,
): ByteArray {
    require(iterations > 0) { "iterations must be positive" }
    require(keyLengthBytes > 0) { "keyLengthBytes must be positive" }
    val mac = Mac.getInstance(HMAC_ALGORITHM)
    mac.init(SecretKeySpec(password, HMAC_ALGORITHM))
    val hashLength = mac.macLength
    val blocks = (keyLengthBytes + hashLength - 1) / hashLength
    val derived = ByteArray(blocks * hashLength)
    for (block in 1..blocks) {
        mac.update(salt)
        // INT(i), big-endian, appended to the salt for the first HMAC only.
        mac.update(
            byteArrayOf(
                (block ushr 24).toByte(),
                (block ushr 16).toByte(),
                (block ushr 8).toByte(),
                block.toByte(),
            ),
        )
        var u = mac.doFinal()
        val accumulator = u.copyOf()
        for (round in 2..iterations) {
            u = mac.doFinal(u)
            for (i in accumulator.indices) {
                accumulator[i] = (accumulator[i].toInt() xor u[i].toInt()).toByte()
            }
        }
        System.arraycopy(accumulator, 0, derived, (block - 1) * hashLength, hashLength)
    }
    return derived.copyOf(keyLengthBytes)
}

/**
 * The key-encryption key, from a passphrase or a recovery code.
 *
 * Web's `deriveKek`. [iterations] is a parameter for the same reason it is one
 * there — so a future cost bump can read the value off the row it is
 * unwrapping instead of guessing — but every call today passes the constant.
 */
fun deriveKek(
    passphrase: String,
    salt: ByteArray,
    iterations: Int = SECURITY_PBKDF2_ITERATIONS,
): ByteArray = pbkdf2HmacSha256(
    password = passphrase.toByteArray(Charsets.UTF_8),
    salt = salt,
    iterations = iterations,
    keyLengthBytes = SECURITY_KEK_LENGTH_BYTES,
)

// ---------------------------------------------------------------------------
// AES-GCM envelope
// ---------------------------------------------------------------------------

/** Cryptographically strong bytes. One source, so nothing reaches for Random. */
fun securityRandomBytes(count: Int): ByteArray {
    val out = ByteArray(count)
    SecureRandom().nextBytes(out)
    return out
}

/** A fresh per-user PBKDF2 salt. */
fun newSecuritySalt(): ByteArray = securityRandomBytes(SECURITY_SALT_LENGTH_BYTES)

/** A fresh 256-bit data encryption key. */
fun generateDek(): ByteArray = securityRandomBytes(SECURITY_DEK_LENGTH_BYTES)

/**
 * Seal [plaintext] under [key] into an envelope.
 *
 * [iv] is injectable ONLY so the golden vectors can pin the output against a
 * browser's; every production caller lets it default to fresh randomness. A
 * reused nonce under the same key breaks GCM completely.
 */
fun aesGcmSeal(
    key: ByteArray,
    plaintext: ByteArray,
    iv: ByteArray = securityRandomBytes(SECURITY_IV_LENGTH_BYTES),
): String {
    val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
    cipher.init(
        Cipher.ENCRYPT_MODE,
        SecretKeySpec(key, AES_ALGORITHM),
        GCMParameterSpec(SECURITY_GCM_TAG_LENGTH_BITS, iv),
    )
    // JCE returns ciphertext||tag, which is exactly WebCrypto's layout.
    return formatSecurityEnvelope(securityBase64Encode(iv), securityBase64Encode(cipher.doFinal(plaintext)))
}

/** Open an envelope, or throw [SecurityEnvelopeError]. */
fun aesGcmOpen(key: ByteArray, envelope: String): ByteArray {
    val parsed = parseSecurityEnvelope(envelope) ?: throw SecurityEnvelopeError(BAD_ENVELOPE)
    val iv = securityBase64Decode(parsed.ivBase64)
    val ciphertext = securityBase64Decode(parsed.ctBase64)
    return try {
        val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            SecretKeySpec(key, AES_ALGORITHM),
            GCMParameterSpec(SECURITY_GCM_TAG_LENGTH_BITS, iv),
        )
        cipher.doFinal(ciphertext)
    } catch (_: Exception) {
        // Wrong key and tampered ciphertext are the same answer on purpose.
        throw SecurityEnvelopeError(BAD_ENVELOPE)
    }
}

/** Wrap the DEK under a KEK. Web's `wrapDek`. */
fun wrapDek(dek: ByteArray, kek: ByteArray): String = aesGcmSeal(kek, dek)

/** Unwrap the DEK. Throws on a wrong passphrase or a tampered row. */
fun unwrapDek(wrapped: String, kek: ByteArray): ByteArray = aesGcmOpen(kek, wrapped)

/** Encrypt one field value for storage. Web's `encryptField`. */
fun encryptField(plaintext: String, dek: ByteArray): String =
    aesGcmSeal(dek, plaintext.toByteArray(Charsets.UTF_8))

/** Decrypt one stored field value. Web's `decryptField`. */
fun decryptField(envelope: String, dek: ByteArray): String =
    String(aesGcmOpen(dek, envelope), Charsets.UTF_8)

// ---------------------------------------------------------------------------
// Recovery code
// ---------------------------------------------------------------------------

/**
 * Web's `generateRecoveryCode` encoding, separated from its randomness.
 *
 * The modulo is biased (256 is not a multiple of 31) and that is web's
 * encoding, not a mistake to fix here: a phone and a browser have to produce
 * codes from the same alphabet, and 20 bytes of entropy squeezed into a
 * slightly non-uniform 31-symbol code is still ~98 bits. Changing it would
 * make the two sides disagree about nothing useful.
 */
fun recoveryCodeFromBytes(raw: ByteArray): String {
    val out = StringBuilder()
    for (i in raw.indices) {
        val index = (raw[i].toInt() and 0xFF) % SECURITY_RECOVERY_CODE_ALPHABET.length
        out.append(SECURITY_RECOVERY_CODE_ALPHABET[index])
        if ((i + 1) % SECURITY_RECOVERY_CODE_GROUP_SIZE == 0 && i < raw.size - 1) out.append('-')
    }
    return out.toString()
}

/** A fresh one-time recovery code. Shown once, never stored in the clear. */
fun generateRecoveryCode(): String =
    recoveryCodeFromBytes(securityRandomBytes(SECURITY_RECOVERY_CODE_LENGTH_BYTES))

/**
 * What a typed recovery code becomes before it is fed to the KDF.
 *
 * Web's `unlockWithRecovery` does `code.trim().toUpperCase()` and nothing
 * else — the dashes are part of the derived string, so they cannot be
 * stripped here however tempting that looks.
 */
fun normalizeRecoveryCode(input: String): String = input.trim().uppercase()

// ---------------------------------------------------------------------------
// Panel state
// ---------------------------------------------------------------------------

/** Web's `CryptoStatus`. String-valued so the vectors can pin it. */
object SecurityStatus {
    const val LOADING = "loading"
    const val UNSET = "unset"
    const val LOCKED = "locked"
    const val UNLOCKED = "unlocked"
}

/**
 * Web's `status()`: null means "we have not looked yet", which is a different
 * thing from "there are no keys" and must not render as the setup form.
 */
fun securityStatus(hasKeys: Boolean?, unlocked: Boolean): String = when {
    hasKeys == null -> SecurityStatus.LOADING
    !hasKeys -> SecurityStatus.UNSET
    unlocked -> SecurityStatus.UNLOCKED
    else -> SecurityStatus.LOCKED
}

/** i18n keys for the two setup-form refusals, or null when the form is fine. */
object SecuritySetupError {
    const val TOO_SHORT = "setupTooShort"
    const val MISMATCH = "setupMismatch"
}

/**
 * Web's `SetupBox.go()` guard, in the order it runs there: length first, so a
 * user who typed a short passphrase twice is told the useful thing.
 */
fun passphraseSetupErrorKey(passphrase: String, confirm: String): String? = when {
    passphrase.length < SECURITY_MIN_PASSPHRASE_LENGTH -> SecuritySetupError.TOO_SHORT
    passphrase != confirm -> SecuritySetupError.MISMATCH
    else -> null
}

// ---------------------------------------------------------------------------
// Support grants
// ---------------------------------------------------------------------------

/** Web's `Date.now() + ttlHours * 3_600_000`. */
fun grantExpiryMillis(nowMs: Long, ttlHours: Int): Long = nowMs + ttlHours * SECURITY_MILLIS_PER_HOUR

/**
 * The exact bytes the user signs to authorise a support grant.
 *
 * Web signs `canonical({ userId, grantId, exp, scope })` — sorted keys, so the
 * signature is deterministic. Built by hand rather than through a serializer
 * because :domain has no JSON library in its main source set, and because a
 * serializer that decides its own key order is precisely the thing this
 * function exists to prevent. Sorted here means: exp, grantId, scope, userId.
 */
fun canonicalGrantJson(userId: String, grantId: String, exp: Long, scope: String): String =
    """{"exp":$exp,"grantId":${jsonString(grantId)},"scope":${jsonString(scope)},"userId":${jsonString(userId)}}"""

/**
 * `JSON.stringify` for a string, restricted to what a UUID/scope can contain
 * plus the escapes JSON requires. Not a general serializer — the two call
 * sites pass a UUID and one of two fixed words.
 */
private fun jsonString(value: String): String {
    val out = StringBuilder("\"")
    for (ch in value) {
        when {
            ch == '"' -> out.append("\\\"")
            ch == '\\' -> out.append("\\\\")
            ch < ' ' -> out.append("\\u").append(String.format("%04x", ch.code))
            else -> out.append(ch)
        }
    }
    return out.append('"').toString()
}

/** A user's ECDSA consent-signing keypair, as the two JWK documents web stores. */
data class SigningKeypairJwk(val publicJwkJson: String, val privateJwkJson: String)

/**
 * The P-256 domain parameters, taken off a freshly generated key.
 *
 * NOT `AlgorithmParameters.getInstance("EC").init(ECGenParameterSpec(…))`, which
 * is the obvious spelling and has a patchy history on Android: several OEM and
 * older-API provider combinations either do not register an "EC"
 * `AlgorithmParameters` implementation at all or refuse
 * `getParameterSpec(ECParameterSpec::class.java)`, and the failure is a
 * `NoSuchAlgorithmException`/`InvalidParameterSpecException` at the moment a
 * user tries to authorise support access. `KeyPairGenerator` for EC is
 * available everywhere -- [generateSigningKeypair] already depends on it, so a
 * device that cannot do this cannot have set encryption up in the first place.
 *
 * Generating a throwaway keypair to read a curve constant is wasteful and is
 * chosen deliberately: it happens at most twice in a session (only when a
 * grant is signed), and the alternative is a hard-coded copy of the SECP256R1
 * constants, which is the kind of transcription this file exists to avoid.
 */
private fun p256Parameters(): ECParameterSpec {
    val generator = KeyPairGenerator.getInstance(EC_ALGORITHM)
    generator.initialize(ECGenParameterSpec(SECURITY_SIGNING_CURVE))
    return (generator.generateKeyPair().public as ECPublicKey).params
}

/** Left-pad (or trim a BigInteger's sign byte off) to the fixed JWK width. */
private fun fixedWidth(value: BigInteger, width: Int): ByteArray {
    val raw = value.toByteArray()
    if (raw.size == width) return raw
    if (raw.size > width) return raw.copyOfRange(raw.size - width, raw.size)
    val padded = ByteArray(width)
    System.arraycopy(raw, 0, padded, width - raw.size, raw.size)
    return padded
}

/**
 * Generate the consent-signing keypair, as `generateSigningKeypair()` does.
 *
 * The public JWK goes to the server so support can verify a grant; the private
 * JWK is encrypted under the DEK before it goes anywhere. Emitting the same
 * field set WebCrypto's `exportKey("jwk", …)` does matters: this row is read
 * back by the browser, and by the headless support-admin script, both of which
 * feed it straight to `importKey("jwk", …)`.
 */
fun generateSigningKeypair(): SigningKeypairJwk {
    val generator = KeyPairGenerator.getInstance(EC_ALGORITHM)
    generator.initialize(ECGenParameterSpec(SECURITY_SIGNING_CURVE))
    val pair = generator.generateKeyPair()
    // `publicKey` / `privateKey`, not `public` / `private`: both are legal
    // identifiers (they are modifier keywords, not hard ones) and both read as
    // an access-level modifier at a glance, which is worse than being long.
    val publicKey = pair.public as ECPublicKey
    val privateKey = pair.private as ECPrivateKey
    val x = base64UrlEncode(fixedWidth(publicKey.w.affineX, SECURITY_P256_COORDINATE_BYTES))
    val y = base64UrlEncode(fixedWidth(publicKey.w.affineY, SECURITY_P256_COORDINATE_BYTES))
    val d = base64UrlEncode(fixedWidth(privateKey.s, SECURITY_P256_COORDINATE_BYTES))
    return SigningKeypairJwk(
        publicJwkJson = """{"crv":"$SECURITY_SIGNING_CURVE_JWK","ext":true,"key_ops":["verify"],"kty":"EC","x":"$x","y":"$y"}""",
        privateJwkJson = """{"crv":"$SECURITY_SIGNING_CURVE_JWK","d":"$d","ext":true,"key_ops":["sign"],"kty":"EC","x":"$x","y":"$y"}""",
    )
}

/**
 * DER (`SEQUENCE { INTEGER r, INTEGER s }`) to the raw `r || s` WebCrypto uses.
 *
 * `Signature("SHA256withECDSA")` emits DER; WebCrypto's `sign` emits 64 raw
 * bytes and its `verify` accepts nothing else. Support's verifier is
 * WebCrypto, so a DER signature stored in `support_grants.signature` would be
 * a grant that can never be honoured — and the failure would surface months
 * later, to somebody trying to help a user.
 */
fun ecdsaDerToRawSignature(der: ByteArray): ByteArray {
    var index = 0
    fun byteAt(): Int {
        if (index >= der.size) throw SecurityEnvelopeError(BAD_ENVELOPE)
        return der[index++].toInt() and 0xFF
    }
    if (byteAt() != ASN1_SEQUENCE) throw SecurityEnvelopeError(BAD_ENVELOPE)
    readDerLength(der) { byteAt() }
    fun readInteger(): ByteArray {
        if (byteAt() != ASN1_INTEGER) throw SecurityEnvelopeError(BAD_ENVELOPE)
        val length = readDerLength(der) { byteAt() }
        if (index + length > der.size) throw SecurityEnvelopeError(BAD_ENVELOPE)
        val value = der.copyOfRange(index, index + length)
        index += length
        return fixedWidth(BigInteger(1, value), SECURITY_P256_COORDINATE_BYTES)
    }
    val r = readInteger()
    val s = readInteger()
    return r + s
}

/** Definite-length DER, short form and the 0x81/0x82 long forms. */
private fun readDerLength(der: ByteArray, next: () -> Int): Int {
    val first = next()
    if (first < 0x80) return first
    val count = first and 0x7F
    if (count == 0 || count > 4) throw SecurityEnvelopeError(BAD_ENVELOPE)
    var value = 0
    repeat(count) { value = (value shl 8) or next() }
    if (value < 0 || value > der.size) throw SecurityEnvelopeError(BAD_ENVELOPE)
    return value
}

/** Sign a consent grant with the user's ECDSA private JWK, WebCrypto-style. */
fun signGrant(canonicalPayload: String, privateJwkD: String): ByteArray {
    val parameters = p256Parameters()
    val key = KeyFactory.getInstance(EC_ALGORITHM)
        .generatePrivate(ECPrivateKeySpec(BigInteger(1, base64UrlDecode(privateJwkD)), parameters))
    val signature = Signature.getInstance(ECDSA_SIGNATURE_ALGORITHM)
    signature.initSign(key)
    signature.update(canonicalPayload.toByteArray(Charsets.UTF_8))
    return ecdsaDerToRawSignature(signature.sign())
}

/** DER length prefix, emitted (the inverse of [readDerLength]). */
private fun writeDerLength(out: ByteArrayOutputStream, length: Int) {
    when {
        length < 0x80 -> out.write(length)
        length < 0x100 -> { out.write(0x81); out.write(length) }
        else -> { out.write(0x82); out.write((length shr 8) and 0xFF); out.write(length and 0xFF) }
    }
}

private fun derInteger(value: ByteArray): ByteArray {
    var start = 0
    while (start < value.size - 1 && value[start].toInt() == 0) start++
    var body = value.copyOfRange(start, value.size)
    // A leading high bit would read as a negative INTEGER; DER prepends 0x00.
    if (body.isNotEmpty() && (body[0].toInt() and 0x80) != 0) body = byteArrayOf(0) + body
    val out = ByteArrayOutputStream()
    out.write(ASN1_INTEGER)
    writeDerLength(out, body.size)
    out.write(body)
    return out.toByteArray()
}

/**
 * PKCS#1 `RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }`.
 *
 * Android does not need this — `RSAPublicKeySpec` takes the two integers
 * directly — but iOS's `SecKeyCreateWithData` accepts nothing else, and a DER
 * builder that only one platform runs is a DER builder only one platform has
 * ever checked. Both sides register it against the same vector.
 */
fun rsaPublicKeyDer(modulusB64Url: String, exponentB64Url: String): ByteArray {
    val body = derInteger(base64UrlDecode(modulusB64Url)) + derInteger(base64UrlDecode(exponentB64Url))
    val out = ByteArrayOutputStream()
    out.write(ASN1_SEQUENCE)
    writeDerLength(out, body.size)
    out.write(body)
    return out.toByteArray()
}

/**
 * Re-wrap the DEK for the SUPPORT public key. Web's `wrapDekForSupport`.
 *
 * Takes the JWK's two integers rather than the JWK document: :domain has no
 * JSON parser in main, and the caller in :data already has one.
 */
fun wrapDekForSupport(dek: ByteArray, modulusB64Url: String, exponentB64Url: String): String {
    val key = KeyFactory.getInstance(RSA_ALGORITHM).generatePublic(
        RSAPublicKeySpec(
            BigInteger(1, base64UrlDecode(modulusB64Url)),
            BigInteger(1, base64UrlDecode(exponentB64Url)),
        ),
    )
    val cipher = Cipher.getInstance(RSA_OAEP_TRANSFORMATION)
    cipher.init(
        Cipher.ENCRYPT_MODE,
        key,
        OAEPParameterSpec(OAEP_DIGEST, OAEP_MGF, MGF1ParameterSpec.SHA256, PSource.PSpecified.DEFAULT),
    )
    return securityBase64Encode(cipher.doFinal(dek))
}
