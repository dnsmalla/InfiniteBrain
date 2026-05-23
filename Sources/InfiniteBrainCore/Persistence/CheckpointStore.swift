import Foundation

/// Per-file ingest progress record. Tracks which chunks have been fully
/// processed (atomized → decided → written). Lets a re-run after a Stop
/// click or a crash pick up only the missing chunks.
public struct Checkpoint: Codable, Sendable, Equatable {
    public let fileHash: String
    public let sourceId: String
    public var chunkCount: Int
    public var completedChunks: Set<Int>

    public init(fileHash: String, sourceId: String, chunkCount: Int, completedChunks: Set<Int> = []) {
        self.fileHash = fileHash
        self.sourceId = sourceId
        self.chunkCount = chunkCount
        self.completedChunks = completedChunks
    }

    public var isComplete: Bool {
        chunkCount > 0 && completedChunks.count == chunkCount
    }

    public var pendingChunkIndices: [Int] {
        (0..<chunkCount).filter { !completedChunks.contains($0) }
    }
}

/// Reads/writes Checkpoint values to `<vault>/.infinitebrain/checkpoints/`.
/// Atomic writes per save so a crash mid-write can't corrupt the record.
public actor CheckpointStore {
    public let vault: Vault
    public init(vault: Vault) { self.vault = vault }

    public func load(fileHash: String) async throws -> Checkpoint? {
        let url = path(for: fileHash)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try? JSONDecoder().decode(Checkpoint.self, from: data)
    }

    public func save(_ checkpoint: Checkpoint) async throws {
        let dir = vault.sidecar.appendingPathComponent("checkpoints", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(checkpoint)
        try data.write(to: path(for: checkpoint.fileHash), options: .atomic)
    }

    /// Mark a chunk index as complete and persist atomically. Returns the
    /// updated checkpoint.
    public func markChunkComplete(fileHash: String, chunkIndex: Int) async throws -> Checkpoint? {
        guard var current = try await load(fileHash: fileHash) else { return nil }
        current.completedChunks.insert(chunkIndex)
        try await save(current)
        return current
    }

    public func delete(fileHash: String) async throws {
        let url = path(for: fileHash)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func path(for hash: String) -> URL {
        let safe = hash.replacingOccurrences(of: "/", with: "_")
        return vault.sidecar.appendingPathComponent("checkpoints/\(safe).json")
    }
}
