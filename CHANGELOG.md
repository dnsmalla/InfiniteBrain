# Changelog

## [0.8.0] — 2026-05-07

Graph view — see the knowledge graph the app has been building, not just
a list of files.

- New `GraphLayout` (in InfiniteBrainCore, pure function): maps notes onto
  a circular type-clustered layout. Each of the 16 NodeTypes gets a slice
  of the canvas; notes within a type spread along three concentric rings.
  Dangling edges (target missing from the input) are dropped.
- `VaultStore.allNotes()` reads every note in a vault, silently skipping
  files that fail to parse so a single corrupted note can't take down the
  listing.
- `GraphView` (in the GUI target) renders the layout via SwiftUI Canvas
  with a hand-picked 16-colour palette, hit-tests taps to select a node,
  and shows a sidebar with the selected note's type / title / summary or
  a colour legend when nothing is selected.
- The graph relayouts on window resize so it always fills the canvas.

3 new layout tests cover empty input, position bounds, and dangling-edge
filtering. 51 tests green (31 InfiniteBrain, 20 SharedLLMKit).

## [0.7.0] — 2026-05-07

App packaging — InfiniteBrain.app and a distributable .dmg can now be
produced from the repo with one command.

- `bin/build_app.sh` builds the SwiftPM release product, lays out a proper
  `.app` bundle (Contents/{MacOS, Resources, Info.plist, PkgInfo}), copies
  the `InfiniteBrain_InfiniteBrainCore.bundle` resource bundle alongside the
  binary, code-signs with an ad-hoc identity by default, and copies the
  `infb` CLI alongside.
- `--dmg` flag wraps the `.app` in a UDZO-compressed disk image via
  `hdiutil`.
- `--sign IDENTITY` passes through to `codesign` for a real Developer ID.
- Output goes to `.build/dist/` (already gitignored).
- Removed empty placeholder folders (`Resources/Assets.xcassets`,
  `Resources/prompts`) that were tripping a SwiftPM "unhandled file"
  warning.

## [0.6.0] — 2026-05-07

Concurrency + crash recovery — long-book ingest is now both faster and
durable.

Per-unit concurrency
- New `concurrency` parameter on `Orchestrator` (default 4) runs the
  per-unit decision pipeline (classify, summarize, embed, reconcile,
  infer-edges/improve-note) in parallel via a sliding TaskGroup.
- Phase B writes outcomes serially in input order so the vault and the
  embedding index stay consistent. Cuts a 100-unit ingest from ~12 minutes
  to roughly a quarter of that on the API path.
- IDs are reserved up-front in input order so parallel tasks can't race on
  the id generator.

Checkpoint-based resume
- New `CheckpointStore` writes a per-file JSON checkpoint to
  `<vault>/.infinitebrain/checkpoints/sha256-<hash>.json` after every
  successful unit apply.
- The checkpoint records the source-note id, the atomized units, the
  reserved ids, and the index of the next unit to apply.
- On the next ingest of the same content, the orchestrator finds the
  checkpoint and skips: the source-note write, the atomize-text calls
  (the expensive part), and any units already applied. It picks up at
  the next pending unit with stable ids.
- Once every unit is applied the checkpoint file is deleted; rerunning
  ingest on a finished file is a no-op (well-typed).

Tests
- New `CheckpointStoreTests` and `CheckpointResumeTests` cover the
  round-trip and the resume path (verified by ingesting with no
  `atomize-text` route — proves the call was skipped).
- 48 tests green (28 InfiniteBrain, 20 SharedLLMKit).

## [0.5.0] — 2026-05-07

CLI: `infb` executable provides the same ingest + query pipeline from the
terminal, so a folder of PDFs can be processed without opening the GUI.

```
infb ingest book.pdf chapter1.md  --vault ~/MyBrain
infb query  "what did we decide about pricing?"  --vault ~/MyBrain
infb seed   ~/MyBrain
```

`ANTHROPIC_API_KEY` and `INFINITEBRAIN_VAULT` env vars are honored, so
shell scripts and cron jobs don't need to repeat flags.

Refactor
- Models, services, view-models, and bundled skills/rules moved into a new
  `InfiniteBrainCore` library target. Both the `InfiniteBrain` GUI and the
  `infb` CLI executables depend on it
- `Vault.init` is now public; `BundledResources` exposes the skills/rules
  paths so consumers don't need to reach into `Bundle.module`

## [0.4.0] — 2026-05-06

Scale handling: works for inputs from a few paragraphs up to a 500-page book.

- New `TextChunker` splits long input on paragraph boundaries (then sentence,
  then hard char split as a last resort), respecting a configurable
  `chunkSize` (default 16,000 chars ≈ ~4k tokens).
- Orchestrator no longer sends the entire document to `atomize-text` in one
  call. Each chunk is atomised separately and the resulting units are
  flattened, so a 500-page book naturally produces hundreds of atomic notes
  instead of being silently truncated to ~10–20 by the response token cap.
- `atomize-text` SKILL.md updated: now declares `chunk_index` /
  `chunk_total` inputs and tells the model not to invent cross-chunk
  structure.
- `AnthropicClient.maxTokens` default raised 4096 → 8192 to give atomize and
  improve-note room to breathe.
- IngestView log prints file size and approximate chunk count up front so
  long ingests are observable.

## [0.3.0] — 2026-05-06

Production-readiness pass driven by an honest internal review.

Fixed
- Edge inference no longer fires on every add (was guarded by an
  always-true condition). Now runs only when the candidate set is non-empty.
- Citation policy is now enforced. Every ingested file produces a `source`
  note up front, and every atomic note carries `sources: [<source-id>]`
  plus a `derived_from` edge back to it.
- AnthropicClient retries on 429 and 5xx with exponential backoff, honoring
  `Retry-After`. Other 4xx still throw immediately. Configurable via
  `RetryPolicy(maxAttempts:baseDelaySeconds:)`.
- Low-confidence classifications (`< 0.7`) are routed to `custom` and the
  resulting note is marked `needs_review: true` in frontmatter. The Vault
  browser shows a yellow warning icon next to flagged notes.
- Index flush failures no longer pass silently; surfaced via the orchestrator's
  do/catch path and the index is rebuildable from the markdown anyway.

Known limitations (deferred)
- Token budgets in `token-budget.mdc` are still documentation-only; no
  per-stage truncation yet.
- Per-unit work is still serial; orchestration-policy.mdc's "concurrency
  up to 4" is not implemented.
- No checkpointing — a crash mid-ingest re-runs from the file start.

## [0.2.0] — 2026-05-06

- VaultInitializer seeds `inbox/`, `notes/`, and copies bundled skills + rules
  into `<vault>/.infinitebrain/` on first ingest. User-edited skills are
  preserved across re-runs.
- Edge inference: after every `add` the orchestrator calls `infer-edges`
  with the new note + nearest candidates, and persists returned edges into
  the note's frontmatter.
- New `answer-question` skill and `QueryService` provide single-pass
  retrieval-augmented answering: embed the question, take top-K nearest
  notes, hand them to the skill, return answer + cited ids.
- QueryView wires the service end-to-end with a text field, Cmd-Return
  shortcut, and citation list.

## [0.1.0] — 2026-05-06

- Initial scaffold: SwiftUI app shell, SharedLLMKit local package, skill +
  rule files for the full ingest pipeline, sidecar SQLite schema docs.
