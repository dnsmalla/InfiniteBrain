import XCTest
@testable import InfiniteBrain
@testable import SharedLLMKit

final class OrchestratorEmbeddingTests: XCTestCase {
    /// On the second ingest, the orchestrator should embed the unit, find the
    /// previously-recorded note as a neighbour, and pass it to reconcile-note
    /// as a non-empty `nearest` candidate list.
    func testReconcileSeesPreviousNoteAsCandidateOnSecondIngest() async throws {
        let vault = try Self.makeVault()
        defer { try? FileManager.default.removeItem(at: vault.root) }

        let inbox = vault.inbox
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let f1 = inbox.appendingPathComponent("a.txt")
        let f2 = inbox.appendingPathComponent("b.txt")
        try "free tier dropped".write(to: f1, atomically: true, encoding: .utf8)
        try "free tier dropped".write(to: f2, atomically: true, encoding: .utf8)

        // Capture the user prompt sent to reconcile-note across runs.
        let capture = PromptCapture()
        let baseRoutes: [String: String] = [
            "atomize-text":   #"{"units":[{"title":"x","body":"free tier dropped","line_count":50,"suggested_type_hint":"decision"}]}"#,
            "classify-node":  #"{"type":"decision","confidence":0.9,"rationale":"clear"}"#,
            "summarize-note": #"{"summary":"dropped"}"#,
            "reconcile-note": #"{"decision":"add","target_id":null,"rationale":"new"}"#,
        ]
        let client = CapturingDispatchClient(routes: baseRoutes, capture: capture)

        let provider = HashEmbeddingProvider(dim: 16)
        let indexURL = vault.sidecar.appendingPathComponent("embeddings.json")

        // First ingest — fresh index. Two ids consumed: source note + atomic note.
        let orchestrator1 = Orchestrator(
            skillRunner: SkillRunner(client: client, skillsRoot: Self.bundledSkillsRoot),
            idGenerator: FixedIDGenerator(ids: ["01JFIRSTSRC0000000000000A", "01JFIRSTNOTE000000000000B"]),
            dateProvider: FixedDateProvider(date: Date()),
            embeddings: provider,
            index: EmbeddingIndex(storeURL: indexURL)
        )
        let r1 = try await orchestrator1.ingest(file: f1, into: vault)
        XCTAssertEqual(r1.added, 1)

        // Second ingest — load persisted index.
        let index2 = EmbeddingIndex(storeURL: indexURL)
        try await index2.load()
        let orchestrator2 = Orchestrator(
            skillRunner: SkillRunner(client: client, skillsRoot: Self.bundledSkillsRoot),
            idGenerator: FixedIDGenerator(ids: ["01JSECONDSRC000000000000C", "01JSECONDNOTE00000000000D"]),
            dateProvider: FixedDateProvider(date: Date()),
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

// Records every (system, user) the client sees, then lets tests query them.
actor PromptCapture {
    private(set) var calls: [(system: String, user: String)] = []
    func record(system: String, user: String) { calls.append((system, user)) }
    func prompts(matching needle: String) -> [String] {
        calls.filter { $0.system.contains(needle) }.map(\.user)
    }
}

/// Like DispatchingFakeClient but also records prompts via the supplied capture.
actor CapturingDispatchClient: LLMClient {
    private let routes: [String: String]
    private let capture: PromptCapture
    init(routes: [String: String], capture: PromptCapture) {
        self.routes = routes; self.capture = capture
    }
    func complete(system: String, user: String, responseSchema: [String: Any]?) async throws -> String {
        await capture.record(system: system, user: user)
        for (key, value) in routes where system.contains(matchToken(forSkill: key)) {
            return value
        }
        throw NSError(domain: "CapturingDispatchClient", code: 1)
    }
    private func matchToken(forSkill name: String) -> String {
        switch name {
        case "atomize-text":   return "convert long-form text into atomic units"
        case "classify-node":  return "Pick exactly one type"
        case "summarize-note": return "Write a single English sentence"
        case "reconcile-note": return "Compare the candidate against"
        default: return name
        }
    }
}

/// Deterministic embedding for tests: hashes the input into a fixed-dim vector.
/// Same text → same vector, different text → different vector. Good enough to
/// verify the wiring (real embeddings live in NLEmbeddingProvider).
struct HashEmbeddingProvider: EmbeddingProvider {
    let dim: Int
    func embed(_ text: String) async throws -> [Float] {
        var v = [Float](repeating: 0, count: dim)
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        for i in 0..<dim {
            let mixed = hash &+ UInt64(i) &* 2654435761
            v[i] = Float(Int32(truncatingIfNeeded: mixed)) / Float(Int32.max)
        }
        return v
    }
}
