# Code Graph — Understand-Anything Port

**Date:** 2026-06-02
**Status:** Approved

## Goal

Replace InfiniteBrain's simple `graphify`-backed CodeGraph tab with a port of meet-notes'
3-panel `UAGraphView` system, powered by the `understand-anything` CLI. All other
InfiniteBrain features (vault, knowledge graph, notes) are left untouched.

---

## Architecture

### InfiniteBrainCore/CodeGraph/

Old graphify files are removed; new UA files take their place.

| Remove | Add |
|---|---|
| `GraphifyRunner.swift` | `UARunner.swift` |
| `GraphifyParser.swift` | `UAParser.swift` |
| `GraphifyStore.swift` | `UAStore.swift` |
| `GraphifyError.swift` | `UAError.swift` |
| — | `CodeGraphModels.swift` |
| — | `CodeGraphLayout.swift` |
| `ProcessLauncher.swift` | *(keep as-is)* |

**`CodeGraphModels.swift`** — self-contained data types ported from meet-notes:
- `CGNodeKind` (30+ cases: file, symbol, module, function, classType, service, endpoint, …)
- `CGEdgeKind` (50+ cases: imports, calls, contains, inherits, dependsOn, …)
- `CGNode(id, title, kind, position, metadata)`
- `CGEdge(fromId, toId, kind)`
- `UALayer(id, name, nodeIds)` — architecture layers from UA output
- `UATourStep(nodeId, title, body)` — guided tour steps
- `CGData(nodes, edges, layers, tour)` — top-level graph payload
- `CGPalette.color(for:)` — stable colour per node kind (pure SwiftUI, no ThemeStore dep)

**`UAError.swift`** — `binaryMissing | runFailed | noOutput | parseFailed | unsupportedSchema | cancelled`

**`UARunner.swift`** — runs `understand-anything extract <folder> --json-out <path>` via
`ProcessLauncher`. Resolves binary from `$PATH` and fallback paths
(`~/.local/bin/understand-anything`, `/opt/homebrew/bin/understand-anything`).
Returns `Result<URL, UAError>` pointing at a stable temp copy of `knowledge-graph.json`.
Install hint: `npm install -g understand-anything`.

**`UAParser.swift`** — decodes `knowledge-graph.json` into `CGData`. Maps UA's string type
vocabulary to `CGNodeKind`/`CGEdgeKind`. Resolves relative `filePath` values to absolute
`file://` URLs anchored at `repoRoot`. Handles stale absolute paths by rebasing on
`repoRoot.lastPathComponent`.

**`UAStore.swift`** — disk cache keyed by SHA-256 of the target folder's absolute path.
Stores `knowledge-graph.json` + `meta.json` (timestamp, nodeCount, edgeCount) under
`~/Library/Application Support/InfiniteBrain/CodeGraph/<hash>/`.

**`CodeGraphLayout.swift`** — static type-clustered circular layout. Nodes grouped by
`CGNodeKind`, each kind gets a pie slice, nodes spread across three concentric rings.
No physics dependency. Input/output: `CGData`.

---

### InfiniteBrain/Features/CodeGraph/

| File | Change |
|---|---|
| `CodeGraphView.swift` | Full replacement — 3-panel port of meet-notes' `UAGraphView` |
| `CodeGraphCanvas.swift` | New — port of meet-notes' `CodeGraphCanvas` |
| `UAHelpers.swift` | New — port of meet-notes' pure utility functions |

**`CodeGraphView.swift`** — 3-panel `HSplitView`:

```
┌──────────────────────┬────────────────────────┬─────────────────────┐
│ Panel 1              │ Panel 2                │ Panel 3             │
│ Folder picker        │ Files & Symbols list   │ Graph canvas        │
│ Run / Cancel         │ (sections per file,    │ Pan / zoom / select │
│ Status               │  symbols inside)       │ Double-click → open │
│ Symbols toggle       │                        │ Fit / expand        │
└──────────────────────┴────────────────────────┴─────────────────────┘
```

