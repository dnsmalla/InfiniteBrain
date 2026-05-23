import SwiftUI
import InfiniteBrainCore

/// Pure graph renderer. Force-directed canvas with pan, zoom, single-click
/// selection, and double-click "open". Owns viewport state; data and
/// simulation come from the host view. Used by CodeGraphView; the knowledge
/// graph keeps its own bespoke renderer.
@MainActor
public struct GraphCanvas: View {
    public let data: GraphData
    public let simulation: GraphSimulation
    @Binding public var selected: GraphNode?
    public var isSimulating: Bool
    public var onTick: (() -> Void)?
    public var onNodeOpen: ((GraphNode) -> Void)?

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    public init(data: GraphData,
                simulation: GraphSimulation,
                selected: Binding<GraphNode?>,
                isSimulating: Bool = true,
                onTick: (() -> Void)? = nil,
                onNodeOpen: ((GraphNode) -> Void)? = nil) {
        self.data = data
        self.simulation = simulation
        self._selected = selected
        self.isSimulating = isSimulating
        self.onTick = onTick
        self.onNodeOpen = onNodeOpen
    }

    public var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { _ in
                Canvas { ctx, size in
                    if isSimulating {
                        simulation.step(canvasSize: size)
                        onTick?()
                    }
                    let viewport = CGRect(x: -offset.width / scale,
                                          y: -offset.height / scale,
                                          width: size.width / scale,
                                          height: size.height / scale)
                    let visibleRect = viewport.insetBy(dx: -40, dy: -40)
                    ctx.concatenate(CGAffineTransform(translationX: offset.width, y: offset.height))
                    ctx.concatenate(CGAffineTransform(scaleX: scale, y: scale))

                    let nodePositions = Dictionary(uniqueKeysWithValues: simulation.nodes.map { ($0.id, $0.position) })
                    for e in simulation.edges {
                        guard let p1 = nodePositions[e.fromId], let p2 = nodePositions[e.toId] else { continue }
                        if !visibleRect.contains(p1) && !visibleRect.contains(p2) { continue }
                        var path = Path(); path.move(to: p1); path.addLine(to: p2)
                        let isRelated = (e.fromId == selected?.id || e.toId == selected?.id)
                        let opacity = isRelated ? 1.0 : 0.6
                        let width = (isRelated ? 3.0 : 1.5) / max(scale, 0.5)
                        ctx.stroke(path, with: .color(.primary.opacity(opacity)), lineWidth: width)
                    }
                    for n in simulation.nodes {
                        if !visibleRect.contains(n.position) { continue }
                        guard let full = data.nodes.first(where: { $0.id == n.id }) else { continue }
                        let isSelected = n.id == selected?.id
                        let baseR: CGFloat = isSelected ? 12 : 8
                        let r = max(baseR, baseR / (scale * 0.5))
                        let rect = CGRect(x: n.position.x - r, y: n.position.y - r, width: r*2, height: r*2)
                        let color = NodePalette.color(for: full.type)
                        ctx.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { v in
                                let delta = v / lastScale
                                lastScale = v
                                scale *= delta
                            }
                            .onEnded { _ in lastScale = 1.0 },
                        DragGesture()
                            .onChanged { v in
                                let delta = CGSize(width: v.translation.width - lastOffset.width,
                                                   height: v.translation.height - lastOffset.height)
                                lastOffset = v.translation
                                offset = CGSize(width: offset.width + delta.width,
                                                height: offset.height + delta.height)
                            }
                            .onEnded { _ in lastOffset = .zero }
                    )
                )
                .gesture(
                    SpatialTapGesture(count: 2)
                        .onEnded { event in
                            let world = CGPoint(x: (event.location.x - offset.width) / scale,
                                                y: (event.location.y - offset.height) / scale)
                            if let hit = hitTest(world) { onNodeOpen?(hit) }
                        }
                )
                .gesture(
                    SpatialTapGesture()
                        .onEnded { event in
                            let world = CGPoint(x: (event.location.x - offset.width) / scale,
                                                y: (event.location.y - offset.height) / scale)
                            selected = hitTest(world)
                        }
                )
            }
        }
    }

    private func hitTest(_ point: CGPoint) -> GraphNode? {
        var best: (GraphNode, CGFloat)?
        let radius: CGFloat = 16 / max(scale, 0.5)
        for n in simulation.nodes {
            let dx = n.position.x - point.x, dy = n.position.y - point.y
            let d = sqrt(dx*dx + dy*dy)
            if d < radius, best == nil || d < best!.1 {
                if let full = data.nodes.first(where: { $0.id == n.id }) { best = (full, d) }
            }
        }
        return best?.0
    }
}
