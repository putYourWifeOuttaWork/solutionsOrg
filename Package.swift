// swift-tools-version:5.9
import PackageDescription

// PrepOS core, split into layered SPM library targets (see docs/architecture.md §2) so
// independent agents build on separate surfaces without colliding. Everything here compiles
// and tests under Command Line Tools — no Xcode required. The macOS app bundle (App/) is a
// separate Xcode target on top, added once Xcode is installed.
//
// Targets are added as their pieces land. Dependencies point downward only; PrepOSCore
// depends on nothing.
let package = Package(
    name: "PrepOS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PrepOSCore", targets: ["PrepOSCore"]),
        .library(name: "PrepOSReasoning", targets: ["PrepOSReasoning"])
    ],
    dependencies: [],
    targets: [
        // Domain model, config, pure algorithms. No I/O, no dependencies.
        .target(
            name: "PrepOSCore",
            dependencies: []
        ),
        // ReasoningProvider abstraction, MCP config, read-only guard.
        .target(
            name: "PrepOSReasoning",
            dependencies: ["PrepOSCore"]
        ),

        .testTarget(
            name: "PrepOSCoreTests",
            dependencies: ["PrepOSCore"]
        ),
        .testTarget(
            name: "PrepOSReasoningTests",
            dependencies: ["PrepOSReasoning"]
        )
    ]
)
