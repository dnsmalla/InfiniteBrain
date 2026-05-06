import Foundation

/// Reads and writes notes as Obsidian-compatible markdown files with YAML
/// frontmatter. The vault is the source of truth; the sidecar SQLite index is
/// a rebuildable cache.
public actor VaultStore {
    public let vault: Vault

    public init(vault: Vault) {
        self.vault = vault
    }

    public func write(_ note: Note) async throws {
        fatalError("not yet implemented")
    }

    public func read(id: String) async throws -> Note {
        fatalError("not yet implemented")
    }
}
