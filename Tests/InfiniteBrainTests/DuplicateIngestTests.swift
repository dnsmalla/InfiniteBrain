import XCTest
@testable import InfiniteBrainCore
@testable import SharedLLMKit

/// Re-ingesting the same file content must not produce duplicate source notes
/// or re-run the pipeline. The orchestrator detects this by content_hash and
/// short-circuits.
final class DuplicateIngestTests: XCTestCase {
    func testSecondIngestOfSameFileSkipsAndDoesNotDuplicateSource() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        try FileManager.default.createDirectory(at: vault.inbox, withIntermediateDirectories: true)
        let f = vault.inbox.appendingPathComponent("memo.txt")
        try "stable content used twice".write(to: f, atomically: true, encoding: .utf8)

        let routes: [String: String] = [
            "atomize-text":   #"{"units":[{"title":"u","body":"stable content used twice","line_count":50,"suggested_type_hint":"note"}]}"#,
            "process-unit":   #"{"type":"note","confidence":0.9,"rationale":"","summary":"x"}"#,
            "reconcile-note": #"{"decision":"add","target_id":null,"rationale":""}"#,
        ]
        let client = DispatchingFakeClient(routes: routes)
        func makeOrch(ids: [String]) -> Orchestrator {
            Orchestrator(
                skillRunner: SkillRunner(client: client, skillsRoot: TestPaths.bundledSkills),
                idGenerator: FixedIDGenerator(ids: ids),
                dateProvider: FixedDateProvider(date: Date()),
                checkpoints: CheckpointStore(vault: vault)
            )
        }

        let r1 = try await makeOrch(ids: ["01JSRC0", "01JNOTE1"]).ingest(file: f, into: vault)
        XCTAssertEqual(r1.added, 1, "first ingest creates one atomic note")

        // Second ingest of the same file content must short-circuit.
        let r2 = try await makeOrch(ids: ["UNUSED-A", "UNUSED-B"]).ingest(file: f, into: vault)
        XCTAssertEqual(r2.added, 0)
        XCTAssertEqual(r2.skipped, 1)

        // Vault must still contain exactly one source note, not two.
        let store = VaultStore(vault: vault)
        let all = try await store.allNotes()
        let sources = all.filter { $0.type == .source }
        XCTAssertEqual(sources.count, 1, "second ingest must NOT create another source note")
    }
}
