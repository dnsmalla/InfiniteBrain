# InfiniteBrain Production-Readiness Review — Findings & Fix Plan

Consolidated from a 5-pass read-only review (services, persistence, security, SharedLLMKit/tests, UI/CLI). De-duplicated and ranked. Each item links to the fix approach. Fixed items get checked off as we go.

## CRITICAL (correctness / data-loss / blocking)

- [ ] **CR1 — SharedLLMKit test target is broken (blocks all its tests).** 3 mock `LLMClient`s miss the `onUsage:` parameter: `SkillRunnerTests.swift:110`, `SkillRunnerBudgetTests.swift:79`, `SkillRunnerHedgingTests.swift:96`. Add the 4th param. *Trivial; do first to restore the safety net.*
- [ ] **CR2 — CLIProcessRunner pipe-drain deadlock.** `CLIProcessRunner.swift:70-103` reads stdout/stderr only *after* the process exits. Output >~64KB fills the OS pipe buffer, the child blocks on write, never exits → false `timedOut` + lost LLM output. Drain pipes concurrently while waiting.
- [ ] **CR3 — CLIProcessRunner leaks process/FDs on timeout.** `:82-85` sends SIGTERM and throws without reaping or escalating to SIGKILL. Reap + SIGKILL fallback + close handles on all paths.
- [ ] **CR4 — CLI vs app embedding-index filename mismatch.** App uses `embeddings.bin`; CLI uses `embeddings.json` (`main.swift:54,90,120`). A vault ingested in one is invisible to the other. Single `Vault.embeddingIndexURL` constant everywhere.
- [ ] **CR5 — Orchestrator concurrency limit broken.** `activeLLMCalls` is mutated inconsistently (pre-`addTask` for chunks vs in-closure for units) and the unit launch loop ignores the limit entirely (`Orchestrator.swift:229-307`) → unbounded concurrent LLM calls (rate-limit storm / memory blowup). One increment per enqueued task, gate both launchers.
- [ ] **CR6 — Index/disk divergence.** `metadataIndex.update` is called in `decideOne` (`Orchestrator.swift:472`) before the note is written *and* redundantly (VaultStore.write already updates it); `VaultStore.delete` never persists the index; no rebuild-on-mismatch. Remove the premature update; persist after delete; validate on load.

## HIGH

- [ ] **H1 — NoteSerializer corrupts notes whose body contains `---` or `key:`** (`NoteSerializer.swift:50`). A markdown horizontal rule is read as the frontmatter fence → data loss. Use a real YAML parse for frontmatter (Yams is already in the dependency tree via GraphKit) or require the 2nd fence + treat the remainder as opaque body. Add a round-trip property test.
- [ ] **H2 — Prompt leaked via process argv.** `claude -p <prompt>` and `cursor … <prompt>` put verbatim vault content in argv (world-readable via `ps`). Codex already pipes via stdin — do the same for claude (plumbing exists).
- [ ] **H3 — `openNode` path-traversal guard skipped when `targetFolder == nil`** (`CodeGraphView.swift:567-588`) + `UAParser.resolveFileURL` returns arbitrary absolute paths. Make the guard unconditional; clamp paths to the repo root at parse time (GraphKit).
- [ ] **H4 — DraftingViewModel: import has no `catch` → stuck spinner + lost errors** (`:218-258`); `searchNotes`/`saveSession` swallow to `print()` (`:189,318`). Add catch, surface `error`, log via LogService, drop prints.
- [ ] **H5 — AnthropicClient: no request timeout, no cancellation checks, drops multi-block/thinking responses** (`AnthropicClient.swift:79,103,121-130`). Set `timeoutInterval`; check cancellation between retries; concatenate all `type==text` blocks.
- [ ] **H6 — SkillRunner conflates transport errors with validation failures** (`SkillRunner.swift:44-57`) → a 401 is reported as "invalid output". Separate the `complete` call from the validation try/catch.
- [ ] **H7 — No timeout on any LLM/embedding call in the ingest pipeline** (`Orchestrator decideOne`). A hung provider call stalls a slot forever (overnight-ingest hazard). Wrap each call in a timeout → quarantine on expiry.
- [ ] **H8 — ULID generator ignores injected `DateProvider`, uses `Date()` + full re-roll** (`IDGenerator.swift:18-35`); collision → silent note overwrite (`VaultStore.write` clobbers). Use DateProvider, monotonic randomness, refuse clobber.
- [ ] **H9 — Empty `slugify` result commingles sources** (`VaultStore.swift:122-160`): punctuation/emoji-only titles → `""` → shared folder. Fall back to note id.
- [ ] **H10 — Index files load partial on truncation, silently** (`MetadataIndex.swift:67-75`, `EmbeddingIndex.swift:83-104`). Add magic+version/length trailer; on mismatch error + trigger `IndexRebuilder`.

