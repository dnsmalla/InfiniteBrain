# Hierarchical Knowledge Graph — Design

## Problem

The Knowledge Graph loads every note and renders them flat at once. With many
PDFs → many notes, this is an unreadable hairball. Users want an *index* of their
sources and the ability to show/hide detail level by level.

## Data model (existing, unchanged)

Each ingested PDF/text becomes a `Source` note (`type == .source`) in its own
vault folder; every atomic note derived from it lives in the same folder and links
back via `note.sources[0] == <sourceId>`. So the natural hierarchy is two levels:

```
Source (one per PDF/folder)  →  derived Notes (concept, fact, …)
```

Notes with no source (`sources` empty) are "loose" and shown at the top level
alongside sources.

## Approach: view-layer expand/collapse over the full graph

All notes still load (nothing lost). Expansion/visibility is a display filter.

### Grouping
- `childrenBySource: [String: [String]]` — sourceId → derived note ids.
- `sourceIds: [String]` — note ids of `.source` nodes (+ any loose notes treated as their own top-level entries).

### View state (GraphView)
- `expandedSources: Set<String>` — sources whose notes are visible. Default: empty (all collapsed).
- `hiddenSources: Set<String>` — sources toggled fully off. Default: empty (all visible).

### Visible subgraph
- Visible nodes = source nodes not in `hiddenSources`
  + notes whose source ∈ `expandedSources` and source ∉ `hiddenSources`
  + loose notes (unless hidden).
- Visible edges = edges where both endpoints are visible.

### Layout (localized, non-jarring)
- Source nodes are positioned once by `CodeGraphLayout` on the sources-only graph; these positions stay stable across toggles.
- When a source expands, its child notes are placed in a ring around the source's current position (radius scales with child count). Existing nodes do not move.
- This "blooms" detail around a stable index instead of re-running global physics on every toggle.

### Controls
1. **Sources panel** (right sidebar, primary control): a scrollable list, one row per source:
   - disclosure chevron → toggles `expandedSources` (show/hide its notes in the graph)
   - eye icon → toggles `hiddenSources` (hide the source entirely)
   - title + note-count badge ("Multi-Head Attention · 12")
2. **Toolbar:** `Expand all` / `Collapse all`, live node count ("N / Total nodes").
3. **Canvas:** clicking a source node also toggles its expansion (in addition to selecting it for the detail panel). Clicking a note selects it only.

### Visual polish
- Source nodes: larger radius, bold label, hub styling; collapsed source shows a small "+N" badge of hidden children.
- Note nodes: smaller, colored by kind (existing palette).
- Smooth opacity/scale transition on expand/collapse.
- Existing legend + selected-node detail panel retained.

## Components touched
- `Sources/InfiniteBrain/Features/KnowledgeGraph/GraphView.swift` — grouping, state, visible-subgraph computation, sources panel, toolbar buttons, localized layout call.
- `Sources/InfiniteBrain/Features/KnowledgeGraph/GraphLayoutBloom.swift` (new) — pure helper: given a source position + child ids + count, return child positions in a ring. Unit-testable, no SwiftUI.
- `CodeGraphCanvas` — no API change; consumes the filtered `CGData`. Optional: surface source taps via the existing `selected` binding (GraphView reacts).

## Out of scope (future)
- Named multi-PDF "collections" above sources (would need a vault grouping feature).
- Persisting expansion state across launches.

## Testing
- `GraphLayoutBloom`: ring placement returns N positions around a center at the expected radius; deterministic.
- Visible-subgraph computation: pure function `visibleSubgraph(full:expanded:hidden:childrenBySource:)` → assert correct node/edge filtering for collapsed/expanded/hidden cases.
