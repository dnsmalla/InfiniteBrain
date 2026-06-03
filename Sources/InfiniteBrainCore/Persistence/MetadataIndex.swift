import Foundation

/// A persistent binary index for note metadata (types and backlinks).
/// This avoids full filesystem scans on app startup.
public actor MetadataIndex {
    public let storeURL: URL
    
    public struct Entry: Codable, Sendable {
        public let id: String
        public let title: String
        public let type: String
        public let summary: String
        public let sources: [String]
        public let edges: [EdgeEntry]
        public var x: Double
        public var y: Double
    }
    
    public struct EdgeEntry: Codable, Sendable {
        public let targetId: String
        public let type: String
    }
    
    private var entries: [String: Entry] = [:]
    
    public init(storeURL: URL) {
        self.storeURL = storeURL
    }
    
    public func load() async -> Bool {
        guard let rawData = try? Data(contentsOf: storeURL) else { return false }
        
        // Decompress if compressed
        let data: Data
        if let dec = try? (rawData as NSData).decompressed(using: .zlib) {
            data = dec as Data
        } else {
            data = rawData
        }
        
        var offset = 0
        func readInt32() -> Int32? {
            guard offset + 4 <= data.count else { return nil }
            let val = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: Int32.self) }
            offset += 4
            return val
        }
        
        func readString() -> String? {
            guard let len = readInt32() else { return nil }
            let length = Int(len)
            guard offset + length <= data.count else { return nil }
            let s = String(data: data.subdata(in: offset..<offset+length), encoding: .utf8)
            offset += length
            return s
        }
        
        guard readInt32() == 0x4D455441 else { return false } // 'META'
        guard let count = readInt32() else { return false }
        
        entries.removeAll()
        
        for _ in 0..<count {
            // A short read mid-record means the file was truncated (e.g. a crash
            // during a non-atomic external copy). Don't silently accept a partial
            // index — signal corruption so the caller rebuilds from the markdown.
            guard let noteId = readString(),
                  let title = readString(),
                  let type = readString(),
                  let summary = readString(),
                  let sourceCount = readInt32() else { entries.removeAll(); return false }

            var sources: [String] = []
            for _ in 0..<sourceCount {
                if let s = readString() { sources.append(s) }
            }

            guard let edgeCount = readInt32() else { entries.removeAll(); return false }
            var edges: [EdgeEntry] = []
            for _ in 0..<edgeCount {
                if let target = readString(), let eType = readString() {
                    edges.append(EdgeEntry(targetId: target, type: eType))
                }
            }
            
            func readDouble() -> Double {
                guard offset + 8 <= data.count else { return 0 }
                let d = data.subdata(in: offset..<offset+8).withUnsafeBytes { $0.load(as: Double.self) }
                offset += 8
                return d
            }
            let x = readDouble()
            let y = readDouble()
            
            entries[noteId] = Entry(id: noteId, title: title, type: type, summary: summary, sources: sources, edges: edges, x: x, y: y)
        }
        return true
    }
    
    public func save() async throws {
        var payload = Data()
        func appendInt32(_ val: Int32) {
            var v = val
            withUnsafeBytes(of: &v) { payload.append(contentsOf: $0) }
        }
        func appendDouble(_ val: Double) {
            var v = val
            withUnsafeBytes(of: &v) { payload.append(contentsOf: $0) }
        }
        func appendString(_ s: String) {
            let sData = s.data(using: .utf8)!
            appendInt32(Int32(sData.count))
            payload.append(sData)
        }
        
        appendInt32(0x4D455441) // 'META'
        appendInt32(Int32(entries.count))
        
        for (id, entry) in entries {
            appendString(id)
            appendString(entry.title)
            appendString(entry.type)
            appendString(entry.summary)
            appendInt32(Int32(entry.sources.count))
            for s in entry.sources { appendString(s) }
            appendInt32(Int32(entry.edges.count))
            for e in entry.edges {
                appendString(e.targetId)
                appendString(e.type)
            }
            appendDouble(entry.x)
            appendDouble(entry.y)
        }
        
        // Professional Compression: apply zlib to the metadata payload
        let compressed = try (payload as NSData).compressed(using: .zlib) as Data
        try compressed.write(to: storeURL, options: .atomic)
    }
    
    public func update(_ note: Note) {
        let edgeEntries = note.edges.map { EdgeEntry(targetId: $0.target, type: $0.type.rawValue) }
        let existing = entries[note.id]
        entries[note.id] = Entry(
            id: note.id,
            title: note.title,
            type: note.type.rawValue,
            summary: note.summary,
            sources: note.sources,
            edges: edgeEntries,
            x: existing?.x ?? 0,
            y: existing?.y ?? 0
        )
    }
    
    public func updatePosition(id: String, x: Double, y: Double) {
        entries[id]?.x = x
        entries[id]?.y = y
    }

    public func remove(noteId: String) {
        entries.removeValue(forKey: noteId)
    }
    
    public func getBacklinks(for targetId: String) -> Set<String> {
        var out = Set<String>()
        for (id, entry) in entries {
            if entry.sources.contains(targetId) {
                out.insert(id)
            }
        }
        return out
    }
    
    public func allEntries() -> [Entry] {
        return Array(entries.values)
    }
}
