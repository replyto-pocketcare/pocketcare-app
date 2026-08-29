package com.sanvya.app.domain.security

import com.sanvya.app.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.put

// Wires Security.kt into FunctionRegistry.
//
// These fixtures are NOT hand-written expectations. `security.json` was
// produced by running the SAME WebCrypto calls apps/web makes -- PBKDF2 at
// 210 000 iterations over a fixed salt, AES-GCM under a fixed key and a fixed
// IV -- and capturing the output. That is the only honest way to test this
// domain: the requirement is not "the port is self-consistent", it is "the
// port can open a ciphertext a browser wrote, byte for byte, and the browser
// can open what the port writes".
//
// Three of the cases are the ones that would otherwise ship silently broken:
//
//   * a non-ASCII passphrase in `deriveKekHex`. Android's stock
//     `PBKDF2WithHmacSHA256` converts the passphrase's chars to bytes with
//     PKCS#5's 8-bit rule, not UTF-8, so this vector is the whole reason
//     Security.kt derives over explicit UTF-8 bytes instead.
//   * a one-bit-flipped ciphertext in `decryptFieldWithDekHex`. GCM must
//     REFUSE it. A port that ignored the tag would pass every other case here.
//   * `ecdsaDerToRawSignatureHex` with a 33-byte INTEGER (leading 0x00 for the
//     sign bit) and with a 1-byte one. JCE emits DER; WebCrypto -- which is
//     what support's verifier runs -- accepts only raw r||s, and the two
//     lengths above are exactly where a naive conversion loses or gains a byte.
private const val DOMAIN = "security"

private fun hexToBytes(hex: String): ByteArray {
    val out = ByteArray(hex.length / 2)
    for (i in out.indices) {
        out[i] = ((Character.digit(hex[i * 2], 16) shl 4) or Character.digit(hex[i * 2 + 1], 16)).toByte()
    }
    return out
}

private fun bytesToHex(bytes: ByteArray): String {
    val out = StringBuilder(bytes.size * 2)
    for (b in bytes) out.append(String.format("%02x", b.toInt() and 0xFF))
    return out.toString()
}

private fun JsonElement.str(key: String): String = jsonObject.getValue(key).jsonPrimitive.content

