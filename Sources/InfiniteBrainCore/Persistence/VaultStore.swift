import Foundation
import CryptoKit

public enum VaultStoreError: Error, Equatable {
    case notFound(id: String)
    case malformed(String)
}

/// Reads and writes notes as Obsidian-compatible markdown files with YAML
/// frontmatter. The vault is the source of truth; the sidecar SQLite index
/// is a rebuildable cache.
///
/// Layout:
///   notes/<source-slug>/<type>/<id>--<slug>.md
/// Source notes use their own slugified title for the source-slug folder;
/// every atomic note created from that source goes into the same folder
/// (resolved via Note.sources[0]).
///
/// Notes with no source AND that aren't themselves a source land in the
/// legacy top-level type folder so older vaults still round-trip:
///   notes/<type>/<id>--<slug>.md
public actor VaultStore {
    public let vault: Vault
    public let metadataIndex: MetadataIndex
    private var pathCache: [String: URL] = [:]
    private var isCacheWarm = false

    public init(vault: Vault) {
        self.vault = vault
        let storeURL = vault.sidecar.appendingPathComponent("metadata.bin")
        self.metadataIndex = MetadataIndex(storeURL: storeURL)
    }

    /// Performs a full scan of the vault to warm the path cache.
    /// This should be called once at startup or when the vault changes.
    public func warmCache() async {
        guard !isCacheWarm else { return }
        let fm = FileManager.default
        let root = vault.notesRoot
        guard fm.fileExists(atPath: root.path) else {
            isCacheWarm = true; return
        }
        
        let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            let name = url.lastPathComponent
            if let dashIdx = name.range(of: "--") {
                let id = String(name[..<dashIdx.lowerBound])
                pathCache[id] = url
            }
        }
        isCacheWarm = true
    }

    public func invalidateCache() {
        pathCache.removeAll()
        isCacheWarm = false
    }

    /// Writes a note's markdown file. When the caller knows the source
    /// folder (the orchestrator does — derived from the input filename
    /// once per ingest), passing `in:` skips the per-write vault scan that
    /// would otherwise look up the source note to derive its folder name.
    /// For a 200-note book this saves 200 recursive directory walks.
    public func write(_ note: Note, in folder: String? = nil) async throws {
        let dir = try await directory(for: note, folderOverride: folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(Self.fileName(for: note))
        let serialized = NoteSerializer.serialize(note)
        try serialized.write(to: url, atomically: true, encoding: .utf8)
        pathCache[note.id] = url
        await metadataIndex.update(note)
    }

    public func read(id: String) async throws -> Note {
        guard let url = try await locateFile(forId: id) else {
            throw VaultStoreError.notFound(id: id)
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        let note = try NoteSerializer.parse(content)
        await metadataIndex.update(note)
        return note
    }

    public func delete(id: String) async throws {
        guard let url = try await locateFile(forId: id) else {
            throw VaultStoreError.notFound(id: id)
        }
        // Remove the index entry unconditionally — gating on a successful read
        // meant a corrupt/unparseable note left a dangling index entry (ghost
        // node) after its file was deleted.
        await metadataIndex.remove(noteId: id)
        try FileManager.default.removeItem(at: url)
        pathCache.removeValue(forKey: id)
    }

    public func saveMetadata() async throws {
        try await metadataIndex.save()
    }

    /// Returns every note in the vault. Walks the entire `notes/` tree
    /// recursively so it picks up both per-source layouts and any
    /// legacy-layout notes still on disk. Silently skips files that fail
    /// to parse — a single corrupted note can't take down the listing.
    public func allNotes() async throws -> [Note] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: vault.notesRoot.path) else { return [] }
        var out: [Note] = []
        let enumerator = fm.enumerator(at: vault.notesRoot, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8),
                  let note = try? NoteSerializer.parse(content) else { continue }
            await metadataIndex.update(note)
            out.append(note)
        }
        return out
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
        guard collapsed.isEmpty else { return collapsed }
        // Punctuation/emoji-only titles collapse to "". Fall back to a short
        // deterministic hash of the title so two distinct such titles never
        // share a folder (which previously commingled unrelated sources).
        let digest = SHA256.hash(data: Data(title.utf8))
        return "t-" + digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// Where to write the given note.
    ///   1. `folderOverride` wins. The orchestrator passes its
    ///      pre-computed `sourceFolder` here per ingest.
    ///   2. Source notes own their folder name (slugified title).
    ///   3. Atomic notes look up `sources[0]` to inherit its folder
    ///      (slow path — used only when no override is provided).
    ///   4. Legacy `notes/<type>/` for notes with no resolvable source.
    private func directory(for note: Note, folderOverride: String?) async throws -> URL {
        if let override = folderOverride {
            return vault.notesRoot
                .appendingPathComponent(override, isDirectory: true)
                .appendingPathComponent(note.type.rawValue, isDirectory: true)
        }
        if note.type == .source {
            let folder = Self.slugify(note.title)
            return vault.notesRoot
                .appendingPathComponent(folder, isDirectory: true)
                .appendingPathComponent(note.type.rawValue, isDirectory: true)
        }
        if let sourceId = note.sources.first,
           let sourceNote = try? await readWithoutAutoCreate(id: sourceId) {
            let folder = Self.slugify(sourceNote.title)
            return vault.notesRoot
                .appendingPathComponent(folder, isDirectory: true)
                .appendingPathComponent(note.type.rawValue, isDirectory: true)
        }
        return vault.notesRoot.appendingPathComponent(note.type.rawValue, isDirectory: true)
    }

    /// Convenience accessor so callers (Orchestrator) can ask for the
    /// canonical folder name without knowing the slugify rule.
    public static func folderName(forSourceTitle title: String) -> String {
        slugify(title)
    }

    /// Read a note by id without creating directories along the way.
    /// Used internally by `directory(for:)` to avoid recursive write loops.
    private func readWithoutAutoCreate(id: String) async throws -> Note? {
        guard let url = try await locateFile(forId: id) else { return nil }
        let content = try String(contentsOf: url, encoding: .utf8)
        return try NoteSerializer.parse(content)
    }

    /// Recursive walk of `<vault>/notes/` looking for `<id>--*.md`.
    /// Handles both new (per-source) and legacy layouts.
    private func locateFile(forId id: String) async throws -> URL? {
        if let cached = pathCache[id] { return cached }
        
        // If not in cache and cache is warm, it really doesn't exist.
        if isCacheWarm { return nil }
        
        // If cache isn't warm, do a one-off walk and warm it.
        await warmCache()
        return pathCache[id]
    }
}
