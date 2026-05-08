import XCTest
@testable import InfiniteBrainCore
@testable import SharedLLMKit

final class OrchestratorEmbeddingTests: XCTestCase {
    /// On the second ingest, the orchestrator should embed the unit, find the
    /// previously-recorded note as a neighbour, and pass it to reconcile-note
    /// as a non-empty `nearest` candidate list.
    func testReconcileSeesPreviousNoteAsCandidateOnSecondIngest() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }

        let inbox = vault.inbox
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let f1 = inbox.appendingPathComponent("a.txt")
        let f2 = inbox.appendingPathComponent("b.txt")
        // Different bytes per file (so the dup-by-content short-circuit doesn't
        // skip the second ingest), but semantically similar so embeddings stay
        // close and the reconcile candidate set is non-empty.
        try "free tier dropped from indie plan".write(to: f1, atomically: true, encoding: .utf8)
        try "the free tier is being dropped".write(to: f2, atomically: true, encoding: .utf8)

        // Capture the user prompt sent to reconcile-note across runs.
        let capture = PromptCapture()
        let baseRoutes: [String: String] = [
            "atomize-text":   #"{"units":[{"title":"x","body":"free tier dropped","line_count":50,"suggested_type_hint":"decision"}]}"#,
            "process-unit":   #"{"type":"decision","confidence":0.9,"rationale":"clear","summary":"dropped"}"#,
            "reconcile-note": #"{"decision":"add","target_id":null,"rationale":"new"}"#,
        ]
        let client = CapturingDispatchClient(routes: baseRoutes, capture: capture)

        let provider = HashEmbeddingProvider(dim: 16)
        let indexURL = vault.sidecar.appendingPathComponent("embeddings.json")

        // First ingest — fresh index. Two ids consumed: source note + atomic note.
        let orchestrator1 = Orchestrator(
            skillRunner: SkillRunner(client: client, skillsRoot: TestPaths.bundledSkills),
            idGenerator: FixedIDGenerator(ids: ["01JFIRSTSRC0000000000000A", "01JFIRSTNOTE000000000000B"]),
            dateProvider: FixedDateProvider(date: Date()),
            checkpoints: CheckpointStore(vault: vault),
            embeddings: provider,
            index: EmbeddingIndex(storeURL: indexURL)
        )
        let r1 = try await orchestrator1.ingest(file: f1, into: vault)
        XCTAssertEqual(r1.added, 1)

        // Second ingest — load persisted index.
        let index2 = EmbeddingIndex(storeURL: indexURL)
        try await index2.load()
        let orchestrator2 = Orchestrator(
            skillRunner: SkillRunner(client: client, skillsRoot: TestPaths.bundledSkills),
            idGenerator: FixedIDGenerator(ids: ["01JSECONDSRC000000000000C", "01JSECONDNOTE00000000000D"]),
            dateProvider: FixedDateProvider(date: Date()),
            checkpoints: CheckpointStore(vault: vault),
            embeddings: provider,
            index: index2
        )
        _ = try await orchestrator2.ingest(file: f2, into: vault)

        let reconcilePrompts = await capture.prompts(matching: "Compare the candidate against")
        XCTAssertEqual(reconcilePrompts.count, 2)
        XCTAssertFalse(reconcilePrompts[0].contains("01JFIRSTNOTE000000000000B"),
                       "first reconcile should not see itself as a candidate")
        XCTAssertTrue(reconcilePrompts[1].contains("01JFIRSTNOTE000000000000B"),
                      "second reconcile must see the first atomic note's id in nearest[]")
    }

}
