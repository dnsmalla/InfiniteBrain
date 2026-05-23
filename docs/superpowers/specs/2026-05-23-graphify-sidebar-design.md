# Graphify Sidebar — Design Spec

**Date:** 2026-05-23
**Status:** Approved (brainstorming, revised after second-pass read)
**Owner:** dnsmalla

## Goal

Add a **Code Graph** tab to InfiniteBrain's sidebar that runs [Graphify](https://github.com/safishamsi/graphify) over a user-selected folder (codebase and/or docs), renders the resulting graph using the existing graph rendering pipeline, and lets users click a node to open the underlying source file.

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
│  └─ GraphCanvas      (shared pure renderer — see refactor) │
│                                                            │
└────────────────────────────────────────────────────────────┘
                       │
                       ▼
┌─ InfiniteBrainCore/CodeGraph (new module) ─────────────────┐
│  GraphifyRunner   — wraps `graphify extract` via Process   │
│  GraphifyParser   — graph.json → GraphData                 │
│  GraphifyStore    — caches per-folder runs on disk         │
└────────────────────────────────────────────────────────────┘
```

Code graph and knowledge graph share `GraphData`, `GraphSimulation`, `GraphLayout`, and a newly-extracted `GraphCanvas` view. No parallel rendering stack.

## Type System Reuse (revised)

After re-reading `InfiniteBrainCore/Models`:

- **`NodeType` is `RawRepresentable` + `ExpressibleByStringLiteral`** ([NodeType.swift](../../../Sources/InfiniteBrainCore/Models/NodeType.swift)). Extend it with new static constants — no new enum:
  ```swift
  public static let codeFile: NodeType   = "code_file"
  public static let codeSymbol: NodeType = "code_symbol"
  public static let codeModule: NodeType = "code_module"
  public static let docPage: NodeType    = "doc_page"
  ```
- **`EdgeType` is a closed `enum`** ([EdgeType.swift](../../../Sources/InfiniteBrainCore/Models/EdgeType.swift)). Add four cases additively:
  ```swift
  case imports        // "imports"
  case calls          // "calls"
  case references     // "references"
  case defines        // "defines"
  ```
- **IDs are `String`** in `GraphNode` ([GraphLayout.swift:7](../../../Sources/InfiniteBrainCore/Graph/GraphLayout.swift)) — Graphify's string IDs pass through unchanged.
- **`GraphNode` gains an optional metadata bag** so code nodes can carry `fileURL`, `language`, `lineRange` without leaking into `summary`:
  ```swift
  public struct GraphNode: Equatable, Sendable, Identifiable {
      public let id: String
      public let title: String
      public let type: NodeType
      public let summary: String
      public var position: CGPoint
      public let metadata: [String: String]?   // new, optional, backward compatible
      ...
  }
  ```

## Refactor: extract `GraphCanvas` from `GraphView`

Current [GraphView.swift](../../../Sources/InfiniteBrain/Features/KnowledgeGraph/GraphView.swift) bundles rendering (Canvas drawing, zoom/pan/select gestures, simulation step) with vault-specific concerns (`VaultStore`, `persistPositions()`, `notesCache`). The code-graph view needs only the rendering half.

**Action:** Extract a pure renderer to `Sources/InfiniteBrainCore/Graph/GraphCanvas.swift` (or `Sources/InfiniteBrain/CoreUI/GraphCanvas.swift` if SwiftUI must live outside the Core target):

```swift
@MainActor
public struct GraphCanvas: View {
    let data: GraphData
    let simulation: GraphSimulation
    @Binding var selected: GraphNode?
    var onNodeOpen: ((GraphNode) -> Void)? = nil   // double-click / Enter
    // zoom + pan state managed internally
}
```

`GraphView` (knowledge graph) keeps its vault persistence and consumes `GraphCanvas`. `CodeGraphView` consumes the same `GraphCanvas` and supplies `onNodeOpen` that calls `NSWorkspace.shared.open(fileURL)`.

This is scoped, targeted, removes duplication, and improves `GraphView` on its own merits.

## Components

### 1. Sidebar entry
Add `.codeGraph` to the `Tab` enum at [InfiniteBrainApp.swift:52-77](../../../Sources/InfiniteBrain/App/InfiniteBrainApp.swift). SF Symbol: `point.3.connected.trianglepath.dotted`. One switch arm added to the detail view to route to `CodeGraphView`.

### 2. GraphifyRunner
`Sources/InfiniteBrainCore/CodeGraph/GraphifyRunner.swift`.

- Resolves the `graphify` binary via `which graphify`, then fallback paths: `~/.local/bin/graphify`, `/opt/homebrew/bin/graphify`, `/usr/local/bin/graphify`.
- Spawns `Process` with: `graphify extract <path> --json-out <tmp>/graph.json --quiet`.
- Streams stderr into a bounded log buffer surfaced in the status strip.
- Async, cancellable. Returns `Result<URL, GraphifyError>` with cases: `.binaryMissing`, `.runFailed(exitCode: Int32, stderrTail: String)`, `.parseFailed(Error)`, `.cancelled`.
- Injects a `ProcessLauncher` protocol seam so unit tests don't spawn `graphify`.

### 3. GraphifyParser
`Sources/InfiniteBrainCore/CodeGraph/GraphifyParser.swift`.

- Decodes `graph.json`. Pins to a known schema version; emits `.unsupportedSchema(version)` on mismatch.
- Maps Graphify node kinds → `NodeType` (table below). Unknown kinds map to `.custom` with the original kind preserved in `metadata["graphify_kind"]`.
- Maps Graphify edge kinds → `EdgeType` (table below). Unknown kinds map to `.relatedTo`.
- Emits `GraphData` directly. No intermediate type.

| Graphify node kind | NodeType |
| --- | --- |
| `file` | `.codeFile` |
| `class`, `struct`, `function`, `method` | `.codeSymbol` |
| `module`, `package` | `.codeModule` |
| `markdown_section`, `doc` | `.docPage` |
| anything else | `.custom` |

| Graphify edge kind | EdgeType |
| --- | --- |
| `imports` | `.imports` |
| `calls` | `.calls` |
| `references`, `uses` | `.references` |
| `defines`, `declares` | `.defines` |
| anything else | `.relatedTo` |

### 4. GraphifyStore
`Sources/InfiniteBrainCore/CodeGraph/GraphifyStore.swift`.

- Persists each run at `~/Library/Application Support/InfiniteBrain/CodeGraph/<sha256(absolutePath)>/graph.json` plus a sibling `meta.json` (timestamp, node/edge counts, graphify version).
- One run per target folder; rerun overwrites.
- `lastRun(for: URL) -> RunMetadata?` for the "last graphed N ago" badge.

### 5. CodeGraphView
`Sources/InfiniteBrain/Features/CodeGraph/CodeGraphView.swift`.

- Folder picker. Default candidates, in order: repo root (walk up from CWD for `Package.swift`), last-used folder from `UserDefaults`, then home.
- "Run Graphify" button kicks off `GraphifyRunner` on a background `Task`; spinner + cancel button while running.
- On completion, builds a `GraphSimulation` from the parsed `GraphData` and hands both to `GraphCanvas`.
- Node open (`onNodeOpen`): if `metadata["fileURL"]` resolves under the user-picked root, `NSWorkspace.shared.open(url)`. Reject paths outside the root — guard against malicious or stale graph files.

### 6. Cross-link to Knowledge Graph (optional)
Behind a Settings toggle, default **off**. When enabled, the parser injects a synthetic `.relatedTo` edge whenever a code symbol's docstring/leading comment whole-word matches an existing vault note's title (case-insensitive).

## Data Flow

```
User picks folder
  → GraphifyRunner.run()             [Process → graph.json]
  → GraphifyParser.parse()           [graph.json → GraphData]
  → GraphifyStore.save()             [cache to App Support + meta.json]
  → GraphSimulation(data:)
  → GraphCanvas renders
  → User double-clicks node → NSWorkspace.open(fileURL)
