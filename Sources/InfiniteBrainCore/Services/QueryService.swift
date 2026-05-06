import Foundation
import SharedLLMKit

public struct Answer: Sendable, Equatable {
    public let text: String
    public let citedIds: [String]
}

/// Answers a natural-language question using vault contents.
///
/// Defaults to **two-pass retrieval**:
///  1. embed the question, fetch top-`candidateK` summaries from the index;
///     send only the summaries to `select-notes-for-question` and let the
///     model pick which bodies to expand (up to `fullNotesBudget`).
///  2. load full bodies for the picked ids and call `answer-question`.
///
/// Single-pass mode (`twoPass: false`) loads top-K full bodies up-front and
/// goes straight to `answer-question`. Cheaper to set up but eats more tokens
/// per question because every retrieved note's full body is sent.
public actor QueryService {
    public let skillRunner: SkillRunner
    public let store: VaultStore
    public let embeddings: EmbeddingProvider
    public let index: EmbeddingIndex
    public let twoPass: Bool
    public let candidateK: Int
    public let fullNotesBudget: Int

    public init(
        skillRunner: SkillRunner,
        store: VaultStore,
        embeddings: EmbeddingProvider,
        index: EmbeddingIndex,
        twoPass: Bool = true,
        candidateK: Int = 12,
        fullNotesBudget: Int = 4
    ) {
        self.skillRunner = skillRunner
        self.store = store
        self.embeddings = embeddings
        self.index = index
        self.twoPass = twoPass
        self.candidateK = candidateK
        self.fullNotesBudget = fullNotesBudget
    }

    /// `topK` is honoured only in single-pass mode (legacy callers). Two-pass
    /// uses `candidateK` for retrieval and `fullNotesBudget` for expansion.
    public func ask(_ question: String, topK: Int = 6) async throws -> Answer {
        if twoPass {
            return try await askTwoPass(question)
        } else {
            return try await askSinglePass(question, topK: topK)
        }
    }

    // MARK: - Two-pass

    private func askTwoPass(_ question: String) async throws -> Answer {
        let qVector = try await embeddings.embed(question)
        let hits = await index.nearest(to: qVector, k: candidateK)

        // Pass 1 input: summaries only (cheap).
        var summaries: [[String: Any]] = []
        for hit in hits {
            if let note = try? await store.read(id: hit.id) {
                summaries.append([
                    "id": note.id,
                    "type": note.type.rawValue,
                    "title": note.title,
                    "summary": note.summary,
                ])
            }
        }

        let selection = try await skillRunner.run(
            "select-notes-for-question",
            input: [
                "question": question,
                "candidates": summaries,
                "full_notes_budget": fullNotesBudget,
            ]
        )
        let neededIds = (selection["needed_ids"] as? [String]) ?? []

        // Load only what was selected, in order, capped at fullNotesBudget.
        var loaded: [[String: Any]] = []
        for id in neededIds.prefix(fullNotesBudget) {
            if let note = try? await store.read(id: id) {
                loaded.append([
                    "id": note.id,
                    "type": note.type.rawValue,
                    "title": note.title,
                    "body": note.body,
                ])
            }
        }

        // Pass 2: produce the answer.
        let answered = try await skillRunner.run(
            "answer-question",
            input: ["question": question, "notes": loaded]
        )
        return Answer(
            text: (answered["answer"] as? String) ?? "",
            citedIds: (answered["cited_ids"] as? [String]) ?? []
        )
    }

    // MARK: - Single-pass (legacy)

    private func askSinglePass(_ question: String, topK: Int) async throws -> Answer {
        let qVector = try await embeddings.embed(question)
        let hits = await index.nearest(to: qVector, k: topK)

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

        let answered = try await skillRunner.run(
            "answer-question",
            input: ["question": question, "notes": loaded]
        )
        return Answer(
            text: (answered["answer"] as? String) ?? "",
            citedIds: (answered["cited_ids"] as? [String]) ?? []
        )
    }
}
