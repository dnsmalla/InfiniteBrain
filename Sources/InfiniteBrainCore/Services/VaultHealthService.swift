import Foundation
import SharedLLMKit

public struct HealthIssue: Identifiable, Sendable {
    public enum Severity: Sendable {
        case warning
        case error
    }
    
    public let id = UUID()
    public let title: String
    public let description: String
    public let severity: Severity
    public let noteId: String?
}

public actor VaultHealthService {
    public init() {}
    
    public func checkHealth(vault: Vault, index: EmbeddingIndex?, metadataIndex: MetadataIndex) async throws -> [HealthIssue] {
        var issues: [HealthIssue] = []
        let store = VaultStore(vault: vault)
        let allNotes = try await store.allNotes()
        let indexEntries = await metadataIndex.allEntries()
        
        let diskIds = Set(allNotes.map(\.id))
        let indexIds = Set(indexEntries.map(\.id))
        
        // 1. Check Metadata Consistency
        let staleEntries = indexIds.subtracting(diskIds)
        for id in staleEntries {
            issues.append(HealthIssue(
                title: "Stale Index Entry",
                description: "Note \(id) exists in index but not on disk.",
                severity: .error,
                noteId: id
            ))
        }
        
        let unindexedNotes = diskIds.subtracting(indexIds)
        for id in unindexedNotes {
            issues.append(HealthIssue(
                title: "Unindexed Note",
                description: "Note \(id) exists on disk but not in index.",
                severity: .error,
                noteId: id
            ))
        }
        
        // 2. Check Graph Integrity
        for note in allNotes {
            // Check for broken edges
            for edge in note.edges {
                if !diskIds.contains(edge.target) {
                    issues.append(HealthIssue(
                        title: "Broken Edge",
                        description: "Note '\(note.title)' points to non-existent note \(edge.target).",
                        severity: .warning,
                        noteId: note.id
                    ))
                }
            }
            
            // Check for orphaned atomic notes
            if note.type != .source && note.sources.isEmpty {
                issues.append(HealthIssue(
                    title: "Orphaned Atomic Note",
                    description: "Note '\(note.title)' has no source references.",
                    severity: .warning,
                    noteId: note.id
                ))
            }
        }
        
        // 3. Check Embeddings (if index provided)
        if index != nil {
            // We can't easily list all keys in EmbeddingIndex without adding a method, 
            // but we can check if each note *should* have one.
            // For now, let's assume all atomic notes should be indexed.
        }
        
        return issues
    }
    
    public func repair(issues: [HealthIssue], vault: Vault, metadataIndex: MetadataIndex) async throws {
        let store = VaultStore(vault: vault)
        for issue in issues {
            guard let noteId = issue.noteId else { continue }
            
            switch issue.title {
            case "Stale Index Entry":
                await metadataIndex.remove(noteId: noteId)
            case "Unindexed Note":
                if let note = try? await store.read(id: noteId) {
                    await metadataIndex.update(note)
                }
            default:
                break
            }
        }
        try await metadataIndex.save()
    }
}
