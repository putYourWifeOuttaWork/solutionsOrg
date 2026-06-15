import XCTest
@testable import PrepOSBucketing

/// `DeterministicEmbeddingService` and the `EmbeddingService` contract (design note §4).
/// Uses only the deterministic fake — no model, no network, no Xcode-only frameworks.
final class EmbeddingServiceTests: XCTestCase {

    func testReproducibleSameTextSameVector() async throws {
        let service = DeterministicEmbeddingService()
        let a = try await service.embed("Acme renewal next quarter")
        let b = try await service.embed("Acme renewal next quarter")
        XCTAssertEqual(a, b, "same text must map to an identical vector")
        XCTAssertEqual(a.count, service.dimension)
    }

    func testResultIsL2Normalized() async throws {
        let service = DeterministicEmbeddingService()
        let v = try await service.embed("some normalized item text here")
        let magnitude = (v.reduce(0) { $0 + $1 * $1 }).squareRoot()
        XCTAssertEqual(magnitude, 1.0, accuracy: 1e-9, "vector should be unit length")
    }

    func testSharedTokensScoreHigherThanUnrelated() async throws {
        let service = DeterministicEmbeddingService()
        let base = try await service.embed("quarterly revenue forecast for the account team")
        let related = try await service.embed("quarterly revenue forecast meeting notes")
        let unrelated = try await service.embed("zebra giraffe purple umbrella")
        let simRelated = cosineSimilarity(base, related)
        let simUnrelated = cosineSimilarity(base, unrelated)
        XCTAssertGreaterThan(simRelated, simUnrelated)
    }

    func testEmptyTextThrows() async {
        let service = DeterministicEmbeddingService()
        await assertThrows(EmbeddingError.emptyText) { try await service.embed("") }
        await assertThrows(EmbeddingError.emptyText) { try await service.embed("   \n\t ") }
    }

    func testCustomDimensionHonoredAndReproducible() async throws {
        for dimension in [8, 256] {
            let service = DeterministicEmbeddingService(dimension: dimension)
            let a = try await service.embed("dimension boundary check")
            let b = try await service.embed("dimension boundary check")
            XCTAssertEqual(a.count, dimension)
            XCTAssertEqual(a, b)
        }
    }

    // MARK: - Helpers

    private func assertThrows(
        _ expected: EmbeddingError,
        _ body: () async throws -> [Double],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await body()
            XCTFail("expected \(expected) to be thrown", file: file, line: line)
        } catch let error as EmbeddingError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}
