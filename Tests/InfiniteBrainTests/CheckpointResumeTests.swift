import XCTest
import CryptoKit
@testable import InfiniteBrainCore
@testable import SharedLLMKit

/// Verifies that an ingest can resume from a saved checkpoint: atomize-text
/// is skipped, the source note is reused, reserved ids stay stable, and only
/// units past `completedThrough` are processed.
final class CheckpointResumeTests: XCTestCase {
    func testResumeSkipsAtomizeAndPicksUpFromCompletedThrough() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        try FileManager.default.createDirectory(at: vault.inbox, withIntermediateDirectories: true)
        let f = vault.inbox.appendingPathComponent("doc.txt")
        let content = "stable file content for hash matching"
        try content.write(to: f, atomically: true, encoding: .utf8)

        // Simulate a previous run: source note + first atomic note already written;
        // checkpoint says completedThrough=1, units count=3.
        let store = VaultStore(vault: vault)
        let sourceId = "01JSRC0000000000000000000"
        let unit1Id  = "01JNOTE00000000000000001"
        let unit2Id  = "01JNOTE00000000000000002"
        let unit3Id  = "01JNOTE00000000000000003"
        try await store.write(Note(
            id: sourceId, type: .source, title: "doc.txt",
            summary: "Original source: doc.txt.", body: "Path: \(f.path)",
            edges: [], sources: [], contentHash: "h",
            version: 1, createdAt: Date(), updatedAt: Date()))
        try await store.write(Note(
            id: unit1Id, type: .note, title: "u1",
            summary: "first", body: "first body",
            edges: [], sources: [sourceId], contentHash: "h1",
            version: 1, createdAt: Date(), updatedAt: Date()))

        let fileHash = Self.fileHash(content)
        let cps = CheckpointStore(vault: vault)
        try await cps.save(Checkpoint(
            fileHash: fileHash,
            sourceId: sourceId,
            units: [
                .init(title: "u1", body: "first body", lineCount: 50, suggestedTypeHint: "note"),
                .init(title: "u2", body: "second body", lineCount: 50, suggestedTypeHint: "note"),
                .init(title: "u3", body: "third body", lineCount: 50, suggestedTypeHint: "note"),
            ],
            reservedIds: [unit1Id, unit2Id, unit3Id],
            completedThrough: 1
        ))

        // No `atomize-text` route — if the orchestrator tries to atomize,
        // the fake throws and the test fails.
        let routes: [String: String] = [
            "classify-node":  #"{"type":"note","confidence":0.9,"rationale":""}"#,
            "summarize-note": #"{"summary":"s"}"#,
            "reconcile-note": #"{"decision":"add","target_id":null,"rationale":""}"#,
        ]
        let client = DispatchingFakeClient(routes: routes)
        let orch = Orchestrator(
            skillRunner: SkillRunner(client: client, skillsRoot: TestPaths.bundledSkills),
            idGenerator: FixedIDGenerator(ids: ["UNUSED-1", "UNUSED-2"]),
            dateProvider: FixedDateProvider(date: Date()),
            concurrency: 2
        )

        let r = try await orch.ingest(file: f, into: vault)
        XCTAssertEqual(r.added, 2)
        let n2 = try await store.read(id: unit2Id)
        let n3 = try await store.read(id: unit3Id)
        XCTAssertEqual(n2.title, "u2")
        XCTAssertEqual(n3.title, "u3")
        XCTAssertEqual(n2.sources, [sourceId])

        let after = try await cps.load(fileHash: fileHash)
        XCTAssertNil(after, "checkpoint must be deleted when all units complete")
    }

    func testFreshIngestWritesAndDeletesCheckpoint() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        try FileManager.default.createDirectory(at: vault.inbox, withIntermediateDirectories: true)
        let f = vault.inbox.appendingPathComponent("doc.txt")
        let content = "fresh content"
        try content.write(to: f, atomically: true, encoding: .utf8)

        let routes: [String: String] = [
            "atomize-text":   #"{"units":[{"title":"u1","body":"b","line_count":50,"suggested_type_hint":"note"}]}"#,
            "classify-node":  #"{"type":"note","confidence":0.9,"rationale":""}"#,
            "summarize-note": #"{"summary":"s"}"#,
            "reconcile-note": #"{"decision":"add","target_id":null,"rationale":""}"#,
        ]
        let client = DispatchingFakeClient(routes: routes)
        let orch = Orchestrator(
            skillRunner: SkillRunner(client: client, skillsRoot: TestPaths.bundledSkills),
            idGenerator: FixedIDGenerator(ids: ["01JSRC", "01JNOTE"]),
            dateProvider: FixedDateProvider(date: Date())
        )

        let r = try await orch.ingest(file: f, into: vault)
        XCTAssertEqual(r.added, 1)

        let cps = CheckpointStore(vault: vault)
        let after = try await cps.load(fileHash: Self.fileHash(content))
        XCTAssertNil(after, "checkpoint must be deleted on full completion")
    }

    /// Same hash format Orchestrator uses internally.
    static func fileHash(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return "sha256-" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
