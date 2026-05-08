import XCTest
@testable import InfiniteBrainCore
@testable import SharedLLMKit

/// Verifies that bounded-concurrency unit processing produces the same notes,
/// preserves input order, and does not duplicate ids.
final class ConcurrencyTests: XCTestCase {
    func testFourUnitsUnderConcurrencyTwoYieldFourNotesInOrder() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        try FileManager.default.createDirectory(at: vault.inbox, withIntermediateDirectories: true)
        let f = vault.inbox.appendingPathComponent("memo.txt")
        try "doesn't matter; atomize is mocked".write(to: f, atomically: true, encoding: .utf8)

        // atomize-text returns four units in a fixed order.
        let routes: [String: String] = [
            "atomize-text": #"""
            {"units":[
              {"title":"u1","body":"unit one body","line_count":50,"suggested_type_hint":"note"},
              {"title":"u2","body":"unit two body","line_count":50,"suggested_type_hint":"note"},
              {"title":"u3","body":"unit three body","line_count":50,"suggested_type_hint":"note"},
              {"title":"u4","body":"unit four body","line_count":50,"suggested_type_hint":"note"}
            ]}
            """#,
            "process-unit":   #"{"type":"note","confidence":0.9,"rationale":"","summary":"s"}"#,
            "reconcile-note": #"{"decision":"add","target_id":null,"rationale":""}"#,
        ]
        let client = DispatchingFakeClient(routes: routes)
        let orch = Orchestrator(
            skillRunner: SkillRunner(client: client, skillsRoot: TestPaths.bundledSkills),
            idGenerator: FixedIDGenerator(ids: [
                "01JSRC000000000000000000",
                "01JNOTE00000000000000001",
                "01JNOTE00000000000000002",
                "01JNOTE00000000000000003",
                "01JNOTE00000000000000004",
            ]),
            dateProvider: FixedDateProvider(date: Date()),
            checkpoints: CheckpointStore(vault: vault),
            concurrency: 2
        )

        let r = try await orch.ingest(file: f, into: vault)
        XCTAssertEqual(r.added, 4)

        let store = VaultStore(vault: vault)
        // All four notes exist with distinct ids in input order.
        let n1 = try await store.read(id: "01JNOTE00000000000000001")
        let n2 = try await store.read(id: "01JNOTE00000000000000002")
        let n3 = try await store.read(id: "01JNOTE00000000000000003")
        let n4 = try await store.read(id: "01JNOTE00000000000000004")
        XCTAssertEqual([n1.title, n2.title, n3.title, n4.title], ["u1", "u2", "u3", "u4"])

        // All four cite the source.
        for n in [n1, n2, n3, n4] {
            XCTAssertEqual(n.sources, ["01JSRC000000000000000000"])
        }
    }
}
