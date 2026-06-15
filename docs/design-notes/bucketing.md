# Design note — PrepOSBucketing (piece "bucketing", PRD §8, C2, C3)

Status: **design only** (this note). Implementation lands next, TDD-first (XCTest).

Target: `PrepOSBucketing` (source `Sources/PrepOSBucketing/`, tests
`Tests/PrepOSBucketingTests/`). Depends on `PrepOSCore` **only** — that is the sole
dependency declared for this target in `Package.swift`, which this piece must not edit.
No new package dependencies, no network, no secrets.

> Note on the architecture doc: architecture.md §2 lists `PrepOSBucketing → Core,
> Persistence`. That dependency is **not yet wired** in `Package.swift` (the target
> depends on `PrepOSCore` alone) and editing `Package.swift` is forbidden for this piece.
> Everything below is expressible over `PrepOSCore` types plus pure Swift, so this piece
> ships against Core only; persistence wiring (sqlite-vec, prototype storage) is a later
> piece. The `EmbeddingService` protocol is defined here and the real
> `NLContextualEmbedding` impl is `#if canImport(NaturalLanguage)`-guarded so tests never
> depend on model availability (mirrors the PDF/DOCX guard pattern in PrepOSParsing).

## 1. Scope

This piece is the **embedding → scoring → graph** core of the bucketing engine (PRD §8
steps 2–3, 6; C2.6; C3.2). It deliberately stops short of the ingestion coordinator and
the LLM cold-start/entity-resolution boost, which live elsewhere:

In scope:
- `EmbeddingService` protocol + a **deterministic test fake** + an
  `NLContextualEmbedding`-backed real impl (guarded).
- Pure **cosine similarity** over `[Double]`.
- `BucketPrototype` (centroid + labeled exemplar vectors) with
  `score(_:) = max cosine over centroid + exemplars` (PRD §8 step 3).
- `PrototypeIndex` mapping `bucketId → BucketPrototype`, producing `[ScoredBucket]`
  (the `PrepOSCore` type) and then calling `FilingDecider.decide(candidates:config:)`
  (the **real** decider from `PrepOSCore`) to yield a `FilingDecision`.
- **Prototype learning** (PRD C2.6): a pure function that appends an exemplar and
  recomputes the centroid on correction.
- `BucketGraph` over `[BucketLink]` with `neighbors(of:depth:weightFloor:)` — weight-pruned
  BFS traversal up to a depth (PRD C3.2).

Explicitly **out of scope** for this piece (later pieces / other targets):
- Single-vs-bulk routing of `.ambiguous`/`.proposeNewBucket` (ingestion coordinator,
  PRD C2.3/C2.4) — this piece only produces the `FilingDecision`.
- The entity-resolution **boost** via Altify find tools (PRD §8 step 4, C2.1) — that lives
  in `PrepOSReasoning`; here the caller may pre-adjust scores, but this piece issues **no**
  network/MCP calls.
- LLM zero-shot **cold-start** type/name suggestion (PRD §8 cold start) — `PrepOSReasoning`.
- Re-clustering merge/split maintenance (PRD C2.7).
- Persisting prototypes / embeddings (sqlite-vec) — `PrepOSPersistence`.

### Constitution posture (inviolable)
On-device only. The embedding fake and the `NLContextualEmbedding` impl run locally; **no
network, no secrets, no Salesforce/Altify write paths**. No key material is handled, so the
`SecretStore` protocol is not needed here. Nothing is logged. A Constitution boundary test
(below) asserts the module's API surface exposes no network/secret/write affordance.

## 2. Public Swift API

All in the `PrepOSBucketing` module. Value types are `Sendable`/`Codable`/`Equatable`;
the async service protocol is `Sendable`. Vectors are `[Double]`. The placeholder
`enum PrepOSBucketing {}` namespace file and `PlaceholderTests.swift` are deleted and
replaced with the code below. Doc-comments match the PrepOSCore style.

### 2.1 Embedding

