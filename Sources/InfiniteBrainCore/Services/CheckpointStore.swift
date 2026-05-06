import Foundation

/// Per-file ingest checkpoint. Captures everything needed to resume an
/// in-progress ingest after a crash without re-running atomize-text or
/// re-assigning ids.
public struct Checkpoint: Codable, Sendable, Equatable {
    public struct Unit: Codable, Sendable, Equatable {
        public let title: String
        public let body: String
        public let lineCount: Int?
        public let suggestedTypeHint: String?

        public init(title: String, body: String, lineCount: Int?, suggestedTypeHint: String?) {
            self.title = title
            self.body = body
            self.lineCount = lineCount
            self.suggestedTypeHint = suggestedTypeHint
        }
    }

    public let fileHash: String
    public let sourceId: String
    public let units: [Unit]
    public let reservedIds: [String]
    public var completedThrough: Int   // number of units fully applied

    public init(fileHash: String, sourceId: String, units: [Unit], reservedIds: [String], completedThrough: Int) {
        self.fileHash = fileHash
        self.sourceId = sourceId
        self.units = units
        self.reservedIds = reservedIds
        self.completedThrough = completedThrough
    }
}

/// Reads/writes Checkpoint values to `<vault>/.infinitebrain/checkpoints/`.
public actor CheckpointStore {
    public let vault: Vault
    public init(vault: Vault) { self.vault = vault }

    public func load(fileHash: String) async throws -> Checkpoint? {
        let url = path(for: fileHash)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Checkpoint.self, from: data)
    }

    public func save(_ checkpoint: Checkpoint) async throws {
        let dir = vault.sidecar.appendingPathComponent("checkpoints", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(checkpoint)
        try data.write(to: path(for: checkpoint.fileHash), options: .atomic)
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
