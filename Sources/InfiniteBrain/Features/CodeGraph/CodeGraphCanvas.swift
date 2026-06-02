// Pure renderer for CGData. Pan, zoom, single-click select, double-click open.
// Auto-fits to viewport on each new graph load (fingerprint guard).
import SwiftUI
import InfiniteBrainCore

@MainActor
struct CodeGraphCanvas: View {
    let data: CGData
    @Binding var selected: CGNode?
    var onNodeOpen: ((CGNode) -> Void)? = nil

    @State private var scale:       CGFloat = 1.0
    @State private var lastScale:   CGFloat = 1.0
    @State private var offset:      CGSize  = .zero
    @State private var lastOffset:  CGSize  = .zero
    @State private var canvasSize:  CGSize  = .zero
    @State private var lastFitFingerprint: Int = 0
    @State private var nodePositions: [String: CGPoint] = [:]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                Canvas { ctx, size in
                    let viewport = CGRect(x: -offset.width  / scale,
                                         y: -offset.height / scale,
                                         width:  size.width  / scale,
                                         height: size.height / scale)
                    let visible = viewport.insetBy(dx: -40, dy: -40)
                    ctx.concatenate(CGAffineTransform(translationX: offset.width, y: offset.height))
                    ctx.concatenate(CGAffineTransform(scaleX: scale, y: scale))

                    for e in data.edges {
                        guard let p1 = nodePositions[e.fromId],
                              let p2 = nodePositions[e.toId] else { continue }
                        if !visible.contains(p1) && !visible.contains(p2) { continue }
                        var path = Path(); path.move(to: p1); path.addLine(to: p2)
                        let related = (e.fromId == selected?.id || e.toId == selected?.id)
                        ctx.stroke(path,
                                   with: .color(related ? AppPalette.brand : Color.secondary.opacity(0.3)),
                                   lineWidth: (related ? 2.0 : 0.8) / max(scale, 0.5))
                    }

                    for n in data.nodes {
                        if !visible.contains(n.position) { continue }
                        let isSel  = n.id == selected?.id
                        let baseR: CGFloat = isSel ? 10 : 5
                        let r = max(baseR, baseR / (scale * 0.5))
                        let rect = CGRect(x: n.position.x - r, y: n.position.y - r,
                                          width: r * 2, height: r * 2)
                        ctx.fill(Path(ellipseIn: rect),
                                 with: .color(CGPalette.color(for: n.kind)))
                        if isSel {
                            ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -4/scale, dy: -4/scale)),
                                       with: .color(AppPalette.brand),
                                       lineWidth: 3.0 / max(scale, 0.5))
                        }
                    }
                }
                .background(Color(NSColor.windowBackgroundColor))
                .gesture(panZoomGesture)
                .gesture(tapGestures)
                .onAppear {
                    canvasSize = geo.size
                    rebuildPositions()
                    fitIfNewGraph(in: geo.size)
                }
                .onChange(of: geo.size) { _, new in canvasSize = new }
                .onChange(of: data) { _, _ in
                    rebuildPositions()
                    fitIfNewGraph(in: canvasSize)
                }
                .onChange(of: selected) { _, new in
                    centerOnSelected(new, canvas: geo.size)
                }
            }
            controls.padding(12)
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            iconBtn("viewfinder",        "Fit graph") { fit(animated: true, in: canvasSize, force: true) }
            iconBtn("plus.magnifyingglass",  "Zoom in")  { withAnimation(.easeInOut(duration: 0.18)) { scale = min(4, scale * 1.25) } }
            iconBtn("minus.magnifyingglass", "Zoom out") { withAnimation(.easeInOut(duration: 0.18)) { scale = max(0.05, scale * 0.8) } }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(NSColor.separatorColor), lineWidth: 1))
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

    private var panZoomGesture: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { v in
                    let delta = v / lastScale; lastScale = v
                    scale = max(0.05, min(4.0, scale * delta))
                }
                .onEnded { _ in lastScale = 1.0 },
            DragGesture()
                .onChanged { v in
                    let delta = CGSize(width:  v.translation.width  - lastOffset.width,
                                       height: v.translation.height - lastOffset.height)
                    lastOffset = v.translation
                    offset = CGSize(width: offset.width + delta.width,
                                    height: offset.height + delta.height)
                }
                .onEnded { _ in lastOffset = .zero }
        )
    }

    private var tapGestures: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { e in
                let w = worldPoint(from: e.location)
                if let hit = hitTest(w) { onNodeOpen?(hit) }
            }
            .exclusively(before:
                SpatialTapGesture()
                    .onEnded { e in selected = hitTest(worldPoint(from: e.location)) }
            )
    }

    private func worldPoint(from pt: CGPoint) -> CGPoint {
        CGPoint(x: (pt.x - offset.width)  / scale,
                y: (pt.y - offset.height) / scale)
    }

    private func rebuildPositions() {
        nodePositions = Dictionary(uniqueKeysWithValues: data.nodes.map { ($0.id, $0.position) })
    }

    private func fitIfNewGraph(in size: CGSize) {
        let fp = fingerprint(of: data)
        guard fp != lastFitFingerprint else { return }
        lastFitFingerprint = fp
        fit(animated: false, in: size, force: true)
    }

    private func fit(animated: Bool, in size: CGSize, force: Bool) {
        guard size.width > 0, size.height > 0, !data.nodes.isEmpty else { return }
        let xs = data.nodes.map { $0.position.x }
        let ys = data.nodes.map { $0.position.y }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return }
        let s = min(size.width * 0.9 / max(maxX - minX, 1),
                    size.height * 0.9 / max(maxY - minY, 1))
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        let tOff = CGSize(width: size.width / 2 - cx * s, height: size.height / 2 - cy * s)
        let apply = { self.scale = max(0.05, min(4.0, s)); self.offset = tOff }
        if animated { withAnimation(.easeInOut(duration: 0.25)) { apply() } } else { apply() }
        _ = force
    }

    private func centerOnSelected(_ node: CGNode?, canvas size: CGSize) {
        guard let node, size.width > 0, size.height > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            offset = CGSize(width:  size.width  / 2 - node.position.x * scale,
                            height: size.height / 2 - node.position.y * scale)
        }
    }

    private func fingerprint(of d: CGData) -> Int {
        var h = Hasher()
        h.combine(d.nodes.count); h.combine(d.edges.count)
        if let f = d.nodes.first?.id { h.combine(f) }
        if let l = d.nodes.last?.id  { h.combine(l) }
        return h.finalize()
    }

    private func hitTest(_ point: CGPoint) -> CGNode? {
        let radius: CGFloat = 16 / max(scale, 0.5)
        var best: (CGNode, CGFloat)?
        for n in data.nodes {
            let dx = n.position.x - point.x, dy = n.position.y - point.y
            let d  = sqrt(dx * dx + dy * dy)
            if d < radius, d < (best?.1 ?? .infinity) { best = (n, d) }
        }
        return best?.0
    }
}