```swift
/// Turns normalized item text into a fixed-dimension on-device embedding (PRD §8 step 2).
/// Implementations are `Sendable` and run **locally** — no network, no secrets. The real
/// impl wraps Apple's `NLContextualEmbedding`; tests inject `DeterministicEmbeddingService`
/// so they never depend on model availability or Xcode-only frameworks.
public protocol EmbeddingService: Sendable {
    /// The dimensionality of vectors this service returns. Vectors compared with each other
    /// (scoring, centroids) must share a dimension.
    var dimension: Int { get }

    /// Embed `text` into a `dimension`-length vector.
    /// - Throws: `EmbeddingError` if the on-device model is unavailable or the text is empty.
    func embed(_ text: String) async throws -> [Double]
}

/// Failures from the embedding layer.
public enum EmbeddingError: Error, Sendable, Equatable {
    /// The on-device contextual-embedding model could not be loaded for the requested
    /// language/script (e.g. asset not present). Real impl only; the fake never throws this.
    case modelUnavailable
    /// `text` was empty or whitespace-only — nothing to embed.
    case emptyText
}
```

#### Deterministic fake (tests + previews)
```swift
/// A reproducible, dependency-free `EmbeddingService` for tests: the **same text always
/// maps to the same vector**, and different text generally maps to different vectors, so
/// scoring/learning/decision behavior is exercised without any model. Pure hashing — no
/// randomness, no I/O, no network. NOT for production classification quality.
public struct DeterministicEmbeddingService: EmbeddingService {
    public let dimension: Int
    /// - Parameter dimension: vector length (default 64).
    public init(dimension: Int = 64)
    public func embed(_ text: String) async throws -> [Double]   // throws .emptyText on blank
}
```
Algorithm (deterministic, documented in source): lowercase + tokenize on non-alphanumerics;
for each token, fold a stable FNV-1a hash of the token into a bucket index `0..<dimension`,
accumulating a per-token signed weight; then **L2-normalize** the vector. Stable across
runs/platforms (no `Hashable` seed, no `Set` ordering). Same string → identical vector;
shared tokens → higher cosine. Empty/whitespace text throws `.emptyText`.

#### Real impl (guarded, on-device)
```swift
#if canImport(NaturalLanguage)
import NaturalLanguage

/// On-device embedding via Apple's `NLContextualEmbedding` (PRD §5 Embeddings, §8 step 2).
/// Compiled only where `NaturalLanguage` is available; behind the `EmbeddingService`
/// protocol so package logic and tests never depend on it. No network, no secrets.
public struct ContextualEmbeddingService: EmbeddingService { … }
#endif
```
The real impl loads an `NLContextualEmbedding` for a configured `NLLanguage`/script, calls
`embeddingResult(for:language:)`, mean-pools token vectors to a single fixed-length vector,
L2-normalizes, and maps `Float`→`Double`. Throws `.modelUnavailable` if the asset is absent.
It is `#if`-guarded so `swift test` on Command Line Tools never links it.

### 2.2 Cosine similarity (pure)

```swift
/// Cosine similarity between two equal-length vectors, in `[-1, 1]`. Pure, allocation-light,
/// exhaustively unit-tested. Returns `0` if either vector is all-zero (degenerate), and the
/// vectors **must** share a length (precondition) — callers guarantee this via `dimension`.
public func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double
```
Defined as a free function in the module (mirrors `JaroWinkler` living as a pure unit in
Core). `dot / (‖a‖·‖b‖)`; zero-magnitude guard avoids NaN.

### 2.3 Bucket prototype

```swift
/// The derived similarity model for one bucket (PRD §8 step 3; design.md §1): a `centroid`
/// vector plus labeled `exemplar` vectors. Not a persisted table row — recomputed as items
/// are filed/corrected (PRD C2.6). `Sendable`/`Codable` so it can be cached/persisted later.
public struct BucketPrototype: Sendable, Codable, Equatable {
    /// The average of all filed exemplar vectors (L2-normalized).
    public public(set) var centroid: [Double]
    /// Labeled exemplars — one per filed/corrected item embedding. The label is the item id
    /// (or any caller key) for provenance; it does not affect scoring.
    public private(set) var exemplars: [LabeledVector]
    public var dimension: Int { centroid.count }

    /// Build a prototype from at least one exemplar; the centroid is computed from them.
    /// - Precondition: `exemplars` is non-empty and all vectors share a length.
    public init(exemplars: [LabeledVector])

    /// Max cosine of `vector` against the centroid **and** every exemplar (PRD §8 step 3).
    /// Taking the max (not just centroid) keeps multi-modal buckets matchable.
    public func score(_ vector: [Double]) -> Double
}

/// A vector tagged with a stable label (the source item id) for provenance.
public struct LabeledVector: Sendable, Codable, Equatable {
    public var label: UUID
    public var vector: [Double]
    public init(label: UUID, vector: [Double])
}
```

### 2.4 Prototype learning (pure — PRD C2.6)

