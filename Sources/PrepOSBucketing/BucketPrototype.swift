import Foundation

/// A vector tagged with a stable label (the source item id) for provenance. The label does
/// not affect scoring — it lets callers trace which filed item contributed an exemplar.
public struct LabeledVector: Sendable, Codable, Equatable {
    public var label: UUID
    public var vector: [Double]
    public init(label: UUID, vector: [Double]) {
        self.label = label
        self.vector = vector
    }
}

/// The derived similarity model for one bucket (PRD §8 step 3; design.md §1): a `centroid`
/// vector plus labeled `exemplar` vectors. Not a persisted table row — recomputed as items
/// are filed or corrected (PRD C2.6). `Sendable`/`Codable` so it can be cached or persisted
/// by a later piece.
public struct BucketPrototype: Sendable, Codable, Equatable {
    /// The L2-normalized mean of all filed exemplar vectors.
    public private(set) var centroid: [Double]
    /// Labeled exemplars — one per filed/corrected item embedding.
    public private(set) var exemplars: [LabeledVector]

    /// The vector dimension (the centroid's length).
    public var dimension: Int { centroid.count }

    /// Build a prototype from at least one exemplar; the centroid is computed from them.
    /// - Precondition: `exemplars` is non-empty and all vectors share a length.
    public init(exemplars: [LabeledVector]) {
        precondition(!exemplars.isEmpty, "a prototype needs at least one exemplar")
        let dimension = exemplars[0].vector.count
        precondition(
            exemplars.allSatisfy { $0.vector.count == dimension },
            "all exemplar vectors must share a length"
        )
        self.exemplars = exemplars
        self.centroid = BucketPrototype.centroid(of: exemplars)
    }

    /// Max cosine of `vector` against the centroid **and** every exemplar (PRD §8 step 3).
    /// Taking the max (not just the centroid) keeps multi-modal buckets matchable: an item
    /// near any one exemplar scores high even when the averaged centroid sits elsewhere.
    public func score(_ vector: [Double]) -> Double {
        var best = cosineSimilarity(centroid, vector)
        for exemplar in exemplars {
            best = max(best, cosineSimilarity(exemplar.vector, vector))
        }
        return best
    }

    /// Return a new prototype with `exemplar` appended and the centroid recomputed as the
    /// L2-normalized mean of all exemplars (PRD §8 step 6, C2.6). Pure — value-in/value-out,
    /// `self` is never mutated.
    /// - Precondition: `exemplar.vector.count == dimension`.
    public func learning(_ exemplar: LabeledVector) -> BucketPrototype {
        precondition(exemplar.vector.count == dimension, "exemplar dimension must match")
        return BucketPrototype(exemplars: exemplars + [exemplar])
    }

    /// L2-normalized mean of the exemplar vectors.
    private static func centroid(of exemplars: [LabeledVector]) -> [Double] {
        let dimension = exemplars[0].vector.count
        var sum = [Double](repeating: 0, count: dimension)
        for exemplar in exemplars {
            for i in 0..<dimension { sum[i] += exemplar.vector[i] }
        }
        let count = Double(exemplars.count)
        return l2Normalized(sum.map { $0 / count })
    }
}
