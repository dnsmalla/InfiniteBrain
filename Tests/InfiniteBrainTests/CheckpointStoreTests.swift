import XCTest
@testable import InfiniteBrainCore

final class CheckpointStoreTests: XCTestCase {
    func testSaveLoadDeleteRoundTrip() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        let store = CheckpointStore(vault: vault)

        let cp = Checkpoint(
            fileHash: "sha256-abc",
            sourceId: "01JSRC0000000000000000000",
            units: [
                .init(title: "u1", body: "one", lineCount: 50, suggestedTypeHint: "note"),
                .init(title: "u2", body: "two", lineCount: 50, suggestedTypeHint: "decision"),
            ],
            reservedIds: ["01JID000000000000000000A1", "01JID000000000000000000A2"],
            completedThrough: 1
        )
        try await store.save(cp)

        let loaded = try await store.load(fileHash: "sha256-abc")
        XCTAssertEqual(loaded?.fileHash, cp.fileHash)
        XCTAssertEqual(loaded?.sourceId, cp.sourceId)
        XCTAssertEqual(loaded?.units.count, 2)
        XCTAssertEqual(loaded?.units.first?.title, "u1")
        XCTAssertEqual(loaded?.reservedIds, cp.reservedIds)
        XCTAssertEqual(loaded?.completedThrough, 1)

        try await store.delete(fileHash: "sha256-abc")
        let after = try await store.load(fileHash: "sha256-abc")
        XCTAssertNil(after)
    }

    func testLoadReturnsNilWhenAbsent() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        let store = CheckpointStore(vault: vault)
        let result = try await store.load(fileHash: "sha256-nonexistent")
        XCTAssertNil(result)
    }
}
