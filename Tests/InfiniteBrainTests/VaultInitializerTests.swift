import XCTest
@testable import InfiniteBrain

final class VaultInitializerTests: XCTestCase {
    func testCopiesBundledSkillsAndRulesIntoVaultSidecar() throws {
        let vault = try Self.makeVault()
        defer { try? FileManager.default.removeItem(at: vault.root) }

        let init_ = VaultInitializer(bundledSkills: Self.bundledSkills, bundledRules: Self.bundledRules)
        try init_.ensureSeeded(vault: vault)

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: vault.skillsDir.appendingPathComponent("classify-node/SKILL.md").path))
        XCTAssertTrue(fm.fileExists(atPath: vault.rulesDir.appendingPathComponent("output-format.mdc").path))
        XCTAssertTrue(fm.fileExists(atPath: vault.inbox.path))
        XCTAssertTrue(fm.fileExists(atPath: vault.notesRoot.path))
    }

    func testDoesNotOverwriteUserEditedSkill() throws {
        let vault = try Self.makeVault()
        defer { try? FileManager.default.removeItem(at: vault.root) }

        let init_ = VaultInitializer(bundledSkills: Self.bundledSkills, bundledRules: Self.bundledRules)
        try init_.ensureSeeded(vault: vault)

        let userEdit = vault.skillsDir.appendingPathComponent("classify-node/SKILL.md")
        try "USER-EDITED CONTENT".write(to: userEdit, atomically: true, encoding: .utf8)

        try init_.ensureSeeded(vault: vault)  // second call must be idempotent
        let after = try String(contentsOf: userEdit, encoding: .utf8)
        XCTAssertEqual(after, "USER-EDITED CONTENT", "must not overwrite user-edited skill")
    }

    private static func makeVault() throws -> Vault {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ib-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Vault(root: root)
    }

    private static var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent(); url.deleteLastPathComponent(); url.deleteLastPathComponent()
        return url
    }
    private static var bundledSkills: URL { repoRoot.appendingPathComponent("Sources/InfiniteBrain/Resources/skills") }
    private static var bundledRules:  URL { repoRoot.appendingPathComponent("Sources/InfiniteBrain/Resources/rules") }
}
