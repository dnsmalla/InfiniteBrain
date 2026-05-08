import Foundation

/// In-memory index of incoming links and source associations.
/// Enables O(1) backlink discovery and bulk "Undo Ingest" operations.
public actor BacklinkIndex {
    // targetId -> set of sourceIds that point to it
    private var backlinks: [String: Set<String>] = [:]
    // sourceId (e.g. PDF id) -> set of noteIds generated from it
    private var batchMap: [String: Set<String>] = [:]
    
    public init() {}
    
    /// Indexes a note's connections.
    public func index(_ note: Note) {
        // Track backlinks
        for edge in note.edges {
            backlinks[edge.target, default: []].insert(note.id)
        }
        // Track source batches
        for sourceId in note.sources {
            batchMap[sourceId, default: []].insert(note.id)
        }
    }
    
    /// Removes a note from the index.
    public func deindex(_ note: Note) {
        for edge in note.edges {
            backlinks[edge.target]?.remove(note.id)
        }
        for sourceId in note.sources {
            batchMap[sourceId]?.remove(note.id)
        }
    }
    
    public func getBacklinks(for id: String) -> Set<String> {
        backlinks[id] ?? []
    }
    
    public func getBatch(for sourceId: String) -> Set<String> {
        batchMap[sourceId] ?? []
    }
    
    public func clear() {
        backlinks.removeAll()
        batchMap.removeAll()
    }
}
