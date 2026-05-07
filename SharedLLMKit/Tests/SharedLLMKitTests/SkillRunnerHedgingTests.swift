import XCTest
@testable import SharedLLMKit

/// quality-bar.mdc requires SkillRunner to reject outputs containing hedging
/// boilerplate ("as an AI", "this note discusses", …) and trigger a retry.
final class SkillRunnerHedgingTests: XCTestCase {
    func testRejectsHedgingOutputAndRetries() async throws {
        let skillsRoot = try Self.makeSkill(name: "summ", body: """
        ---
        name: summ
        description: test
        outputs:
          summary: string
        ---
        Write a one-sentence summary.
        """)
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        let fake = SequenceClient(responses: [
            #"{"summary":"As an AI assistant, I will summarize this for you."}"#,  // hedging
            #"{"summary":"Stripe charges 2.9% + $0.30 per transaction."}"#,         // clean
        ])
        let runner = SkillRunner(client: fake, skillsRoot: skillsRoot)

        let result = try await runner.run("summ", input: ["body": "x"])
        XCTAssertEqual(result["summary"] as? String, "Stripe charges 2.9% + $0.30 per transaction.")
        let calls = await fake.snapshot()
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls[1].user.contains("hedging"),
                      "retry must mention the hedging failure so the model fixes it")
    }

    func testThrowsAfterRetryStillHedges() async throws {
        let skillsRoot = try Self.makeSkill(name: "summ", body: """
        ---
        name: summ
        description: test
        outputs:
          summary: string
        ---
        body
        """)
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        let fake = SequenceClient(responses: [
            #"{"summary":"This note discusses pricing."}"#,
            #"{"summary":"As an AI, I cannot help."}"#,
        ])
        let runner = SkillRunner(client: fake, skillsRoot: skillsRoot)
        do {
            _ = try await runner.run("summ", input: [:])
            XCTFail("expected throw")
        } catch SkillRunnerError.outputInvalidAfterRetry {
            // ok
        }
    }

    func testCleanOutputPassesThrough() async throws {
        let skillsRoot = try Self.makeSkill(name: "summ", body: """
        ---
        name: summ
        description: test
        outputs:
          summary: string
        ---
        body
        """)
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        let fake = SequenceClient(responses: [
            #"{"summary":"Stripe charges 2.9% + $0.30."}"#,
        ])
        let runner = SkillRunner(client: fake, skillsRoot: skillsRoot)
        let r = try await runner.run("summ", input: [:])
        XCTAssertEqual(r["summary"] as? String, "Stripe charges 2.9% + $0.30.")
        let calls = await fake.snapshot()
        XCTAssertEqual(calls.count, 1, "clean output must not retry")
    }

    private static func makeSkill(name: String, body: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ib-skills-hedge-\(UUID().uuidString)", isDirectory: true)
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try body.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return root
    }
}

actor SequenceClient: LLMClient {
    struct Call: Sendable { let system: String; let user: String }
    private var queue: [String]
    private(set) var calls: [Call] = []
    init(responses: [String]) { self.queue = responses }

    func complete(system: String, user: String, responseSchema: [String: Any]?) async throws -> String {
        calls.append(Call(system: system, user: user))
        guard !queue.isEmpty else {
            throw NSError(domain: "SequenceClient", code: 0)
        }
        return queue.removeFirst()
    }
    func snapshot() -> [Call] { calls }
}
