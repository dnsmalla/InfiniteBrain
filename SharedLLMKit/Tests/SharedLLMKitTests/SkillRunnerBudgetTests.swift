import XCTest
@testable import SharedLLMKit

/// When a SKILL.md declares max_input_chars, SkillRunner must enforce it: the
/// user prompt actually sent to the LLM is capped, with a truncation marker
/// telling the model that some input was dropped.
final class SkillRunnerBudgetTests: XCTestCase {
    func testTruncatesOversizedUserPrompt() async throws {
        let skillsRoot = try Self.makeSkill(
            name: "tight",
            body: """
            ---
            name: tight
            description: budget test
            max_input_chars: 200
            outputs:
              ok: string
            ---
            body
            """
        )
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        let fake = CapturingClient(response: #"{"ok":"y"}"#)
        let runner = SkillRunner(client: fake, skillsRoot: skillsRoot)

        let huge = String(repeating: "x", count: 10_000)
        _ = try await runner.run("tight", input: ["body": huge])

        let calls = await fake.snapshot()
        XCTAssertEqual(calls.count, 1)
        XCTAssertLessThanOrEqual(calls[0].user.count, 220, "user prompt must be at most cap + a small marker")
        XCTAssertTrue(calls[0].user.contains("[truncated]"), "must mark truncation so the model knows")
    }

    func testNoCapMeansNoTruncation() async throws {
        let skillsRoot = try Self.makeSkill(
            name: "loose",
            body: """
            ---
            name: loose
            description: no cap
            outputs:
              ok: string
            ---
            body
            """
        )
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        let fake = CapturingClient(response: #"{"ok":"y"}"#)
        let runner = SkillRunner(client: fake, skillsRoot: skillsRoot)

        let big = String(repeating: "y", count: 5_000)
        _ = try await runner.run("loose", input: ["body": big])

        let calls = await fake.snapshot()
        XCTAssertEqual(calls.count, 1)
        XCTAssertGreaterThan(calls[0].user.count, 5_000)
        XCTAssertFalse(calls[0].user.contains("[truncated]"))
    }

    private static func makeSkill(name: String, body: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ib-skills-budget-\(UUID().uuidString)", isDirectory: true)
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try body.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return root
    }
}

actor CapturingClient: LLMClient {
    struct Call: Sendable { let system: String; let user: String }
    private(set) var calls: [Call] = []
    private let response: String
    init(response: String) { self.response = response }

    func complete(system: String, user: String, responseSchema: [String: Any]?,
                  onUsage: (@Sendable (LLMUsage) -> Void)? = nil) async throws -> String {
        calls.append(Call(system: system, user: user))
        return response
    }
    func snapshot() -> [Call] { calls }
}
