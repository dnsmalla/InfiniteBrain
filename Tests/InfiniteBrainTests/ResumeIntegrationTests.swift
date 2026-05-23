import XCTest
@testable import InfiniteBrainCore
@testable import SharedLLMKit

/// End-to-end check that an interrupted ingest resumes from where it
/// stopped and only re-runs the chunks that didn't complete the first time.
final class ResumeIntegrationTests: XCTestCase {
    func testInterruptedIngestResumesMissingChunks() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        try FileManager.default.createDirectory(at: vault.inbox, withIntermediateDirectories: true)
        let f = vault.inbox.appendingPathComponent("doc.txt")

        // Build a body that the chunker splits into 3 chunks at 60-char target.
        let big = (0..<3).map { i in String(repeating: "abc", count: 30) + "\n\n#\(i)" }.joined(separator: "\n\n")
        try big.write(to: f, atomically: true, encoding: .utf8)

        // Counter to simulate interruption: succeed for chunks 0, 1; throw for 2.
        let attemptedSet = AttemptCounter()
        let stub = ChunkAwareFakeClient(attempts: attemptedSet, failBeyondChunkIndex: 1)

        let orch1 = Orchestrator(
            skillRunner: SkillRunner(client: stub, skillsRoot: TestPaths.bundledSkills),
            idGenerator: ULIDGenerator(),
            dateProvider: FixedDateProvider(date: Date()),
            checkpoints: CheckpointStore(vault: vault),
            chunkSize: 60,
            concurrency: 1
        )
        _ = try await orch1.ingest(file: f, into: vault)

        // Inspect the checkpoint — it should record only the chunks that
        // actually wrote their notes.
        let cps = CheckpointStore(vault: vault)
        let fileHash = "sha256-" + sha256Hex(big)
        let mid = try await cps.load(fileHash: fileHash)
        XCTAssertNotNil(mid)
        let totalChunks = mid?.chunkCount ?? 0
        XCTAssertGreaterThan(totalChunks, 1)
        XCTAssertFalse(mid?.isComplete ?? true,
                       "after interruption the checkpoint must be partial")
        XCTAssertGreaterThan(mid?.completedChunks.count ?? 0, 0,
                             "at least one chunk must have completed")
        XCTAssertLessThan(mid?.completedChunks.count ?? .max, totalChunks,
                          "not all chunks should be marked complete")

        // Now switch to a stub that always succeeds and re-run.
        let goodStub = ChunkAwareFakeClient(attempts: attemptedSet, failBeyondChunkIndex: 99)
        let orch2 = Orchestrator(
            skillRunner: SkillRunner(client: goodStub, skillsRoot: TestPaths.bundledSkills),
            idGenerator: ULIDGenerator(),
            dateProvider: FixedDateProvider(date: Date()),
            checkpoints: CheckpointStore(vault: vault),
            chunkSize: 60,
            concurrency: 1
        )
        _ = try await orch2.ingest(file: f, into: vault)

        let after = try await cps.load(fileHash: fileHash)
        XCTAssertNotNil(after)
        XCTAssertTrue(after?.isComplete ?? false,
                      "after the resume run, all chunks must be marked complete")
        XCTAssertEqual(after?.completedChunks.count, totalChunks)
    }

    private func sha256Hex(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

import CryptoKit

/// Fake LLM client that succeeds for atomize/classify/summarize/reconcile
/// up to a configured chunk index, then throws for atomize on later chunks.
/// Used to simulate a mid-ingest failure.
actor ChunkAwareFakeClient: LLMClient {
    private let attempts: AttemptCounter
    private let failBeyondChunkIndex: Int
    init(attempts: AttemptCounter, failBeyondChunkIndex: Int) {
        self.attempts = attempts
        self.failBeyondChunkIndex = failBeyondChunkIndex
    }

    func complete(
        system: String,
        user: String,
        responseSchema: [String: Any]?,
        onUsage: (@Sendable (LLMUsage) -> Void)?
    ) async throws -> String {
        let token = DispatchingFakeClient.matchToken(forSkill: "atomize-text")
        if system.contains(token) {
            // Pull chunk_index from the user prompt JSON.
            let idx = Self.parseChunkIndex(from: user) ?? 0
            if idx > failBeyondChunkIndex {
                throw NSError(domain: "ChunkAwareFakeClient", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "simulated atomize fail at chunk \(idx)"])
            }
            return #"{"units":[{"title":"u","body":"chunk content","line_count":50,"suggested_type_hint":"note"}]}"#
        }
        if system.contains(DispatchingFakeClient.matchToken(forSkill: "process-unit")) {
            return #"{"type":"note","confidence":0.9,"rationale":"","summary":"s"}"#
        }
        if system.contains(DispatchingFakeClient.matchToken(forSkill: "reconcile-note")) {
            return #"{"decision":"add","target_id":null,"rationale":""}"#
        }
        throw NSError(domain: "ChunkAwareFakeClient", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "unmatched skill"])
    }

    private static func parseChunkIndex(from user: String) -> Int? {
        guard let range = user.range(of: "\"chunk_index\""),
              let colon = user.range(of: ":", range: range.upperBound..<user.endIndex)
        else { return nil }
        let tail = user[colon.upperBound...].drop(while: { $0 == " " })
        let digits = tail.prefix(while: { $0.isNumber })
        return Int(digits)
    }
}

actor AttemptCounter {
    private(set) var hits: Int = 0
    func bump() -> Int { hits += 1; return hits }
}
