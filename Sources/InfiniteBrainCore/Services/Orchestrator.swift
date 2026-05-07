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

/// Outcome from the parallel decision phase. Phase B applies these serially
/// so the vault and the embedding index stay consistent.
enum UnitOutcome: Sendable {
    case skip
    case quarantine
    case improve(updated: Note)
    case add(note: Note, vector: [Float]?)
}

/// Sequences pipeline stages per ingested file.
///
/// End-to-end flow:
///   read → atomize (per chunk) → for each unit, in parallel:
///     classify → summarize → embed → fetch nearest → reconcile →
///     (if add: build note + infer-edges)
///     (if improve: read existing + improve-note)
///   then serially: write outcomes to vault and update index.
///
/// `concurrency` controls how many units the parallel decision phase runs
/// at once. Defaults to 4. Within a batch, units don't see each other in the
/// candidate set — that's the documented trade-off for the speedup.
public typealias ProgressHandler = @Sendable (String) async -> Void

public actor Orchestrator {
    public let skillRunner: SkillRunner
    public let idGenerator: IDGenerator
    public let dateProvider: DateProvider
    public let embeddings: EmbeddingProvider?
    public let index: EmbeddingIndex?
    public let candidateK: Int
    public let confidenceThreshold: Float
    public let chunkSize: Int
    public let concurrency: Int
    public let onProgress: ProgressHandler?

    public init(
        skillRunner: SkillRunner,
        idGenerator: IDGenerator = ULIDGenerator(),
        dateProvider: DateProvider = SystemDateProvider(),
        embeddings: EmbeddingProvider? = nil,
        index: EmbeddingIndex? = nil,
        candidateK: Int = 5,
        confidenceThreshold: Float = 0.7,
        chunkSize: Int = 16_000,
        concurrency: Int = 2,
        onProgress: ProgressHandler? = nil
    ) {
        self.skillRunner = skillRunner
        self.idGenerator = idGenerator
        self.dateProvider = dateProvider
        self.embeddings = embeddings
        self.index = index
        self.candidateK = candidateK
        self.confidenceThreshold = confidenceThreshold
        self.chunkSize = chunkSize
        self.concurrency = max(1, concurrency)
        self.onProgress = onProgress
    }

    private func progress(_ line: String) async {
        await onProgress?(line)
    }

    public func ingest(file: URL, into vault: Vault) async throws -> IngestResult {
        let store = VaultStore(vault: vault)
        let checkpoints = CheckpointStore(vault: vault)
        let text = try Self.readText(from: file)
        let fileHash = Self.hash(text)

        // Short-circuit logic for re-ingest:
        //   - In-flight checkpoint?  → resume below.
        //   - No source with this hash?  → fresh ingest.
        //   - Source AND ≥1 atomic note citing it?  → fully done, skip.
        //   - Source but NO atomic notes citing it?  → orphaned source from a
        //     previous failed ingest. Delete the orphan and proceed fresh
        //     (otherwise we'd skip forever and the user could never recover).
        let inFlight = (try? await checkpoints.load(fileHash: fileHash)) != nil
        if !inFlight {
            let existing = (try? await store.allNotes()) ?? []
            if let prior = existing.first(where: { $0.type == .source && $0.contentHash == fileHash }) {
                let cited = existing.contains { $0.type != .source && $0.sources.contains(prior.id) }
                if cited {
                    return IngestResult(skipped: 1)
                }
                // Orphan — clean up so the fresh ingest doesn't leave
                // duplicate source notes behind.
                try? await store.delete(id: prior.id)
                await progress("found incomplete previous ingest, re-running")
            }
        }

        // Streaming pipeline: write source note up-front, then per-chunk
        // atomize → decide-each-unit → write-immediately. Multiple chunks
        // run in parallel up to `concurrency`. Notes appear in the vault as
        // chunks finish, instead of all at the end.
        let now = dateProvider.now()
        let sourceNote = Note(
            id: idGenerator.next(),
            type: .source,
            title: file.lastPathComponent,
            summary: "Original source: \(file.lastPathComponent).",
            body: "Path: \(file.path)",
            edges: [],
            sources: [],
            contentHash: fileHash,
            version: 1,
            createdAt: now,
            updatedAt: now
        )
        try await store.write(sourceNote)
        if let embeddings, let index {
            let preview = "\(file.lastPathComponent): \(text.prefix(400))"
            if let v = try? await embeddings.embed(preview) {
                await index.record(id: sourceNote.id, vector: v)
            }
        }
        let sourceId = sourceNote.id
        let label = file.lastPathComponent

        let chunks = TextChunker().chunk(text, targetChars: chunkSize)
        let total = chunks.count
        await progress("split into \(total) chunk(s) — pipelining up to \(concurrency) at once")

        // Per-chunk pipeline: atomize → for each unit: decide → write.
        @Sendable func processChunk(_ i: Int) async -> IngestResult {
            // Atomize with one retry.
            var atomized: [[String: Any]] = []
            for attempt in 0..<2 {
                do {
                    let r = try await skillRunner.run("atomize-text", input: [
                        "text": chunks[i], "source_id": sourceId,
                        "chunk_index": i, "chunk_total": total,
                    ])
                    atomized = (r["units"] as? [[String: Any]]) ?? []
                    await progress("chunk \(i + 1)/\(total): atomized → \(atomized.count) unit(s)")
                    break
                } catch {
                    if attempt == 0 {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await progress("chunk \(i + 1)/\(total): retrying after \(Self.brief(error))")
                        continue
                    }
                    await progress("chunk \(i + 1)/\(total): atomize failed (\(Self.brief(error))), skipping")
                    return IngestResult()
                }
            }

            // Decide + write each unit. Serial within a chunk so the user sees
            // notes accrue at a steady pace.
            var local = IngestResult()
            for (j, unit) in atomized.enumerated() {
                let reservedId = idGenerator.next()
                let outcome: UnitOutcome
                do {
                    outcome = try await decideOne(
                        unit: unit, reservedId: reservedId,
                        sourceId: sourceId, sourceLabel: label, store: store
                    )
                } catch {
                    await progress("chunk \(i + 1)/\(total) unit \(j + 1)/\(atomized.count): \(Self.brief(error))")
                    local.quarantined += 1
                    continue
                }
                switch outcome {
                case .skip: local.skipped += 1
                case .quarantine: local.quarantined += 1
                case .improve(let updated):
                    try? await store.write(updated)
                    local.improved += 1
                case .add(let note, let vector):
                    try? await store.write(note)
                    if let index, let vector {
                        await index.record(id: note.id, vector: vector)
                    }
                    local.added += 1
                }
            }
            await progress("chunk \(i + 1)/\(total) done: +\(local.added) added, \(local.improved) improved, \(local.skipped) skipped")
            return local
        }

        // Keep `checkpoints` referenced so unused-variable warnings stay quiet
        // while the streaming version forgoes mid-run resume. The orphan
        // detect above already handles "previous ingest never completed".
        _ = checkpoints

        var result = IngestResult()
        await withTaskGroup(of: IngestResult.self) { group in
            var nextSubmit = 0
            for _ in 0..<min(concurrency, total) {
                let i = nextSubmit; nextSubmit += 1
                group.addTask { await processChunk(i) }
            }
            while let r = await group.next() {
                result.added += r.added
                result.improved += r.improved
                result.skipped += r.skipped
                result.quarantined += r.quarantined
                if nextSubmit < total {
                    let i = nextSubmit; nextSubmit += 1
                    group.addTask { await processChunk(i) }
                }
            }
        }

        if let index {
            do { try await index.flush() }
            catch { /* index is rebuildable from the markdown */ }
        }
        return result
    }

    // MARK: - Phase A: parallel decision

    /// Runs the per-unit decision pipeline in parallel up to `concurrency`,
    /// preserving the original unit order in the returned outcomes array.
    private func decideOne(
        unit: [String: Any],
        reservedId: String,
        sourceId: String,
        sourceLabel: String,
        store: VaultStore
    ) async throws -> UnitOutcome {
        let title = (unit["title"] as? String) ?? "Untitled"
        let body  = (unit["body"]  as? String) ?? ""

        let classified = try await skillRunner.run(
            "classify-node",
            input: ["unit_title": title, "unit_body": body]
        )
        let typeRaw = (classified["type"] as? String) ?? "note"
        let confidence = Self.numberValue(classified["confidence"])
        let lowConfidence = confidence < confidenceThreshold
        let type = lowConfidence ? .custom : (NodeType(rawValue: typeRaw) ?? .note)

        let summarized = try await skillRunner.run(
            "summarize-note",
            input: ["title": title, "body": body]
        )
        let summary = (summarized["summary"] as? String) ?? ""

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
            return .skip

        case "improve":
            guard let targetId = reconciled["target_id"] as? String else { return .quarantine }
            let existing: Note
            do { existing = try await store.read(id: targetId) }
            catch { return .quarantine }
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
            return .improve(updated: updated)

        default:  // add
            let writeNow = dateProvider.now()
            var note = Note(
                id: reservedId,
                type: type,
                title: title,
                summary: summary,
                body: body,
                edges: [Edge(type: .derivedFrom, target: sourceId, evidence: "extracted from \(sourceLabel)")],
                sources: [sourceId],
                contentHash: Self.hash(body),
                version: 1,
                createdAt: writeNow,
                updatedAt: writeNow,
                needsReview: lowConfidence
            )
            if !nearest.isEmpty {
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
                note.edges.append(contentsOf: Self.parseEdges(from: inferred))
            }
            return .add(note: note, vector: unitVector)
        }
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

    /// Short error description for progress logs — e.g. "rate_limit",
    /// "timed out", or the first line of a longer message.
    static func brief(_ error: any Error) -> String {
        let s = String(describing: error)
            .replacingOccurrences(of: "\n", with: " ")
        return String(s.prefix(120))
    }

    private static func numberValue(_ any: Any?) -> Float {
        if let d = any as? Double { return Float(d) }
        if let f = any as? Float { return f }
        if let i = any as? Int { return Float(i) }
        if let n = any as? NSNumber { return n.floatValue }
        return 0
    }

    private static func hash(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return "sha256-" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
