# Obsidian-Style Code Graph — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the code graph into an Obsidian-quality interactive canvas — force-directed physics layout, visible labels, node sizes by connectivity, double-click focus mode (neighbours bright, rest shadowed), drag to reposition, hover preview.

**Architecture:** Add `CGSimulation` (Barnes-Hut force engine for CGData) to InfiniteBrainCore; rewrite `CodeGraphCanvas` with labels/sizes/focus/drag; update `CodeGraphView` to run the simulation in a background task after scan and pass `focusedNode` binding to the canvas.

**Tech Stack:** Swift 5.9, SwiftUI Canvas API, CoreGraphics, existing `QuadTreeNode` (InfiniteBrainCore), macOS 14+

---

## File Map

| File | Change |
|------|--------|
| `Sources/InfiniteBrainCore/CodeGraph/CGSimulation.swift` | **Create** — Barnes-Hut force simulation for CGData |
| `Tests/InfiniteBrainTests/CGSimulationTests.swift` | **Create** — unit tests |
| `Sources/InfiniteBrain/Features/CodeGraph/CodeGraphCanvas.swift` | **Rewrite** — labels, sizes, focus, drag, hover |
| `Sources/InfiniteBrain/Features/CodeGraph/CodeGraphView.swift` | **Modify** — simulation task, focusedNode state |

---

## Task 1 — CGSimulation physics engine

**Files:**
- Create: `Sources/InfiniteBrainCore/CodeGraph/CGSimulation.swift`
- Create: `Tests/InfiniteBrainTests/CGSimulationTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/InfiniteBrainTests/CGSimulationTests.swift
import XCTest
@testable import InfiniteBrainCore

final class CGSimulationTests: XCTestCase {

    func testSettleSpreadsSuperimposedNodes() {
        // All nodes at the same point — physics must push them apart.
        let nodes = (0..<5).map { i in
            CGNode(id: "n\(i)", title: "N\(i)", kind: .file,
                   position: CGPoint(x: 300, y: 300))
        }
        let data = CGData(nodes: nodes, edges: [])
        let sim  = CGSimulation(data: data)
        sim.settle(maxIterations: 80)
        let result = sim.appliedData(to: data)
        let uniquePositions = Set(result.nodes.map {
            "\(Int($0.position.x / 10)),\(Int($0.position.y / 10))"
        })
        XCTAssertGreaterThan(uniquePositions.count, 1,
                             "Superimposed nodes must spread after settle")
    }

    func testConnectedNodesDontFlyInfinitelyFar() {
        let n0 = CGNode(id: "n0", title: "A", kind: .file, position: CGPoint(x:   0, y:   0))
        let n1 = CGNode(id: "n1", title: "B", kind: .file, position: CGPoint(x: 800, y: 800))
        let edges = [CGEdge(fromId: "n0", toId: "n1", kind: .imports)]
        let data  = CGData(nodes: [n0, n1], edges: edges)
        let sim   = CGSimulation(data: data)
        sim.settle(maxIterations: 200)
        let result = sim.appliedData(to: data)
        let a = result.nodes.first { $0.id == "n0" }!.position
        let b = result.nodes.first { $0.id == "n1" }!.position
        let dist = hypot(b.x - a.x, b.y - a.y)
        XCTAssertLessThan(dist, 1200,
                          "Edge spring should pull connected nodes closer than 1200pt")
    }

    func testEmptyGraphHandledGracefully() {
        let sim = CGSimulation(data: .empty)
        sim.settle()   // must not crash
        let result = sim.appliedData(to: .empty)
        XCTAssertTrue(result.nodes.isEmpty)
    }

    func testAppliedDataPreservesEdgesAndMetadata() {
        let n = CGNode(id: "n0", title: "Foo", kind: .file, position: .zero,
                       metadata: ["source_file": "foo.swift"])
        let e = CGEdge(fromId: "n0", toId: "n0", kind: .imports)
        let data = CGData(nodes: [n], edges: [e])
        let sim  = CGSimulation(data: data)
        sim.settle(maxIterations: 1)
        let result = sim.appliedData(to: data)
        XCTAssertEqual(result.edges.count, 1)
        XCTAssertEqual(result.nodes.first?.metadata["source_file"], "foo.swift")
    }
}
```

