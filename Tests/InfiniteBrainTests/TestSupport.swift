import Foundation
import XCTest
@testable import InfiniteBrain
@testable import SharedLLMKit

// Shared test helpers. Single source of truth for fixtures and fakes used
// across the InfiniteBrain test target.

enum TestPaths {
    /// Repo root, derived from this file's path. Tests run from
    /// .build/.../debug, so we anchor on #filePath rather than CWD.
    static var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()  // InfiniteBrainTests/
        url.deleteLastPathComponent()  // Tests/
        url.deleteLastPathComponent()  // repo root
        return url
    }

    static var bundledSkills: URL {
        repoRoot.appendingPathComponent("Sources/InfiniteBrain/Resources/skills", isDirectory: true)
    }

    static var bundledRules: URL {
        repoRoot.appendingPathComponent("Sources/InfiniteBrain/Resources/rules", isDirectory: true)
    }
}

enum TestVault {
    /// Creates an empty vault folder under the system temp dir.
    static func make() throws -> Vault {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ib-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Vault(root: root)
    }
}

// MARK: - Test fakes

/// LLMClient that dispatches by skill body markers, ignoring user input.
actor DispatchingFakeClient: LLMClient {
    private let routes: [String: String]
    init(routes: [String: String]) { self.routes = routes }

    func complete(system: String, user: String, responseSchema: [String: Any]?) async throws -> String {
        for (key, value) in routes where system.contains(Self.matchToken(forSkill: key)) {
            return value
        }
        throw NSError(domain: "DispatchingFakeClient", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "no route matched system prompt"])
    }

    /// Unique substring guaranteed to appear in each bundled skill's body.
    static func matchToken(forSkill name: String) -> String {
        switch name {
        case "atomize-text":    return "convert a chunk of long-form text"
        case "classify-node":   return "Pick exactly one type"
        case "summarize-note":  return "Write a single English sentence"
        case "reconcile-note":  return "Compare the candidate against"
        case "improve-note":    return "Produce an improved version"
        case "infer-edges":     return "You connect a new note"
        case "answer-question": return "Answer the user's `question`"
        default: return name
        }
    }
}

/// Records every (system, user) it sees so tests can assert on prompts.
actor PromptCapture {
    private(set) var calls: [(system: String, user: String)] = []
    func record(system: String, user: String) { calls.append((system, user)) }
    func prompts(matching needle: String) -> [String] {
        calls.filter { $0.system.contains(needle) }.map(\.user)
    }
}

/// Like DispatchingFakeClient but routes capture every prompt.
actor CapturingDispatchClient: LLMClient {
    private let routes: [String: String]
    private let capture: PromptCapture
    init(routes: [String: String], capture: PromptCapture) {
        self.routes = routes; self.capture = capture
    }
    func complete(system: String, user: String, responseSchema: [String: Any]?) async throws -> String {
        await capture.record(system: system, user: user)
        for (key, value) in routes where system.contains(DispatchingFakeClient.matchToken(forSkill: key)) {
            return value
        }
        throw NSError(domain: "CapturingDispatchClient", code: 1)
    }
}

/// Hands out a pre-baked list of ids in order, falling back to a synthesised
/// id once the list runs out so tests don't crash on incidental extra calls.
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

/// Deterministic embedding for tests: same text → same vector, different
/// text → different vector. Just enough to verify wiring without depending
/// on Apple's NLEmbedding model being installed.
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

/// Test double for KeychainStore.
final class InMemoryKeychain: KeychainStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()
    func get(_ key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }; return storage[key]
    }
    func set(_ value: String?, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        if let value { storage[key] = value } else { storage.removeValue(forKey: key) }
    }
}
