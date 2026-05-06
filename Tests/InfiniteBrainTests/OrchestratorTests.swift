import XCTest
@testable import InfiniteBrain
@testable import SharedLLMKit

final class OrchestratorTests: XCTestCase {
    func testIngestsTextFileAndWritesNotes() async throws {
        let vault = try Self.makeVault()
        defer { try? FileManager.default.removeItem(at: vault.root) }

        // Drop a text file in the inbox.
        let input = vault.inbox.appendingPathComponent("memo.txt")
        try FileManager.default.createDirectory(at: vault.inbox, withIntermediateDirectories: true)
        try "We decided to drop the free tier on the Indie plan.".write(to: input, atomically: true, encoding: .utf8)

        // Skills root mirrors the bundled layout.
        let skillsRoot = Self.bundledSkillsRoot

        let fake = DispatchingFakeClient(routes: [
            "atomize-text":    #"{"units":[{"title":"No free tier","body":"We decided to drop the free tier on the Indie plan.","line_count":52,"suggested_type_hint":"decision"}]}"#,
            "classify-node":   #"{"type":"decision","confidence":0.93,"rationale":"clear choice"}"#,
            "summarize-note":  #"{"summary":"We will not offer a free tier on the Indie plan."}"#,
            "reconcile-note":  #"{"decision":"add","target_id":null,"rationale":"new topic"}"#,
        ])

        let orchestrator = Orchestrator(
            skillRunner: SkillRunner(client: fake, skillsRoot: skillsRoot),
            idGenerator: FixedIDGenerator(ids: ["01JNOTE000000000000000001", "01JSRC000000000000000002"]),
            dateProvider: FixedDateProvider(date: Date(timeIntervalSince1970: 1_700_000_000))
        )

        let result = try await orchestrator.ingest(file: input, into: vault)

        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.improved, 0)
        XCTAssertEqual(result.skipped, 0)

        let store = VaultStore(vault: vault)
        let written = try await store.read(id: "01JNOTE000000000000000001")
        XCTAssertEqual(written.type, .decision)
        XCTAssertEqual(written.title, "No free tier")
        XCTAssertEqual(written.summary, "We will not offer a free tier on the Indie plan.")
        XCTAssertTrue(written.body.contains("free tier"))
        XCTAssertEqual(written.version, 1)
    }

    func testReconcilerSkipDecisionDoesNotWriteNote() async throws {
        let vault = try Self.makeVault()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        let input = vault.inbox.appendingPathComponent("memo.txt")
        try FileManager.default.createDirectory(at: vault.inbox, withIntermediateDirectories: true)
        try "Already-known content.".write(to: input, atomically: true, encoding: .utf8)

        let fake = DispatchingFakeClient(routes: [
            "atomize-text":   #"{"units":[{"title":"x","body":"already-known content","line_count":50,"suggested_type_hint":"note"}]}"#,
            "classify-node":  #"{"type":"note","confidence":0.8,"rationale":""}"#,
            "summarize-note": #"{"summary":"already-known."}"#,
            "reconcile-note": #"{"decision":"skip","target_id":"01JEXISTING0000000000000","rationale":"dup"}"#,
        ])

        let orchestrator = Orchestrator(
            skillRunner: SkillRunner(client: fake, skillsRoot: Self.bundledSkillsRoot),
            idGenerator: FixedIDGenerator(ids: ["01JNEW000000000000000099"]),
            dateProvider: FixedDateProvider(date: Date())
        )

        let result = try await orchestrator.ingest(file: input, into: vault)
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.skipped, 1)

        // No note file should exist.
        let typeDirs = (try? FileManager.default.contentsOfDirectory(at: vault.notesRoot, includingPropertiesForKeys: nil)) ?? []
        let total = typeDirs.flatMap { (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
        XCTAssertTrue(total.isEmpty, "no note files should be written on skip")
    }

    private static func makeVault() throws -> Vault {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ib-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Vault(root: root)
    }

    private static var bundledSkillsRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()  // InfiniteBrainTests/
        url.deleteLastPathComponent()  // Tests/
        url.deleteLastPathComponent()  // repo root
        return url.appendingPathComponent("Sources/InfiniteBrain/Resources/skills", isDirectory: true)
    }
}

// MARK: - Fakes

actor DispatchingFakeClient: LLMClient {
    private let routes: [String: String]
    init(routes: [String: String]) { self.routes = routes }

    func complete(system: String, user: String, responseSchema: [String: Any]?) async throws -> String {
        for (key, value) in routes {
            if system.range(of: matchToken(forSkill: key)) != nil {
                return value
            }
        }
        throw NSError(domain: "DispatchingFakeClient", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "no route matched system prompt"])
    }

    /// A unique substring guaranteed to appear in each skill's bundled body.
    private func matchToken(forSkill name: String) -> String {
        switch name {
        case "atomize-text":   return "convert long-form text into atomic units"
        case "classify-node":  return "Pick exactly one type"
        case "summarize-note": return "Write a single English sentence"
        case "reconcile-note": return "Compare the candidate against"
        case "improve-note":   return "Produce an improved version"
        case "infer-edges":    return "You connect a new note"
        case "extract-pdf":    return "Take per-page raw text"
        case "query-brain":    return "Two-pass retrieval"
        case "answer-question":return "Answer the user's `question`"
        default: return name
        }
    }
}

struct FixedIDGenerator: IDGenerator {
    let ids: [String]
    private let counter = Counter()
    func next() -> String {
        let i = counter.bump()
        return i < ids.count ? ids[i] : "01J\(String(format: "%023d", i))"
    }
    final class Counter: @unchecked Sendable {
        private var n = -1
        private let lock = NSLock()
        func bump() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
    }
}

struct FixedDateProvider: DateProvider {
    let date: Date
    func now() -> Date { date }
}
