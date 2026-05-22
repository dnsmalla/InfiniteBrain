import Foundation
import SwiftUI
import SharedLLMKit

@MainActor
public final class DraftingViewModel: ObservableObject {
    @Published public var session: DraftingSession?
    @Published public var selectedSectionId: String?
    @Published public var isWorking: Bool = false
    @Published public var error: String?
    
    // Inputs for new session
    @Published public var newTopic: String = ""
    @Published public var newTemplate: String = "Scientific Paper"
    @Published public var globalSelectedCitations: [String] = []
    @Published public var ingestionStatus: String? = nil
    @Published public var isIngesting: Bool = false
    @Published public var recentSessions: [DraftingSession] = []
    
    public let templates = ["Scientific Paper", "Executive Summary", "Blog Post", "Project Proposal"]
    
    // Note Search for Citations
    @Published public var noteSearchQuery: String = ""
    @Published public var searchResults: [Note] = []
    
    // UI State
    @Published public var isOutlineCollapsed: Bool = false
    @Published public var isReferencesCollapsed: Bool = true
    
    public init() {}
    
    public var canStart: Bool {
        !newTopic.isEmpty && !newTemplate.isEmpty
    }
    
    public var selectedSection: DraftSection? {
        session?.sections.first { $0.id == selectedSectionId }
    }
    
    public func startSession(settings: AppSettings) async {
        guard canStart else { return }
        isWorking = true
        error = nil
        
        do {
            if let v = settings.vaultPath {
                SkillSyncService.sync(to: Vault(root: v))
            }
            let service = try await makeService(settings: settings)
            let sections = try await service.planOutline(topic: newTopic, template: newTemplate)
            self.session = DraftingSession(
                topic: newTopic, 
                template: newTemplate, 
                sections: sections,
                globalCitationIds: globalSelectedCitations
            )
            await saveSession(settings: settings)
            await loadRecentSessions(settings: settings)
            self.selectedSectionId = sections.first?.id
        } catch {
            self.error = error.localizedDescription
        }
        isWorking = false
    }
    
    public func resumeSession(_ session: DraftingSession) {
        self.session = session
        self.newTopic = session.topic
        self.newTemplate = session.template
        self.globalSelectedCitations = session.globalCitationIds
    }
    
    public func toggleGlobalCitation(_ id: String) {
        if globalSelectedCitations.contains(id) {
            globalSelectedCitations.removeAll { $0 == id }
        } else {
            globalSelectedCitations.append(id)
        }
    }
    
