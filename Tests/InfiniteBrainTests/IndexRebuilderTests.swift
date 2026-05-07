import XCTest
@testable import InfiniteBrainCore
@testable import SharedLLMKit

final class IndexRebuilderTests: XCTestCase {
    func testRebuildIndexFromMarkdownDropsStaleEntriesAndAddsMissingOnes() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }

        let store = VaultStore(vault: vault)
        let n1 = Note(
            id: "01JNOTE00000000000000001", type: .note,
            title: "n1", summary: "first", body: "body of one",
            edges: [], sources: [], contentHash: "h",
            version: 1, createdAt: Date(), updatedAt: Date())
        let n2 = Note(
            id: "01JNOTE00000000000000002", type: .fact,
            title: "n2", summary: "second", body: "body of two",
            edges: [], sources: [], contentHash: "h",
            version: 1, createdAt: Date(), updatedAt: Date())
        try await store.write(n1)
        try await store.write(n2)

        // Pre-populate the index with a stale entry for a deleted note and an
        // entry for a note that exists. Rebuild must drop the stale one.
        let indexURL = vault.sidecar.appendingPathComponent("embeddings.json")
        let oldIndex = EmbeddingIndex(storeURL: indexURL)
        await oldIndex.record(id: "01JGONE0000000000000000099", vector: [1, 0, 0])
        await oldIndex.record(id: n1.id, vector: [0, 1, 0])
        try await oldIndex.flush()

        let rebuilt = try await IndexRebuilder.rebuild(
            vault: vault,
            embeddings: HashEmbeddingProvider(dim: 8)
        )

        // Two notes in the vault → two entries in the rebuilt index.
        let hits = await rebuilt.nearest(to: [Float](repeating: 1, count: 8), k: 10)
        let ids = Set(hits.map(\.id))
        XCTAssertEqual(ids, [n1.id, n2.id])
        XCTAssertFalse(ids.contains("01JGONE0000000000000000099"),
                       "stale entries must be dropped on rebuild")
    }
}
