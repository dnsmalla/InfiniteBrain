import XCTest
@testable import InfiniteBrain
@testable import SharedLLMKit

final class QueryServiceTests: XCTestCase {
    func testReturnsAnswerWithCitedIds() async throws {
        let vault = try Self.makeVault()
        defer { try? FileManager.default.removeItem(at: vault.root) }

        // Seed the vault with two notes the QueryService can retrieve.
        let store = VaultStore(vault: vault)
        let n1 = Note(
            id: "01JFACT0000000000000000001", type: .fact,
            title: "Stripe fees",
            summary: "Stripe charges 2.9% + $0.30 per transaction.",
            body: "Stripe charges 2.9% + $0.30. Below $9 ARPU this dominates.",
            edges: [], sources: [], contentHash: "h1", version: 1,
            createdAt: Date(), updatedAt: Date(), supersededBy: nil)
        let n2 = Note(
            id: "01JNOTE0000000000000000002", type: .note,
            title: "Unrelated",
            summary: "Something unrelated.",
            body: "weather forecast",
            edges: [], sources: [], contentHash: "h2", version: 1,
            createdAt: Date(), updatedAt: Date(), supersededBy: nil)
        try await store.write(n1)
        try await store.write(n2)

        // Index: place n1 close to the question vector, n2 far.
        let index = EmbeddingIndex(storeURL: vault.sidecar.appendingPathComponent("e.json"))
        await index.record(id: n1.id, vector: [1.0, 0.0])
        await index.record(id: n2.id, vector: [0.0, 1.0])

        // Embedding of the question maps to [1,0] so n1 is the nearest.
        struct StaticEmbed: EmbeddingProvider {
            func embed(_ text: String) async throws -> [Float] { [1.0, 0.0] }
        }

        let routes: [String: String] = [
            "answer-question": #"{"answer":"Stripe charges 2.9% + $0.30 [[01JFACT0000000000000000001]].","cited_ids":["01JFACT0000000000000000001"]}"#,
        ]
        let client = DispatchingFakeClient(routes: routes)

        let service = QueryService(
            skillRunner: SkillRunner(client: client, skillsRoot: Self.bundledSkillsRoot),
            store: store,
            embeddings: StaticEmbed(),
            index: index
        )

        let answer = try await service.ask("What does Stripe charge?", topK: 5)
        XCTAssertTrue(answer.text.contains("2.9%"))
        XCTAssertEqual(answer.citedIds, ["01JFACT0000000000000000001"])
    }

    private static func makeVault() throws -> Vault {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ib-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Vault(root: root)
    }

    private static var bundledSkillsRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent(); url.deleteLastPathComponent(); url.deleteLastPathComponent()
        return url.appendingPathComponent("Sources/InfiniteBrain/Resources/skills", isDirectory: true)
    }
}
