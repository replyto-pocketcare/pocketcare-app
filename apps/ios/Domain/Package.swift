// swift-tools-version: 6.0
import PackageDescription

// Pure Swift package — no UIKit/SwiftUI/Foundation-beyond-basics import
// beyond what's unavoidable, no platform target other than "runs on Apple
// platforms". This is what makes it fast to test (plain `swift test`, no
// simulator) and honest (see docs/plans/native-mobile-apps.md §4 P0.3, §0
// golden rule 8 "web is the spec").
let package = Package(
    name: "Domain",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "Domain", targets: ["Domain"])
    ],
    targets: [
        .target(name: "Domain"),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
    ]
)