fun registerSecurityVectors() {
    FunctionRegistry.register(DOMAIN, "isEncryptedEnvelope") { input ->
        JsonPrimitive(isEncryptedEnvelope(input.str("value")))
    }

    FunctionRegistry.register(DOMAIN, "formatSecurityEnvelope") { input ->
        JsonPrimitive(formatSecurityEnvelope(input.str("ivBase64"), input.str("ctBase64")))
    }

    FunctionRegistry.register(DOMAIN, "parseSecurityEnvelope") { input ->
        val parsed = parseSecurityEnvelope(input.str("envelope"))
        if (parsed == null) {
            JsonNull
        } else {
            buildJsonObject {
                put("ivBase64", parsed.ivBase64)
                put("ctBase64", parsed.ctBase64)
            }
        }
    }

    FunctionRegistry.register(DOMAIN, "recoveryCodeFromBytes") { input ->
        JsonPrimitive(recoveryCodeFromBytes(hexToBytes(input.str("bytesHex"))))
    }

    FunctionRegistry.register(DOMAIN, "normalizeRecoveryCode") { input ->
        JsonPrimitive(normalizeRecoveryCode(input.str("input")))
    }

    FunctionRegistry.register(DOMAIN, "securityStatus") { input ->
        val obj: JsonObject = input.jsonObject
        // JsonNull is a JsonPrimitive whose booleanOrNull is null -- which is
        // exactly the "we have not looked yet" state the status machine reads.
        val hasKeys = obj.getValue("hasKeys").jsonPrimitive.booleanOrNull
        val unlocked = obj.getValue("unlocked").jsonPrimitive.booleanOrNull == true
        JsonPrimitive(securityStatus(hasKeys, unlocked))
    }

    FunctionRegistry.register(DOMAIN, "passphraseSetupErrorKey") { input ->
        val key = passphraseSetupErrorKey(input.str("passphrase"), input.str("confirm"))
        if (key == null) JsonNull else JsonPrimitive(key)
    }

    FunctionRegistry.register(DOMAIN, "canonicalGrantJson") { input ->
        JsonPrimitive(
            canonicalGrantJson(
                userId = input.str("userId"),
                grantId = input.str("grantId"),
                exp = input.jsonObject.getValue("exp").jsonPrimitive.long,
                scope = input.str("scope"),
            ),
        )
    }

    FunctionRegistry.register(DOMAIN, "grantExpiryMillis") { input ->
        JsonPrimitive(
            grantExpiryMillis(
                nowMs = input.jsonObject.getValue("nowMs").jsonPrimitive.long,
                ttlHours = input.jsonObject.getValue("ttlHours").jsonPrimitive.int,
            ),
        )
    }

    // Registered SEPARATELY from deriveKekHex, which can only ever ask for 32
    // bytes -- exactly SHA-256's own output length, so `blocks` is always 1 and
    // the INT(i) block counter for i > 1 and the output-offset arithmetic have
    // no coverage at all through that door. These cases ask for 20, 32, 64 and
    // 100 bytes, which is one partial block, one exact block, two blocks, and
    // four blocks truncated mid-block.
    FunctionRegistry.register(DOMAIN, "pbkdf2HmacSha256") { input ->
        JsonPrimitive(
            bytesToHex(
                pbkdf2HmacSha256(
                    password = input.str("passwordUtf8").toByteArray(Charsets.UTF_8),
                    salt = securityBase64Decode(input.str("saltBase64")),
                    iterations = input.jsonObject.getValue("iterations").jsonPrimitive.int,
                    keyLengthBytes = input.jsonObject.getValue("keyLengthBytes").jsonPrimitive.int,
                ),
            ),
        )
    }

    FunctionRegistry.register(DOMAIN, "deriveKekHex") { input ->
        JsonPrimitive(
            bytesToHex(
                deriveKek(
                    passphrase = input.str("passphrase"),
                    salt = securityBase64Decode(input.str("saltBase64")),
                    iterations = input.jsonObject.getValue("iterations").jsonPrimitive.int,
                ),
            ),
        )
    }

    FunctionRegistry.register(DOMAIN, "decryptFieldWithDekHex") { input ->
        JsonPrimitive(decryptField(input.str("envelope"), hexToBytes(input.str("dekHex"))))
    }

    FunctionRegistry.register(DOMAIN, "unwrapDekHex") { input ->
        JsonPrimitive(bytesToHex(unwrapDek(input.str("wrapped"), hexToBytes(input.str("kekHex")))))
    }

    // The write path. A round trip cannot be pinned to a browser-produced
    // string (the IV is random by design), so what it pins is that this port's
    // OWN sealing is openable -- and, together with decryptFieldWithDekHex
    // above, that both directions speak the same format.
    FunctionRegistry.register(DOMAIN, "fieldRoundTrip") { input ->
        val dek = hexToBytes(input.str("dekHex"))
        JsonPrimitive(decryptField(encryptField(input.str("plaintext"), dek), dek))
    }

    FunctionRegistry.register(DOMAIN, "ecdsaDerToRawSignatureHex") { input ->
        JsonPrimitive(bytesToHex(ecdsaDerToRawSignature(hexToBytes(input.str("derHex")))))
    }

    FunctionRegistry.register(DOMAIN, "rsaPublicKeyDerHexFromJwk") { input ->
        JsonPrimitive(bytesToHex(rsaPublicKeyDer(input.str("n"), input.str("e"))))
    }

    FunctionRegistry.register(DOMAIN, "base64UrlToBase64") { input ->
        JsonPrimitive(base64UrlToBase64(input.str("input")))
    }

    FunctionRegistry.register(DOMAIN, "base64ToBase64Url") { input ->
        JsonPrimitive(base64ToBase64Url(input.str("input")))
    }
}
