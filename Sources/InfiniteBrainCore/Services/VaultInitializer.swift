import Foundation

/// Seeds a vault folder on first use:
///   - creates `inbox/`, `notes/`, `.infinitebrain/` and friends
///   - copies bundled `skills/` and `rules/` into the sidecar so the user
///     can edit them per-vault
/// Idempotent: never overwrites a file the user has touched.
public struct VaultInitializer: Sendable {
    public let bundledSkills: URL?
    public let bundledRules: URL?

    public init(bundledSkills: URL? = nil, bundledRules: URL? = nil) {
        self.bundledSkills = bundledSkills ?? Bundle.module.url(forResource: "skills", withExtension: nil)
        self.bundledRules  = bundledRules  ?? Bundle.module.url(forResource: "rules",  withExtension: nil)
    }

    public func ensureSeeded(vault: Vault) throws {
        let fm = FileManager.default
        for dir in [vault.root, vault.inbox, vault.notesRoot, vault.sidecar, vault.skillsDir, vault.rulesDir,
                    vault.sidecar.appendingPathComponent("quarantine")] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        if let bundledSkills { try copyTreeIfMissing(from: bundledSkills, to: vault.skillsDir) }
        if let bundledRules  { try copyTreeIfMissing(from: bundledRules,  to: vault.rulesDir)  }
    }

    private func copyTreeIfMissing(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: src, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let item as URL in enumerator {
            let rel = item.path.replacingOccurrences(of: src.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let target = dst.appendingPathComponent(rel)
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else if !fm.fileExists(atPath: target.path) {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: item, to: target)
            }
        }
    }
}
