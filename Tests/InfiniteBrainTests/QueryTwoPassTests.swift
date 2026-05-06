import XCTest
@testable import InfiniteBrainCore
@testable import SharedLLMKit

/// Verifies the two-pass query flow:
///   1. select-notes-for-question receives the question + summaries (no bodies)
///   2. only the picked-id full bodies are loaded for answer-question
final class QueryTwoPassTests: XCTestCase {
    func testTwoPassLoadsOnlySelectedBodies() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }

        // Three candidate notes in the vault and the index.
        let store = VaultStore(vault: vault)
        let n1 = Note(id: "01JFACT0000000000000000001", type: .fact,
                      title: "Stripe fees", summary: "Stripe charges 2.9% + $0.30.",
                      body: "FULL BODY OF n1 — should be loaded.",
                      edges: [], sources: [], contentHash: "h", version: 1,
                      createdAt: Date(), updatedAt: Date())
        let n2 = Note(id: "01JFACT0000000000000000002", type: .fact,
                      title: "Other fee", summary: "Other unrelated fact.",
                      body: "FULL BODY OF n2 — should NOT be loaded.",
                      edges: [], sources: [], contentHash: "h", version: 1,
                      createdAt: Date(), updatedAt: Date())
        let n3 = Note(id: "01JFACT0000000000000000003", type: .fact,
                      title: "Misc", summary: "Yet another summary.",
                      body: "FULL BODY OF n3 — should NOT be loaded.",
                      edges: [], sources: [], contentHash: "h", version: 1,
                      createdAt: Date(), updatedAt: Date())
        try await store.write(n1)
        try await store.write(n2)
        try await store.write(n3)

        let index = EmbeddingIndex(storeURL: vault.sidecar.appendingPathComponent("e.json"))
        await index.record(id: n1.id, vector: [1, 0])
        await index.record(id: n2.id, vector: [0, 1])
        await index.record(id: n3.id, vector: [0.1, 0.9])

        struct StaticEmbed: EmbeddingProvider {
            func embed(_ text: String) async throws -> [Float] { [1, 0] }
        }

        // The select skill picks only n1; the answer skill returns a stock answer
        // citing it. We capture every prompt to verify pass 2's input.
        let routes: [String: String] = [
            "select-notes-for-question": #"{"needed_ids":["01JFACT0000000000000000001"]}"#,
            "answer-question":           #"{"answer":"Stripe charges 2.9% + $0.30 [[01JFACT0000000000000000001]].","cited_ids":["01JFACT0000000000000000001"]}"#,
        ]
        let capture = PromptCapture()
        let client = CapturingDispatchClient(routes: routes, capture: capture)
        let service = QueryService(
            skillRunner: SkillRunner(client: client, skillsRoot: TestPaths.bundledSkills),
            store: store,
            embeddings: StaticEmbed(),
            index: index,
            twoPass: true,
            candidateK: 3,
            fullNotesBudget: 4
        )

        let answer = try await service.ask("What does Stripe charge?")
        XCTAssertTrue(answer.text.contains("2.9%"))
        XCTAssertEqual(answer.citedIds, ["01JFACT0000000000000000001"])

        // Pass 1 input must contain summaries but NOT full bodies.
        let selectPrompts = await capture.prompts(matching: "pass 1 of a two-pass retrieval pipeline")
        XCTAssertEqual(selectPrompts.count, 1)
        XCTAssertTrue(selectPrompts[0].contains("Stripe charges 2.9% + $0.30."),
                      "pass 1 must see the n1 summary")
        XCTAssertFalse(selectPrompts[0].contains("FULL BODY OF n1"),
                       "pass 1 must not see any full body")

        // Pass 2 input must contain n1's full body and not n2/n3.
        let answerPrompts = await capture.prompts(matching: "Answer the user's `question`")
        XCTAssertEqual(answerPrompts.count, 1)
        XCTAssertTrue(answerPrompts[0].contains("FULL BODY OF n1"))
        XCTAssertFalse(answerPrompts[0].contains("FULL BODY OF n2"))
        XCTAssertFalse(answerPrompts[0].contains("FULL BODY OF n3"))
    }

    /// Single-pass mode (twoPass: false) must still work — it skips the
    /// selection skill and loads top-K full bodies directly.
    func testSinglePassSkipsSelectionStep() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        let store = VaultStore(vault: vault)
        let n1 = Note(id: "01JFACT0000000000000000001", type: .fact,
                      title: "x", summary: "x", body: "B1",
                      edges: [], sources: [], contentHash: "h", version: 1,
                      createdAt: Date(), updatedAt: Date())
        try await store.write(n1)
        let index = EmbeddingIndex(storeURL: vault.sidecar.appendingPathComponent("e.json"))
        await index.record(id: n1.id, vector: [1, 0])

        struct StaticEmbed: EmbeddingProvider {
            func embed(_ text: String) async throws -> [Float] { [1, 0] }
        }

        let routes: [String: String] = [
            "answer-question": #"{"answer":"a","cited_ids":["01JFACT0000000000000000001"]}"#,
            // No selection route. If single-pass tries to call it, this fails.
        ]
        let capture = PromptCapture()
        let client = CapturingDispatchClient(routes: routes, capture: capture)
        let service = QueryService(
            skillRunner: SkillRunner(client: client, skillsRoot: TestPaths.bundledSkills),
            store: store,
            embeddings: StaticEmbed(),
            index: index,
            twoPass: false
        )

        let answer = try await service.ask("q", topK: 5)
        XCTAssertEqual(answer.citedIds, ["01JFACT0000000000000000001"])

        let selectPrompts = await capture.prompts(matching: "pass 1 of a two-pass retrieval pipeline")
        XCTAssertTrue(selectPrompts.isEmpty, "single-pass mode must not call the selection skill")
    }
}
