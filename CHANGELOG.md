# Changelog

## [0.17.0] — 2026-05-07

Two requested features.

Stop button
- Run button flips to a red "Stop" while an ingest is running.
  Clicking it cancels the in-flight Task. Atomic notes already
  written stay in the vault, the checkpoint records what's done,
  and a future Run resumes from the missing chunks.
- Orchestrator checks Task.isCancelled at chunk + unit boundaries
  and bails before submitting another LLM call. CancellationError
  thrown by an in-flight skill call is caught cleanly, no retry,
  no log noise.

Per-chunk resume of incomplete ingests
- Checkpoint schema redesigned: `completedChunks: Set<Int>`
  instead of a contiguous `completedThrough` index, because
  streaming chunks can finish out of order.
- Checkpoint is now persisted across runs (not deleted on success):
  - isComplete=true (all chunks done) → re-ingest skips with
    `IngestResult.skipped = 1`.
  - isComplete=false (some pending) → re-ingest atomizes only the
    missing chunks. Source note + already-written atomic notes
    are kept; pending chunks pick up from where they stopped.
- Each chunk task atomically updates the checkpoint via
  `markChunkComplete` after its writes land.
- Orphan detect (source exists but no checkpoint) still cleans up
  and re-runs fresh — covers vaults from before this version.

Tests: 37 InfiniteBrain (+1 in CheckpointStore for the new
markChunkComplete + isComplete logic) + 30 SharedLLMKit = 67.

## [0.16.0] — 2026-05-07

Per-source folder layout + skip-boilerplate rule.

Folder layout
- Was: `notes/<type>/<id>--<slug>.md`. Two PDFs each producing 200 notes
  meant 400 mixed files in `notes/decision/`, hard to tell which book a
  note came from.
- Now: `notes/<source-slug>/<type>/<id>--<slug>.md`. Every note from a
  given input file lives under that file's slugified-name folder, with
  type still as a subfolder so the per-book Obsidian view groups
  cleanly.
- Source notes go in `notes/<source-slug>/source/<id>--<slug>.md`.
- Backwards compatible: notes without a resolvable source land in the
  legacy top-level type folder, and the recursive locate/allNotes walk
  finds notes regardless of which layout they're in.

Skip boilerplate
- atomize-text SKILL.md gains an explicit "skip these — return zero
  units" rule listing TOC, index, acknowledgments, copyright, references,
  legal boilerplate, OCR artefacts. Partly-boilerplate chunks emit
  units for the substantive parts only.

Tests still 66 green (added PerSourceFolderTests; updated
OrchestratorTests to walk the new layout via VaultStore.allNotes).

## [0.15.0] — 2026-05-07

Streaming ingest pipeline. Notes now appear in the vault as the run
progresses, instead of all at the end.

What changed
- The orchestrator's two-phase model (atomize-everything → decide-and-write
  -everything) is replaced by a per-chunk pipeline. Each chunk runs
  atomize → for each unit: classify → summarize → reconcile → infer-edges
  → write to vault. Multiple chunks run in parallel up to `concurrency`.
- User-visible effect: instead of waiting until ~95% of the run for the
  first note, atomic notes appear in the Vault tab as soon as their
  parent chunk's pipeline completes.
- Per-chunk fault tolerance preserved: a failing atomize logs + skips,
  a failing unit decision quarantines.
- Per-chunk progress logs now include a final summary like
  `chunk 12/44 done: +5 added, 0 improved, 0 skipped`.

What this drops
- Mid-run resume via Checkpoint. With per-chunk streaming, the partial
  state is just whatever atomic notes already landed in the vault. The
  orphan-detect path still recovers a vault left with a source but no
  atomic notes (incomplete previous ingest → re-run).
- CheckpointResumeTests removed; CheckpointStoreTests kept (still useful
  infra unit test).

Test count: 34 InfiniteBrain (was 36; lost 2 from the resume test) +
30 SharedLLMKit = 64 green.

## [0.14.7] — 2026-05-07

Reliability tweaks for long ingests with the Claude CLI provider.

- Default `concurrency` lowered from 4 → 2. Running 4 concurrent
  `claude -p` subprocesses sometimes produces `nonzeroExit(1, stderr:"")`
  on individual chunks (looks like local rate limiting / contention).
  Two in flight is more reliable; users on the API can bump back up.
- Per-chunk atomize now retries once after a 1.5s pause if the first
  attempt fails before logging "skipping". Recovers transient failures
  without lowering throughput when things are healthy.
- Same atomize-task body lived in two places (priming + sliding
  window). Extracted to a single inner func.

Note: notes still don't appear in the vault until Phase A (atomize all
chunks) completes. A streaming pipeline (atomize chunk → decide+write
its units → continue) is the right architectural fix and is queued —
ping me to ship it.

