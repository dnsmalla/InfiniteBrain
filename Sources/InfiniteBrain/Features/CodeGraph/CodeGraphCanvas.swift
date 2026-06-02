// Obsidian-style code graph renderer.
// • Labels on every node (scale-corrected, viewport-culled)
// • Node radius scales with sqrt(degree)
// • Double-click: focus mode — neighbours bright, rest 8% opacity
// • Single-click: select node (drives detail panel)
// • Drag over a node: reposition that node
// • Drag empty space: pan canvas
// • Hover: neighbours 85%, rest 30%
// • Clear-focus button in toolbar
import SwiftUI
import InfiniteBrainCore

@MainActor
struct CodeGraphCanvas: View {
    let data: CGData
    @Binding var selected:    CGNode?
    @Binding var focusedNode: CGNode?
    var onNodeOpen: ((CGNode) -> Void)? = nil

    // MARK: Pan / zoom
    @State private var scale:      CGFloat = 1.0
    @State private var lastScale:  CGFloat = 1.0
    @State private var offset:     CGSize  = .zero
    @State private var lastOffset: CGSize  = .zero
    @State private var canvasSize: CGSize  = .zero
    @State private var lastFitFingerprint: Int = 0

    // MARK: Node drag
    @State private var positionOverrides: [String: CGPoint] = [:]
    @State private var draggedNodeId:     String?    = nil
    @State private var dragStartLoc:      CGPoint?   = nil

    // MARK: Interaction
    @State private var hoveredNodeId: String? = nil

