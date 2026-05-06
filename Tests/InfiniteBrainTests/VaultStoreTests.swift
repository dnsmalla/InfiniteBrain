import XCTest
@testable import InfiniteBrain

final class VaultStoreTests: XCTestCase {
    func testWriteThenReadRoundTrip() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        let store = VaultStore(vault: vault)

        let original = Note(
            id: "01JABCDEFGHJKMNPQRSTVWXYZ0",
            type: .decision,
            title: "No free tier for Indie plan",
            summary: "We will not offer a free tier on the Indie plan because Stripe-fee economics break below $9 ARPU.",
            body: "# No free tier for Indie plan\n\nDetails of the decision live here.\nMultiple paragraphs.\n",
            edges: [
                Edge(type: .supports, target: "01JFACT0000000000000000001", evidence: "Stripe fee table shows $0.30 floor"),
                Edge(type: .contradicts, target: "01JHYP00000000000000000002", evidence: "Earlier hypothesis assumed flat 2.9% fees"),
            ],
            sources: ["01JSRC00000000000000000003"],
            contentHash: "sha256-abc",
            version: 1,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            supersededBy: nil
        )

        try await store.write(original)
        let read = try await store.read(id: original.id)

        XCTAssertEqual(read.id, original.id)
        XCTAssertEqual(read.type, original.type)
        XCTAssertEqual(read.title, original.title)
        XCTAssertEqual(read.summary, original.summary)
        XCTAssertEqual(read.body.trimmingCharacters(in: .whitespacesAndNewlines),
                       original.body.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(read.edges, original.edges)
        XCTAssertEqual(read.sources, original.sources)
        XCTAssertEqual(read.version, original.version)
        XCTAssertEqual(read.contentHash, original.contentHash)
    }

    func testFilePathFollowsTypeAndIdConvention() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        let store = VaultStore(vault: vault)

        let note = Note(
            id: "01JTEST0000000000000000099",
            type: .fact,
            title: "Stripe charges 2.9% + $0.30",
            summary: "Stripe fee floor of $0.30 makes free tiers unprofitable below $9 ARPU.",
            body: "Body.",
            edges: [],
            sources: [],
            contentHash: "h",
            version: 1,
            createdAt: Date(),
            updatedAt: Date(),
            supersededBy: nil
        )
        try await store.write(note)

        let expected = vault.notesRoot
            .appendingPathComponent("fact")
            .appendingPathComponent("01JTEST0000000000000000099--stripe-charges-2-9-0-30.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path),
                      "expected file at \(expected.path)")
    }

    func testReadingMissingNoteThrows() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        let store = VaultStore(vault: vault)
        do {
            _ = try await store.read(id: "01JNONEXISTENT0000000000000")
            XCTFail("expected throw")
        } catch VaultStoreError.notFound {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

}
