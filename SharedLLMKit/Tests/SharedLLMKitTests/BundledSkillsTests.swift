import XCTest
@testable import SharedLLMKit

/// End-to-end sanity check: every SKILL.md committed in the project must
/// parse and declare a name, description, and outputs schema. If a future
/// edit to a SKILL.md breaks the format, this fails first.
final class BundledSkillsTests: XCTestCase {
    func testEveryBundledSkillParses() throws {
        let skillsDir = Self.repoRoot
            .appendingPathComponent("Sources/InfiniteBrainCore/Resources/skills", isDirectory: true)

        let entries = try FileManager.default.contentsOfDirectory(
            at: skillsDir, includingPropertiesForKeys: nil)
        let dirs = entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

        XCTAssertGreaterThan(dirs.count, 0, "no skill folders found")

        for dir in dirs {
            let file = dir.appendingPathComponent("SKILL.md")
            let skill = try Skill.parse(at: file)
            XCTAssertFalse(skill.manifest.name.isEmpty, "\(dir.lastPathComponent): empty name")
            XCTAssertFalse(skill.manifest.description.isEmpty, "\(dir.lastPathComponent): empty description")
            XCTAssertNotNil(skill.manifest.outputs, "\(dir.lastPathComponent): no outputs declared")
            XCTAssertFalse(skill.body.isEmpty, "\(dir.lastPathComponent): empty body")
        }
    }

    /// Walks up from the test binary location to the InfiniteBrain repo root.
    private static var repoRoot: URL {
        // Tests run from .build/.../debug → walk up to a dir containing Package.swift
        // for InfiniteBrain (not the SharedLLMKit one).
        var url = URL(fileURLWithPath: #filePath)
        // #filePath is .../SharedLLMKit/Tests/SharedLLMKitTests/BundledSkillsTests.swift
        // → repoRoot is three levels up from the file's parent.
        url.deleteLastPathComponent()  // SharedLLMKitTests/
        url.deleteLastPathComponent()  // Tests/
        url.deleteLastPathComponent()  // SharedLLMKit/
        url.deleteLastPathComponent()  // InfiniteBrain/ (repo root)
        return url
    }
}
