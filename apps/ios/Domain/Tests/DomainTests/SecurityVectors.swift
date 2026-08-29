import Foundation
@testable import Domain

// Wires Security.swift into FunctionRegistry.
//
// These fixtures are NOT hand-written expectations. `security.json` was
// produced by running the SAME WebCrypto calls apps/web makes — PBKDF2 at
// 210 000 iterations over a fixed salt, AES-GCM under a fixed key and a fixed
// IV — and capturing the output. That is the only honest way to test this
// domain: the requirement is not "the port is self-consistent", it is "the
// port can open a ciphertext a browser wrote, byte for byte, and the browser
// can open what the port writes".
//
// Three of the cases are the ones that would otherwise ship silently broken:
//
//   * a non-ASCII passphrase in `deriveKekHex`. Both ports derive over
//     explicit UTF-8 bytes rather than through a library that decides the
//     encoding for them; this vector is what proves the decision was right.
//   * a one-bit-flipped ciphertext in `decryptFieldWithDekHex`. GCM must
//     REFUSE it. A port that ignored the tag would pass every other case here.
//   * `ecdsaDerToRawSignatureHex` with a 33-byte INTEGER (leading 0x00 for the
//     sign bit) and with a 1-byte one — exactly where a naive DER conversion
//     loses or gains a byte. CryptoKit hands Swift the raw form already, so
//     this function exists here only to be checked alongside Android's, which
//     genuinely needs it.

private func hexToData(_ hex: String) -> Data {
    var bytes = [UInt8]()
    bytes.reserveCapacity(hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
        index = next
    }
    return Data(bytes)
}

private func dataToHex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