    public func generateActiveSection(settings: AppSettings) async {
        guard let s = session, let sId = selectedSectionId else { return }
        guard let index = s.sections.firstIndex(where: { $0.id == sId }) else { return }
        
        isWorking = true
        error = nil
        
        do {
            let service = try await makeService(settings: settings)
            let result = try await service.generateSection(s.sections[index], in: s)
            
            var updated = s
            if result.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updated.sections[index].content = "> [!ERROR] Synthesis Empty\n> The background engine completed its run but was unable to synthesize any content.\n> \n> **Why this occurs:**\n> This typically happens when the AI cannot satisfy both your instructions and the provided evidence context, or if the context notes were insufficient.\n> \n> _Tip: Try simplifying your drafting instructions or referencing broader contextual sources._"
            } else {
                updated.sections[index].content = result.content
            }
            updated.sections[index].actualCitedIds = result.citedIds
            self.session = updated
            
            await saveSession(settings: settings)
        } catch {
            self.error = error.localizedDescription
            
            var updated = s
            let errorMsg: String
            
            if let cliError = error as? CLIClientError, case .executableNotFound(let name) = cliError {
                errorMsg = "> [!WARNING] Engine Disconnected\n> The requested LLM engine (`\(name)`) is not linked to your system's PATH.\n> \n> **To resolve:**\n> 1. Install the CLI tool matching your engine selection in Settings.\n> 2. Ensure it's available in `/usr/local/bin`.\n> 3. Alternatively, switch to **Anthropic API** in Settings for immediate, zero-setup access."
            } else if let nsError = error as NSError?, nsError.domain == "Drafting", nsError.code == 404 {
                errorMsg = "> [!WARNING] Engine Disconnected\n> \(nsError.localizedDescription)"
            } else {
                errorMsg = "> [!ERROR] Synthesis Interrupted\n> The AI failed to synthesize this section properly or returned an unexpected format.\n> \n> **System Return Details:**\n> ```text\n> \(error.localizedDescription)\n> ```\n> \n> _Tip: Check if your chosen Model Provider requires additional configuration._"
            }
            
            updated.sections[index].content = errorMsg
            self.session = updated
        }
        isWorking = false
    }
    
    public func updateSectionContent(_ sectionId: String, content: String) {
        guard var updated = session else { return }
        guard let idx = updated.sections.firstIndex(where: { $0.id == sectionId }) else { return }
        updated.sections[idx].content = content
        self.session = updated
    }
    
    public func updateSectionInstruction(_ sectionId: String, instruction: String) {
        guard let idx = session?.sections.firstIndex(where: { $0.id == sectionId }) else { return }
        session?.sections[idx].customPrompt = instruction
    }
    
    public func addSection() {
        guard var updated = session else { return }
        let new = DraftSection(title: "New Section")
        updated.sections.append(new)
        self.session = updated
        self.selectedSectionId = new.id
    }
    
    public func removeSection(_ id: String) {
        guard var updated = session else { return }
        updated.sections.removeAll { $0.id == id }
        self.session = updated
        if selectedSectionId == id {
            selectedSectionId = updated.sections.first?.id
        }
    }
    
    public func toggleCitation(sectionId: String, noteId: String) {
        guard let sIdx = session?.sections.firstIndex(where: { $0.id == sectionId }) else { return }
        var current = session?.sections[sIdx].selectedCitationIds ?? []
        if current.contains(noteId) {
            current.removeAll { $0 == noteId }
        } else {
            current.append(noteId)
        }
        session?.sections[sIdx].selectedCitationIds = current
    }
    
    public func searchNotes(settings: AppSettings) async {
        guard !noteSearchQuery.isEmpty else { 
            searchResults = []
            return 
        }
        
        do {
            let vaultURL = settings.vaultPath ?? URL(fileURLWithPath: "/")
            let v = Vault(root: vaultURL)
            let store = VaultStore(vault: v)
            let embeddings = NLEmbeddingProvider()
            let index = EmbeddingIndex(storeURL: v.sidecar.appendingPathComponent("embeddings.bin"))
            try? await index.load()
            
            let vector = try await embeddings.embed(noteSearchQuery)
            let hits = await index.nearest(to: vector, k: 5)
            
            var notes: [Note] = []
            for hit in hits {
                if let note = try? await store.read(id: hit.id) {
                    notes.append(note)
                }
            }
            self.searchResults = notes
        } catch {
            print("Search error: \(error)")
        }
    }
    
    public func importFiles(urls: [URL], settings: AppSettings) async {
        guard let vaultURL = settings.vaultPath else { return }
        let vault = Vault(root: vaultURL)
        
        isIngesting = true
        error = nil
        
        do {
            let apiKey = (try? settings.apiKey()) ?? nil
            let client = try LLMClientFactory.make(provider: settings.provider, apiKey: apiKey, gate: GlobalRateGate.shared)
            
            let orchestrator = UnifiedIngestionService.makeOrchestrator(
                vault: vault, 
                client: client, 
                concurrency: settings.concurrency,
                onProgress: { [weak self] msg in 
                    Task { @MainActor in self?.ingestionStatus = msg }
                },
                onUsage: { _ in }
            )
            
            let allFiles = UnifiedIngestionService.resolveFiles(urls: urls)
            
            for url in allFiles {
                let targetURL = vault.root.appendingPathComponent("sources", isDirectory: true).appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: targetURL.path) {
                    try? FileManager.default.copyItem(at: url, to: targetURL)
                }
                
                _ = try await orchestrator.ingest(file: targetURL, into: vault)
                
                let fileName = url.deletingPathExtension().lastPathComponent
                await MainActor.run {
                    self.toggleGlobalCitation(url.lastPathComponent)
                    if self.newTopic.isEmpty { self.newTopic = fileName }
                }
            }
            
            await MainActor.run { self.ingestionStatus = "Import complete!" }
            try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            await MainActor.run { self.ingestionStatus = nil }
            
        } catch {
            await MainActor.run { self.error = "Import failed: \(error.localizedDescription)" }
        }
        
        isIngesting = false
    }

    private func makeService(settings: AppSettings) async throws -> DraftingService {
        guard let vaultURL = settings.vaultPath else {
            throw NSError(domain: "Drafting", code: 1, userInfo: [NSLocalizedDescriptionKey: "No vault path set."])
        }
        
        let vault = Vault(root: vaultURL)
        
        // Ensure skills are bridged/synced before instantiating the service
        SkillSyncService.sync(to: vault)
        
        let apiKey = (try? settings.apiKey()) ?? nil
        let client: LLMClient
        do {
            client = try LLMClientFactory.make(provider: settings.provider, apiKey: apiKey, gate: GlobalRateGate.shared)
        } catch {
            if let cliError = error as? CLIClientError, case .executableNotFound(let name) = cliError {
                throw NSError(domain: "Drafting", code: 404, userInfo: [NSLocalizedDescriptionKey: "The '\(name)' CLI is not linked or installed. Please install it or switch to Anthropic API in Settings."])
            }
            throw error
        }
        
        let store = VaultStore(vault: vault)
        let index = EmbeddingIndex(storeURL: vault.sidecar.appendingPathComponent("embeddings.bin"))
        try? await index.load()

        return DraftingService(
            skillRunner: SkillRunner(client: client, skillsRoot: vault.skillsDir),
            store: store,
            embeddings: NLEmbeddingProvider(),
            index: index
        )
    }
    
    // MARK: - Persistence
    public func saveSession(settings: AppSettings) async {
        guard let session = session, let vaultURL = settings.vaultPath else { return }
        let draftsDir = vaultURL.appendingPathComponent(".drafts", isDirectory: true)
        try? FileManager.default.createDirectory(at: draftsDir, withIntermediateDirectories: true)
        
        let fileURL = draftsDir.appendingPathComponent("\(session.topic.replacingOccurrences(of: "/", with: "-")).json")
        do {
            let data = try JSONEncoder().encode(session)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save session: \(error)")
        }
    }
    
    public func loadRecentSessions(settings: AppSettings) async {
        guard let vaultURL = settings.vaultPath else { return }
        let draftsDir = vaultURL.appendingPathComponent(".drafts", isDirectory: true)
        
        let files = (try? FileManager.default.contentsOfDirectory(at: draftsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)) ?? []
        
        var loaded: [DraftingSession] = []
        let decoder = JSONDecoder()
        
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let session = try? decoder.decode(DraftingSession.self, from: data) {
                loaded.append(session)
            }
        }
        
        let sorted = loaded.sorted { $0.topic < $1.topic }
        
        DispatchQueue.main.async {
            self.recentSessions = sorted
        }
    }
}
