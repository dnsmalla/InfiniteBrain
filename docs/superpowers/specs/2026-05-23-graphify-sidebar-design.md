# Graphify Sidebar — Design Spec

**Date:** 2026-05-23
**Status:** Approved (brainstorming)
**Owner:** dnsmalla

## Goal

Add a **Code Graph** tab to InfiniteBrain's sidebar that runs [Graphify](https://github.com/safishamsi/graphify) over a user-selected folder (codebase and/or docs), renders the resulting graph in the existing `GraphView`, and lets users click a node to open the underlying source file. The feature reuses InfiniteBrain's existing graph rendering stack; it does not duplicate the Knowledge Graph implementation.

## Non-Goals

- Live re-graphing on file save (deferred to v2).
- Diffing two graph snapshots over time (deferred to v2).
- In-app editing of graph nodes/edges — graphs are read-only artifacts of an extraction run.
- Bundling the Graphify Python tool inside the macOS app.

## Architecture

```
┌─ Sidebar Tab: .codeGraph (new) ────────────────────────────┐
│                                                            │
│  CodeGraphView (SwiftUI)                                   │
│  ├─ FolderPickerBar  (target dir + "Run Graphify")         │
│  ├─ StatusStrip      (last run, node/edge counts, errors)  │
│  └─ GraphView        (reused — driven by GraphifyStore)    │
│                                                            │
└────────────────────────────────────────────────────────────┘
                       │
                       ▼
┌─ InfiniteBrainCore/CodeGraph (new module) ─────────────────┐
│  GraphifyRunner   — wraps `graphify extract` via Process   │
│  GraphifyParser   — graph.json → [CodeNote] + [CodeEdge]   │
│  GraphifyStore    — caches per-folder runs on disk         │
│  CodeNodeType     — new enum: .codeFile, .codeSymbol,      │
│                     .codeModule, .docPage                  │
│  CodeEdgeType     — new enum: .imports, .calls,            │
│                     .references, .defines                  │
└────────────────────────────────────────────────────────────┘
```

The new module sits beside `InfiniteBrainCore/Graph` and depends on the same `GraphSimulation` / `GraphLayout`. The existing `GraphView` is generalized to consume any conforming `GraphNodeRenderable` source (see Refactor section) so it serves both Knowledge Graph and Code Graph without forking.

## Components

### 1. Sidebar entry
Add `.codeGraph` case to the `Tab` enum in `Sources/InfiniteBrain/App/InfiniteBrainApp.swift` (around line 52–77). SF Symbol: `point.3.connected.trianglepath.dotted`. One switch arm added to the detail view to route to `CodeGraphView`. No other navigation changes.

### 2. GraphifyRunner
Located at `Sources/InfiniteBrainCore/CodeGraph/GraphifyRunner.swift`.

- Resolves the `graphify` binary via `which graphify`, then fallback paths: `~/.local/bin/graphify`, `/opt/homebrew/bin/graphify`, `/usr/local/bin/graphify`.
- Spawns `Process` with: `graphify extract <path> --json-out <tmp>/graph.json --quiet`.
- Streams stderr into a bounded log buffer surfaced in the status strip.
- Async, cancellable. Returns `Result<URL, GraphifyError>`. Errors: `.binaryMissing`, `.runFailed(exitCode, stderr)`, `.parseFailed(underlying)`, `.cancelled`.

### 3. GraphifyParser
Located at `Sources/InfiniteBrainCore/CodeGraph/GraphifyParser.swift`.

- Decodes `graph.json`. Pins to a known schema version; fails loud with `.unsupportedSchema(version)` on mismatch.
- Maps Graphify node kinds (`file`, `class`, `function`, `module`, `markdown_section`) → `CodeNodeType`.
- Maps Graphify edge kinds (`imports`, `calls`, `references`, `defines`) → `CodeEdgeType`. **No reuse** of semantic `EdgeType` values like `supports`/`contradicts` — those carry meaning specific to knowledge notes.

### 4. GraphifyStore
Located at `Sources/InfiniteBrainCore/CodeGraph/GraphifyStore.swift`.

- Persists runs under `~/Library/Application Support/InfiniteBrain/CodeGraph/<sha256(absolutePath)>/graph.json`.
- One run per target folder; re-running overwrites.
- Exposes `lastRun(for: URL) -> RunMetadata?` so the view can show "last graphed 2 hours ago" without reloading the JSON.