- Panel 1 replaces `LibraryItemStore` with `NSOpenPanel` folder picker (persists last path in
  `UserDefaults` under `"CodeGraph.lastFolder"`, same key as the old view).
- Panel 2: `List` with sections per source file, symbol rows with colour dot + title + line.
  Populated from `UAHelpers.collectCodeArtifacts(graph)`.
- Panel 3: `CodeGraphCanvas` + bottom detail pane (node title, path, line, connectivity).
- Symbols toggle (`showSymbols: Bool`) filters `fullData` → `displayData` — files-only by
  default, full graph when on. Same logic as meet-notes.
- Expand button overlays the canvas full-window (same `graphExpanded` bool).
- No data/memory mode — code only.

**`CodeGraphCanvas.swift`** — pure renderer for `CGData`. Pan, zoom, single-click select,
double-click open. Auto-fits on new graph load (fingerprint check). Floating controls:
Fit, Zoom in, Zoom out. No `ThemeStore` — uses system colours directly.

**`UAHelpers.swift`** — `collectCodeArtifacts`, `isPanelNoise`, `isHeadingChunk`,
`layoutSize`, `commonAncestor`. Pure static functions; no view dependencies.

---

## Style mapping (ThemeStore → InfiniteBrain)

| meet-notes token | InfiniteBrain equivalent |
|---|---|
| `t.accent` | `AppPalette.brand` |
| `t.accent2` | `Color.blue` |
| `t.accent3` | `Color.green` |
| `t.accent4` | `Color.orange` |
| `t.danger` | `Color.red` |
| `t.text` | `Color.primary` |
| `t.textMuted` | `Color.secondary` |
| `t.surface` | `Color(NSColor.controlBackgroundColor)` |
| `t.surface2` | `Color(NSColor.windowBackgroundColor)` |
| `t.body` | `Color(NSColor.windowBackgroundColor)` |
| `t.border` | `Color.separator` |
| `Typography.caption` | `.caption` |
| `Typography.captionStrong` | `.caption.weight(.semibold)` |
| `Typography.bodyStrong` | `.callout.weight(.semibold)` |
| `Typography.mono` | `.system(.caption, design: .monospaced)` |
| `Typography.title` | `.title3` |
| `Typography.emptyHint` | `.body` |
| `Spacing.sm/md/lg` | `6 / 10 / 16` |
| `Radius.sm` | `6` |
| `SectionLabel(text)` | `Text(text).font(.caption).foregroundStyle(.secondary)` |

`AppJSON.encoder/decoder` → standard `JSONDecoder()`/`JSONEncoder()` with
`dateDecodingStrategy = .iso8601` where needed.

---

## What is NOT changing

- `GraphView.swift` (knowledge graph) — untouched
- `VaultBrowser.swift`, `IngestView.swift`, `QueryView.swift`, `DraftingRoom.swift` — untouched
- `GraphCanvas.swift` (CoreUI) — untouched (used by knowledge graph)
- `GraphSimulation.swift`, `GraphLayout.swift` — untouched
- All models, persistence, services unrelated to CodeGraph — untouched
- `ContentView.swift` / `InfiniteBrainApp.swift` — untouched (CodeGraph tab already wired)

---

## Verification plan

1. `swift build` — clean build with no graphify references remaining
2. Run app, navigate to Code Graph tab
3. Pick a folder, click Run — `understand-anything` must be installed; binary-missing state shown if not
4. Graph renders with nodes coloured by kind, static circular layout
5. Click node → detail pane shows title, path, line, connectivity
6. Double-click node → file opens in default editor
7. Symbols toggle: off shows files-only, on shows full graph
8. Expand button overlays full-window canvas; Esc closes
9. Re-open app → cached graph loads from `UAStore`
10. Panel hide/show toggles work
