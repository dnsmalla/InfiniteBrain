import XCTest
@testable import SharedLLMKit

final class SkillParseTests: XCTestCase {
    func testParsesFrontmatterAndBody() throws {
        let content = """
        ---
        name: classify-node
        description: Assigns one of 16 node types to an atomic unit.
        model: claude-sonnet-4-6
        inputs:
          unit_title: string
          unit_body: string
        outputs:
          type: enum
          confidence: number
        ---

        # Role

        Pick exactly one type.
        """
        let url = try Self.write(content, name: "classify-node-test.md")
        defer { try? FileManager.default.removeItem(at: url) }

        let skill = try Skill.parse(at: url)

        XCTAssertEqual(skill.manifest.name, "classify-node")
        XCTAssertEqual(skill.manifest.description, "Assigns one of 16 node types to an atomic unit.")
        XCTAssertEqual(skill.manifest.model, "claude-sonnet-4-6")
        XCTAssertEqual(skill.manifest.inputs?["unit_title"], "string")
        XCTAssertEqual(skill.manifest.outputs?["type"], "enum")
        XCTAssertEqual(skill.manifest.outputs?["confidence"], "number")
        XCTAssertTrue(skill.body.contains("# Role"))
        XCTAssertTrue(skill.body.contains("Pick exactly one type."))
        XCTAssertFalse(skill.body.contains("---"))
    }

    func testRejectsFileMissingFrontmatter() throws {
        let url = try Self.write("just a body, no fences", name: "no-frontmatter.md")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try Skill.parse(at: url)) { err in
            guard case SkillParseError.missingFrontmatter = err else {
                return XCTFail("wrong error: \(err)")
            }
        }
    }

    private static func write(_ content: String, name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("infinitebrain-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
