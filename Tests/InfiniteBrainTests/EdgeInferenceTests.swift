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
        let orchestrator = Orchestrator(
            skillRunner: SkillRunner(client: client, skillsRoot: Self.bundledSkillsRoot),
            idGenerator: FixedIDGenerator(ids: ["01JNEW0000000000000000001"]),
            dateProvider: FixedDateProvider(date: Date())
        )
        let r = try await orchestrator.ingest(file: f, into: vault)
        XCTAssertEqual(r.added, 1)

        let store = VaultStore(vault: vault)
        let note = try await store.read(id: "01JNEW0000000000000000001")
        XCTAssertEqual(note.edges.count, 1)
        XCTAssertEqual(note.edges.first?.type, .supports)
        XCTAssertEqual(note.edges.first?.target, "01JFACT0000000000000000001")
        XCTAssertEqual(note.edges.first?.evidence, "price floor proves it")
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