- [ ] **Step 2: Run — expect failure**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && swift test --filter CGSimulationTests 2>&1 | head -10
```
Expected: `error: cannot find type 'CGSimulation' in scope`

- [ ] **Step 3: Create CGSimulation.swift**

```swift
// Sources/InfiniteBrainCore/CodeGraph/CGSimulation.swift
import Foundation
import CoreGraphics

/// Force-directed physics for the code graph. Uses the same Barnes-Hut
/// QuadTree already in InfiniteBrainCore (used by GraphSimulation for the
/// knowledge graph). Settle-then-freeze workflow:
///   1. Call `settle()` in a detached background task.
///   2. Publish `appliedData(to:)` on the main actor.
public final class CGSimulation: @unchecked Sendable {

    public struct NodeState: Sendable {
        public let id: String
        public var position: CGPoint
        public var velocity: CGPoint = .zero
    }

    public private(set) var nodes: [NodeState]
    private let edges: [CGEdge]

    public init(data: CGData) {
        self.nodes = data.nodes.map { NodeState(id: $0.id, position: $0.position) }
        self.edges = data.edges
    }

    /// Run up to `maxIterations` ticks, stopping early when all velocities
    /// drop below `threshold`. Safe to call off the main actor.
    public func settle(maxIterations: Int = 200, threshold: CGFloat = 0.4) {
        guard nodes.count > 1 else { return }
        for i in 0..<maxIterations {
            tick()
            if i > 30 {
                let maxV = nodes.reduce(CGFloat(0)) { acc, s in
                    max(acc, abs(s.velocity.x), abs(s.velocity.y))
                }
                if maxV < threshold { break }
            }
        }
    }

    /// One physics step.
    public func tick() {
        let n = nodes.count
        guard n > 1 else { return }

        let alpha: CGFloat        = 0.05
        let kRepulsion: CGFloat   = 900.0
        let kAttraction: CGFloat  = 0.07
        let restLength: CGFloat   = 80.0
        let damping: CGFloat      = 0.88
        let center = CGPoint(x: 600, y: 400)

        // --- Spring attraction along edges ---
        let idxById = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
        for e in edges {
            guard let i = idxById[e.fromId], let j = idxById[e.toId] else { continue }
            let dx = nodes[j].position.x - nodes[i].position.x
            let dy = nodes[j].position.y - nodes[i].position.y
            let d  = max(hypot(dx, dy), 0.1)
            let f  = (d - restLength) * kAttraction
            let fx = f * (dx / d), fy = f * (dy / d)
            nodes[i].velocity.x += fx;  nodes[i].velocity.y += fy
            nodes[j].velocity.x -= fx;  nodes[j].velocity.y -= fy
        }

        // --- Barnes-Hut repulsion ---
        var minX = nodes[0].position.x, minY = nodes[0].position.y
        var maxX = minX, maxY = minY
        for s in nodes {
            minX = min(minX, s.position.x); minY = min(minY, s.position.y)
            maxX = max(maxX, s.position.x); maxY = max(maxY, s.position.y)
        }
        let side = max(maxX - minX, maxY - minY, 800)
        let bounds = CGRect(x: minX - 50, y: minY - 50,
                            width: side + 100, height: side + 100)
        let tree = QuadTreeNode(bounds: bounds)
        for s in nodes { tree.insert(id: s.id, position: s.position) }
        for i in 0..<n {
            applyRepulsion(to: &nodes[i], tree: tree,
                           theta: 0.5, k: kRepulsion)
        }

        // --- Centering + integrate ---
        for i in 0..<n {
            nodes[i].velocity.x += (center.x - nodes[i].position.x) * 0.008
            nodes[i].velocity.y += (center.y - nodes[i].position.y) * 0.008
            nodes[i].position.x += nodes[i].velocity.x * alpha
            nodes[i].position.y += nodes[i].velocity.y * alpha
            nodes[i].velocity.x *= damping
            nodes[i].velocity.y *= damping
        }
    }

