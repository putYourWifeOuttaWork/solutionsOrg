import Foundation

/// Cosine similarity between two equal-length vectors, in `[-1, 1]`. Pure, allocation-light,
/// and exhaustively unit-tested. Returns `0` if either vector is all-zero (degenerate) to
/// avoid `NaN`. The vectors **must** share a length (precondition); callers guarantee this
/// via `EmbeddingService.dimension`.
///
/// Defined as a free function (mirrors `JaroWinkler` living as a pure unit in `PrepOSCore`).
public func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
    precondition(a.count == b.count, "cosineSimilarity requires equal-length vectors")
    var dot = 0.0, normA = 0.0, normB = 0.0
    for i in a.indices {
        dot += a[i] * b[i]
        normA += a[i] * a[i]
        normB += b[i] * b[i]
    }
    let denom = (normA * normB).squareRoot()
    guard denom > 0 else { return 0 }   // zero-magnitude guard avoids NaN
    return dot / denom
}

/// L2-normalize `vector` (scale to unit length). Returns the input unchanged when it is the
/// zero vector (no direction to normalize). Internal helper shared by the embedding fake,
/// prototype centroid computation, and learning.
func l2Normalized(_ vector: [Double]) -> [Double] {
    let magnitude = (vector.reduce(0) { $0 + $1 * $1 }).squareRoot()
    guard magnitude > 0 else { return vector }
    return vector.map { $0 / magnitude }
}
