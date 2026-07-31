import XCTest
@testable import Domain

/// Proves `swift test` runs XCTest against the Domain package (P0.3
/// Done-when). The real golden-vector runner is P0.4b — this stays a
/// placeholder until that task wires up JSON vector loading.
final class PlaceholderTests: XCTestCase {
    func testDomainPackageIsWired() {
        XCTAssertTrue(DomainSkeleton.ready)
    }
}
