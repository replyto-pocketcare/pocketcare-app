import XCTest
@testable import Data

// DataTests — placeholder for P2.2b/P2.4b unit tests.
//
// The real gate for P2.2b/P2.4b is TP L3 (sync integration against a local
// Supabase + PowerSync project). Unit tests here will cover the pure logic
// (opKey, bumpAttempts/clearAttempts against an in-memory DB, AuthState
// derivation) once the L3 harness is set up.
//
// For now: ensures the package compiles and the test target is present.

final class DataTests: XCTestCase {
    func testOpKeyFormat() {
        let key = opKey(table: "transactions", op: "PUT", rowId: "abc-123")
        XCTAssertEqual(key, "transactions|PUT|abc-123")
    }

    func testAuthStateEnum() {
        // AuthState is Codable — verify round-trip.
        let state = AuthState.signedInOffline
        let encoded = try! JSONEncoder().encode(state)
        let decoded = try! JSONDecoder().decode(AuthState.self, from: encoded)
        XCTAssertEqual(decoded, state)
    }

    func testEncodePayloadNil() {
        XCTAssertEqual(encodePayload(nil), "{}")
    }

    func testEncodePayloadBasic() {
        let json = encodePayload(["amount": 1000, "note": "test"])
        // Must be valid JSON.
        let data = json.data(using: .utf8)!
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["amount"] as? Int, 1000)
        XCTAssertEqual(obj["note"] as? String, "test")
    }
}
