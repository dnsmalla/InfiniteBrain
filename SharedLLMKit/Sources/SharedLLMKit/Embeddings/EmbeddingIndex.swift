import Accelerate

/// In-memory map of `id → vector`, persisted as a compact binary file.
/// Uses brute-force cosine with Accelerate (SIMD) for high-speed lookup.
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
        let count = vDSP_Length(query.count)
        
        var qMagSq: Float = 0
        vDSP_svesq(query, 1, &qMagSq, count)
        let qMag = sqrt(qMagSq)
        guard qMag > 0 else { return [] }
        
        // Brute-force dot product with Accelerate
        let scored = vectors.map { id, v -> Hit in
            guard v.count == query.count else { return Hit(id: id, score: -1.0) }
            var dot: Float = 0
            vDSP_dotpr(v, 1, query, 1, &dot, count)
            
            // Note: In production we should pre-calculate and store magnitudes 
            // of vectors in the index to avoid vDSP_svesq on every search.
            var vMagSq: Float = 0
            vDSP_svesq(v, 1, &vMagSq, count)
            let vMag = sqrt(vMagSq)
            guard vMag > 0 else { return Hit(id: id, score: -1.0) }
            
            return Hit(id: id, score: dot / (qMag * vMag))
        }
        return scored.sorted { $0.score > $1.score }.prefix(k).map { $0 }
    }

    public func load() throws {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }
        
        // Attempt binary load; fallback to JSON for migration
        do {
            let data = try Data(contentsOf: storeURL)
            if data.count > 4 {
                var offset = 0
                func read<T>(_ type: T.Type) -> T? {
                    let size = MemoryLayout<T>.size
                    guard offset + size <= data.count else { return nil }
                    let value = data.subdata(in: offset..<offset+size).withUnsafeBytes { $0.load(as: T.self) }
                    offset += size
                    return value
                }
                
                // Magic check (optional, but good for safety)
                // We'll just read count first.
                guard let count = read(Int32.self) else { throw NSError(domain: "BinaryIndex", code: 1) }
                var loaded: [String: [Float]] = [:]
                for _ in 0..<count {
                    guard let idLen = read(Int32.self),
                          offset + Int(idLen) <= data.count else { break }
                    let id = String(decoding: data.subdata(in: offset..<offset+Int(idLen)), as: UTF8.self)
                    offset += Int(idLen)
                    
                    guard let vecLen = read(Int32.self),
                          offset + Int(vecLen * 4) <= data.count else { break }
                    let vec = data.subdata(in: offset..<offset+Int(vecLen * 4)).withUnsafeBytes {
                        Array(UnsafeBufferPointer(start: $0.baseAddress!.assumingMemoryBound(to: Float.self), count: Int(vecLen)))
                    }
                    offset += Int(vecLen * 4)
                    loaded[id] = vec
                }
                vectors = loaded
                dirty = false
                return
            }
        } catch {
            // Fallback to JSON
        }
        
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
        
        var data = Data()
        var count = Int32(vectors.count)
        data.append(withUnsafeBytes(of: &count) { Data($0) })
        
        for (id, v) in vectors {
            let idData = Data(id.utf8)
            var idLen = Int32(idData.count)
            data.append(withUnsafeBytes(of: &idLen) { Data($0) })
            data.append(idData)
            
            var vecLen = Int32(v.count)
            data.append(withUnsafeBytes(of: &vecLen) { Data($0) })
            v.withUnsafeBytes { data.append(Data($0)) }
        }
        
        try data.write(to: storeURL, options: .atomic)
        dirty = false
    }
}
