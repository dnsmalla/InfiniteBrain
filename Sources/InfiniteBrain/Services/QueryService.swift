import Foundation
import SharedLLMKit

public struct Answer: Sendable, Equatable {
    public let text: String
    public let citedIds: [String]
}

/// Answers a natural-language question using vault contents. Single-pass
/// retrieval for v1: embed the question, take top-K nearest notes from the
/// EmbeddingIndex, load their full bodies, and let the `answer-question`
/// skill produce the answer with citations.
public actor QueryService {
    public let skillRunner: SkillRunner
    public let store: VaultStore
    public let embeddings: EmbeddingProvider
    public let index: EmbeddingIndex

    public init(
        skillRunner: SkillRunner,
        store: VaultStore,
        embeddings: EmbeddingProvider,
        index: EmbeddingIndex
    ) {
        self.skillRunner = skillRunner
        self.store = store
        self.embeddings = embeddings
        self.index = index
    }

    public func ask(_ question: String, topK: Int = 6) async throws -> Answer {
        let queryVector = try await embeddings.embed(question)
        let hits = await index.nearest(to: queryVector, k: topK)

        var loaded: [[String: Any]] = []
        for hit in hits {
            if let note = try? await store.read(id: hit.id) {
                loaded.append([
                    "id": note.id,
                    "type": note.type.rawValue,
                    "title": note.title,
                    "body": note.body,
                ])
            }
        }

        let response = try await skillRunner.run(
            "answer-question",
            input: ["question": question, "notes": loaded]
        )
        let text = (response["answer"] as? String) ?? ""
        let cited = (response["cited_ids"] as? [String]) ?? []
        return Answer(text: text, citedIds: cited)
    }
}