## MEDIUM

- [ ] **M1 — Main-thread filesystem IO in view lifecycle** (`VaultBrowser.swift:51-54,246`, `SettingsView.checkTools`). Move to `Task.detached`.
- [ ] **M2 — Keychain `set` is delete-then-add (key loss window) + no `kSecAttrAccessible`** (`Keychain.swift:37-52`) → key can sync to iCloud/backup and is lost if interrupted. Use SecItemUpdate-or-add + `…ThisDeviceOnly`.
- [ ] **M3 — revertIngest swallows all errors (`try?`) → fake success** (`Orchestrator.swift:99-108`); re-ingest after chunk-count change duplicates notes (`:141,158`). Aggregate errors; call `revertIngest` in the fresh branch.
- [ ] **M4 — QueryService: non-deterministic `prefix` over Dictionary.values + no token budget on bodies** (`QueryService.swift:175-177`); empty-input/empty-index returns blank answer. Order deterministically, cap by length, short-circuit empties.
- [ ] **M5 — Logging is ~5 call sites; most VM/persistence errors never hit OSLog.** Add `LogService.error` alongside user-facing error assignments.
- [ ] **M6 — Embedding index load `try?` everywhere → corrupt index silently = "no results"** (QueryViewModel/DraftingViewModel/Ingest). Log + surface "run reindex".
- [ ] **M7 — Size caps missing on ingested files / graph JSON / scanner stdout** (DoS/OOM on untrusted input). Pre-read size guards.
- [ ] **M8 — Concurrent `improve` is a read-modify-write with a suspension point → lost update** (`Orchestrator.swift:287-290`). Serialize per-note.
- [ ] **M9 — VaultWatcher watches one dir node, misses subtree edits + misleading "could not start watcher"** (`VaultWatcher.swift`). Use FSEvents recursive; seed before watching.

## LOW

- [ ] **L1 — Magic numbers**: `16_000` chunk size duplicated 3×; `512`/`100_000` CLI reindex hack; unnamed debounce literals.
- [ ] **L2 — CLI value-flags silently no-op at end of args / on bad Int** (`main.swift:157-161`).
- [ ] **L3 — SkillSyncService version check is a no-op** — bundled skill fixes never reach existing vaults.
- [ ] **L4 — CLI clients ignore `responseSchema`; usage accounting dark for CLI providers; Anthropic usage swallowed on parse error.**
- [ ] **L5 — Test coverage gaps**: NoteSerializer round-trip, UnifiedIngestionService, UsageTracker, GlobalRateGate, Keychain, QuadTree, MetadataIndex corruption.
- [ ] **L6 — SRP**: `CodeGraphView.swift` (595, scan+cache+UI) should split scan/cache into a ViewModel.

## Execution order
CR1 → CR4 → CR2/CR3 → CR5 → CR6 → H1 → H2 → H3 → H4 → H5/H6/H7 → H8/H9/H10 → M tier → L tier. Verify (build + test) and commit after each item or small safe batch. Items touching GraphKit (H3 clamp, H10 index headers) ship as GraphKit point releases.
