import XCTest
@testable import InfiniteBrainCore
@testable import SharedLLMKit

/// Citation-policy.mdc requires every fact/decision/event to cite a source.
/// The orchestrator must therefore (a) emit a `source` note per ingested
/// file, and (b) link every atomic note back to it via `sources` and a
/// `derived_from` edge.
final class SourceNoteTests: XCTestCase {
    func testIngestEmitsSourceNoteAndLinksAtomicNoteToIt() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }

        let inbox = vault.inbox
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let f = inbox.appendingPathComponent("memo.txt")
        try "We decided to drop the free tier.".write(to: f, atomically: true, encoding: .utf8)

        let routes: [String: String] = [
            "atomize-text":   #"{"units":[{"title":"x","body":"decided to drop","line_count":50,"suggested_type_hint":"decision"}]}"#,
            "process-unit":   #"{"type":"decision","confidence":0.9,"rationale":"clear","summary":"dropped"}"#,
            "reconcile-note": #"{"decision":"add","target_id":null,"rationale":"new"}"#,
        ]
        let client = DispatchingFakeClient(routes: routes)
        let orch = Orchestrator(
            skillRunner: SkillRunner(client: client, skillsRoot: TestPaths.bundledSkills),
            idGenerator: FixedIDGenerator(ids: ["01JSRC000000000000000000A", "01JNOT000000000000000000B"]),
            dateProvider: FixedDateProvider(date: Date()),
            checkpoints: CheckpointStore(vault: vault)
        )
        _ = try await orch.ingest(file: f, into: vault)

        let store = VaultStore(vault: vault)
        let source = try await store.read(id: "01JSRC000000000000000000A")
        XCTAssertEqual(source.type, .source)
        XCTAssertEqual(source.title, "memo.txt")

        let atomic = try await store.read(id: "01JNOT000000000000000000B")
        XCTAssertEqual(atomic.type, .decision)
        XCTAssertEqual(atomic.sources, ["01JSRC000000000000000000A"],
                       "every produced note must cite the source")
        XCTAssertTrue(atomic.edges.contains(where: { $0.type == .derivedFrom && $0.target == "01JSRC000000000000000000A" }),
                      "must include a derived_from edge to the source note")
    }

}
