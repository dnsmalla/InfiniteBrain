import XCTest
@testable import SharedLLMKit

final class SkillRunnerTests: XCTestCase {
    func testRunsSkillAndValidatesOutput() async throws {
        let skillsRoot = try Self.makeSkill(
            name: "classify",
            body: """
            ---
            name: classify
            description: test classifier
            outputs:
              type: string
              confidence: number
            ---
            Pick a type.
            """
        )
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        let fake = FakeLLMClient(responses: [
            #"{"type": "decision", "confidence": 0.91}"#
        ])
        let runner = SkillRunner(client: fake, skillsRoot: skillsRoot)

        let result = try await runner.run("classify", input: ["text": "decided to drop free tier"])

        XCTAssertEqual(result["type"] as? String, "decision")
        XCTAssertEqual((result["confidence"] as? NSNumber)?.doubleValue ?? -1, 0.91, accuracy: 0.0001)
        let calls = await fake.snapshot()
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(calls[0].system.contains("Pick a type."))
        XCTAssertTrue(calls[0].user.contains("decided to drop free tier"))
    }

    func testRetriesOnceOnInvalidJSON() async throws {
        let skillsRoot = try Self.makeSkill(
            name: "classify",
            body: """
            ---
            name: classify
            description: test
            outputs:
              type: string
            ---
            body
            """
        )
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        let fake = FakeLLMClient(responses: [
            "not json at all",
            #"{"type": "decision"}"#,
        ])
        let runner = SkillRunner(client: fake, skillsRoot: skillsRoot)

        let result = try await runner.run("classify", input: [:])
        XCTAssertEqual(result["type"] as? String, "decision")
        let calls = await fake.snapshot()
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls[1].user.contains("previous output failed"),
                      "retry must include the validation failure")
    }

    func testRaisesAfterRetryStillFails() async throws {
        let skillsRoot = try Self.makeSkill(
            name: "classify",
            body: """
            ---
            name: classify
            description: test
            outputs:
              type: string
            ---
            body
            """
        )
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        let fake = FakeLLMClient(responses: ["nope", "still bad"])
        let runner = SkillRunner(client: fake, skillsRoot: skillsRoot)

        do {
            _ = try await runner.run("classify", input: [:])
            XCTFail("expected throw")
        } catch SkillRunnerError.outputInvalidAfterRetry {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    private static func makeSkill(name: String, body: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ib-skills-\(UUID().uuidString)", isDirectory: true)
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try body.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return root
    }
}

actor FakeLLMClient: LLMClient {
    struct Call: Sendable { let system: String; let user: String }
    private var responses: [String]
    private var calls: [Call] = []

    init(responses: [String]) { self.responses = responses }

    func complete(system: String, user: String, responseSchema: [String: Any]?,
                  onUsage: (@Sendable (LLMUsage) -> Void)? = nil) async throws -> String {
        calls.append(Call(system: system, user: user))
        guard !responses.isEmpty else {
            throw NSError(domain: "FakeLLMClient", code: 0)
        }
        return responses.removeFirst()
    }

    func snapshot() -> [Call] { calls }
}