    private func applyRepulsion(to node: inout NodeState,
                                tree: QuadTreeNode,
                                theta: CGFloat, k: CGFloat) {
        if let item = tree.nodeItem {
            guard item.id != node.id else { return }
            let dx = node.position.x - item.position.x
            let dy = node.position.y - item.position.y
            let d2 = dx*dx + dy*dy + 0.1
            let f  = k / d2
            node.velocity.x += f * (dx / sqrt(d2))
            node.velocity.y += f * (dy / sqrt(d2))
            return
        }
        let dx = node.position.x - tree.centerOfMass.x
        let dy = node.position.y - tree.centerOfMass.y
        let d2 = dx*dx + dy*dy + 0.1
        let d  = sqrt(d2)
        if tree.bounds.width / d < theta {
            let f = (k * CGFloat(tree.totalMass)) / d2
            node.velocity.x += f * (dx / d)
            node.velocity.y += f * (dy / d)
        } else if let children = tree.children {
            for child in children {
                applyRepulsion(to: &node, tree: child, theta: theta, k: k)
            }
        }
    }

    /// Returns a new CGData where every node has the simulated position.
    /// Edges, layers, tour, and metadata are preserved unchanged.
    public func appliedData(to data: CGData) -> CGData {
        let posMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.position) })
        let updated = data.nodes.map { n in
            CGNode(id: n.id, title: n.title, kind: n.kind,
                   position: posMap[n.id] ?? n.position,
                   metadata: n.metadata)
        }
        return CGData(nodes: updated, edges: data.edges,
                      layers: data.layers, tour: data.tour)
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && swift test --filter CGSimulationTests 2>&1 | tail -8
```
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/InfiniteBrainCore/CodeGraph/CGSimulation.swift \
        Tests/InfiniteBrainTests/CGSimulationTests.swift
git commit -m "feat(code-graph): add CGSimulation Barnes-Hut force layout engine"
```

---

## Task 2 — Obsidian-style CodeGraphCanvas

**Files:**
- Modify (full rewrite): `Sources/InfiniteBrain/Features/CodeGraph/CodeGraphCanvas.swift`

This task rewrites the canvas with:
- **Labels** drawn next to every node (scale-corrected, viewport-culled)
- **Variable node radius** = `5 + √degree × 1.5`
- **Focus mode** (double-click): focused node + direct neighbours full opacity; everything else 8% opacity
- **Drag individual nodes**: if drag starts over a node → move that node; otherwise → pan
- **Hover preview**: hovering a node dims all non-neighbours to 30%
- **Selected-edge highlight**: edges touching the selected node are coloured; rest are 20% grey

- [ ] **Step 1: Rewrite CodeGraphCanvas.swift**