func registerSecurityVectors() {
    FunctionRegistry.register(domain: "security", fn: "isEncryptedEnvelope") { input in
        let d = input as! [String: Any]
        return isEncryptedEnvelope(d["value"] as? String)
    }

    FunctionRegistry.register(domain: "security", fn: "formatSecurityEnvelope") { input in
        let d = input as! [String: Any]
        return formatSecurityEnvelope(ivBase64: d["ivBase64"] as! String, ctBase64: d["ctBase64"] as! String)
    }

    FunctionRegistry.register(domain: "security", fn: "parseSecurityEnvelope") { input in
        let d = input as! [String: Any]
        guard let parsed = parseSecurityEnvelope(d["envelope"] as? String) else { return NSNull() }
        return ["ivBase64": parsed.ivBase64, "ctBase64": parsed.ctBase64] as [String: Any]
    }

    FunctionRegistry.register(domain: "security", fn: "recoveryCodeFromBytes") { input in
        let d = input as! [String: Any]
        return recoveryCodeFromBytes(hexToData(d["bytesHex"] as! String))
    }

    FunctionRegistry.register(domain: "security", fn: "normalizeRecoveryCode") { input in
        let d = input as! [String: Any]
        return normalizeRecoveryCode(d["input"] as! String)
    }

    FunctionRegistry.register(domain: "security", fn: "securityStatus") { input in
        let d = input as! [String: Any]
        // JSON null arrives as NSNull, which is the "we have not looked yet"
        // state the status machine reads — not `false`.
        let hasKeys = (d["hasKeys"] as? NSNumber)?.boolValue
        let unlocked = (d["unlocked"] as? NSNumber)?.boolValue ?? false
        return securityStatus(hasKeys: hasKeys, unlocked: unlocked)
    }

    FunctionRegistry.register(domain: "security", fn: "passphraseSetupErrorKey") { input in
        let d = input as! [String: Any]
        let key = passphraseSetupErrorKey(
            passphrase: d["passphrase"] as! String,
            confirm: d["confirm"] as! String
        )
        // `.map { $0 as Any } ?? NSNull()`, not `key ?? NSNull()`: `??` needs
        // both sides to be the same type, and String is not NSNull.
        return key.map { $0 as Any } ?? NSNull()
    }

    FunctionRegistry.register(domain: "security", fn: "canonicalGrantJson") { input in
        let d = input as! [String: Any]
        return canonicalGrantJson(
            userId: d["userId"] as! String,
            grantId: d["grantId"] as! String,
            exp: (d["exp"] as! NSNumber).int64Value,
            scope: d["scope"] as! String
        )
    }

    FunctionRegistry.register(domain: "security", fn: "grantExpiryMillis") { input in
        let d = input as! [String: Any]
        return NSNumber(value: grantExpiryMillis(
            nowMs: (d["nowMs"] as! NSNumber).int64Value,
            ttlHours: (d["ttlHours"] as! NSNumber).intValue
        ))
    }

    // Registered SEPARATELY from deriveKekHex, which can only ever ask for 32
    // bytes — exactly SHA-256's own output length, so `blocks` is always 1 and
    // the INT(i) block counter for i > 1 and the output-offset arithmetic have
    // no coverage at all through that door. These cases ask for 20, 32, 64 and
    // 100 bytes, which is one partial block, one exact block, two blocks, and
    // four blocks truncated mid-block.
    FunctionRegistry.register(domain: "security", fn: "pbkdf2HmacSha256") { input in
        let d = input as! [String: Any]
        return dataToHex(pbkdf2HmacSha256(
            password: Data((d["passwordUtf8"] as! String).utf8),
            salt: try securityBase64Decode(d["saltBase64"] as! String),
            iterations: (d["iterations"] as! NSNumber).intValue,
            keyLengthBytes: (d["keyLengthBytes"] as! NSNumber).intValue
        ))
    }

    FunctionRegistry.register(domain: "security", fn: "deriveKekHex") { input in
        let d = input as! [String: Any]
        return dataToHex(deriveKek(
            passphrase: d["passphrase"] as! String,
            salt: try securityBase64Decode(d["saltBase64"] as! String),
            iterations: (d["iterations"] as! NSNumber).intValue
        ))
    }

    FunctionRegistry.register(domain: "security", fn: "decryptFieldWithDekHex") { input in
        let d = input as! [String: Any]
        return try decryptField(d["envelope"] as! String, dek: hexToData(d["dekHex"] as! String))
    }

    FunctionRegistry.register(domain: "security", fn: "unwrapDekHex") { input in
        let d = input as! [String: Any]
        return dataToHex(try unwrapDek(
            wrapped: d["wrapped"] as! String,
            kek: hexToData(d["kekHex"] as! String)
        ))
    }

    // The write path. A round trip cannot be pinned to a browser-produced
    // string (the IV is random by design), so what it pins is that this port's
    // OWN sealing is openable — and, together with decryptFieldWithDekHex
    // above, that both directions speak the same format.
    FunctionRegistry.register(domain: "security", fn: "fieldRoundTrip") { input in
        let d = input as! [String: Any]
        let dek = hexToData(d["dekHex"] as! String)
        return try decryptField(try encryptField(d["plaintext"] as! String, dek: dek), dek: dek)
    }

    FunctionRegistry.register(domain: "security", fn: "ecdsaDerToRawSignatureHex") { input in
        let d = input as! [String: Any]
        return dataToHex(try ecdsaDerToRawSignature(hexToData(d["derHex"] as! String)))
    }

    FunctionRegistry.register(domain: "security", fn: "rsaPublicKeyDerHexFromJwk") { input in
        let d = input as! [String: Any]
        return dataToHex(try rsaPublicKeyDer(
            modulusB64Url: d["n"] as! String,
            exponentB64Url: d["e"] as! String
        ))
    }

    FunctionRegistry.register(domain: "security", fn: "base64UrlToBase64") { input in
        let d = input as! [String: Any]
        return base64UrlToBase64(d["input"] as! String)
    }

    FunctionRegistry.register(domain: "security", fn: "base64ToBase64Url") { input in
        let d = input as! [String: Any]
        return base64ToBase64Url(d["input"] as! String)
    }
}
