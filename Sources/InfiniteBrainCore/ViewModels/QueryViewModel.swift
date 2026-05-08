import Foundation
import SwiftUI
import SharedLLMKit

@MainActor
public final class QueryViewModel: ObservableObject {
    @Published public var question: String = ""
    @Published public var answer: String = ""
    @Published public var citedIds: [String] = []
    @Published public var citedNotes: [String: Note] = [:]
    @Published public var isAsking: Bool = false
    @Published public var error: String?

    public init() {}

    public func ask(settings: AppSettings) async {
        guard !isAsking else { return }
        guard let vaultURL = settings.vaultPath else {
            error = "Pick a vault folder in Settings first."; return
        }
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        let apiKey = (try? settings.apiKey()) ?? nil
        let client: LLMClient
        do {
            client = try LLMClientFactory.make(provider: settings.provider, apiKey: apiKey)
        } catch LLMClientFactory.FactoryError.missingAPIKey {
            error = "Anthropic provider needs an API key. Add one in Settings or switch to a CLI provider."
            return
        } catch CLIClientError.executableNotFound(let name) {
            error = "`\(name)` CLI not found on PATH. Install it or pick a different provider."
            return
        } catch {
            self.error = error.localizedDescription
            return
        }

        isAsking = true
        defer { isAsking = false }
        error = nil
        answer = ""
        citedIds = []

        let vault = Vault(root: vaultURL)
        let skillsRoot = FileManager.default.fileExists(atPath: vault.skillsDir.path)
            ? vault.skillsDir
            : (Bundle.module.url(forResource: "skills", withExtension: nil) ?? vault.skillsDir)

        let runner = SkillRunner(client: client, skillsRoot: skillsRoot)
        let store = VaultStore(vault: vault)
        let index = EmbeddingIndex(storeURL: vault.sidecar.appendingPathComponent("embeddings.json"))
        try? await index.load()

        let service = QueryService(
            skillRunner: runner,
            store: store,
            embeddings: NLEmbeddingProvider(),
            index: index
        )
        do {
            let result = try await service.ask(q)
            answer = result.text
            citedIds = result.citedIds
            
            // Resolve citation details for the UI
            var notes: [String: Note] = [:]
            for id in result.citedIds {
                if let note = try? await store.read(id: id) {
                    notes[id] = note
                }
            }
            citedNotes = notes
        } catch {
            self.error = error.localizedDescription
        }
    }
}