## [0.14.6] — 2026-05-07

Speed: parallel atomize.

The user reported "every chunk's data isn't being created" after a few
minutes. Diagnosis: nothing was wrong — atomic notes only get written
after Phase A (atomize-all-chunks) completes, then Phase B (per-unit
decide+classify+summarize+reconcile) runs. Phase A was serial, so a
44-chunk book at ~25s per Claude CLI atomize call meant ~18 minutes
of waiting before any note hit the vault.

Fix: atomize chunks in parallel up to `concurrency` (default 4) using
the same sliding TaskGroup pattern as Phase B. ~4× speedup on the
Phase A wall-clock.

Per-chunk failures still log + skip; results are reordered by chunk
index after the parallel batch completes so atomize order matches
input order.

Tests still 36 InfiniteBrain + 30 SharedLLMKit = 66 green.

## [0.14.5] — 2026-05-07

Fix: dedup wrongly skipped re-ingest of an *orphaned* source.

What the user saw: dropped a 1.7 MB book in, hit Run, got
"added: 0  improved: 0  skipped: 1" — even though the vault contained
a source note but ZERO atomic notes (the previous ingest had aborted
mid-pipeline). The dedup short-circuit treated the orphan source as
proof of completion and refused to re-run. Stuck forever.

Fix
- Dedup now checks both: (a) a source note with the right
  content_hash exists, AND (b) at least one atomic note cites it via
  `sources: [<source-id>]`. Only then short-circuit with skipped=1.
- If (a) but not (b) — orphan from a failed run — delete the orphan
  source and proceed with a fresh ingest. New `VaultStore.delete(id:)`
  helper.
- Logs "found incomplete previous ingest, re-running" so the user
  understands what happened.

Tests
- New OrphanedSourceReingestTests plants an orphan source, runs ingest,
  asserts re-run produces atomic notes and only one source remains
  (the new one — orphan cleaned up).

36 InfiniteBrain + 30 SharedLLMKit = 66 tests green.

## [0.14.4] — 2026-05-07

Long-PDF resilience — a single failing API call no longer kills the
whole ingest, and the user sees forward progress per chunk and per unit.

The previous behaviour: dropping a multi-hundred-page book in the
Ingest tab showed nothing in the activity log for several minutes (just
the "spinner") because everything before the first written note ran
silently. If any one of the ~95 atomize calls or ~500 per-unit calls
returned malformed JSON, hit a rate limit twice, or timed out, the
whole ingest aborted and threw — the user only saw the final error.

What changed
- New ProgressHandler on Orchestrator, called at every meaningful
  boundary: chunk N/M atomized → produced K units, unit i/N decided
  (added/improved/skipped/quarantined). IngestViewModel attaches a
  sink that pipes each line into the activity log on the main actor.
- Per-chunk atomize failures are caught and logged; remaining chunks
  still run. Result: a long book with a few flaky API calls still
  produces a partial graph instead of zero notes.
- Per-unit decision failures (classify timeout, JSON-parse abort,
  reconcile error) are caught and counted as quarantined. Other
  units continue. Whole-ingest only aborts on a fatal vault-write
  error.

What this didn't fix (because it can't from here without a fresh log)
- If macOS or NLEmbedding silently kills the app via memory pressure,
  watchdog, or another uncatchable abort. None has been logged so far,
  and the 800-char NLEmbedding cap from 0.14.2 should prevent the
  known abort path.

## [0.14.3] — 2026-05-07

Fix: re-ingesting the same file produced a duplicate source note. Caught
by inspecting the Vault tab after dragging the same PDF in twice — count
went to 2 with identical titles.

Root cause: the orchestrator's checkpoint is deleted on full success, so
the next ingest of the same content hash sees no checkpoint and falls
into the fresh-ingest branch, writing another source note.

Fix: before doing any work, the orchestrator scans the vault for an
existing source note with `contentHash == fileHash`. If found AND no
in-flight checkpoint exists, the call returns
`IngestResult(skipped: 1)` immediately — no atomize, no LLM calls, no
new files. Tested by ingesting the same file twice and asserting the
vault contains exactly one source note.

NOTE: Existing duplicates from earlier versions remain in the vault
until you delete the old `source/` files manually. The dup-detect only
prevents NEW duplicates going forward.

## [0.14.2] — 2026-05-07

Fixes a SIGABRT inside Apple's NLEmbedding when ingesting a long PDF.

