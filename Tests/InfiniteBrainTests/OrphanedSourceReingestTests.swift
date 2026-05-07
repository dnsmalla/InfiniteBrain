import XCTest
import CryptoKit
@testable import InfiniteBrainCore
@testable import SharedLLMKit

/// If a previous ingest aborted after writing the source note but before any
/// atomic notes landed, the next ingest must re-run instead of treating the
/// orphaned source as proof of completion.
final class OrphanedSourceReingestTests: XCTestCase {
    func testOrphanedSourceTriggersReingestNotSkip() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        try FileManager.default.createDirectory(at: vault.inbox, withIntermediateDirectories: true)
        let f = vault.inbox.appendingPathComponent("memo.txt")
        let content = "stable content"
        try content.write(to: f, atomically: true, encoding: .utf8)

        // Hash the same way Orchestrator does so the dedup path matches.
        let fileHash = "sha256-" + sha256Hex(content)

        // Plant an orphan: a source note with the right hash, but no atomic
        // notes citing it.
        let store = VaultStore(vault: vault)
        try await store.write(Note(
            id: "01ORPHAN0000000000000000",
            type: .source,
            title: "memo.txt",
            summary: "Original source: memo.txt.",
            body: "Path: \(f.path)",
            edges: [], sources: [],
            contentHash: fileHash,
            version: 1,
            createdAt: Date(), updatedAt: Date()))

        // The new ingest should NOT skip — it should re-run and produce atomic notes.
        let routes: [String: String] = [
            "atomize-text":   #"{"units":[{"title":"u","body":"stable content","line_count":50,"suggested_type_hint":"note"}]}"#,
            "classify-node":  #"{"type":"note","confidence":0.9,"rationale":""}"#,
            "summarize-note": #"{"summary":"x"}"#,
            "reconcile-note": #"{"decision":"add","target_id":null,"rationale":""}"#,
        ]
        let client = DispatchingFakeClient(routes: routes)
        let orch = Orchestrator(
            skillRunner: SkillRunner(client: client, skillsRoot: TestPaths.bundledSkills),
            idGenerator: FixedIDGenerator(ids: ["01NEWSRC0000000000000000", "01NEWNOTE000000000000000"]),
            dateProvider: FixedDateProvider(date: Date())
        )
        let r = try await orch.ingest(file: f, into: vault)
        XCTAssertEqual(r.added, 1, "orphaned source must trigger a re-run, not a skip")
        XCTAssertEqual(r.skipped, 0)

        // After the re-run there should be exactly one source note (orphan
        // cleaned up), plus the new atomic note.
        let all = try await store.allNotes()
        let sources = all.filter { $0.type == .source }
        XCTAssertEqual(sources.count, 1, "orphan must be removed; only the new source remains")
        let atomic = all.filter { $0.type != .source }
        XCTAssertEqual(atomic.count, 1)
        XCTAssertEqual(atomic.first?.sources, sources.first.map { [$0.id] })
    }

    private func sha256Hex(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

