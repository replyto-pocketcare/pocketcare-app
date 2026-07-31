// swift-tools-version: 6.0
import PackageDescription

// Data package — bridges PowerSync + Supabase to the app's data layer.
// Unlike the Domain package (pure Swift, no external deps), this package
// depends on the approved irreducible third-party set from plan §0:
//   - PowerSync Swift SDK (1.15.1+)
//   - supabase-swift (2.54.0+)
//
// P2.2b: SupabaseConnector (PowerSync backend connector + quarantine)
// P2.4b: Auth helpers (guest sign-in, in-place upgrade, offline marker)
let package = Package(
    name: "Data",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Data", targets: ["Data"])
    ],
    dependencies: [
        // Domain is a local path dependency — provides already-ported sync-policy
        // and diagnostics domain logic (in :domain for Android, Domain/ for iOS).
        .package(path: "../Domain"),
        // PowerSync Swift SDK — approved irreducible dependency (plan §0).
        // Pure Swift as of 1.14.0 (no KMP XCFramework).
        .package(
            url: "https://github.com/powersync-ja/powersync-swift",
            from: "1.15.1"
        ),
        // Supabase Swift SDK — approved irreducible dependency (plan §0).
        .package(
            url: "https://github.com/supabase/supabase-swift.git",
            from: "2.54.0"
        ),
    ],
    targets: [
        .target(
            name: "Data",
            dependencies: [
                .product(name: "Domain", package: "Domain"),
                .product(name: "PowerSync", package: "powersync-swift"),
                // Use umbrella Supabase product — includes Auth + PostgREST.
                .product(name: "Supabase", package: "supabase-swift"),
            ]
        ),
        .testTarget(
            name: "DataTests",
            dependencies: ["Data"]
        ),
    ]
)