- The orchestrator was feeding the entire extracted source text into
  `NLEmbedding.vector(for:)` for the source-note embedding. On a
  ~1.5M-character book this overflowed an internal buffer in
  `CoreNLP::ContextualWordEmbedding::fillWordVectors` and the C++
  exception became an uncatchable SIGABRT (try? doesn't help — abort()
  bypasses Swift's error path).
- `NLEmbeddingProvider.embed` now hard-caps input at 800 characters
  before calling Apple's API. Defends every caller automatically.
- The orchestrator additionally embeds only a short preview (file name
  + first 400 chars) for the source-note vector instead of the whole
  document, so the source still has a meaningful retrieval signature.
- Also reverted to the working TabView layout — NavigationSplitView
  was rendering blank panes on macOS 26.3. Status bar moved under a
  divider beneath the tabs instead of via safeAreaInset.

## [0.14.1] — 2026-05-07

UX fixes around provider selection.

- First-run default now picks the best available LLM backend instead of
  blindly defaulting to the Anthropic API. Order: existing API key in
  Keychain → Claude Code CLI → Codex CLI → Cursor CLI → Anthropic. So a
  user with `claude` installed and no API key can hit Run immediately
  without visiting Settings first.
- The "needs an API key" error now lists the locally-installed CLI
  alternatives the user could switch to in Settings.
- Added a regression test that asserts AppSettings always returns a
  valid `LLMProviderKind` from a clean keychain + defaults state.

## [0.14.0] — 2026-05-07

UI polish — the app looks like a real macOS app now, not a quick demo.

Navigation
- Replaced TabView with NavigationSplitView. Sidebar lists the five
  panes (Ingest / Vault / Graph / Query / Settings), title bar carries
  the current section name. Window minimum bumped to 1180×760.
- New always-visible status bar at the bottom of every pane: vault
  folder, active LLM provider, configured/incomplete state. Built with
  `.regularMaterial` so it picks up appearance changes automatically.
- Sidebar header shows the app name + version pulled from
  CFBundleShortVersionString.

Pane redesign
- IngestView: drop zone is now a tinted rounded card that reacts to
  drag state; queued files render as styled rows with type-icon and
  file size; Run is a borderedProminent button with Cmd-Return; the log
  has a real "Activity" header and an empty-state hint; results render
  as a coloured pill (added/improved/skipped) instead of plain text.
- SettingsView: card-based layout with section icons; vault path
  truncates middle-style; provider picker shows live status with
  green-check / orange-warn / info badges; API key card hides when a
  CLI provider is selected. Capped at 720pt wide so it doesn't sprawl.
- QueryView: search-bar style ask field with up-arrow circle button
  and inline progress; example-question placeholder replaces the bare
  "Coming soon"; cited ids render as monospaced chips in a flow layout
  that wraps naturally; errors get a coloured callout.
- VaultBrowser: type-grouped list with smallCaps headers and per-type
  count, filter field in the toolbar, large-icon empty states for
  no-vault and no-notes cases, monospaced markdown preview pane.

A few unrelated nits cleaned up along the way (consistent `.padding`
multiples, system materials, Label everywhere instead of plain Text).

## [0.13.0] — 2026-05-07

LLM provider choice — use a locally installed `claude`, `codex`, or
`cursor` CLI instead of paying for the Anthropic API. Pattern mirrors
`ucp-demo`'s `BaseCLIProvider` shape.

SharedLLMKit
- New `LLMProviderKind` enum: `anthropic` (default) | `claude-cli` |
  `codex-cli` | `cursor-cli`.
- New `LLMClientFactory.make(provider:apiKey:)` builds the right concrete
  `LLMClient` and `isAvailable(...)` lets the GUI gate the Run button.
- Three CLI clients — `ClaudeCLIClient`, `CodexCLIClient`,
  `CursorCLIClient` — shell out to the installed binary via a shared
  `CLIProcessRunner` (Process + pipes + timeout). Argument shapes match
  `ucp-demo` exactly:
    - `claude -p <prompt> --output-format text --allow-dangerously-skip-permissions`
    - `codex exec --output-last-message <file> --sandbox read-only --skip-git-repo-check`
    - `cursor agent --trust --print <prompt>`
- New `CLILocator` walks common install paths (Homebrew, /usr/local,
  npm-global, ~/.local/bin, …) then falls back to `/usr/bin/which`.

App + CLI integration
- AppSettings persists `provider` in UserDefaults (default: anthropic).
  `isConfigured` now uses the factory's availability check, so the API
  key requirement only applies when anthropic is selected.
- Settings tab gains a Provider picker with live status: green check +
  resolved path when the CLI is installed, orange warning when missing.
  The API-key section only shows for the anthropic provider.
- IngestViewModel and QueryViewModel route through the factory; CLI
  failures get specific error messages ("install the binary" vs "add an
  API key").
- `infb` gains `--provider` flag and `INFINITEBRAIN_PROVIDER` env var.
  Examples in `infb help`.

Tests
- New `CLIClientArgumentTests` pins the per-CLI argument shapes so a
  drift in any of the binaries' interface is caught at build time.
- 63 tests green (33 InfiniteBrain, 30 SharedLLMKit).

## [0.12.1] — 2026-05-07

UX fix: VaultBrowser and GraphView now auto-refresh after an ingest
completes. Previously you had to click Refresh manually or wait for the
next tab switch. Wired via `.onChange(of: ingest.lastResult)` — both
views observe `IngestViewModel` and re-read the vault when a new
IngestResult lands.

## [0.12.0] — 2026-05-07

`infb reindex` — recovery path when the embedding index drifts from the
markdown.

If you delete notes from the vault by hand, copy a vault between machines,
or the `embeddings.json` cache gets corrupted, you previously had no way
back to a clean index. Now there is one.

- New `IndexRebuilder.rebuild(vault:embeddings:)` walks every markdown note
  in the vault, embeds each body (or title for empty-body sources), and
  writes a fresh `embeddings.json`. The old file is deleted first so a
  partial rebuild can't leave stale entries mixed with new.
- New CLI subcommand: `infb reindex <vault-path>`. Uses Apple's offline
  NaturalLanguage embeddings — no API key needed.
- A single un-embeddable note is logged-and-skipped rather than failing
  the whole rebuild.

Tests
- IndexRebuilderTests: pre-populate index with one stale id and one valid
  id, write two notes to the vault, rebuild — assert the result contains
  exactly the two vault note ids and not the stale one.
- 58 tests green (33 InfiniteBrain, 25 SharedLLMKit).

## [0.11.0] — 2026-05-07

Hedging-text linting — the last unenforced clause of `quality-bar.mdc` is
now real code.

- `SkillRunner.detectHedging` walks every string in the parsed output and
  rejects responses containing hedging boilerplate (`as an AI`,
  `this note discusses`, `as a language model`, `I cannot help`, etc.).
- A rejected response triggers the existing one-shot retry, with a
  rewritten retry hint that tells the model exactly why and what to
  avoid (no meta-commentary, no AI self-references).
- `SkillRunnerError.hedgingDetected(phrase:)` is the new error case.
  After two hedging-only outputs the runner throws
  `outputInvalidAfterRetry` like any other validation failure.

Tests
- New `SkillRunnerHedgingTests` covers: clean output passes through with
  no retry; one hedge then a clean output retries and succeeds; two
  consecutive hedges throw.
- 57 tests green (32 InfiniteBrain, 25 SharedLLMKit).

## [0.10.0] — 2026-05-07

Token-budget enforcement — `token-budget.mdc` is no longer documentation
only. Per-skill input caps are now declared in SKILL.md frontmatter and
applied by SkillRunner before the API call.

- New optional `max_input_chars` frontmatter key. Uses the well-known
  4-chars-per-token heuristic (good enough for English; the model is
  told the input was clipped so it can still produce useful output).
- SkillRunner truncates the user prompt when it exceeds the cap and
  appends a `[truncated]` marker.
- Caps applied (matching the table in `Resources/rules/token-budget.mdc`):
  - classify-node: 6000 chars
  - summarize-note: 6000 chars
  - reconcile-note: 16000 chars
  - improve-note: 16000 chars
  - infer-edges: 16000 chars
- `atomize-text` is uncapped because the orchestrator already chunks
  before calling it.

Tests
- New `SkillRunnerBudgetTests`: oversized prompts get truncated with the
  marker; uncapped skills are unaffected.
- 54 tests green (32 InfiniteBrain, 22 SharedLLMKit).

## [0.9.0] — 2026-05-07

Two-pass query — saves tokens on every question by sending summaries first
and only expanding the bodies the model says it actually needs.

- New `select-notes-for-question` skill (Haiku-class — cheap pass 1) takes
  a question + candidate summaries + budget and returns the ids whose
  full bodies should be loaded for pass 2.
- `QueryService` is now two-pass by default. Pass 1 sends top-K summaries
  (default candidateK=12), pass 2 sends only the picked-id full bodies
  (default fullNotesBudget=4) to `answer-question`.
- Single-pass mode still available via `twoPass: false` for callers that
  prefer the older one-shot approach (eats more tokens per question).
- `topK` parameter on `ask(_:topK:)` is now honored only in single-pass.

Tests
- New QueryTwoPassTests proves: pass 1 sees summaries but never full
  bodies; pass 2 receives only the bodies named by pass 1's `needed_ids`;
  single-pass mode skips the selection skill entirely.
- The old QueryServiceTests was made redundant by the above and removed.
- 52 tests green (32 InfiniteBrain, 20 SharedLLMKit).

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
