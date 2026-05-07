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
        embeddings: EmbeddingProvider
    ) async throws -> EmbeddingIndex {
        let store = VaultStore(vault: vault)
        let notes = try await store.allNotes()

        let url = vault.sidecar.appendingPathComponent("embeddings.json")
        // Remove any existing index file so a partial rebuild can't leave
        // stale-mixed-with-new behind. Flush after we're done writing.
        try? FileManager.default.removeItem(at: url)
        let index = EmbeddingIndex(storeURL: url)

        for note in notes {
            // Source notes embed their full original text; everything else
            // embeds the body it has on disk.
            let text = note.body.isEmpty ? note.title : note.body
            do {
                let vec = try await embeddings.embed(text)
                await index.record(id: note.id, vector: vec)
            } catch {
                // A single un-embeddable note shouldn't fail the rebuild.
                continue
            }
        }
        try await index.flush()
        return index
    }
}
