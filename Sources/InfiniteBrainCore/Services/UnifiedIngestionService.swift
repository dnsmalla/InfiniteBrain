import Foundation
import SharedLLMKit

/// Production-grade service to unify file ingestion logic across multiple view models.
/// Handles recursive discovery, file validation, and orchestrator configuration.
public final class UnifiedIngestionService {
    
    public static func resolveFiles(urls: [URL]) -> [URL] {
        var resolved: [URL] = []
        let fm = FileManager.default
        
        for url in urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                        for case let fileURL as URL in enumerator {
                            if let attrs = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]), attrs.isRegularFile == true {
                                if isValidType(fileURL) { resolved.append(fileURL) }
                            }
                        }
                    }
                } else {
                    if isValidType(url) { resolved.append(url) }
                }
            }
        }
        return resolved
    }
    
    public static func isValidType(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let valid = ["pdf", "epub", "md", "markdown", "txt"]
        return valid.contains(ext)
    }
    
    public static func makeOrchestrator(vault: Vault, client: LLMClient, concurrency: Int, onProgress: @escaping ProgressHandler, onUsage: @escaping UsageHandler) -> Orchestrator {
        let store = VaultStore(vault: vault)
        let indexURL = vault.embeddingIndexURL
        let index = EmbeddingIndex(storeURL: indexURL)
        
        return Orchestrator(
            skillRunner: SkillRunner(client: client, skillsRoot: vault.skillsDir),
            checkpoints: CheckpointStore(vault: vault),
            embeddings: NLEmbeddingProvider(),
            index: index,
            metadataIndex: store.metadataIndex,
            concurrency: concurrency,
            onProgress: onProgress,
            onUsage: onUsage
        )
    }
}
