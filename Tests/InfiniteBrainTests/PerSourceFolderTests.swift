import XCTest
@testable import InfiniteBrainCore
@testable import SharedLLMKit

/// New layout: every note from a given input file lives under
/// `notes/<source-slug>/<type>/<id>--<slug>.md`. Source notes go into
/// the same per-source folder.
final class PerSourceFolderTests: XCTestCase {
    func testWriteAndReadRoundTripUnderSourceFolder() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        let store = VaultStore(vault: vault)

        let sourceId = "01KSRC0000000000000000000"
        let source = Note(
            id: sourceId, type: .source,
            title: "Coding Theory.pdf",
            summary: "src", body: "x",
            edges: [], sources: [], contentHash: "h",
            version: 1, createdAt: Date(), updatedAt: Date()
        )
        try await store.write(source)

        let atomic = Note(
            id: "01KNOTE000000000000000001", type: .decision,
            title: "Use BCH for ECC",
            summary: "dec", body: "x",
            edges: [], sources: [sourceId], contentHash: "h",
            version: 1, createdAt: Date(), updatedAt: Date()
        )
        try await store.write(atomic)

        let fm = FileManager.default
        let folder = vault.notesRoot.appendingPathComponent("coding-theory-pdf")
        XCTAssertTrue(fm.fileExists(atPath: folder.path),
                      "source's slugified filename should be the folder name")
        XCTAssertTrue(fm.fileExists(atPath: folder.appendingPathComponent("source").path))
        XCTAssertTrue(fm.fileExists(atPath: folder.appendingPathComponent("decision").path))

        // Notes are still discoverable by id regardless of layout.
        let read = try await store.read(id: atomic.id)
        XCTAssertEqual(read.title, "Use BCH for ECC")
        XCTAssertEqual(read.sources, [sourceId])

        // allNotes walks the new tree.
        let all = try await store.allNotes()
        XCTAssertEqual(all.count, 2)
    }

    func testFallsBackToLegacyTypeFolderWhenNoSource() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        let store = VaultStore(vault: vault)

        // A note with no source (and not itself a source) lands in the legacy
        // top-level type folder so older vaults still work.
        let note = Note(
            id: "01KSTRAY000000000000000001", type: .note,
            title: "stray", summary: "s", body: "b",
            edges: [], sources: [], contentHash: "h",
            version: 1, createdAt: Date(), updatedAt: Date()
        )
        try await store.write(note)
        let path = vault.notesRoot
            .appendingPathComponent("note")
            .appendingPathComponent("01KSTRAY000000000000000001--stray.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
    }
}
