import XCTest
@testable import InfiniteBrainCore
@testable import SharedLLMKit

final class Phase8ConcurrencyTests: XCTestCase {
    func testConcurrentRebuildPerformance() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        
        let store = VaultStore(vault: vault)
        let noteCount = 50
        
        // Create 50 synthetic notes
        for i in 0..<noteCount {
            let note = Note(
                id: "n\(i)", type: .note, title: "Note \(i)",
                summary: "Summary \(i)", body: "Body content for note \(i). " + String(repeating: "test ", count: 100),
                edges: [], sources: [], contentHash: "h\(i)", version: 1,
                createdAt: Date(), updatedAt: Date()
            )
            try await store.write(note)
        }
        
        let embeddings = FakeEmbeddingProvider()
        let metadataIndex = MetadataIndex(storeURL: vault.sidecar.appendingPathComponent("metadata.bin"))
        
        let start = CFAbsoluteTimeGetCurrent()
        let index = try await IndexRebuilder.rebuild(vault: vault, embeddings: embeddings, metadataIndex: metadataIndex)
        let end = CFAbsoluteTimeGetCurrent()
        
        let elapsed = end - start
        print("CONCURRENT REBUILD TIME (\(noteCount) notes): \(String(format: "%.4f", elapsed))s")
        
        let hits = await index.nearest(to: Array(repeating: 0.1, count: 768), k: 5)
        XCTAssertEqual(hits.count, 5)
    }
}

class FakeEmbeddingProvider: EmbeddingProvider {
    func embed(_ text: String) async throws -> [Float] {
        // Simulate Neural Engine latency
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        return Array(repeating: 0.5, count: 768)
    }
}
