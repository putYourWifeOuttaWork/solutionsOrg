import Foundation

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

/// A reproducible, dependency-free `EmbeddingService` for tests and previews: the **same
/// text always maps to the same vector**, and different text generally maps to different
/// vectors, so scoring/learning/decision behaviour is exercised without any model. Pure
/// hashing — no randomness, no I/O, no network. NOT for production classification quality.
///
/// Algorithm: lowercase and tokenize on non-alphanumerics; for each token, fold a stable
/// FNV-1a hash into a bucket index `0..<dimension`, accumulating a signed per-token weight;
/// then L2-normalize. Stable across runs and platforms — no `Hashable` seed, no `Set`
/// ordering. Same string → identical vector; shared tokens → higher cosine.
public struct DeterministicEmbeddingService: EmbeddingService {
    public let dimension: Int

    /// - Parameter dimension: vector length (default 64).
    public init(dimension: Int = 64) {
        precondition(dimension > 0, "dimension must be positive")
        self.dimension = dimension
    }

    public func embed(_ text: String) async throws -> [Double] {
        let tokens = Self.tokenize(text)
        guard !tokens.isEmpty else { throw EmbeddingError.emptyText }

        var vector = [Double](repeating: 0, count: dimension)
        for token in tokens {
            let hash = Self.fnv1a(token)
            let index = Int(hash % UInt64(dimension))
            // A second, independent fold derives a stable sign so distinct tokens don't all
            // push the same direction.
            let sign: Double = (hash & 1) == 0 ? 1 : -1
            vector[index] += sign
        }
        return l2Normalized(vector)
    }

    /// Lowercase and split on any non-alphanumeric character, dropping empties.
    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// Stable 64-bit FNV-1a hash of a token's UTF-8 bytes — deterministic across runs and
    /// platforms (unlike Swift's seeded `Hasher`).
    private static func fnv1a(_ token: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in token.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

#if canImport(NaturalLanguage)
import NaturalLanguage

/// On-device embedding via Apple's `NLContextualEmbedding` (PRD §5 Embeddings, §8 step 2).
/// Compiled only where `NaturalLanguage` is available, and kept behind the `EmbeddingService`
/// protocol so package logic and tests never depend on it. No network, no secrets.
///
/// Loads the contextual-embedding model for a configured language, mean-pools the per-token
/// vectors into one fixed-length vector, L2-normalizes, and maps `Double`. Throws
/// `.modelUnavailable` if the on-device asset is absent, and `.emptyText` for blank input.
@available(macOS 14.0, *)
public struct ContextualEmbeddingService: EmbeddingService {
    // Only value types are stored, so the struct is genuinely `Sendable`; the non-`Sendable`
    // `NLContextualEmbedding` is created and loaded per call inside `embed`.
    private let language: NLLanguage
    public let dimension: Int

    /// - Parameter language: the script/language whose model to load (default English).
    /// - Throws: `EmbeddingError.modelUnavailable` if no model exists for `language`.
    public init(language: NLLanguage = .english) throws {
        guard let embedding = NLContextualEmbedding(language: language) else {
            throw EmbeddingError.modelUnavailable
        }
        self.language = language
        self.dimension = embedding.dimension
    }

    public func embed(_ text: String) async throws -> [Double] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EmbeddingError.emptyText
        }
        guard let embedding = NLContextualEmbedding(language: language) else {
            throw EmbeddingError.modelUnavailable
        }
        if !embedding.hasAvailableAssets {
            // Best-effort asset request; if it can't load, surface as unavailable.
            do {
                try await embedding.requestAssets()
            } catch {
                throw EmbeddingError.modelUnavailable
            }
        }
        do {
            try embedding.load()
        } catch {
            throw EmbeddingError.modelUnavailable
        }
        let result = try embedding.embeddingResult(for: text, language: language)

        // Mean-pool the per-token vectors into one fixed-length vector.
        var pooled = [Double](repeating: 0, count: embedding.dimension)
        var count = 0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { tokenVector, _ in
            for (i, value) in tokenVector.enumerated() where i < pooled.count {
                pooled[i] += Double(value)
            }
            count += 1
            return true
        }
        guard count > 0 else { throw EmbeddingError.emptyText }
        for i in pooled.indices { pooled[i] /= Double(count) }
        return l2Normalized(pooled)
    }
}
#endif
