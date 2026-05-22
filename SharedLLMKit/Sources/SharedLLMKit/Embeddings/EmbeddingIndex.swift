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
    private var magnitudes: [String: Float] = [:]
    private var dirty: Bool = false

    public init(storeURL: URL) {
        self.storeURL = storeURL
    }

    public func record(id: String, vector: [Float]) {
        vectors[id] = vector
        magnitudes[id] = Self.calculateMagnitude(vector)
        dirty = true
    }

    public func remove(id: String) {
        if vectors.removeValue(forKey: id) != nil {
            magnitudes.removeValue(forKey: id)
            dirty = true
        }
    }

    public func nearest(to query: [Float], k: Int) -> [Hit] {
        guard !vectors.isEmpty, k > 0 else { return [] }
        let count = vDSP_Length(query.count)
        
        var qMagSq: Float = 0
        vDSP_svesq(query, 1, &qMagSq, count)
        let qMag = sqrt(qMagSq)
        guard qMag > 0 else { return [] }
        
        // Brute-force dot product with Accelerate
        let scored = vectors.compactMap { id, v -> Hit? in
            guard v.count == query.count else { return nil }
            var dot: Float = 0
            vDSP_dotpr(v, 1, query, 1, &dot, count)
            
            guard let vMag = magnitudes[id], vMag > 0 else { return nil }
            
            return Hit(id: id, score: dot / (qMag * vMag))
        }
        return scored.sorted { $0.score > $1.score }.prefix(k).map { $0 }
    }

    public func load() throws {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }
        
        let data = try Data(contentsOf: storeURL)
        if data.count < 4 { return }
        
        // Check for zlib compression (magic 0x78 0x9C or similar, but we'll try decompress)
        let decompressed: Data
        if let dec = try? (data as NSData).decompressed(using: .zlib) {
            decompressed = dec as Data
        } else {
            decompressed = data
        }
        
        var offset = 0
        func read<T>(_ type: T.Type) -> T? {
            let size = MemoryLayout<T>.size
            guard offset + size <= decompressed.count else { return nil }
            let value = decompressed.subdata(in: offset..<offset+size).withUnsafeBytes { $0.load(as: T.self) }
            offset += size
            return value
        }
        
        // Attempt binary load
        if let count = read(Int32.self) {
            var loaded: [String: [Float]] = [:]
            for _ in 0..<count {
                guard let idLen = read(Int32.self),
                      offset + Int(idLen) <= decompressed.count else { break }
                let id = String(decoding: decompressed.subdata(in: offset..<offset+Int(idLen)), as: UTF8.self)
                offset += Int(idLen)
                
                guard let vecLen = read(Int32.self),
                      offset + Int(vecLen * 2) <= decompressed.count else { break } // Float16 is 2 bytes
                
                // Read Float16 and convert to Float32 for memory
                let f16Data = decompressed.subdata(in: offset..<offset+Int(vecLen * 2))
                var f32Vec = [Float](repeating: 0, count: Int(vecLen))
                
                f16Data.withUnsafeBytes { ptr in
                    let f16Ptr = ptr.baseAddress!.assumingMemoryBound(to: Float16.self)
                    for j in 0..<Int(vecLen) {
                        f32Vec[j] = Float(f16Ptr[j])
                    }
                }
                
                offset += Int(vecLen * 2)
                loaded[id] = f32Vec
            }
            vectors = loaded
            recalculateMagnitudes()
            dirty = false
            return
        }
        
        // Fallback to legacy JSON if binary load fails
        vectors = try JSONDecoder().decode([String: [Float]].self, from: data)
        recalculateMagnitudes()
        dirty = false
    }

    private func recalculateMagnitudes() {
        magnitudes.removeAll()
        for (id, v) in vectors {
            magnitudes[id] = Self.calculateMagnitude(v)
        }
    }

    private static func calculateMagnitude(_ v: [Float]) -> Float {
        var magSq: Float = 0
        vDSP_svesq(v, 1, &magSq, vDSP_Length(v.count))
        return sqrt(magSq)
    }

    public func flush() throws {
        guard dirty else { return }
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        var payload = Data()
        var count = Int32(vectors.count)
        payload.append(withUnsafeBytes(of: &count) { Data($0) })
        
        for (id, v) in vectors {
            let idData = Data(id.utf8)
            var idLen = Int32(idData.count)
            payload.append(withUnsafeBytes(of: &idLen) { Data($0) })
            payload.append(idData)
            
            var vecLen = Int32(v.count)
            payload.append(withUnsafeBytes(of: &vecLen) { Data($0) })
            
            // Quantize to Float16 for 50% space saving
            let f16Vec = v.map { Float16($0) }
            f16Vec.withUnsafeBytes { payload.append(Data($0)) }
        }
        
        // Professional Compression: apply zlib to the already binary payload
        let compressed = try (payload as NSData).compressed(using: .zlib) as Data
        try compressed.write(to: storeURL, options: .atomic)
        dirty = false
    }
}
