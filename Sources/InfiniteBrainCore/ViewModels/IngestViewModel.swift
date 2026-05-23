import Foundation
import SwiftUI
import CryptoKit
import SharedLLMKit

@MainActor
public final class IngestViewModel: ObservableObject {
    @Published public var droppedFiles: [URL] = []
    @Published public var log: [String] = []
    @Published public var isRunning: Bool = false
    @Published public var lastResult: IngestResult?
    @Published public var usageSummary: UsageSummary?

    /// Holds the currently-running ingest Task so the Stop button can
    /// cancel it. `nil` when no run is in flight.
    private var runTask: Task<Void, Never>?
    
    private var watcher: VaultWatcher?
    private var syncTask: Task<Void, Never>?

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

    /// Start a run, or cancel the in-flight one if there already is one.
    /// The Run/Stop button calls this. Cancellation propagates through the
    /// Orchestrator's TaskGroup; chunks that have already finished stay in
    /// the vault, the checkpoint records what's done, and a future Run
    /// will resume from there.
    public func toggle(settings: AppSettings) {
        if let existing = runTask {
            existing.cancel()
            LogService.shared.info("Stop requested by user", category: .ingest)
            append("⏹ stop requested — finishing in-flight subtasks…")
            runTask = nil
            return
        }
        runTask = Task { [weak self] in
            await self?.run(settings: settings)
            self?.runTask = nil
        }
    }

    /// Delete the source note + every atomic note citing it + the matching
    /// checkpoint, for each currently-dropped file. Used by the Re-ingest
    /// button so users can wipe an in-progress or fully-done ingest.
    public func wipePrevious(settings: AppSettings) async {
        guard let vaultURL = settings.vaultPath else { return }
        let vault = Vault(root: vaultURL)
        let store = VaultStore(vault: vault)
        
        let orchestrator = UnifiedIngestionService.makeOrchestrator(
            vault: vault, 
            client: SilentLLMClient(), 
            concurrency: settings.concurrency,
            onProgress: { _ in },
            onUsage: { _ in }
        )

        for file in droppedFiles {
            let text: String
            do {
                text = try InputReader.read(file).text
            } catch { continue }
            
            let hash = Self.sha256Hex(text)
            let all = (try? await store.allNotes()) ?? []
            if let prior = all.first(where: { $0.type == .source && $0.contentHash == hash }) {
                append("↩️ wiping previous ingest for \(file.lastPathComponent)…")
                try? await orchestrator.revertIngest(sourceId: prior.id, in: vault)
            }
        }
        lastResult = IngestResult(skipped: 0)
    }

    /// Reverts an ingestion batch given a path to a .source markdown file.
    public func revertIngest(sourceURL: URL, settings: AppSettings) async {
        guard let vaultURL = settings.vaultPath else { return }
        let vault = Vault(root: vaultURL)
        
        let orchestrator = UnifiedIngestionService.makeOrchestrator(
            vault: vault, 
            client: SilentLLMClient(), 
            concurrency: settings.concurrency,
            onProgress: { _ in },
            onUsage: { _ in }
        )

        guard let content = try? String(contentsOf: sourceURL, encoding: .utf8),
              let note = try? NoteSerializer.parse(content) else { return }
        
        append("↩️ reverting ingest for \(note.title)…")
        do {
            try await orchestrator.revertIngest(sourceId: note.id, in: vault)
            append("   done. removed generated notes.")
            lastResult = IngestResult(skipped: 0)
        } catch {
            append("   revert error: \(error.localizedDescription)")
        }
    }
    
    // Client for non-LLM metadata operations
    private class SilentLLMClient: LLMClient, @unchecked Sendable {
        func complete(system: String, user: String, responseSchema: [String : Any]?, onUsage: (@Sendable (LLMUsage) -> Void)?) async throws -> String {
            return ""
        }
    }

    private static func sha256Hex(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return "sha256-" + digest.map { String(format: "%02x", $0) }.joined()
    }

