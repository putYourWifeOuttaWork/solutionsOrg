// swift-tools-version:5.9
import PackageDescription

// PrepOSKit — the core logic of PrepOS, built as a Swift Package so it compiles and
// tests under Command Line Tools alone (no Xcode required). The macOS app bundle
// (SwiftUI shell, share extension, entitlements) lives in App/ and consumes this package.
//
// Dependencies are added per-phase as the PRD requires them (GRDB + sqlite-vec in
// Phase 1). Phase 0 is intentionally dependency-free so the skeleton builds offline.
let package = Package(
    name: "PrepOSKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PrepOSKit", targets: ["PrepOSKit"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PrepOSKit",
            dependencies: []
        ),
        .testTarget(
            name: "PrepOSKitTests",
            dependencies: ["PrepOSKit"]
        )
    ]
)