```swift
public extension BucketPrototype {
    /// Return a new prototype with `exemplar` appended and the centroid recomputed as the
    /// L2-normalized mean of all exemplars (PRD §8 step 6, C2.6). Pure — value-in/value-out,
    /// no mutation of `self`, so it is trivially unit-testable.
    /// - Precondition: `exemplar.vector.count == dimension`.
    func learning(_ exemplar: LabeledVector) -> BucketPrototype
}
```
Centroid = normalized mean of all exemplar vectors. Adding an exemplar **shifts** the
centroid toward it (the learning test asserts the shift direction and magnitude bound).

### 2.5 Prototype index → decision

```swift
/// Holds the live `bucketId → BucketPrototype` map and turns an item vector into ranked
/// `ScoredBucket`s (from `PrepOSCore`), then into a `FilingDecision` via the **real**
/// `FilingDecider` (PrepOSCore). This piece adds no decision logic of its own — the
/// double-threshold + margin rule stays single-sourced in `PrepOSCore.FilingDecider`.
public struct PrototypeIndex: Sendable {
    public private(set) var prototypes: [UUID: BucketPrototype]
    public init(prototypes: [UUID: BucketPrototype] = [:])

    /// Upsert a bucket's prototype (e.g. after `learning`).
    public mutating func setPrototype(_ prototype: BucketPrototype, for bucketId: UUID)

    /// Score `vector` against every prototype → `[ScoredBucket]`, sorted descending.
    /// Empty when there are no prototypes (cold start → decider yields `.proposeNewBucket`).
    public func scored(for vector: [Double]) -> [ScoredBucket]

    /// Full path: score `vector`, then route via `FilingDecider.decide(candidates:config:)`.
    /// An optional `boosts: [UUID: Double]` lets a caller fold in a pre-computed entity-
    /// resolution boost (PRD §8 step 4) **without** this piece making any network/MCP call —
    /// the boost is supplied by the caller; values are added then clamped to `[-1, 1]`.
    public func decide(
        for vector: [Double],
        config: AppConfig,
        boosts: [UUID: Double] = [:]
    ) -> FilingDecision
}
```
`decide` is the integration point with the real `FilingDecider`: it never re-implements
thresholds. `boosts` defaults to empty (no boost), keeping the no-network guarantee while
leaving a seam for the later entity-resolution piece.

### 2.6 Bucket graph (PRD C3.2)

```swift
/// An adjacency view over `[BucketLink]` (PRD §6.3) for weight-pruned, depth-bounded
/// traversal during prep composition (PRD C3.2). Built once from links, then queried. Pure
/// in-memory graph — no I/O. Links are treated as **undirected** (each edge connects both
/// endpoints), matching the "undirected semantically" note on `BucketLink`.
public struct BucketGraph: Sendable {
    public init(links: [BucketLink])

    /// Buckets reachable from `bucket` within `depth` hops, traversing only edges whose
    /// `weight >= weightFloor`. BFS; each neighbor returned once at its **shortest** hop
    /// distance; the origin is excluded. `depth <= 0` or `weightFloor > 1` → empty.
    /// - Parameters:
    ///   - depth: max hops (PRD default `AppConfig.linkTraversalDepth` = 1).
    ///   - weightFloor: minimum edge weight to traverse (prunes weak links).
    public func neighbors(
        of bucket: UUID,
        depth: Int,
        weightFloor: Double
    ) -> [Neighbor]
}

/// A reachable bucket plus the hop distance at which it was first reached (1 = direct).
public struct Neighbor: Sendable, Equatable {
    public var bucketId: UUID
    public var hops: Int
}
```
Traversal: standard BFS over the undirected adjacency, skipping edges below `weightFloor`,
stopping past `depth`, recording each bucket at its first (shortest) hop, excluding the
origin and already-visited nodes. Deterministic ordering (by hop then by a stable key) so
results are unit-testable.

## 3. Dependencies

- **`PrepOSCore`** (declared): `ScoredBucket`, `FilingDecision`, `FilingDecider`,
  `AppConfig`, `BucketLink`. No other package depends on this piece yet.
- **`NaturalLanguage`** (system framework, `#if canImport`-guarded): real embedding impl
  only; never linked by tests.
- **`Foundation`**: `UUID`, `Data`-free math only.
- **No** GRDB, no Persistence, no Reasoning, no network client, no `SecretStore`.

## 4. Test list (`Tests/PrepOSBucketingTests/`, XCTest)

Tests inject `DeterministicEmbeddingService` and hand-built `[Double]` vectors only — no
model, no network, no Xcode-only frameworks. Replaces `PlaceholderTests.swift`.

