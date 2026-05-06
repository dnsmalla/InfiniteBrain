import Foundation

public enum VaultStoreError: Error, Equatable {
    case notFound(id: String)
    case malformed(String)
}

/// Reads and writes notes as Obsidian-compatible markdown files with YAML
/// frontmatter. The vault is the source of truth; the sidecar SQLite index is
/// a rebuildable cache.
public actor VaultStore {
    public let vault: Vault

    public init(vault: Vault) {
        self.vault = vault
    }

    public func write(_ note: Note) async throws {
        let dir = vault.notesRoot.appendingPathComponent(note.type.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(Self.fileName(for: note))
        let serialized = NoteSerializer.serialize(note)
        try serialized.write(to: url, atomically: true, encoding: .utf8)
    }

    public func read(id: String) async throws -> Note {
        guard let url = try locateFile(forId: id) else {
            throw VaultStoreError.notFound(id: id)
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        return try NoteSerializer.parse(content)
    }

    // MARK: - Path conventions

    static func fileName(for note: Note) -> String {
        "\(note.id)--\(slugify(note.title)).md"
    }

    static func slugify(_ title: String) -> String {
        let lowered = title.lowercased()
        let mapped = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return "-"
        }
        let collapsed = String(mapped).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return collapsed
    }

    private func locateFile(forId id: String) throws -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: vault.notesRoot.path) else { return nil }
        let typeDirs = try fm.contentsOfDirectory(at: vault.notesRoot, includingPropertiesForKeys: nil)
        for dir in typeDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            for f in files where f.lastPathComponent.hasPrefix("\(id)--") && f.pathExtension == "md" {
                return f
            }
        }
        return nil
    }
}
