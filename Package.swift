// swift-tools-version:5.9
import PackageDescription

// PrepOS core, split into layered SPM library targets (see docs/architecture.md §2) so
// independent agents build on separate surfaces without colliding. Everything here compiles
// and tests under Command Line Tools / Xcode — the macOS app bundle (App/) consumes these
// products. Dependencies point downward only; PrepOSCore depends on nothing.
let package = Package(
    name: "PrepOS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PrepOSCore", targets: ["PrepOSCore"]),
        .library(name: "PrepOSReasoning", targets: ["PrepOSReasoning"]),
        .library(name: "PrepOSParsing", targets: ["PrepOSParsing"]),
        .library(name: "PrepOSBucketing", targets: ["PrepOSBucketing"]),
        .library(name: "PrepOSPersistence", targets: ["PrepOSPersistence"]),
        .library(name: "PrepOSIngestion", targets: ["PrepOSIngestion"]),
        .library(name: "PrepOSPipeline", targets: ["PrepOSPipeline"])
    ],
    dependencies: [
        // Persistence layer (Phase 1 P1-b): SQLite via GRDB. Encryption (AES-GCM) is layered
        // on top via CryptoKit + SecretStore; vector similarity is computed in Swift for MVP
        // (sqlite-vec is a later optimization — see docs/scaffold-plan.md §2).
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
    ],
    targets: [
        // Domain model, config, pure algorithms, shared protocols. No I/O, no dependencies.
        .target(
            name: "PrepOSCore",
            dependencies: []
        ),
        // ReasoningProvider abstraction, MCP config, read-only guard.
        .target(
            name: "PrepOSReasoning",
            dependencies: ["PrepOSCore"]
        ),
        // Document parsers: txt/md/vtt/srt/pdf/docx → normalized item text (PRD C1.5).
        .target(
            name: "PrepOSParsing",
            dependencies: ["PrepOSCore"]
        ),
        // Embedding service, similarity scoring over bucket prototypes, triage routing, and
        // the bucket relatedness graph (PRD §8, C2, C3).
        .target(
            name: "PrepOSBucketing",
            dependencies: ["PrepOSCore"]
        ),
        // GRDB store: records, migrations, AES-GCM encryption, repositories, backup (PRD §6, C8).
        .target(
            name: "PrepOSPersistence",
            dependencies: [
                "PrepOSCore",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),

        // Capture→file ingestion coordinator: parse → embed → decide → persist, with the
        // single-vs-bulk interrupt/triage routing (PRD C1.6, C2). Persistence is injected via
        // the IngestionStore protocol so the pipeline is testable without a database.
        .target(
            name: "PrepOSIngestion",
            dependencies: ["PrepOSCore", "PrepOSParsing", "PrepOSBucketing"]
        ),

        // Concrete wiring layer: a GRDB-backed IngestionStore + prototype builder that makes
        // the IngestionCoordinator run against the real database. The app depends on this.
        .target(
            name: "PrepOSPipeline",
            dependencies: ["PrepOSCore", "PrepOSBucketing", "PrepOSPersistence", "PrepOSIngestion"]
        ),

        .testTarget(name: "PrepOSCoreTests", dependencies: ["PrepOSCore"]),
        .testTarget(name: "PrepOSReasoningTests", dependencies: ["PrepOSReasoning"]),
        .testTarget(name: "PrepOSParsingTests", dependencies: ["PrepOSParsing"]),
        .testTarget(name: "PrepOSBucketingTests", dependencies: ["PrepOSBucketing"]),
        .testTarget(name: "PrepOSPersistenceTests", dependencies: ["PrepOSPersistence"]),
        .testTarget(name: "PrepOSIngestionTests", dependencies: ["PrepOSIngestion"]),
        .testTarget(name: "PrepOSPipelineTests", dependencies: ["PrepOSPipeline"])
    ]
)