```

## Error Handling

| Condition | UX |
| --- | --- |
| `graphify` binary not found | Status strip: "Graphify not installed" + copyable `uv tool install graphifyy` (note double-y) + help link. |
| Run fails (non-zero exit) | Status strip shows exit code + last 5 stderr lines; previous cached graph stays loaded. |
| `graph.json` parse fails | Same as run-fails; cached graph stays loaded. |
| Schema version mismatch | Loud banner: "Graphify v$X output not supported — upgrade InfiniteBrain or pin graphify to v$Y." |
| User cancels | Process terminated; UI returns to prior state. |
| Node `fileURL` outside picked root | Silent reject; show metadata popover instead of opening. |

## Testing

- **GraphifyParser**: golden-file tests in `Tests/CodeGraphTests/Fixtures/` against checked-in `graph.json` samples (small Swift project, mixed code+markdown, empty graph, unknown node/edge kind, schema mismatch).
- **GraphifyRunner**: inject `ProcessLauncher`; mock it; assert argv, env, cancellation. No real `graphify` in unit tests.
- **GraphifyStore**: round-trip a parsed graph; assert path hashing is stable across runs.
- **CodeGraphView**: SwiftUI snapshot tests for empty / loading / loaded / error states.
- **Install command literal**: a tiny test asserts the install hint string is exactly `uv tool install graphifyy` — prevents typo regressions.
- **GraphCanvas refactor**: existing knowledge-graph tests must continue to pass unchanged.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| External Python dependency (Graphify) | Detect at first launch of the tab, surface install instructions, never silently fail. |
| Graphify JSON schema drift across versions | Pin a supported schema version range; fail loud on mismatch. |
| Layout pie-slice bloat from new NodeType values on knowledge graph | `GraphLayout` already filters to `Set(notes.map(\.type))` — new types only appear when actually present in data. |
| Large monorepos producing huge graphs | Async run with cancel; status strip soft-warns >10k nodes. Filtering deferred to v2. |
| Opening arbitrary file URLs from a third-party graph | Constrain `NSWorkspace.open` to URLs resolved under the user-picked root. |
| `GraphCanvas` extraction breaks knowledge-graph behavior | Refactor lands in its own commit before any code-graph code; existing tests gate it. |

## Open Questions (resolved by reasonable default)

- **Sandbox?** No for v1 — user explicitly invokes on a folder they chose. Revisit for Mac App Store.
- **"Install Graphify" placement?** First-launch of the tab only.
- **Where does `GraphCanvas` live — `InfiniteBrainCore` or `InfiniteBrain/CoreUI`?** Decide during implementation based on whether SwiftUI is already imported in the Core target; default to `InfiniteBrain/CoreUI` to avoid expanding Core's surface.
