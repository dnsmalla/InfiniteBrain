import Foundation
import SharedLLMKit

/// Sequences pipeline stages per ingested file. Writes checkpoints to the
/// sidecar DB so long jobs can resume after a crash.
public actor Orchestrator {
    public init() {}

    public func ingest(file: URL, into vault: Vault) async throws {
        // 1. extract-pdf      → raw text + page map
        // 2. atomize-text     → [AtomicUnit] (50–300 lines each)
        // 3. classify-node    → assign NodeType
        // 4. summarize-note   → one-sentence summary
        // 5. reconcile-note   → skip | improve | add
        // 6. infer-edges      → populate edges across vault
        // 7. VaultStore.write → markdown + frontmatter
        fatalError("not yet implemented")
    }
}
