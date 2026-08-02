import XCTest
@testable import Domain

/// Placeholder App-level test so `xcodebuild test -scheme Sanvya` has
/// something real to run on a simulator (P0.3 Done-when). The substantive
/// Domain vector tests run via `swift test` inside Domain/ (fast, no
/// simulator) — this just proves the App target + its Domain dependency
/// build and run end-to-end on a simulator.
final class AppTests: XCTestCase {
    func testDomainIsReachableFromApp() {
        XCTAssertTrue(DomainSkeleton.ready)
    }
}