**EmbeddingService / deterministic fake**
- *happy* — same input text yields an **identical** vector across two `embed` calls
  (reproducibility); vector length == `dimension`; result is L2-normalized (‖v‖ ≈ 1).
- *happy* — two texts sharing many tokens score higher cosine than two unrelated texts.
- *edge* — empty / whitespace-only text throws `EmbeddingError.emptyText`.
- *boundary* — custom `dimension` (e.g. 8 and 256) honored; identical text in different
  dimensions both reproducible.

**cosineSimilarity (pure)**
- *happy* — identical vectors → 1.0; antiparallel → -1.0; orthogonal → 0.0 (within ε).
- *edge* — all-zero vector vs anything → 0 (no NaN).
- *boundary* — scale invariance: `cos(a, k·a) == 1` for `k > 0`.

**BucketPrototype.score**
- *happy* — score == max cosine over centroid + exemplars; a vector equal to one exemplar
  scores 1.0 even when far from the centroid (proves "max over exemplars", not centroid-only).
- *edge* — single-exemplar prototype: centroid == that exemplar; scoring matches cosine.
- *boundary* — vector orthogonal to centroid and all exemplars scores ≈ 0.

**Prototype learning (C2.6)**
- *happy* — `learning(_:)` appends the exemplar and **shifts the centroid toward** the new
  vector: cosine(newCentroid, exemplar) > cosine(oldCentroid, exemplar).
- *happy* — purity: original prototype is unchanged (value semantics); new one has +1 exemplar.
- *boundary* — adding an exemplar **equal** to the existing centroid leaves the centroid
  (cosine-)unchanged.

**PrototypeIndex → FilingDecider integration (uses the REAL decider)**
- *happy/autoFile* — a vector ≥ `T_high` cosine to one bucket and clearly ahead of the rest
  → `FilingDecision.autoFile(bucketId:score:)` for that bucket.
- *ambiguous (low band)* — top score in `[T_low, T_high)` → `.ambiguous` with ranked
  candidates (descending).
- *ambiguous (margin)* — two buckets within `T_margin` even above `T_high` → `.ambiguous`
  (proves the margin rule flows through, not re-implemented here).
- *proposeNewBucket* — best score `< T_low` → `.proposeNewBucket(topScore:)`.
- *edge (cold start)* — empty `PrototypeIndex` → `scored` is `[]` → decider returns
  `.proposeNewBucket(topScore: 0)`.
- *boundary (boost seam)* — a `boosts[bucketId]` entry raises exactly that candidate's score
  and can flip an otherwise-ambiguous result to `.autoFile`; boosted score is clamped to ≤ 1;
  with empty `boosts` the result is identical to the unboosted path (no network involved).

**BucketGraph traversal (C3.2)**
- *happy* — depth 1, `weightFloor` below all weights → direct neighbors only, each `hops == 1`.
- *happy* — depth 2 → second-hop buckets included with `hops == 2`; origin excluded.
- *edge (weight pruning)* — an edge below `weightFloor` is **not** traversed, so a bucket
  only reachable through it is absent from results.
- *edge (shortest hop)* — a bucket reachable at both 1 and 2 hops is reported once with
  `hops == 1`.
- *boundary* — `depth == 0` → empty; `weightFloor > max weight` → empty; unknown origin id
  → empty; a cycle terminates (no infinite loop) and visits each node once.

**Constitution boundary test (inviolable)**
- *no-network / no-secret / on-device* — exercise the full embed → score → decide → graph
  path end-to-end with `DeterministicEmbeddingService` and assert it completes **without any
  network or secret dependency**: the test target links no URL/Keychain symbol, the module
  imports no networking framework, and `decide(..., boosts:)` with empty boosts performs no
  I/O. Asserts the API exposes **no** write/upsert/create path and no `SecretStore` use —
  i.e. this piece is structurally read-only and on-device (CLAUDE.md §1, security
  constitution §3–4). (Realized as a compile-/link-level assertion plus a runtime smoke test
  that the deterministic path is fully synchronous-local.)

## 5. Build & test commands

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PrepOSBucketingTests
```
The whole package must still compile. If build or the filtered tests cannot be made green,
the target's `Sources/PrepOSBucketing/` and `Tests/PrepOSBucketingTests/` revert to the
original single placeholder file (`enum PrepOSBucketing {}` + `PlaceholderTests`) so the
tree stays buildable for the next piece.