```swift
// Sources/InfiniteBrain/Features/CodeGraph/CodeGraphCanvas.swift
// Obsidian-style renderer: labels, variable sizes, focus mode, drag nodes, hover.
import SwiftUI
import InfiniteBrainCore

@MainActor
struct CodeGraphCanvas: View {
    /// The graph to render. Immutable — positions come from simulation.
    let data: CGData
    /// Currently selected node (single-click). Drives detail panel.
    @Binding var selected: CGNode?
    /// Currently focused node (double-click). nil = no focus.
    @Binding var focusedNode: CGNode?
    var onNodeOpen: ((CGNode) -> Void)? = nil

    // MARK: - Pan / zoom state
    @State private var scale:      CGFloat = 1.0
    @State private var lastScale:  CGFloat = 1.0
    @State private var offset:     CGSize  = .zero
    @State private var lastOffset: CGSize  = .zero
    @State private var canvasSize: CGSize  = .zero
    @State private var lastFitFingerprint: Int = 0

    // MARK: - Drag-node state
    @State private var positionOverrides: [String: CGPoint] = [:]
    @State private var draggedNodeId:     String?   = nil
    @State private var dragStartLoc:      CGPoint?  = nil

    // MARK: - Interaction state
    @State private var hoveredNodeId: String? = nil

    // MARK: - Pre-computed caches (rebuilt when data changes)
    @State private var nodePositions: [String: CGPoint] = [:]
    @State private var nodeDegree:    [String: Int]     = [:]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                Canvas { ctx, size in
                    drawGraph(ctx: ctx, size: size)
                }
                .background(Color(NSColor.windowBackgroundColor))
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc):
                        hoveredNodeId = hitTest(worldPoint(from: loc, size: geo.size))?.id
                    case .ended:
                        hoveredNodeId = nil
                    }
                }
                .gesture(dragGesture(geoSize: geo.size))
                .gesture(zoomGesture)
                .gesture(tapGestures(geoSize: geo.size))
                .onAppear {
                    canvasSize = geo.size
                    rebuildCaches()
                    fitIfNewGraph(in: geo.size)
                }
                .onChange(of: geo.size) { _, new in canvasSize = new }
                .onChange(of: data) { _, _ in
                    positionOverrides = [:]
                    rebuildCaches()
                    fitIfNewGraph(in: canvasSize)
                }
                .onChange(of: selected) { _, new in
                    centerOnNode(new, canvas: geo.size)
                }
            }
            controls
                .padding(12)
        }
    }

    // MARK: - Drawing

    private func drawGraph(ctx: GraphicsContext, size: CGSize) {
        let focused  = focusedNode
        let hovered  = hoveredNodeId
        let selId    = selected?.id

        // Pre-compute neighbourhood sets
        let focusNbrs  = neighbourIds(of: focused?.id)
        let hoverNbrs  = neighbourIds(of: hovered)

        let viewport = CGRect(x: -offset.width / scale,
                              y: -offset.height / scale,
                              width:  size.width  / scale,
                              height: size.height / scale)
        let visible  = viewport.insetBy(dx: -120, dy: -120)

        ctx.concatenate(CGAffineTransform(translationX: offset.width,  y: offset.height))
        ctx.concatenate(CGAffineTransform(scaleX: scale, y: scale))

        // --- Edges ---
        for e in data.edges {
            guard let p1 = effectivePosition(e.fromId),
                  let p2 = effectivePosition(e.toId) else { continue }
            if !visible.contains(p1) && !visible.contains(p2) { continue }

            let alpha = edgeAlpha(e, focused: focused, focusNbrs: focusNbrs,
                                  hovered: hovered, hoverNbrs: hoverNbrs,
                                  selId: selId)
            if alpha < 0.01 { continue }

            let isHighlighted = (e.fromId == selId || e.toId == selId)
                || (e.fromId == focused?.id || e.toId == focused?.id)

            var path = Path(); path.move(to: p1); path.addLine(to: p2)
            let color: Color = isHighlighted
                ? AppPalette.brand.opacity(alpha)
                : Color.secondary.opacity(alpha * 0.6)
            let width = (isHighlighted ? 1.8 : 0.7) / max(scale, 0.4)
            ctx.stroke(path, with: .color(color), lineWidth: width)
        }

        // --- Nodes + labels ---
        for n in data.nodes {
            let pos = effectivePosition(n.id) ?? n.position
            if !visible.contains(pos) { continue }

            let isSel    = n.id == selId
            let isFocused = n.id == focused?.id
            let isHovered = n.id == hovered
            let alpha    = nodeAlpha(n.id, focused: focused, focusNbrs: focusNbrs,
                                     hovered: hovered, hoverNbrs: hoverNbrs)
            if alpha < 0.01 { continue }

            let r = nodeRadius(id: n.id, isSel: isSel || isFocused || isHovered)
            let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r*2, height: r*2)

            // Fill
            ctx.fill(Path(ellipseIn: rect),
                     with: .color(CGPalette.color(for: n.kind).opacity(Double(alpha))))

            // Selection / focus ring
            if isSel || isFocused {
                let ring = rect.insetBy(dx: -5/scale, dy: -5/scale)
                ctx.stroke(Path(ellipseIn: ring),
                           with: .color(AppPalette.brand),
                           lineWidth: 2.5 / max(scale, 0.4))
            }

            // Label
            if scale > 0.25 {
                let fontSize = max(CGFloat(8), CGFloat(11) / scale)
                let labelX   = pos.x + (r + 4) / scale
                let labelY   = pos.y - fontSize * 0.5
                let labelAlpha = min(1.0, alpha * 1.4)
                ctx.draw(
                    Text(n.title)
                        .font(.system(size: fontSize, weight: isSel || isFocused ? .semibold : .regular))
                        .foregroundStyle(Color.primary.opacity(Double(labelAlpha))),
                    at: CGPoint(x: labelX, y: labelY),
                    anchor: .leading
                )
            }
        }
    }

    // MARK: - Alpha helpers

    private func nodeAlpha(_ id: String,
                           focused: CGNode?, focusNbrs: Set<String>,
                           hovered: String?, hoverNbrs: Set<String>) -> Double {
        // Focus takes priority
        if let f = focused {
            if id == f.id           { return 1.0 }
            if focusNbrs.contains(id) { return 0.9 }
            return 0.07  // shadowed
        }
        // Hover
        if let h = hovered {
            if id == h                { return 1.0 }
            if hoverNbrs.contains(id) { return 0.85 }
            return 0.3
        }
        return 1.0
    }

    private func edgeAlpha(_ e: CGEdge,
                           focused: CGNode?, focusNbrs: Set<String>,
                           hovered: String?, hoverNbrs: Set<String>,
                           selId: String?) -> Double {
        if let f = focused {
            if e.fromId == f.id || e.toId == f.id { return 0.9 }
            return 0.03
        }
        if let h = hovered {
            if e.fromId == h || e.toId == h { return 0.8 }
            return 0.05
        }
        // Default: selected edges brighter
        if e.fromId == selId || e.toId == selId { return 0.85 }
        return 0.18
    }

    // MARK: - Caches

    private func rebuildCaches() {
        // Positions (merges position overrides)
        nodePositions = Dictionary(uniqueKeysWithValues: data.nodes.map {
            ($0.id, positionOverrides[$0.id] ?? $0.position)
        })
        // Degree
        var deg: [String: Int] = [:]
        for e in data.edges {
            deg[e.fromId, default: 0] += 1
            deg[e.toId,   default: 0] += 1
        }
        nodeDegree = deg
    }

    private func effectivePosition(_ id: String) -> CGPoint? {
        positionOverrides[id] ?? nodePositions[id]
    }

    private func nodeRadius(id: String, isSel: Bool) -> CGFloat {
        let deg = CGFloat(nodeDegree[id] ?? 0)
        let base: CGFloat = isSel ? 10 : 5
        return base + sqrt(deg) * 1.4
    }

    private func neighbourIds(of id: String?) -> Set<String> {
        guard let id else { return [] }
        return Set(data.edges.compactMap { e in
            if e.fromId == id { return e.toId }
            if e.toId   == id { return e.fromId }
            return nil
        })
    }

    // MARK: - Gestures

    private func dragGesture(geoSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                if dragStartLoc == nil {
                    dragStartLoc = v.startLocation
                    let world = worldPoint(from: v.startLocation, size: geoSize)
                    draggedNodeId = hitTest(world)?.id
                }
                if let nodeId = draggedNodeId {
                    let world = worldPoint(from: v.location, size: geoSize)
                    positionOverrides[nodeId] = world
                    nodePositions[nodeId]     = world   // keep cache in sync
                } else {
                    let delta = CGSize(
                        width:  v.translation.width  - lastOffset.width,
                        height: v.translation.height - lastOffset.height)
                    lastOffset = v.translation
                    offset = CGSize(width:  offset.width  + delta.width,
                                    height: offset.height + delta.height)
                }
            }
            .onEnded { _ in
                dragStartLoc  = nil
                draggedNodeId = nil
                lastOffset    = .zero
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { v in
                let delta = v / lastScale; lastScale = v
                scale = max(0.05, min(6.0, scale * delta))
            }
            .onEnded { _ in lastScale = 1.0 }
    }

    private func tapGestures(geoSize: CGSize) -> some Gesture {
        // Double-tap → focus / unfocus
        SpatialTapGesture(count: 2)
            .onEnded { e in
                let world = worldPoint(from: e.location, size: geoSize)
                if let hit = hitTest(world) {
                    // Toggle focus: double-tap same node unfocuses
                    focusedNode = (focusedNode?.id == hit.id) ? nil : hit
                } else {
                    focusedNode = nil   // double-tap empty space → clear focus
                }
            }
            .exclusively(before:
                // Single-tap → select
                SpatialTapGesture()
                    .onEnded { e in
                        let world = worldPoint(from: e.location, size: geoSize)
                        selected = hitTest(world)
                    }
            )
    }

    // MARK: - Floating controls

    private var controls: some View {
        HStack(spacing: 4) {
            iconBtn("viewfinder",           "Fit")    { fit(animated: true, in: canvasSize, force: true) }
            iconBtn("plus.magnifyingglass", "Zoom in")  { withAnimation(.easeInOut(duration: 0.18)) { scale = min(6, scale * 1.3) } }
            iconBtn("minus.magnifyingglass","Zoom out") { withAnimation(.easeInOut(duration: 0.18)) { scale = max(0.05, scale * 0.77) } }
            if focusedNode != nil {
                Divider().frame(height: 14)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { focusedNode = nil }
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Clear focus (or double-click empty space)")
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.separator, lineWidth: 1))
    }

    @ViewBuilder
    private func iconBtn(_ icon: String, _ tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tip)
    }

    // MARK: - Fit helpers

    private func fitIfNewGraph(in size: CGSize) {
        let fp = fingerprint(of: data)
        guard fp != lastFitFingerprint else { return }
        lastFitFingerprint = fp
        fit(animated: false, in: size, force: true)
    }

    private func fit(animated: Bool, in size: CGSize, force: Bool) {
        guard size.width > 0, size.height > 0, !data.nodes.isEmpty else { return }
        let positions = data.nodes.map { effectivePosition($0.id) ?? $0.position }
        let xs = positions.map { $0.x }
        let ys = positions.map { $0.y }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return }
        let s = min(size.width  * 0.88 / max(maxX - minX, 1),
                    size.height * 0.88 / max(maxY - minY, 1))
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        let apply = {
            self.scale  = max(0.05, min(6.0, s))
            self.offset = CGSize(width:  size.width  / 2 - cx * s,
                                 height: size.height / 2 - cy * s)
        }
        if animated { withAnimation(.easeInOut(duration: 0.3)) { apply() } } else { apply() }
        _ = force
    }

    private func centerOnNode(_ node: CGNode?, canvas size: CGSize) {
        guard let node, size.width > 0, size.height > 0 else { return }
        let pos = effectivePosition(node.id) ?? node.position
        withAnimation(.easeInOut(duration: 0.25)) {
            offset = CGSize(width:  size.width  / 2 - pos.x * scale,
                            height: size.height / 2 - pos.y * scale)
        }
    }

    private func fingerprint(of d: CGData) -> Int {
        var h = Hasher()
        h.combine(d.nodes.count); h.combine(d.edges.count)
        if let f = d.nodes.first?.id { h.combine(f) }
        if let l = d.nodes.last?.id  { h.combine(l) }
        return h.finalize()
    }

    private func worldPoint(from pt: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: (pt.x - offset.width)  / scale,
                y: (pt.y - offset.height) / scale)
    }

    private func hitTest(_ point: CGPoint) -> CGNode? {
        let radius: CGFloat = max(18, 18 / scale)
        var best: (CGNode, CGFloat)?
        for n in data.nodes {
            let pos = effectivePosition(n.id) ?? n.position
            let dx = pos.x - point.x, dy = pos.y - point.y
            let d  = hypot(dx, dy)
            if d < radius, d < (best?.1 ?? .infinity) { best = (n, d) }
        }
        return best?.0
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/InfiniteBrain/Features/CodeGraph/CodeGraphCanvas.swift
git commit -m "feat(code-graph): Obsidian-style canvas — labels, sizes, focus, drag, hover"
```

