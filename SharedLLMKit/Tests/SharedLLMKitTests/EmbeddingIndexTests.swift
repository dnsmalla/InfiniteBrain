import XCTest
@testable import SharedLLMKit

final class EmbeddingIndexTests: XCTestCase {
    func testNearestReturnsTopKByCosineSimilarity() async throws {
        let url = Self.tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let index = EmbeddingIndex(storeURL: url)

        await index.record(id: "a", vector: [1, 0, 0])  // East
        await index.record(id: "b", vector: [0, 1, 0])  // North
        await index.record(id: "c", vector: [0.9, 0.1, 0])  // mostly East
        await index.record(id: "d", vector: [-1, 0, 0]) // West (opposite of A)

        let query: [Float] = [1, 0, 0]
        let results = await index.nearest(to: query, k: 2)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].id, "a")
        XCTAssertEqual(results[1].id, "c")
        XCTAssertGreaterThan(results[0].score, results[1].score)
    }

    func testEmptyIndexReturnsNoResults() async throws {
        let url = Self.tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let index = EmbeddingIndex(storeURL: url)
        let results = await index.nearest(to: [1, 0, 0], k: 5)
        XCTAssertTrue(results.isEmpty)
    }

    func testPersistenceAcrossInstances() async throws {
        let url = Self.tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let index = EmbeddingIndex(storeURL: url)
            await index.record(id: "x", vector: [0.5, 0.5, 0.0])
            await index.record(id: "y", vector: [0.0, 0.0, 1.0])
            try await index.flush()
        }

        let reopened = EmbeddingIndex(storeURL: url)
        try await reopened.load()
        let r = await reopened.nearest(to: [1, 1, 0], k: 5)
        XCTAssertEqual(r.first?.id, "x")
    }

    func testRecordIsIdempotentByIdAndOverwrites() async throws {
        let url = Self.tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let index = EmbeddingIndex(storeURL: url)
        await index.record(id: "a", vector: [1, 0])
        await index.record(id: "a", vector: [0, 1])
        let r = await index.nearest(to: [0, 1], k: 5)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r.first?.id, "a")
    }

    private static func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ib-embed-\(UUID().uuidString).json")
    }
}
