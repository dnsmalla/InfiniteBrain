import Foundation
import CryptoKit
import SharedLLMKit

public struct IngestResult: Equatable, Sendable {
    public var added: Int
    public var improved: Int
    public var skipped: Int
    public var quarantined: Int

    public init(added: Int = 0, improved: Int = 0, skipped: Int = 0, quarantined: Int = 0) {
        self.added = added
        self.improved = improved
        self.skipped = skipped
        self.quarantined = quarantined
    }
}

/// Sequences pipeline stages per ingested file. End-to-end:
///   read → atomize → (per unit) embed → classify → summarize → reconcile
///   → write/skip/improve. Embedding-backed candidates flow into reconcile so
///   duplicates can actually be detected.
public actor Orchestrator {
    public let skillRunner: SkillRunner
    public let idGenerator: IDGenerator
    public let dateProvider: DateProvider
    public let embeddings: EmbeddingProvider?
    public let index: EmbeddingIndex?
    public let candidateK: Int

    public init(
        skillRunner: SkillRunner,
        idGenerator: IDGenerator = ULIDGenerator(),
        dateProvider: DateProvider = SystemDateProvider(),
        embeddings: EmbeddingProvider? = nil,
        index: EmbeddingIndex? = nil,
        candidateK: Int = 5
    ) {
        self.skillRunner = skillRunner
        self.idGenerator = idGenerator
        self.dateProvider = dateProvider
        self.embeddings = embeddings
        self.index = index
        self.candidateK = candidateK
    }

    public func ingest(file: URL, into vault: Vault) async throws -> IngestResult {
        let store = VaultStore(vault: vault)
        let text = try Self.readText(from: file)

        let atomized = try await skillRunner.run(
            "atomize-text",
            input: ["text": text, "source_id": file.lastPathComponent]
        )
        let units = (atomized["units"] as? [[String: Any]]) ?? []

        var result = IngestResult()

        for unit in units {
            let title = (unit["title"] as? String) ?? "Untitled"
            let body  = (unit["body"]  as? String) ?? ""

            let classified = try await skillRunner.run(
                "classify-node",
                input: ["unit_title": title, "unit_body": body]
            )
            let typeRaw = (classified["type"] as? String) ?? "note"
            let type = NodeType(rawValue: typeRaw) ?? .note

            let summarized = try await skillRunner.run(
                "summarize-note",
                input: ["title": title, "body": body]
            )
            let summary = (summarized["summary"] as? String) ?? ""

            // Embed and look up nearest existing notes so reconcile can see real
            // candidates. If embeddings are unavailable, the candidate list is
            // empty and reconcile defaults to `add`.
            var unitVector: [Float]? = nil
            var nearest: [[String: Any]] = []
            if let embeddings, let index {
                unitVector = try await embeddings.embed(body)
                if let v = unitVector {
                    let hits = await index.nearest(to: v, k: candidateK)
                    for hit in hits {
                        if let neighbor = try? await store.read(id: hit.id) {
                            nearest.append([
                                "id": neighbor.id,
                                "type": neighbor.type.rawValue,
                                "title": neighbor.title,
                                "summary": neighbor.summary,
                                "score": Double(hit.score),
                            ])
                        }
                    }
                }
            }

            let reconciled = try await skillRunner.run(
                "reconcile-note",
                input: [
                    "candidate": ["title": title, "body": body, "suggested_type": typeRaw],
                    "nearest": nearest,
                ]
            )
            let decision = (reconciled["decision"] as? String) ?? "add"

            switch decision {
            case "skip":
                result.skipped += 1

            case "improve":
                guard let targetId = reconciled["target_id"] as? String else {
                    result.quarantined += 1
                    continue
                }
                let existing = try await store.read(id: targetId)
                let improved = try await skillRunner.run(
                    "improve-note",
                    input: [
                        "existing": ["title": existing.title, "body": existing.body, "summary": existing.summary],
                        "candidate": ["title": title, "body": body],
                    ]
                )
                let newBody    = (improved["new_body"]    as? String) ?? existing.body
                let newSummary = (improved["new_summary"] as? String) ?? existing.summary
                var updated = existing
                updated.body = newBody
                updated.summary = newSummary
                updated.version += 1
                updated.updatedAt = dateProvider.now()
                updated.contentHash = Self.hash(newBody)
                try await store.write(updated)
                result.improved += 1

            default:  // add
                let now = dateProvider.now()
                var note = Note(
                    id: idGenerator.next(),
                    type: type,
                    title: title,
                    summary: summary,
                    body: body,
                    edges: [],
                    sources: [],
                    contentHash: Self.hash(body),
                    version: 1,
                    createdAt: now,
                    updatedAt: now,
                    supersededBy: nil
                )

                if !nearest.isEmpty || true {  // run edge inference whenever a candidate set exists OR for v1 always (skill self-limits)
                    let inferred = (try? await skillRunner.run(
                        "infer-edges",
                        input: [
                            "new_note": [
                                "id": note.id, "type": note.type.rawValue,
                                "title": note.title, "summary": note.summary, "body": note.body,
                            ],
                            "candidates": nearest,
                        ]
                    )) ?? [:]
                    note.edges = Self.parseEdges(from: inferred)
                }

                try await store.write(note)
                if let index, let unitVector {
                    await index.record(id: note.id, vector: unitVector)
                }
                result.added += 1
            }
        }

        if let index { try? await index.flush() }
        return result
    }

    // MARK: - Helpers

    private static func readText(from url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            let pages = try PDFExtractor().extract(url)
            return pages.map(\.text).joined(separator: "\n\n")
        default:
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    private static func parseEdges(from inferred: [String: Any]) -> [Edge] {
        guard let raw = inferred["edges"] as? [[String: Any]] else { return [] }
        return raw.compactMap { dict in
            guard let typeRaw = dict["type"] as? String,
                  let type = EdgeType(rawValue: typeRaw),
                  let target = dict["target_id"] as? String,
                  !target.isEmpty
            else { return nil }
            let evidence = dict["evidence"] as? String
            return Edge(type: type, target: target, evidence: evidence)
        }
    }

    private static func hash(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return "sha256-" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
