import Foundation
import SwiftUI
import SharedLLMKit

@MainActor
public final class QueryViewModel: ObservableObject {
    @Published public var question: String = ""
    @Published public var answer: String = ""
    @Published public var citedIds: [String] = []
    @Published public var isAsking: Bool = false
    @Published public var error: String?

    public init() {}

    public func ask(settings: AppSettings) async {
        guard !isAsking else { return }
        guard let vaultURL = settings.vaultPath else {
            error = "Pick a vault folder in Settings first."; return
        }
        guard let apiKey = (try? settings.apiKey()) ?? nil, !apiKey.isEmpty else {
            error = "Add an Anthropic API key in Settings first."; return
        }
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        isAsking = true
        defer { isAsking = false }
        error = nil
        answer = ""
        citedIds = []

        let vault = Vault(root: vaultURL)
        let skillsRoot = FileManager.default.fileExists(atPath: vault.skillsDir.path)
            ? vault.skillsDir
            : (Bundle.module.url(forResource: "skills", withExtension: nil) ?? vault.skillsDir)

        let runner = SkillRunner(client: AnthropicClient(apiKey: apiKey), skillsRoot: skillsRoot)
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
        } catch {
            self.error = error.localizedDescription
        }
    }
}