---

## Task 3 — CodeGraphView: simulation + focusedNode

**Files:**
- Modify: `Sources/InfiniteBrain/Features/CodeGraph/CodeGraphView.swift`

Three changes:
1. Add `@State private var focusedNode: CGNode? = nil`
2. Pass `focusedNode` binding to both `CodeGraphCanvas` call sites
3. Run `CGSimulation.settle()` in a background task after the initial layout, then update `fullData`

- [ ] **Step 1: Add focusedNode state and update both CodeGraphCanvas calls**

Read the file, find the two `CodeGraphCanvas(` call sites and all the current state declarations, then make these edits:

**Add state declaration** (alongside the other `@State private var` lines at the top of the struct):
```swift
@State private var focusedNode: CGNode? = nil
```

**Both CodeGraphCanvas call sites** — change from:
```swift
CodeGraphCanvas(data: displayData,
                selected: $selectedNode,
                onNodeOpen: openNode)
```
to:
```swift
CodeGraphCanvas(data: displayData,
                selected: $selectedNode,
                focusedNode: $focusedNode,
                onNodeOpen: openNode)
```

There are exactly two call sites in `canvasPanel` and `expandedOverlay`.

- [ ] **Step 2: Update runScan() to run CGSimulation after initial layout**

Find `private func runScan()` and replace its body with:

