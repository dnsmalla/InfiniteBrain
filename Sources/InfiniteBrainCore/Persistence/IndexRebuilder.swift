import Foundation
import SharedLLMKit

/// Rebuilds the embedding index for a vault from the markdown notes on disk.
/// Any pre-existing index is replaced, so stale entries (notes the user
/// deleted manually) get dropped and missing ones get added.
///
/// Returns the freshly-flushed index actor so callers can immediately query
/// it without re-loading.
public enum IndexRebuilder {
    public static func rebuild(
        vault: Vault,
        embeddings: EmbeddingProvider,
        metadataIndex: MetadataIndex? = nil
    ) async throws -> EmbeddingIndex {
        let store = VaultStore(vault: vault)
        let notes = try await store.allNotes()

        let indexURL = vault.embeddingIndexURL
        try? FileManager.default.removeItem(at: indexURL)
        let index = EmbeddingIndex(storeURL: indexURL)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for note in notes {
                group.addTask {
                    if let metadataIndex = metadataIndex { await metadataIndex.update(note) }
                    let text = note.body.isEmpty ? note.title : note.body
                    let vec = try await embeddings.embed(text)
                    await index.record(id: note.id, vector: vec)
                }
            }
            try await group.waitForAll()
        }
        try await index.flush()
        try? await metadataIndex?.save()
        return index
    }
}
