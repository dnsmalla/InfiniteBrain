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

    /// Holds the currently-running ingest Task so the Stop button can
    /// cancel it. `nil` when no run is in flight.
    private var runTask: Task<Void, Never>?

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
    /// button so users can wipe an in-progress or fully-done ingest and
    /// start fresh without manually editing the vault folder.
    public func wipePrevious(settings: AppSettings) async {
        guard let vaultURL = settings.vaultPath else {
            append("Pick a vault folder in Settings first.")
            return
        }
        guard !droppedFiles.isEmpty else {
            append("Drop files into the panel above first.")
            return
        }
        let vault = Vault(root: vaultURL)
        let store = VaultStore(vault: vault)
        let cps = CheckpointStore(vault: vault)

        for file in droppedFiles {
            let text: String
            do {
                text = try InputReader.read(file).text
            } catch {
                append("could not read \(file.lastPathComponent): \(error.localizedDescription)")
                continue
            }
            let hash = Self.sha256Hex(text)
            let all = (try? await store.allNotes()) ?? []
            guard let prior = all.first(where: { $0.type == .source && $0.contentHash == hash }) else {
                append("no previous ingest found for \(file.lastPathComponent)")
                continue
            }
            let toDelete = all.filter { $0.id == prior.id || $0.sources.contains(prior.id) }
            for n in toDelete { try? await store.delete(id: n.id) }
            try? await cps.delete(fileHash: hash)
            append("wiped \(file.lastPathComponent): removed \(toDelete.count) note(s)")
        }
        // Tell observers the vault changed.
        lastResult = IngestResult(skipped: 0)
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
            client = try LLMClientFactory.make(provider: settings.provider, apiKey: apiKey)
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
        let skillsRoot = Self.skillsRoot(for: vault)
        let runner = SkillRunner(client: client, skillsRoot: skillsRoot)

        let indexURL = vault.sidecar.appendingPathComponent("embeddings.json")
        let index = EmbeddingIndex(storeURL: indexURL)
        try? await index.load()

        // Capture-safe progress sink: each progress line hops to the main
        // actor and appends to `log` so the user sees forward motion during
        // a long ingest instead of staring at a frozen panel.
        let progressSink: ProgressHandler = { [weak self] line in
            await MainActor.run { self?.append("   · \(line)") }
        }
        let orchestrator = Orchestrator(
            skillRunner: runner,
            embeddings: NLEmbeddingProvider(),
            index: index,
            onProgress: progressSink
        )

        var totals = IngestResult()
        for file in droppedFiles {
            let bytes = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            let approxChunks = max(1, bytes / 16_000)
            append("→ \(file.lastPathComponent)  (\(byteFormatter.string(fromByteCount: Int64(bytes))), ~\(approxChunks) chunk\(approxChunks == 1 ? "" : "s"))")
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
}