    public func run(settings: AppSettings) async {
        guard !isRunning else { return }
        guard let vaultURL = settings.vaultPath else {
            append("Pick a vault folder in Settings first.")
            return
        }
        guard !droppedFiles.isEmpty else {
            append("Drop files into the panel above.")
            return
        }

        let apiKey = (try? settings.apiKey()) ?? nil
        let client: LLMClient
        do {
            client = try LLMClientFactory.make(provider: settings.provider, apiKey: apiKey, gate: GlobalRateGate.shared)
        } catch LLMClientFactory.FactoryError.missingAPIKey {
            let alts = LLMProviderKind.allCases
                .filter { $0 != .anthropic }
                .filter { LLMClientFactory.isAvailable($0, apiKey: nil) }
                .map { "“\($0.displayName)”" }
            if alts.isEmpty {
                append("Anthropic provider needs an API key. Add one in the Settings tab.")
            } else {
                append("Anthropic provider needs an API key. Either add one in Settings, or switch the LLM provider there to \(alts.joined(separator: " / ")).")
            }
            return
        } catch CLIClientError.executableNotFound(let name) {
            append("`\(name)` CLI is not on your PATH. Install it or change the provider in Settings.")
            return
        } catch {
            append("provider error: \(error.localizedDescription)")
            return
        }

        isRunning = true
        defer { isRunning = false }
        append("provider: \(settings.provider.displayName)")

        let vault = Vault(root: vaultURL)
        do { try VaultInitializer().ensureSeeded(vault: vault) }
        catch { append("could not seed vault: \(error.localizedDescription)") }
        
        let indexURL = vault.sidecar.appendingPathComponent("embeddings.bin")
        let index = EmbeddingIndex(storeURL: indexURL)
        try? await index.load()

        await GlobalRateGate.shared.setMaxConcurrent(settings.concurrency)
        await UsageTracker.shared.setPersistURL(vault.sidecar.appendingPathComponent("usage.json"))

        // Capture-safe progress sink
        let progressSink: ProgressHandler = { line in
            Task { @MainActor in
                self.append("   · \(line)")
            }
        }
        
        let usageSink: UsageHandler = { usage in
            Task {
                await UsageTracker.shared.record(metric: UsageMetric(
                    timestamp: Date(),
                    skillName: "ingest", // Note: SkillRunner could pass skillName if we extended the callback
                    provider: settings.provider.displayName,
                    inputTokens: usage.inputTokens,
                    outputTokens: usage.outputTokens,
                    latencySeconds: 0 // AnthropicClient should ideally measure this
                ))
            }
        }
        
        let orchestrator = UnifiedIngestionService.makeOrchestrator(
            vault: vault, 
            client: client, 
            concurrency: settings.concurrency, 
            onProgress: progressSink, 
            onUsage: usageSink
        )

        var totals = IngestResult()
        await withTaskGroup(of: IngestResult?.self) { group in
            for file in droppedFiles {
                group.addTask {
                    let bytes = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
                    let approxChunks = max(1, Int(bytes) / 16_000)
                    let fileName = file.lastPathComponent
                    await self.appendFormattedIngestStart(fileName: fileName, bytes: bytes, approxChunks: approxChunks)
                    
                    do {
                        let r = try await orchestrator.ingest(file: file, into: vault)
                        await self.append("   added: \(r.added)  improved: \(r.improved)  skipped: \(r.skipped)")
                        return r
                    } catch {
                        await self.append("   error: \(fileName): \(error.localizedDescription)")
                        return nil
                    }
                }
            }
            
            for await result in group {
                if let r = result {
                    totals.added += r.added
                    totals.improved += r.improved
                    totals.skipped += r.skipped
                    totals.quarantined += r.quarantined
                }
            }
            
            let summary = await UsageTracker.shared.getSummary()
            self.usageSummary = summary
            LogService.shared.info("Ingest batch complete. Total cost: $\(String(format: "%.4f", summary.totalCost))", category: .ingest)
        }
        lastResult = totals
        append("done. total — added \(totals.added), improved \(totals.improved), skipped \(totals.skipped)")
    }

    /// Keep the activity log bounded so a long-running ingest doesn't
    /// produce thousands of @Published rows that beachball the SwiftUI
    /// list. We retain the most recent 500 lines and silently drop older
    /// ones; users care about what's happening *now*, not 20 minutes ago.
    private static let maxLogLines = 500

    private func append(_ line: String) {
        log.append(line)
        if log.count > Self.maxLogLines {
            log.removeFirst(log.count - Self.maxLogLines)
        }
    }
    
    private func appendFormattedIngestStart(fileName: String, bytes: Int64, approxChunks: Int) {
        let sizeStr = byteFormatter.string(fromByteCount: bytes)
        append("→ \(fileName)  (\(sizeStr), ~\(approxChunks) chunk\(approxChunks == 1 ? "" : "s"))")
    }

    private let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    /// Skills live in the vault sidecar so users can edit them. If the sidecar
    /// copy is absent, fall back to the bundled copy inside the app.
    private static func skillsRoot(for vault: Vault) -> URL {
        let custom = vault.skillsDir
        if FileManager.default.fileExists(atPath: custom.path) { return custom }
        if let bundled = Bundle.module.url(forResource: "skills", withExtension: nil) {
            return bundled
        }
        return custom  // best effort
    }

    // MARK: - Reactive Sync
    
    public func startWatcher(settings: AppSettings) {
        guard watcher == nil, let url = settings.vaultPath else { return }
        
        do {
            watcher = try VaultWatcher(url: url) { [weak self] event in
                Task { @MainActor in
                    self?.handleWatcherEvent(event, settings: settings)
                }
            }
            append("👁 background sync active")
        } catch {
            append("⚠️ could not start watcher: \(error.localizedDescription)")
        }
    }
    
    public func stopWatcher() {
        watcher?.stop()
        watcher = nil
    }
    
    private func handleWatcherEvent(_ event: WatcherEvent, settings: AppSettings) {
        // Debounce: wait for 2 seconds of silence before reconciling.
        // This prevents "thrashing" if multiple files are saved at once.
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await reconcileVault(settings: settings)
        }
    }
    
    private func reconcileVault(settings: AppSettings) async {
        guard let url = settings.vaultPath else { return }
        let vault = Vault(root: url)
        let store = VaultStore(vault: vault)
        
        append("🔄 reconciling with external changes…")
        
        do {
            let diskNotes = try await store.allNotes()
            let indexEntries = await store.metadataIndex.allEntries()
            
            let diskIds = Set(diskNotes.map(\.id))
            let indexIds = Set(indexEntries.map(\.id))
            
            // 1. Remove entries from index that don't exist on disk
            let deleted = indexIds.subtracting(diskIds)
            for id in deleted {
                await store.metadataIndex.remove(noteId: id)
            }
            
            // 2. Identify new or changed notes
            // (Note: we use contentHash to detect changes without full text comparison)
            
            // For now, we Re-update all disk notes into the index. 
            // In a larger vault, we'd only do this for files with newer mtime.
            for note in diskNotes {
                await store.metadataIndex.update(note)
            }
            
            try await store.metadataIndex.save()
            
            if !deleted.isEmpty {
                append("   removed \(deleted.count) stale note(s) from index")
            }
            append("   sync complete")
            
            // Trigger UI refresh
            lastResult = IngestResult(skipped: 0)
        } catch {
            append("   sync failed: \(error.localizedDescription)")
        }
    }
}
