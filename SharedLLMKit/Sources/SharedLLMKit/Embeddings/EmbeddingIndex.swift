import Foundation

/// In-memory map of `id → vector`, persisted as JSON. Brute-force cosine for
/// nearest-K. Adequate for personal-vault sizes (≤ ~50k notes); swap for
/// SQLite + ANN if scale demands it.
public actor EmbeddingIndex {
    public struct Hit: Equatable, Sendable {
        public let id: String
        public let score: Float
    }

    public let storeURL: URL
    private var vectors: [String: [Float]] = [:]
    private var dirty: Bool = false

    public init(storeURL: URL) {
        self.storeURL = storeURL
    }

    public func record(id: String, vector: [Float]) {
        vectors[id] = vector
        dirty = true
    }

    public func remove(id: String) {
        if vectors.removeValue(forKey: id) != nil { dirty = true }
    }

    public func nearest(to query: [Float], k: Int) -> [Hit] {
        guard !vectors.isEmpty, k > 0 else { return [] }
        let qNorm = Self.norm(query)
        guard qNorm > 0 else { return [] }
        let scored = vectors.map { id, v -> Hit in
            let n = Self.norm(v)
            guard n > 0 else { return Hit(id: id, score: -.infinity) }
            return Hit(id: id, score: Self.dot(query, v) / (qNorm * n))
        }
        return scored.sorted { $0.score > $1.score }.prefix(k).map { $0 }
    }

    public func load() throws {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }
        let data = try Data(contentsOf: storeURL)
        vectors = try JSONDecoder().decode([String: [Float]].self, from: data)
        dirty = false
    }

    public func flush() throws {
        guard dirty else { return }
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(vectors)
        try data.write(to: storeURL, options: .atomic)
        dirty = false
    }

    // MARK: - Vector math

    private static func dot(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        var s: Float = 0
        for i in 0..<n { s += a[i] * b[i] }
        return s
    }

    private static func norm(_ v: [Float]) -> Float {
        var s: Float = 0
        for x in v { s += x * x }
        return s.squareRoot()
    }
}
