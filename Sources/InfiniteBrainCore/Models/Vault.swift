import Foundation

/// Represents an Obsidian-compatible vault on disk.
public struct Vault: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }
    public var inbox: URL { root.appendingPathComponent("inbox", isDirectory: true) }
    public var notesRoot: URL { root.appendingPathComponent("notes", isDirectory: true) }
    public var sidecar: URL { root.appendingPathComponent(".infinitebrain", isDirectory: true) }
    public var indexDB: URL { sidecar.appendingPathComponent("index.db") }
    public var skillsDir: URL { sidecar.appendingPathComponent("skills", isDirectory: true) }
    public var rulesDir: URL { sidecar.appendingPathComponent("rules", isDirectory: true) }
    /// Canonical embedding-index location. Single source of truth so the app
    /// and the `infb` CLI read/write the same file (they previously diverged
    /// between `embeddings.bin` and `embeddings.json`).
    public var embeddingIndexURL: URL { sidecar.appendingPathComponent("embeddings.bin") }
}
