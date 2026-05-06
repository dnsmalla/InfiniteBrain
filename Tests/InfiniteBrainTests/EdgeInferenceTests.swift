import XCTest
@testable import InfiniteBrain
@testable import SharedLLMKit

/// After a note is added, the orchestrator must call `infer-edges` and persist
/// the returned edges into the new note's frontmatter.
final class EdgeInferenceTests: XCTestCase {
    func testEdgesArePersistedAfterAdd() async throws {
        let vault = try Self.makeVault()
        defer { try? FileManager.default.removeItem(at: vault.root) }

        let inbox = vault.inbox
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let f = inbox.appendingPathComponent("a.txt")
        try "free tier dropped".write(to: f, atomically: true, encoding: .utf8)

        let routes: [String: String] = [
            "atomize-text":   #"{"units":[{"title":"x","body":"free tier dropped","line_count":50,"suggested_type_hint":"decision"}]}"#,
            "classify-node":  #"{"type":"decision","confidence":0.9,"rationale":"clear"}"#,
            "summarize-note": #"{"summary":"dropped"}"#,
            "reconcile-note": #"{"decision":"add","target_id":null,"rationale":"new"}"#,
            "infer-edges":    #"{"edges":[{"type":"supports","target_id":"01JFACT0000000000000000001","evidence":"price floor proves it"}]}"#,
        ]

        let client = DispatchingFakeClient(routes: routes)
        let provider = HashEmbeddingProvider(dim: 8)
        let index = EmbeddingIndex(storeURL: vault.sidecar.appendingPathComponent("e.json"))
        // Pre-populate the index so reconcile sees a candidate, which triggers infer-edges.
        await index.record(id: "01JFACT0000000000000000001", vector: try await provider.embed("free tier dropped"))
        let orchestrator = Orchestrator(
            skillRunner: SkillRunner(client: client, skillsRoot: Self.bundledSkillsRoot),
            idGenerator: FixedIDGenerator(ids: ["01JSRC0000000000000000001", "01JNEW0000000000000000002"]),
            dateProvider: FixedDateProvider(date: Date()),
            embeddings: provider,
            index: index
        )
        // Pre-write the candidate note so VaultStore.read in the orchestrator's
        // candidate-summary lookup succeeds (otherwise `nearest` ends up empty).
        let store = VaultStore(vault: vault)
        try await store.write(Note(
            id: "01JFACT0000000000000000001", type: .fact, title: "Stripe fee floor",
            summary: "Stripe charges a $0.30 floor.",
            body: "details",
            edges: [], sources: [], contentHash: "h", version: 1,
            createdAt: Date(), updatedAt: Date()))

        let r = try await orchestrator.ingest(file: f, into: vault)
        XCTAssertEqual(r.added, 1)

        let note = try await store.read(id: "01JNEW0000000000000000002")
        // The new note carries: a derived_from edge to the source, plus the
        // inferred `supports` edge to the pre-existing fact.
        XCTAssertTrue(note.edges.contains { $0.type == .derivedFrom && $0.target == "01JSRC0000000000000000001" })
        XCTAssertTrue(note.edges.contains {
            $0.type == .supports && $0.target == "01JFACT0000000000000000001" && $0.evidence == "price floor proves it"
        })
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
