import XCTest
@testable import InfiniteBrain
@testable import SharedLLMKit

/// A long input must be chunked and processed in multiple atomize-text calls,
/// so a 500-page book doesn't (a) blow the API context window or (b) silently
/// truncate to ~10 notes against max_tokens. Conversely, a tiny input must
/// still result in just one atomize call.
final class LongInputIngestTests: XCTestCase {
    func testLongInputProducesManyNotesViaChunking() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }

        // Build a 50,000-char document with paragraph boundaries.
        let bigDoc = (1...500).map { i in
            "Paragraph \(i) discusses an idea worth a separate atomic note. " +
            String(repeating: "x", count: 80)
        }.joined(separator: "\n\n")
        XCTAssertGreaterThan(bigDoc.count, 50_000, "test fixture must be large")
        try FileManager.default.createDirectory(at: vault.inbox, withIntermediateDirectories: true)
        let f = vault.inbox.appendingPathComponent("book.txt")
        try bigDoc.write(to: f, atomically: true, encoding: .utf8)

        // Each atomize call returns one unit. With chunkSize=16_000 → ~4 calls.
        let routes: [String: String] = [
            "atomize-text":   #"{"units":[{"title":"chunk-piece","body":"chunk piece body","line_count":50,"suggested_type_hint":"note"}]}"#,
            "classify-node":  #"{"type":"note","confidence":0.9,"rationale":""}"#,
            "summarize-note": #"{"summary":"piece"}"#,
            "reconcile-note": #"{"decision":"add","target_id":null,"rationale":"new"}"#,
        ]
        let capture = PromptCapture()
        let client = CapturingDispatchClient(routes: routes, capture: capture)
        let orch = Orchestrator(
            skillRunner: SkillRunner(client: client, skillsRoot: TestPaths.bundledSkills),
            idGenerator: ULIDGenerator(),
            dateProvider: FixedDateProvider(date: Date()),
            chunkSize: 16_000
        )

        let result = try await orch.ingest(file: f, into: vault)

        let atomizeCalls = await capture.prompts(matching: "convert a chunk of long-form text")
        XCTAssertGreaterThan(atomizeCalls.count, 1,
                             "long input must trigger multiple atomize calls (got \(atomizeCalls.count))")
        XCTAssertEqual(result.added, atomizeCalls.count,
                       "one unit per chunk → one note per chunk")
    }

    func testShortInputStillUsesOnlyOneAtomizeCall() async throws {
        let vault = try TestVault.make()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        try FileManager.default.createDirectory(at: vault.inbox, withIntermediateDirectories: true)
        let f = vault.inbox.appendingPathComponent("memo.txt")
        try "A short paragraph about something specific.".write(to: f, atomically: true, encoding: .utf8)

        let routes: [String: String] = [
            "atomize-text":   #"{"units":[{"title":"x","body":"short","line_count":50,"suggested_type_hint":"note"}]}"#,
            "classify-node":  #"{"type":"note","confidence":0.9,"rationale":""}"#,
            "summarize-note": #"{"summary":"x"}"#,
            "reconcile-note": #"{"decision":"add","target_id":null,"rationale":"new"}"#,
        ]
        let capture = PromptCapture()
        let client = CapturingDispatchClient(routes: routes, capture: capture)
        let orch = Orchestrator(
            skillRunner: SkillRunner(client: client, skillsRoot: TestPaths.bundledSkills),
            chunkSize: 16_000
        )
        _ = try await orch.ingest(file: f, into: vault)
        let atomizeCalls = await capture.prompts(matching: "convert a chunk of long-form text")
        XCTAssertEqual(atomizeCalls.count, 1)
    }
}