```swift
private func runScan() {
    guard let target = targetFolder else { return }
    status  = .running
    runTask = Task {
        let scanner = StructureScanner(launcher: SystemProcessLauncher())
        let scan    = await scanner.scan(repoRoot: target)
        if Task.isCancelled { self.status = .idle; return }

        let codeGraph = StructureGraphBuilder.build(scan, repoRoot: target)
        let noteNodes = CodeNoteWriter.generateNoteNodes(scan: scan, repoRoot: target)
        let docEdges: [CGEdge] = noteNodes.compactMap { note in
            guard let src = note.metadata["source_code_file"] else { return nil }
            return CGEdge(fromId: note.id, toId: "file:\(src)", kind: .documents)
        }
        let combined = CGData(
            nodes: codeGraph.nodes + noteNodes,
            edges: codeGraph.edges + docEdges)

        // Phase 1: circular layout — show immediately so user isn't waiting
        let initial = CodeGraphLayout.compute(
            combined,
            canvasSize: UAHelpers.layoutSize(for: combined.nodes.count))

        self.selectedNode  = nil
        self.focusedNode   = nil
        self.fullData      = initial
        self.noteArtifacts = UAHelpers.collectNoteArtifacts(initial)
        self.status        = .loaded(nodeCount: codeGraph.nodes.count,
                                     edgeCount: codeGraph.edges.count)

        // Phase 2: physics simulation — runs in background, updates positions
        if Task.isCancelled { return }
        let settled = await Task.detached(priority: .userInitiated) {
            let sim = CGSimulation(data: initial)
            sim.settle(maxIterations: 200)
            return sim.appliedData(to: initial)
        }.value

        if !Task.isCancelled {
            self.fullData = settled
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 4: Run full test suite**

```bash
swift test 2>&1 | grep -E "Executed|failed" | tail -5
```
Expected: all code-graph tests pass, only pre-existing TextChunkerTests failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/InfiniteBrain/Features/CodeGraph/CodeGraphView.swift
git commit -m "feat(code-graph): integrate CGSimulation settle-then-freeze + focusedNode binding"
```

---

## Task 4 — Final verification

- [ ] **Step 1: Full build + tests**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && swift build 2>&1 | tail -3 && swift test 2>&1 | grep -E "Executed|failed" | tail -3
```
Expected: `Build complete!` and all new tests pass.

- [ ] **Step 2: Build release app**

```bash
bash bin/build_app.sh 2>&1 | tail -4
```

- [ ] **Step 3: Launch and verify**

```bash
open .build/dist/InfiniteBrain.app
```

Manual checklist:
1. Click **Generate Graph** → circular layout appears instantly, then nodes re-arrange with physics in ~1-2s
2. **Labels** visible on all nodes (file names next to dots)
3. **Node sizes** vary — files with more imports/dependents are larger
4. **Single-click** a node → detail panel shows note; node gets ring highlight
5. **Double-click** a node → focus mode: that node + direct neighbours stay bright, everything else fades to ~8%
6. **Double-click same node** OR **double-click empty space** → exits focus mode
7. **Drag a node** → it repositions; other nodes stay in place (physics doesn't re-run)
8. **Hover** over a node → its neighbours stay visible, rest dims to 30%
9. **"×" button** in toolbar → clears focus mode
10. **Expand button** → full-window canvas, all interactions work identically
