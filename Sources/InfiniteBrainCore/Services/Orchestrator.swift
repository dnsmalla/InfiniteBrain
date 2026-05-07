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
        concurrency: Int = 4,
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

        // Short-circuit: if a source note with this exact content_hash already
        // lives in the vault AND no in-flight checkpoint exists, the same file
        // has already been fully ingested — don't re-run the pipeline or
        // create a duplicate source note. Returns IngestResult.skipped = 1
        // so the caller can show "already ingested" to the user.
        let inFlight = (try? await checkpoints.load(fileHash: fileHash)) != nil
        if !inFlight {
            let existing = (try? await store.allNotes()) ?? []
            if existing.contains(where: { $0.type == .source && $0.contentHash == fileHash }) {
                return IngestResult(skipped: 1)
            }
        }

        // Resume if a checkpoint exists for this file content; otherwise start fresh.
        let checkpoint: Checkpoint
        let sourceNoteId: String
        let units: [[String: Any]]
        let reservedIds: [String]

        if let existing = try? await checkpoints.load(fileHash: fileHash) {
            checkpoint = existing
            sourceNoteId = existing.sourceId
            units = existing.units.map { u in
                ["title": u.title, "body": u.body]
            }
            reservedIds = existing.reservedIds
        } else {
            // Fresh ingest: write source note, atomise, save initial checkpoint.
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
                // Embed only the file name + a short snippet for the source.
                // Full text would blow Apple's NLEmbedding internal limit.
                let preview = "\(file.lastPathComponent): \(text.prefix(400))"
                if let v = try? await embeddings.embed(preview) {
                    await index.record(id: sourceNote.id, vector: v)
                }
            }
            sourceNoteId = sourceNote.id

            let chunks = TextChunker().chunk(text, targetChars: chunkSize)
            await progress("split into \(chunks.count) chunk(s)")
            var collected: [[String: Any]] = []
            for (idx, chunk) in chunks.enumerated() {
                do {
                    let atomized = try await skillRunner.run(
                        "atomize-text",
                        input: [
                            "text": chunk,
                            "source_id": sourceNote.id,
                            "chunk_index": idx,
                            "chunk_total": chunks.count,
                        ]
                    )
                    let chunkUnits = (atomized["units"] as? [[String: Any]]) ?? []
                    collected.append(contentsOf: chunkUnits)
                    await progress("chunk \(idx + 1)/\(chunks.count): \(chunkUnits.count) unit(s)")
                } catch {
                    // A failing atomize call (rate limit, malformed JSON,
                    // CLI timeout) should not abort the whole book. Log and
                    // move on so the user gets at least partial output.
                    await progress("chunk \(idx + 1)/\(chunks.count): atomize failed (\(Self.brief(error))), skipping")
                }
            }
            units = collected
            await progress("atomized \(units.count) total unit(s) from \(chunks.count) chunk(s)")
            reservedIds = (0..<units.count).map { _ in idGenerator.next() }

            checkpoint = Checkpoint(
                fileHash: fileHash,
                sourceId: sourceNote.id,
                units: units.map { u in
                    Checkpoint.Unit(
                        title: (u["title"] as? String) ?? "",
                        body: (u["body"] as? String) ?? "",
                        lineCount: u["line_count"] as? Int,
                        suggestedTypeHint: u["suggested_type_hint"] as? String
                    )
                },
                reservedIds: reservedIds,
                completedThrough: 0
            )
            try await checkpoints.save(checkpoint)
        }

        let startFrom = checkpoint.completedThrough
        let pendingUnits = Array(units[startFrom...])
        let pendingIds = Array(reservedIds[startFrom...])

        // PHASE A — decide outcomes for pending units in parallel.
        let outcomes = try await decideOutcomes(
            units: pendingUnits,
            reservedIds: pendingIds,
            sourceId: sourceNoteId,
            sourceLabel: file.lastPathComponent,
            store: store
        )

        // PHASE B — apply outcomes serially. Persist progress after each so a
        // crash mid-batch resumes exactly from the next pending unit.
        var result = IngestResult()
        var working = checkpoint
        for (offset, outcome) in outcomes.enumerated() {
            switch outcome {
            case .skip:
                result.skipped += 1
            case .quarantine:
                result.quarantined += 1
            case .improve(let updated):
                try await store.write(updated)
                result.improved += 1
            case .add(let note, let vector):
                try await store.write(note)
                if let index, let vector {
                    await index.record(id: note.id, vector: vector)
                }
                result.added += 1
            }
            working.completedThrough = startFrom + offset + 1
            try await checkpoints.save(working)
        }

        // All units done — drop the checkpoint and flush the index.
        try await checkpoints.delete(fileHash: fileHash)
        if let index {
            do { try await index.flush() }
            catch { /* index is rebuildable from the markdown; surfaced via caller */ }
        }
        return result
    }

    // MARK: - Phase A: parallel decision

    /// Runs the per-unit decision pipeline in parallel up to `concurrency`,
    /// preserving the original unit order in the returned outcomes array.
    private func decideOutcomes(
        units: [[String: Any]],
        reservedIds: [String],
        sourceId: String,
        sourceLabel: String,
        store: VaultStore
    ) async throws -> [UnitOutcome] {
        guard !units.isEmpty else { return [] }
        precondition(reservedIds.count == units.count, "must reserve one id per unit")

        var outcomes: [(Int, UnitOutcome)] = []
        outcomes.reserveCapacity(units.count)

        // Tasks are non-throwing here: a single unit's failure quarantines
        // it instead of aborting the whole book. Errors are logged via the
        // progress channel.
        await withTaskGroup(of: (Int, UnitOutcome).self) { group in
            var nextToSubmit = 0
            let total = units.count
            for _ in 0..<min(concurrency, units.count) {
                let i = nextToSubmit; nextToSubmit += 1
                let unit = units[i]; let id = reservedIds[i]
                group.addTask { [self] in
                    do {
                        return (i, try await decideOne(
                            unit: unit, reservedId: id,
                            sourceId: sourceId, sourceLabel: sourceLabel, store: store
                        ))
                    } catch {
                        await progress("unit \(i + 1)/\(total): \(Self.brief(error)), quarantined")
                        return (i, .quarantine)
                    }
                }
            }
            while let pair = await group.next() {
                outcomes.append(pair)
                await progress("unit \(pair.0 + 1)/\(total) decided (\(outcomes.count)/\(total) done)")
                if nextToSubmit < units.count {
                    let i = nextToSubmit; nextToSubmit += 1
                    let unit = units[i]; let id = reservedIds[i]
                    group.addTask { [self] in
                        do {
                            return (i, try await decideOne(
                                unit: unit, reservedId: id,
                                sourceId: sourceId, sourceLabel: sourceLabel, store: store
                            ))
                        } catch {
                            await progress("unit \(i + 1)/\(total): \(Self.brief(error)), quarantined")
                            return (i, .quarantine)
                        }
                    }
                }
            }
        }

        return outcomes.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

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
