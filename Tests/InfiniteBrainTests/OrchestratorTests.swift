import XCTest
@testable import InfiniteBrainCore
@testable import SharedLLMKit

final class OrchestratorTests: XCTestCase {
    func testIngestsTextFileAndWritesNotes() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }

        // Drop a text file in the inbox.
        let input = vault.inbox.appendingPathComponent("memo.txt")
        try FileManager.default.createDirectory(at: vault.inbox, withIntermediateDirectories: true)
        try "We decided to drop the free tier on the Indie plan.".write(to: input, atomically: true, encoding: .utf8)

        // Skills root mirrors the bundled layout.
        let skillsRoot = TestPaths.bundledSkills

        let fake = DispatchingFakeClient(routes: [
            "atomize-text":    #"{"units":[{"title":"No free tier","body":"We decided to drop the free tier on the Indie plan.","line_count":52,"suggested_type_hint":"decision"}]}"#,
            "classify-node":   #"{"type":"decision","confidence":0.93,"rationale":"clear choice"}"#,
            "summarize-note":  #"{"summary":"We will not offer a free tier on the Indie plan."}"#,
            "reconcile-note":  #"{"decision":"add","target_id":null,"rationale":"new topic"}"#,
        ])

        let orchestrator = Orchestrator(
            skillRunner: SkillRunner(client: fake, skillsRoot: skillsRoot),
            idGenerator: FixedIDGenerator(ids: ["01JSRC000000000000000001", "01JNOTE000000000000000002"]),
            dateProvider: FixedDateProvider(date: Date(timeIntervalSince1970: 1_700_000_000))
        )

        let result = try await orchestrator.ingest(file: input, into: vault)

        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.improved, 0)
        XCTAssertEqual(result.skipped, 0)

        let store = VaultStore(vault: vault)
        let written = try await store.read(id: "01JNOTE000000000000000002")
        XCTAssertEqual(written.type, .decision)
        XCTAssertEqual(written.title, "No free tier")
        XCTAssertEqual(written.summary, "We will not offer a free tier on the Indie plan.")
        XCTAssertTrue(written.body.contains("free tier"))
        XCTAssertEqual(written.version, 1)
        XCTAssertEqual(written.sources, ["01JSRC000000000000000001"])
        XCTAssertTrue(written.edges.contains { $0.type == .derivedFrom && $0.target == "01JSRC000000000000000001" })
        XCTAssertFalse(written.needsReview)
    }

    func testReconcilerSkipDecisionDoesNotWriteNote() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        let input = vault.inbox.appendingPathComponent("memo.txt")
        try FileManager.default.createDirectory(at: vault.inbox, withIntermediateDirectories: true)
        try "Already-known content.".write(to: input, atomically: true, encoding: .utf8)

        let fake = DispatchingFakeClient(routes: [
            "atomize-text":   #"{"units":[{"title":"x","body":"already-known content","line_count":50,"suggested_type_hint":"note"}]}"#,
            "classify-node":  #"{"type":"note","confidence":0.8,"rationale":""}"#,
            "summarize-note": #"{"summary":"already-known."}"#,
            "reconcile-note": #"{"decision":"skip","target_id":"01JEXISTING0000000000000","rationale":"dup"}"#,
        ])

        let orchestrator = Orchestrator(
            skillRunner: SkillRunner(client: fake, skillsRoot: TestPaths.bundledSkills),
            idGenerator: FixedIDGenerator(ids: ["01JNEW000000000000000099"]),
            dateProvider: FixedDateProvider(date: Date())
        )

        let result = try await orchestrator.ingest(file: input, into: vault)
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.skipped, 1)

        // Source note is always written; only atomic units are skipped.
        // Layout-agnostic check via VaultStore.
        let store = VaultStore(vault: vault)
        let all = try await store.allNotes()
        let sources = all.filter { $0.type == .source }
        let atomic = all.filter { $0.type != .source }
        XCTAssertEqual(sources.count, 1, "source note must be written even when atomic units are skipped")
        XCTAssertTrue(atomic.isEmpty, "no atomic notes should be written on skip")
    }

}
