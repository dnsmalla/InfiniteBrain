import Foundation
import GraphKit
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
public typealias UsageHandler = @Sendable (LLMUsage) -> Void

public actor Orchestrator {
    public let checkpoints: CheckpointStore
    public let skillRunner: SkillRunner
    public let idGenerator: IDGenerator
    public let dateProvider: DateProvider
    public let embeddings: EmbeddingProvider?
    public let index: EmbeddingIndex?
    public let metadataIndex: MetadataIndex?
    public let candidateK: Int
    public let confidenceThreshold: Float
    public let chunkSize: Int
    public let concurrency: Int
    public let onProgress: ProgressHandler?
    public let onUsage: UsageHandler?

    public init(
        skillRunner: SkillRunner,
        idGenerator: IDGenerator = ULIDGenerator(),
        dateProvider: DateProvider = SystemDateProvider(),
        checkpoints: CheckpointStore,
        embeddings: EmbeddingProvider? = nil,
        index: EmbeddingIndex? = nil,
        metadataIndex: MetadataIndex? = nil,
        candidateK: Int = 5,
        confidenceThreshold: Float = 0.7,
        chunkSize: Int = 16_000,
        concurrency: Int = 2,
        onProgress: ProgressHandler? = nil,
        onUsage: UsageHandler? = nil
    ) {
        self.skillRunner = skillRunner
        self.idGenerator = idGenerator
        self.dateProvider = dateProvider
        self.checkpoints = checkpoints
        self.embeddings = embeddings
        self.index = index
        self.metadataIndex = metadataIndex
        self.candidateK = candidateK
        self.confidenceThreshold = confidenceThreshold
        self.chunkSize = chunkSize
        self.concurrency = max(1, concurrency)
        self.onProgress = onProgress
        self.onUsage = onUsage
    }

    /// Reverts an entire ingestion batch, deleting all generated atomic notes.
    public func revertIngest(sourceId: String, in vault: Vault) async throws {
        guard let metadataIndex = metadataIndex else { return }
        let store = VaultStore(vault: vault)
        
        let all = await metadataIndex.allEntries()
        let noteIds = all.filter { $0.sources.contains(sourceId) }.map { $0.id }
        
        for id in noteIds {
            // Read note first to know where it points (to update indices)
            if let _ = try? await store.read(id: id) {
                await metadataIndex.remove(noteId: id)
                if let index = index { await index.remove(id: id) }
            }
            try? await store.delete(id: id)
        }
        
        // Final flush
        if let index = index { try? await index.flush() }
        try? await metadataIndex.save()
    }

    private func progress(_ line: String) async {
        await onProgress?(line)
    }

    public func ingest(file: URL, into vault: Vault) async throws -> IngestResult {
        let store = VaultStore(vault: vault)
        let checkpoints = CheckpointStore(vault: vault)
        let text = try await readText(from: file)
        let fileHash = Self.hash(text)

        // Professional Scan: Identify active regions and skip junk
        let scanResult = DocumentScanner().scan(text)
        if scanResult.skippedCount > 0 {
            await progress("professional scan: identifies \(scanResult.skippedCount) junk regions to skip")
        }
        
        let activeText = scanResult.activeRanges.map { String(text[$0]) }.joined(separator: "\n\n")
        let chunks = TextChunker().chunk(activeText, targetChars: chunkSize)
        let total = chunks.count

        // Re-ingest logic:
        //   - Checkpoint exists AND complete  → fully done, skip.
        //   - Checkpoint exists AND incomplete → resume only missing chunks.
        //   - No checkpoint, source matches    → orphan → delete source, fresh.
        //   - No checkpoint, no source         → fresh.
        let existingCheckpoint = (try? await checkpoints.load(fileHash: fileHash)) ?? nil
        let pendingIndices: [Int]
        let sourceNote: Note
        let isResume: Bool

        if let cp = existingCheckpoint, cp.chunkCount == total {
            if cp.isComplete {
                await progress("already fully ingested (\(cp.chunkCount) chunks). skipping.")
                return IngestResult(skipped: 1)
            }
            // Resume: source note must already be in the vault.
            let resumed: Note
            do { resumed = try await store.read(id: cp.sourceId) }
            catch {
                // Source somehow missing — treat as fresh.
                try? await checkpoints.delete(fileHash: fileHash)
                return try await ingest(file: file, into: vault)  // recurse once with clean state
            }
            sourceNote = resumed
            pendingIndices = cp.pendingChunkIndices
            isResume = true
            await progress("resuming previous ingest — \(pendingIndices.count) of \(cp.chunkCount) chunk(s) still to do")
        } else {
            // Fresh: drop any stale checkpoint, clean up orphan source if any.
            if existingCheckpoint != nil {
                try? await checkpoints.delete(fileHash: fileHash)
            }
            let existing = (try? await store.allNotes()) ?? []
            if let prior = existing.first(where: { $0.type == .source && $0.contentHash == fileHash }) {
                try? await store.delete(id: prior.id)
                await progress("found incomplete previous ingest, re-running")
            }
            // Write fresh source note.
            let now = dateProvider.now()
            sourceNote = Note(
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
            try await store.write(sourceNote, in: VaultStore.folderName(forSourceTitle: sourceNote.title))
            if let embeddings, let index {
                let preview = "\(file.lastPathComponent): \(text.prefix(400))"
                if let v = try? await embeddings.embed(preview) {
                    await index.record(id: sourceNote.id, vector: v)
                }
            }
            await metadataIndex?.update(sourceNote)
            // Initial empty checkpoint so we can mark chunks as they complete.
            try? await checkpoints.save(Checkpoint(
                fileHash: fileHash,
                sourceId: sourceNote.id,
                chunkCount: total,
                completedChunks: []
            ))
            pendingIndices = Array(0..<total)
            isResume = false
        }

        let sourceId = sourceNote.id
        let label = file.lastPathComponent
        // Compute the source folder once; threaded through every write so
        // VaultStore doesn't have to re-resolve it per atomic note.
        let sourceFolder = VaultStore.folderName(forSourceTitle: sourceNote.title)

        if isResume {
            await progress("split into \(total) chunk(s) — \(pendingIndices.count) pending, pipelining up to \(concurrency) at once")
        } else {
            await progress("split into \(total) chunk(s) — pipelining up to \(concurrency) at once")
        }

        // Unified task-based pipeline:
        // We use a TaskGroup to manage all concurrent LLM calls (atomizing AND processing).
        // This ensures unit-level parallelism across all chunks.
        enum WorkResult {
            case chunkAtomized(index: Int, units: [[String: Any]])
            case unitProcessed(chunkIndex: Int, result: IngestResult)
            case error(String)
        }

        var result = IngestResult()
        var pendingUnitsPerChunk: [Int: Int] = [:]
        var chunkResults: [Int: IngestResult] = [:]
        
        try await withThrowingTaskGroup(of: WorkResult.self) { group in
            var chunkIterator = pendingIndices.makeIterator()
            var activeLLMCalls = 0
            // Units produced by atomized chunks, waiting for a free slot. Draining
            // these before atomizing new chunks bounds in-flight work (and memory)
            // to `concurrency` regardless of how many units a chunk yields.
            var pendingUnits: [(chunkIndex: Int, unit: [String: Any], reservedId: String)] = []

            // Each launcher increments `activeLLMCalls` exactly once; the main loop
            // decrements exactly once per received WorkResult. This is the single
            // accounting model that actually enforces `concurrency`.
            func launchChunk() -> Bool {
                guard activeLLMCalls < concurrency, let i = chunkIterator.next() else { return false }
                activeLLMCalls += 1
                group.addTask {
                    let chunk = chunks[i]
                    do {
                        let r = try await self.skillRunner.run(
                            "atomize-text",
                            input: [
                                "text": chunk.text,
                                "source_id": sourceNote.id,
                                "context_header": chunk.contextHeader ?? "",
                                "chunk_index": i,
                                "chunk_total": total
                            ],
                            onUsage: self.onUsage
                        )
                        let atomized = (r["units"] as? [[String: Any]]) ?? []
                        return .chunkAtomized(index: i, units: atomized)
                    } catch {
                        return .error("chunk \(i + 1) atomize failed: \(Self.brief(error))")
                    }
                }
                return true
            }

            func launchUnit() -> Bool {
                guard activeLLMCalls < concurrency, !pendingUnits.isEmpty else { return false }
                let item = pendingUnits.removeFirst()
                activeLLMCalls += 1
                group.addTask { [self] in
                    do {
                        let outcome = try await self.decideOne(
                            unit: item.unit, reservedId: item.reservedId,
                            sourceId: sourceId, sourceLabel: label, store: store
                        )
                        var local = IngestResult()
                        switch outcome {
                        case .skip: local.skipped += 1
                        case .quarantine: local.quarantined += 1
                        case .improve(let updated):
                            try await store.write(updated, in: sourceFolder)
                            local.improved += 1
                        case .add(let note, let vector):
                            try await store.write(note, in: sourceFolder)
                            if let index = self.index, let vector = vector { await index.record(id: note.id, vector: vector) }
                            local.added += 1
                        }
                        return .unitProcessed(chunkIndex: item.chunkIndex, result: local)
                    } catch {
                        await self.progress("unit failed (\(Self.brief(error))) — quarantined")
                        var local = IngestResult()
                        local.quarantined += 1
                        return .unitProcessed(chunkIndex: item.chunkIndex, result: local)
                    }
                }
                return true
            }

            // Fill available capacity, preferring to finish in-flight chunks' units
            // before atomizing more chunks. Stops launching new work once cancelled.
            func pump() {
                guard !Task.isCancelled else { return }
                while launchUnit() || launchChunk() {}
            }

            pump()
            
            while let work = try await group.next() {
                switch work {
                case .chunkAtomized(let i, let units):
                    activeLLMCalls -= 1
                    if units.isEmpty {
                        _ = try? await checkpoints.markChunkComplete(fileHash: fileHash, chunkIndex: i)
                        await progress("chunk \(i + 1)/\(total) done (empty)")
                    } else {
                        pendingUnitsPerChunk[i] = units.count
                        chunkResults[i] = IngestResult()
                        await progress("chunk \(i + 1)/\(total): atomized → \(units.count) unit(s)")
                        // Queue units; pump() launches them up to capacity.
                        for unit in units {
                            pendingUnits.append((chunkIndex: i, unit: unit, reservedId: idGenerator.next()))
                        }
                    }
                    pump()

                case .unitProcessed(let i, let r):
                    activeLLMCalls -= 1
                    result.added += r.added
                    result.improved += r.improved
                    result.skipped += r.skipped
                    result.quarantined += r.quarantined

                    if var current = chunkResults[i] {
                        current.added += r.added
                        current.improved += r.improved
                        current.skipped += r.skipped
                        current.quarantined += r.quarantined
                        chunkResults[i] = current
                    }

                    pendingUnitsPerChunk[i, default: 0] -= 1
                    if pendingUnitsPerChunk[i] == 0 {
                        let final = chunkResults[i] ?? IngestResult()
                        _ = try? await checkpoints.markChunkComplete(fileHash: fileHash, chunkIndex: i)
                        await progress("chunk \(i + 1)/\(total) done: +\(final.added) added, \(final.improved) improved")
                        if let index { try? await index.flush() }
                    }
                    pump()

                case .error(let msg):
                    activeLLMCalls -= 1
                    await progress(msg)
                    pump()
                }
            }
        }

        if let index {
            do { try await index.flush() }
            catch { /* index is rebuildable from the markdown */ }
        }
        try? await metadataIndex?.save()

        // Keep the checkpoint either way:
        //   - Fully complete (all chunks marked) → re-ingest sees isComplete
        //     and short-circuits with skipped=1.
        //   - Cancelled or partial → completedChunks reflects what's done,
        //     re-ingest resumes the missing indices.
        let final = (try? await checkpoints.load(fileHash: fileHash)) ?? nil
        if let final, final.isComplete {
            await progress("ingest complete — \(final.chunkCount)/\(final.chunkCount) chunk(s)")
        } else if Task.isCancelled {
            await progress("cancelled — \((final?.completedChunks.count ?? 0))/\(total) chunk(s) saved; re-run to resume")
        } else if let final {
            let pending = total - final.completedChunks.count
            if pending > 0 {
                await progress("\(pending) chunk(s) didn't complete — re-run to retry")
            }
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

        let processed = try await skillRunner.run(
            "process-unit",
            input: ["unit_title": title, "unit_body": body],
            onUsage: onUsage
        )
        let typeRaw = (processed["type"] as? String) ?? "note"
        let confidence = Self.numberValue(processed["confidence"])
        let lowConfidence = confidence < confidenceThreshold
        let type = lowConfidence ? .custom : NodeType(rawValue: typeRaw)
        let summary = (processed["summary"] as? String) ?? ""

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
            ],
            onUsage: onUsage
        )
        let decision = (reconciled["decision"] as? String) ?? "add"

        switch decision {
        case "skip":
            return .skip

        case "improve":
            guard let targetId = reconciled["target_id"] as? String else {
                await progress("reconcile said 'improve' but gave no target_id — quarantined")
                return .quarantine
            }
            let existing: Note
            do { existing = try await store.read(id: targetId) }
            catch {
                await progress("couldn't read improve target \(targetId) (\(Self.brief(error))) — quarantined")
                return .quarantine
            }
            let improved = try await skillRunner.run(
                "improve-note",
                input: [
                    "existing": ["title": existing.title, "body": existing.body, "summary": existing.summary],
                    "candidate": ["title": title, "body": body],
                ],
                onUsage: onUsage
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
            // NOTE: do not update the metadata index here. The note hasn't been
            // written to disk yet (that happens in Phase B), and VaultStore.write
            // updates the index itself. Updating here created an index entry for a
            // note that might never be written if the write later fails → divergence.
            if !nearest.isEmpty {
                let inferred = (try? await skillRunner.run(
                    "infer-edges",
                    input: [
                        "new_note": [
                            "id": note.id, "type": note.type.rawValue,
                            "title": note.title, "summary": note.summary, "body": note.body,
                        ],
                        "candidates": nearest,
                    ],
                    onUsage: onUsage
                )) ?? [:]
                note.edges.append(contentsOf: Self.parseEdges(from: inferred))
            }
            return .add(note: note, vector: unitVector)
        }
    }

    // MARK: - Helpers

    private func readText(from url: URL) async throws -> String {
        let result = try InputReader.read(url)
        if result.ocrPages > 0 {
            await progress("OCR'd \(result.ocrPages) of \(result.totalPages) page(s) from \(url.lastPathComponent)")
        }
        return result.text
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
