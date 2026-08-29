import Foundation
import Security

/**
 Where an unlocked DEK lives between launches.

 WHY THIS EXISTS AT ALL, GIVEN WEB HAS NO EQUIVALENT. In a browser the DEK is a
 module-level variable and a page reload re-locks the session — that is
 `apps/web/src/crypto/session.ts`'s whole storage story. A phone cannot copy
 that: iOS terminates a backgrounded app whenever it likes, invisibly, so a
 memory-only DEK would silently re-lock the app several times a day and demand
 a 20-character passphrase each time. Nobody would keep encryption on.

 So the unlock persists, and it persists in the Keychain — not `UserDefaults`,
 which is a plist any file-level backup reads. `ThisDeviceOnly` so it never
 travels in an iCloud Keychain sync or an encrypted backup restored onto a
 different phone: the DEK is this device's copy of a key the server must never
 see, and a key that syncs itself around defeats the point.
 `AfterFirstUnlock` rather than `WhenUnlocked` because a background sync may
 need to write an encrypted note while the screen is off.

 WHAT THIS DOES AND DOES NOT PROTECT. It protects against the threat the
 encryption feature is about: the server, and anyone with the database. It does
 not protect against somebody holding your unlocked phone — but neither does
 anything else here, because the ledger's amounts, accounts and dates are
 plaintext in the local SQLite by design (see SECURITY_ENCRYPTION_PLAN.md —
 that is the "Hybrid" in Hybrid zero-trust). Explicit Lock and sign-out both
 erase these items.

 Mirrors Android's SecureKeyStore, which does the same job with a Keystore-held
 AES key wrapping a private SharedPreferences entry.
 */
public final class SecureKeyStore: @unchecked Sendable {

    private let service: String

    public init(service: String = "com.sanvya.app.security") {
        self.service = service
    }

    /// Store `value` under `name`, replacing anything already there.
    public func put(_ name: String, _ value: Data) {
        // Delete first rather than SecItemUpdate: an add over an existing item
        // returns errSecDuplicateItem, and the two-call dance is both shorter
        // and idempotent.
        remove(name)
        var query = baseQuery(name)
        query[kSecValueData as String] = value
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Read `name` back, or nil if it is not there.
    public func get(_ name: String) -> Data? {
        var query = baseQuery(name)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    /// Erase one item. Used by Lock and by sign-out.
    public func remove(_ name: String) {
        SecItemDelete(baseQuery(name) as CFDictionary)
    }

    private func baseQuery(_ name: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
        ]
    }
}
