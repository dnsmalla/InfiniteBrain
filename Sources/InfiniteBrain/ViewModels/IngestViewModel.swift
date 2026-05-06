import Foundation
import SwiftUI
import SharedLLMKit

@MainActor
public final class IngestViewModel: ObservableObject {
    @Published public var droppedFiles: [URL] = []
    @Published public var log: [String] = []
    @Published public var isRunning: Bool = false
    @Published public var lastResult: IngestResult?

    public init() {}

    public func add(_ urls: [URL]) {
        for u in urls where !droppedFiles.contains(u) {
            droppedFiles.append(u)
        }
    }

    public func clear() {
        droppedFiles.removeAll()
        log.removeAll()
        lastResult = nil
    }

    public func run(settings: AppSettings) async {
        guard !isRunning else { return }
        guard let vaultURL = settings.vaultPath else {
            append("Pick a vault folder in Settings first.")
            return
        }
        guard let apiKey = (try? settings.apiKey()) ?? nil, !apiKey.isEmpty else {
            append("Add an Anthropic API key in Settings first.")
            return
        }
        guard !droppedFiles.isEmpty else {
            append("Drop files into the panel above.")
            return
        }

        isRunning = true
        defer { isRunning = false }

        let vault = Vault(root: vaultURL)
        let skillsRoot = Self.skillsRoot(for: vault)
        let client = AnthropicClient(apiKey: apiKey)
        let runner = SkillRunner(client: client, skillsRoot: skillsRoot)

        let indexURL = vault.sidecar.appendingPathComponent("embeddings.json")
        let index = EmbeddingIndex(storeURL: indexURL)
        try? await index.load()

        let orchestrator = Orchestrator(
            skillRunner: runner,
            embeddings: NLEmbeddingProvider(),
            index: index
        )

        var totals = IngestResult()
        for file in droppedFiles {
            append("→ \(file.lastPathComponent)")
            do {
                let r = try await orchestrator.ingest(file: file, into: vault)
                append("   added: \(r.added)  improved: \(r.improved)  skipped: \(r.skipped)")
                totals.added += r.added
                totals.improved += r.improved
                totals.skipped += r.skipped
                totals.quarantined += r.quarantined
            } catch {
                append("   error: \(error.localizedDescription)")
            }
        }
        lastResult = totals
        append("done. total — added \(totals.added), improved \(totals.improved), skipped \(totals.skipped)")
    }

    private func append(_ line: String) {
        log.append(line)
    }

    /// Skills live in the vault sidecar so users can edit them. If the sidecar
    /// copy is absent, fall back to the bundled copy inside the app.
    private static func skillsRoot(for vault: Vault) -> URL {
        let custom = vault.skillsDir
        if FileManager.default.fileExists(atPath: custom.path) { return custom }
        if let bundled = Bundle.main.url(forResource: "skills", withExtension: nil) {
            return bundled
        }
        return custom  // best effort
    }
}
