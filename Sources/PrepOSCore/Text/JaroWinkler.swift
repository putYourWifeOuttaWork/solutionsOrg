import Foundation

/// Jaro-Winkler string similarity, used for fuzzy matching event titles / attendee names to
/// Account/Opportunity names during entity resolution (PRD §9 step 3). Pure and
/// deterministic — exhaustively unit-tested. Returns a value in `0...1` (1 = identical).
public enum JaroWinkler {

    /// Jaro-Winkler similarity between two strings.
    /// - Parameter prefixScale: weight for a common prefix (Winkler's `p`, default 0.1,
    ///   capped so the result stays within `0...1`). Common prefix is capped at 4 chars.
    public static func similarity(_ a: String, _ b: String, prefixScale: Double = 0.1) -> Double {
        let s1 = Array(a), s2 = Array(b)   // convert once; share with the Jaro worker
        let jaro = jaroSimilarity(s1, s2)
        guard jaro > 0 else { return 0 }

        var prefix = 0
        for i in 0..<min(4, min(s1.count, s2.count)) {
            if s1[i] == s2[i] { prefix += 1 } else { break }
        }
        let scale = prefix == 0 ? 0 : min(prefixScale, 1.0 / Double(prefix))
        return jaro + Double(prefix) * scale * (1 - jaro)
    }

    /// The underlying Jaro similarity in `0...1`.
    public static func jaroSimilarity(_ a: String, _ b: String) -> Double {
        jaroSimilarity(Array(a), Array(b))
    }

    /// Jaro similarity over pre-converted character arrays — the shared worker so callers
    /// that already hold `[Character]` don't reconvert.
    private static func jaroSimilarity(_ s1: [Character], _ s2: [Character]) -> Double {
        if s1.isEmpty && s2.isEmpty { return 1 }
        if s1.isEmpty || s2.isEmpty { return 0 }
        if s1 == s2 { return 1 }

        // Characters match if equal and within this window of each other.
        let matchWindow = max(s1.count, s2.count) / 2 - 1
        guard matchWindow >= 0 else { return 0 }

        var s1Matched = [Bool](repeating: false, count: s1.count)
        var s2Matched = [Bool](repeating: false, count: s2.count)
        var matches = 0

        for i in 0..<s1.count {
            let lo = max(0, i - matchWindow)
            let hi = min(i + matchWindow + 1, s2.count)
            guard lo < hi else { continue }
            for j in lo..<hi where !s2Matched[j] && s1[i] == s2[j] {
                s1Matched[i] = true
                s2Matched[j] = true
                matches += 1
                break
            }
        }

        guard matches > 0 else { return 0 }

        // Count transpositions among the matched characters.
        var transpositions = 0
        var k = 0
        for i in 0..<s1.count where s1Matched[i] {
            while !s2Matched[k] { k += 1 }
            if s1[i] != s2[k] { transpositions += 1 }
            k += 1
        }
        let t = Double(transpositions) / 2.0
        let m = Double(matches)
        return (m / Double(s1.count) + m / Double(s2.count) + (m - t) / m) / 3.0
    }
}
