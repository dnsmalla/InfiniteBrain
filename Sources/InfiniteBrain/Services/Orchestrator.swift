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

/// Sequences pipeline stages per ingested file. End-to-end happy path:
///   read → atomize → (per unit) classify → summarize → reconcile → write/skip/improve.
/// Edge inference is omitted from v1 — wired in once embeddings land.
public actor Orchestrator {
    public let skillRunner: SkillRunner
    public let idGenerator: IDGenerator
    public let dateProvider: DateProvider

    public init(
        skillRunner: SkillRunner,
        idGenerator: IDGenerator = ULIDGenerator(),
        dateProvider: DateProvider = SystemDateProvider()
    ) {
        self.skillRunner = skillRunner
        self.idGenerator = idGenerator
        self.dateProvider = dateProvider
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

            let reconciled = try await skillRunner.run(
                "reconcile-note",
                input: [
                    "candidate": ["title": title, "body": body, "suggested_type": typeRaw],
                    "nearest": [],   // empty until embeddings land
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
                let note = Note(
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
                try await store.write(note)
                result.added += 1
            }
        }

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

    private static func hash(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return "sha256-" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
