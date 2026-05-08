import XCTest
@testable import InfiniteBrainCore
@testable import SharedLLMKit

final class Phase7OptimizationTests: XCTestCase {
    func testNodeCoordinatePersistence() async throws {
        let fm = FileManager.default
        let tempURL = fm.temporaryDirectory.appendingPathComponent("test_meta_v7.bin")
        defer { try? fm.removeItem(at: tempURL) }
        
        let index = MetadataIndex(storeURL: tempURL)
        let note = Note(
            id: "spatial1", type: .note, title: "Spatial Test",
            summary: "Testing coordinate save", body: "",
            edges: [], sources: [], contentHash: "h1", version: 1,
            createdAt: Date(), updatedAt: Date()
        )
        
        await index.update(note)
        await index.updatePosition(id: "spatial1", x: 123.45, y: 678.90)
        try await index.save()
        
        // Reload
        let index2 = MetadataIndex(storeURL: tempURL)
        let loaded = await index2.load()
        XCTAssertTrue(loaded)
        let entries = await index2.allEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].x, 123.45)
        XCTAssertEqual(entries[0].y, 678.90)
    }

    func testSIMDSearchPerformance() async throws {
        let fm = FileManager.default
        let tempURL = fm.temporaryDirectory.appendingPathComponent("test_embed_v7.bin")
        defer { try? fm.removeItem(at: tempURL) }
        
        let index = EmbeddingIndex(storeURL: tempURL)
        let dim = 768
        let count = 1000
        
        for i in 0..<count {
            let vec = (0..<dim).map { _ in Float.random(in: -1...1) }
            await index.record(id: "v\(i)", vector: vec)
        }
        
        let query = (0..<dim).map { _ in Float.random(in: -1...1) }
        
        let start = CFAbsoluteTimeGetCurrent()
        let hits = await index.nearest(to: query, k: 5)
        let end = CFAbsoluteTimeGetCurrent()
        
        let elapsed = (end - start) * 1000.0
        print("SIMD SEARCH TIME (1000 nodes, 768d): \(String(format: "%.2f", elapsed))ms")
        XCTAssertEqual(hits.count, 5)
        XCTAssertLessThan(elapsed, 50.0, "Search should be fast with SIMD")
    }
}