    // MARK: Caches (rebuilt on data change)
    @State private var nodePositions: [String: CGPoint] = [:]
    @State private var nodeDegree:    [String: Int]     = [:]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                Canvas { ctx, size in
                    drawGraph(ctx: &ctx, size: size)
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

    private func drawGraph(ctx: inout GraphicsContext, size: CGSize) {
        let focused    = focusedNode
        let hovered    = hoveredNodeId
        let selId      = selected?.id
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
            guard let p1 = effectivePos(e.fromId),
                  let p2 = effectivePos(e.toId) else { continue }
            if !visible.contains(p1) && !visible.contains(p2) { continue }

            let alpha = edgeAlpha(e, focused: focused, focusNbrs: focusNbrs,
                                  hovered: hovered, hoverNbrs: hoverNbrs, selId: selId)
            if alpha < 0.01 { continue }

            let isHighlighted = (e.fromId == selId || e.toId == selId)
                || (e.fromId == focused?.id || e.toId == focused?.id)

            var path = Path(); path.move(to: p1); path.addLine(to: p2)
            let colour: Color = isHighlighted
                ? AppPalette.brand.opacity(alpha)
                : Color.secondary.opacity(alpha * 0.55)
            ctx.stroke(path, with: .color(colour),
                       lineWidth: (isHighlighted ? 1.8 : 0.7) / max(scale, 0.4))
        }

        // --- Nodes + labels ---
        for n in data.nodes {
            guard let pos = effectivePos(n.id), visible.contains(pos) else { continue }

            let isSel     = n.id == selId
            let isFocused = n.id == focused?.id
            let isHovered = n.id == hoveredNodeId
            let alpha     = nodeAlpha(n.id, focused: focused, focusNbrs: focusNbrs,
                                      hovered: hovered, hoverNbrs: hoverNbrs)
            if alpha < 0.01 { continue }

            let r    = nodeR(id: n.id, prominent: isSel || isFocused || isHovered)
            let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)

            ctx.fill(Path(ellipseIn: rect),
                     with: .color(CGPalette.color(for: n.kind).opacity(Double(alpha))))

            if isSel || isFocused {
                ctx.stroke(
                    Path(ellipseIn: rect.insetBy(dx: -5 / scale, dy: -5 / scale)),
                    with: .color(AppPalette.brand),
                    lineWidth: 2.5 / max(scale, 0.4))
            }

            // Label — scale-corrected so screen size ≈ 11pt regardless of zoom
            if scale > 0.2 {
                let fontSize  = max(CGFloat(7), CGFloat(11) / scale)
                let labelX    = pos.x + (r + 4) / scale
                let labelY    = pos.y - fontSize * 0.5
                ctx.draw(
                    Text(n.title)
                        .font(.system(size: fontSize,
                                      weight: (isSel || isFocused) ? .semibold : .regular))
                        .foregroundStyle(Color.primary.opacity(Double(min(1.0, alpha * 1.3)))),
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
        if let f = focused {
            if id == f.id              { return 1.0 }
            if focusNbrs.contains(id)  { return 0.90 }
            return 0.07
        }
        if let h = hovered {
            if id == h                 { return 1.0 }
            if hoverNbrs.contains(id)  { return 0.85 }
            return 0.28
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
            return 0.04
        }
        if e.fromId == selId || e.toId == selId { return 0.85 }
        return 0.18
    }

    // MARK: - Caches

    private func rebuildCaches() {
        nodePositions = Dictionary(
            uniqueKeysWithValues: data.nodes.map {
                ($0.id, positionOverrides[$0.id] ?? $0.position)
            })
        var deg: [String: Int] = [:]
        for e in data.edges {
            deg[e.fromId, default: 0] += 1
            deg[e.toId,   default: 0] += 1
        }
        nodeDegree = deg
    }

    private func effectivePos(_ id: String) -> CGPoint? {
        positionOverrides[id] ?? nodePositions[id]
    }

    private func nodeR(id: String, prominent: Bool) -> CGFloat {
        let deg  = CGFloat(nodeDegree[id] ?? 0)
        let base: CGFloat = prominent ? 10 : 5
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
                    dragStartLoc  = v.startLocation
                    let world     = worldPoint(from: v.startLocation, size: geoSize)
                    draggedNodeId = hitTest(world)?.id
                }
                if let nodeId = draggedNodeId {
                    let world                = worldPoint(from: v.location, size: geoSize)
                    positionOverrides[nodeId] = world
                    nodePositions[nodeId]     = world
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
        SpatialTapGesture(count: 2)
            .onEnded { e in
                let world = worldPoint(from: e.location, size: geoSize)
                if let hit = hitTest(world) {
                    focusedNode = (focusedNode?.id == hit.id) ? nil : hit
                } else {
                    focusedNode = nil
                }
            }
            .exclusively(before:
                SpatialTapGesture()
                    .onEnded { e in
                        let world = worldPoint(from: e.location, size: geoSize)
                        selected  = hitTest(world)
                    }
            )
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 4) {
            iconBtn("viewfinder",            "Fit graph") {
                fit(animated: true, in: canvasSize, force: true)
            }
            iconBtn("plus.magnifyingglass",  "Zoom in") {
                withAnimation(.easeInOut(duration: 0.18)) { scale = min(6, scale * 1.3) }
            }
            iconBtn("minus.magnifyingglass", "Zoom out") {
                withAnimation(.easeInOut(duration: 0.18)) { scale = max(0.05, scale * 0.77) }
            }
            if focusedNode != nil {
                Divider().frame(height: 14)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { focusedNode = nil }
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear focus (Esc or double-click empty space)")
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(NSColor.separatorColor), lineWidth: 1))
    }

    @ViewBuilder
    private func iconBtn(_ icon: String, _ tip: String,
                         action: @escaping () -> Void) -> some View {
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
        let positions = data.nodes.compactMap { effectivePos($0.id) }
        let xs = positions.map { $0.x }
        let ys = positions.map { $0.y }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return }
        let s  = min(size.width  * 0.88 / max(maxX - minX, 1),
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
        let pos = effectivePos(node.id) ?? node.position
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
        let radius: CGFloat = max(18, 18 / max(scale, 0.3))
        var best: (CGNode, CGFloat)?
        for n in data.nodes {
            guard let pos = effectivePos(n.id) else { continue }
            let d = hypot(pos.x - point.x, pos.y - point.y)
            if d < radius, d < (best?.1 ?? .infinity) { best = (n, d) }
        }
        return best?.0
    }
}