### 5. CodeGraphView
Located at `Sources/InfiniteBrain/Features/CodeGraph/CodeGraphView.swift`.

- Folder picker. Default candidates, in order: the InfiniteBrain repo root (discovered by walking up for `Package.swift`), then last-used folder from `UserDefaults`, then home.
- "Run Graphify" button kicks off `GraphifyRunner` on a background `Task`; spinner + cancel button while running.
- On completion, the parsed graph is handed to the shared `GraphView`. Identical rendering — different data source.
- **Node click**: if the node's `fileURL` resolves under a known root, `NSWorkspace.shared.open(url)` opens it in the user's default editor. Otherwise, a metadata popover (path, kind, neighbor count).

### 6. Cross-link to Knowledge Graph (optional)
Behind a toggle in Settings, default **off**. When enabled, the parser injects a synthetic `relatesTo` edge whenever a code symbol's docstring or leading comment contains a case-insensitive match for an existing vault note's title. Limited to whole-word matches to avoid noise.

## Data Flow

```
User picks folder
  → GraphifyRunner.run()             [Process → graph.json]
  → GraphifyParser.parse()           [graph.json → [CodeNote], [CodeEdge]]
  → GraphifyStore.save()             [cache to App Support]
  → GraphView renders                [existing GraphSimulation / GraphLayout]
  → User clicks node → NSWorkspace.open(fileURL)
```

## Refactor: generalizing `GraphView`

`GraphView` currently consumes `[Note]` and `[Edge]` directly. Introduce two small protocols in `InfiniteBrainCore/Graph`:

```swift
protocol GraphNodeRenderable {
    var id: UUID { get }
    var displayLabel: String { get }
    var paletteKey: String { get }   // drives color lookup
    var fileURL: URL? { get }
}

protocol GraphEdgeRenderable {
    var sourceID: UUID { get }
    var targetID: UUID { get }
    var styleKey: String { get }
}
```

`Note` and `Edge` get conformance via extension; `CodeNote` and `CodeEdge` conform natively. `GraphView` becomes generic over these protocols. This is targeted refactoring in the spirit of "improve the code you're working in" — it removes the only blocker to reuse and is otherwise scoped tightly.

## Error Handling

| Condition | UX |
| --- | --- |
| `graphify` binary not found | Status strip shows "Graphify not installed" with copyable `uv tool install graphifyy` and link to install doc. |
| Run fails (non-zero exit) | Status strip shows exit code + last 5 stderr lines; previous cached graph stays loaded. |
| `graph.json` parse fails | Same as run-fails; cached graph stays loaded. |
| Schema version mismatch | Loud banner: "Graphify v$X output not supported — upgrade InfiniteBrain or pin graphify to v$Y." |
| User cancels | Process terminated; UI returns to prior state. |

## Testing

- **GraphifyParser**: golden-file tests in `Tests/CodeGraphTests/Fixtures/` against checked-in `graph.json` samples (small Swift project, mixed code+markdown project, edge cases: empty graph, unknown node kind, schema mismatch).
- **GraphifyRunner**: inject a `ProcessLauncher` protocol; mock it to assert argv, env, cancellation behavior. Do not actually spawn `graphify` in unit tests.
- **GraphifyStore**: round-trip a parsed graph through disk; assert path hashing is stable across runs.
- **CodeGraphView**: SwiftUI snapshot tests for empty / loading / loaded / error states.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| External Python dependency (Graphify) | Detect at first launch, surface install instructions, never silently fail. |
| Graphify JSON schema drift across versions | Pin a supported schema version range in the parser; fail loud on mismatch. |
| `NodeType` / `EdgeType` enum bloat from mixing code+knowledge concepts | Use separate `CodeNodeType` / `CodeEdgeType` enums and a unifying protocol in `GraphView`. |
| Large monorepos producing huge graphs | Run is async with cancel; v2 will add filtering. Document a soft size warning (>10k nodes) in the status strip. |
| Opening arbitrary file URLs from a third-party graph | Constrain `NSWorkspace.open` to URLs that resolve under the user-picked root; reject everything else. |

## Open Questions (resolved by reasonable default)

- **Should Graphify run inside a sandbox?** No for v1 — user explicitly invokes it on a folder they chose. Revisit if we ship Mac App Store.
- **Where do we surface "install Graphify"?** First-launch of the tab only, not the app launch.
