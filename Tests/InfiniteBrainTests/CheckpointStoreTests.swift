import XCTest
@testable import InfiniteBrainCore

final class CheckpointStoreTests: XCTestCase {
    func testSaveLoadDeleteRoundTrip() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        let store = CheckpointStore(vault: vault)

        var cp = Checkpoint(
            fileHash: "sha256-abc",
            sourceId: "01JSRC0000000000000000000",
            chunkCount: 5,
            completedChunks: [0, 2]
        )
        try await store.save(cp)

        let loaded = try await store.load(fileHash: "sha256-abc")
        XCTAssertEqual(loaded?.fileHash, cp.fileHash)
        XCTAssertEqual(loaded?.sourceId, cp.sourceId)
        XCTAssertEqual(loaded?.chunkCount, 5)
        XCTAssertEqual(loaded?.completedChunks, [0, 2])
        XCTAssertFalse(loaded?.isComplete ?? true)
        XCTAssertEqual(loaded?.pendingChunkIndices, [1, 3, 4])

        // Mark another chunk complete via the helper.
        cp = (try await store.markChunkComplete(fileHash: "sha256-abc", chunkIndex: 1))!
        XCTAssertEqual(cp.completedChunks, [0, 1, 2])

        try await store.delete(fileHash: "sha256-abc")
        let after = try await store.load(fileHash: "sha256-abc")
        XCTAssertNil(after)
    }

    func testIsCompleteWhenAllChunksMarked() {
        var cp = Checkpoint(fileHash: "h", sourceId: "s", chunkCount: 3, completedChunks: [0, 1])
        XCTAssertFalse(cp.isComplete)
        cp.completedChunks.insert(2)
        XCTAssertTrue(cp.isComplete)
        XCTAssertTrue(cp.pendingChunkIndices.isEmpty)
    }

    func testLoadReturnsNilWhenAbsent() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        let store = CheckpointStore(vault: vault)
        let result = try await store.load(fileHash: "sha256-nonexistent")
        XCTAssertNil(result)
    }
}
