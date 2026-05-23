import SwiftUI
import InfiniteBrainCore

@MainActor
struct GraphView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var ingest: IngestViewModel
    
    @State private var data: GraphData = .init(nodes: [], edges: [])
    @State private var selected: GraphNode?
    @State private var loading = false
    @State private var canvasSize: CGSize = .init(width: 800, height: 600)
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    @State private var simulation: GraphSimulation?
    @State private var isSimulating = true
    @State private var currentBacklinks: [GraphNode] = []
    @State private var store: VaultStore?
    @State private var lastSaveTime: Date = .distantPast
    @State private var notesCache: [Note] = []

    var body: some View {
            ZStack(alignment: .topTrailing) {
                GeometryReader { geo in
                    TimelineView(.animation) { timeline in
                        Canvas { ctx, size in
                            if isSimulating {
                                simulation?.step(canvasSize: size)
                                if Date().timeIntervalSince(lastSaveTime) > 2.0 {
                                    persistPositions()
                                }
                            }
                            
                            let viewport = CGRect(x: -offset.width / scale, y: -offset.height / scale,
                                                  width: size.width / scale, height: size.height / scale)
                            let visibleRect = viewport.insetBy(dx: -40, dy: -40)

                            ctx.concatenate(CGAffineTransform(translationX: offset.width, y: offset.height))
                            ctx.concatenate(CGAffineTransform(scaleX: scale, y: scale))
                            
                            if let sim = simulation {
                                let nodePositions = Dictionary(uniqueKeysWithValues: sim.nodes.map { ($0.id, $0.position) })
                                
                                // Edges
                                for e in sim.edges {
                                    guard let p1 = nodePositions[e.fromId], let p2 = nodePositions[e.toId] else { continue }
                                    if !visibleRect.contains(p1) && !visibleRect.contains(p2) { continue }
                                    var path = Path()
                                    path.move(to: p1)
                                    path.addLine(to: p2)
                                    
                                    // Sleek edges
                                    let isRelated = (e.fromId == selected?.id || e.toId == selected?.id)
                                    let opacity = isRelated ? 1.0 : 0.6
                                    let width = (isRelated ? 3.0 : 1.5) / max(scale, 0.5)
                                    
                                    ctx.stroke(path, with: .color(.primary.opacity(opacity)), lineWidth: width)
                                }
                                
                                // Nodes with Glow
                                for n in sim.nodes {
                                    if !visibleRect.contains(n.position) { continue }
                                    guard let full = data.nodes.first(where: { $0.id == n.id }) else { continue }
                                    
                                    let isSelected = n.id == selected?.id
                                    // Nodes stay visible even when zoomed out:
                                    let baseR: CGFloat = isSelected ? 12 : 8
                                    let r = max(baseR, baseR / (scale * 0.5)) 
                                    
                                    let rect = CGRect(x: n.position.x - r, y: n.position.y - r, width: r*2, height: r*2)
                                    let color = NodePalette.color(for: full.type)
                                    
                                    // Draw Node Core (Solid, high visibility)
                                    ctx.addFilter(.blur(radius: 0))
                                    let nodePath = Path(ellipseIn: rect)
                                    ctx.fill(nodePath, with: .color(color))
                                    
                                    // Stronger outline for definition
                                    ctx.stroke(nodePath, with: .color(.black.opacity(0.4)), lineWidth: 2.0 / max(scale, 0.5))
                                    
                                    if isSelected {
                                        let ring = Path(ellipseIn: rect.insetBy(dx: -6/scale, dy: -6/scale))
                                        ctx.stroke(ring, with: .color(AppPalette.brand), lineWidth: 4.0 / max(scale, 0.5))
                                    }
                                }
                            }
                        }
                        .background(Color(nsColor: .windowBackgroundColor))
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { val in
                                        let delta = val / lastScale
                                        lastScale = val
                                        scale *= delta
                                    }
                                    .onEnded { _ in lastScale = 1.0 },
                                DragGesture()
                                    .onChanged { val in
                                        let delta = CGSize(width: val.translation.width - lastOffset.width,
                                                           height: val.translation.height - lastOffset.height)
                                        lastOffset = val.translation
                                        offset = CGSize(width: offset.width + delta.width,
                                                        height: offset.height + delta.height)
                                    }
                                    .onEnded { _ in lastOffset = .zero }
                            )
                        )
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { event in
                                    let transformed = CGPoint(
                                        x: (event.location.x - offset.width) / scale,
                                        y: (event.location.y - offset.height) / scale
                                    )
                                    selected = hitTest(transformed)
                                }
                        )
                    }
                    .onAppear {
                        canvasSize = geo.size
                        Task { await reload() }
                    }
                    .onChange(of: geo.size) { _, new in
                        canvasSize = new
                    }
                }
                
                VStack(alignment: .trailing, spacing: 12) {
                    toolbarContent
                    sidebar
                }
                .padding(24)
            }
        .onChange(of: ingest.lastResult) { _, _ in
            Task { await reload() }
        }
        .onChange(of: selected) { _, newValue in
            updateBacklinks(for: newValue)
        }
    }

    // MARK: - Components

    private var toolbarContent: some View {
        HStack(spacing: 4) {
            Button {
                isSimulating.toggle()
            } label: {
                Image(systemName: isSimulating ? "pause.fill" : "play.fill")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            
            Divider().frame(height: 16)
            
            Button {
                scale = 1.0
                offset = .zero
            } label: {
                Image(systemName: "scope")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            
            Button(action: { Task { await reload() } }) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            
            Divider().frame(height: 16)
            
            Text("\(data.nodes.count) Nodes")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(AppPalette.border, lineWidth: 1))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let s = selected {
                Text(s.title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)
                Text(s.summary)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                
                if !currentBacklinks.isEmpty {
                    Divider()
                    Text("Semantic Backlinks")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(currentBacklinks) { bl in
                                Button(action: { selected = bl }) {
                                    HStack {
                                        Circle().fill(NodePalette.color(for: bl.type)).frame(width: 8, height: 8)
                                        Text(bl.title).font(.caption).lineLimit(2)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else {
                Text("Knowledge Legend")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                Divider()
                ForEach(NodeType.allCases, id: \.self) { t in
                    HStack {
                        Circle().fill(NodePalette.color(for: t)).frame(width: 10, height: 10)
                            .shadow(color: NodePalette.color(for: t).opacity(0.8), radius: 3)
                        Text(t.rawValue.replacingOccurrences(of: "-", with: " ").capitalized)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 1)
                }
            }
            Spacer()
        }
        .padding(20)
        .frame(width: 260)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppPalette.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
    }

    // MARK: - Logic

    private func reload() async {
        guard let root = settings.vaultPath else { return }
        let vault = Vault(root: root)
        loading = true
        defer { loading = false }
        
        let newStore = VaultStore(vault: vault)
        self.store = newStore
        
        if await newStore.metadataIndex.load() {
            let entries = await newStore.metadataIndex.allEntries()
            if !entries.isEmpty {
                let graphNodes = entries.map { e in
                    GraphNode(id: e.id, title: e.title, type: NodeType(rawValue: e.type), summary: e.summary, position: .zero)
                }
                let graphEdges = entries.flatMap { e in
                    e.edges.map { GraphEdge(fromId: e.id, toId: $0.targetId, type: EdgeType(rawValue: $0.type) ?? .relatedTo) }
                }
                data = GraphData(nodes: graphNodes.map { n in
                    var n2 = n
                    if let entry = entries.first(where: { $0.id == n.id }), entry.x != 0 || entry.y != 0 {
                        n2.position = CGPoint(x: entry.x, y: entry.y)
                    } else {
                        n2.position = CGPoint(x: CGFloat.random(in: 0...canvasSize.width), y: CGFloat.random(in: 0...canvasSize.height))
                    }
                    return n2
                }, edges: graphEdges)
                simulation = GraphSimulation(data: data)
            }
        }

        let notes = (try? await newStore.allNotes()) ?? []
        notesCache = notes
        let newData = GraphLayout.compute(notes: notes, canvasSize: canvasSize)
        data = newData
        simulation = GraphSimulation(data: newData)
        try? await newStore.saveMetadata()
    }

    private func persistPositions() {
        guard let store = store, let sim = simulation else { return }
        let nodesToSave = sim.nodes
        Task {
            for n in nodesToSave {
                await store.metadataIndex.updatePosition(id: n.id, x: Double(n.position.x), y: Double(n.position.y))
            }
            try? await store.saveMetadata()
        }
    }

    private func hitTest(_ loc: CGPoint) -> GraphNode? {
        guard let sim = simulation else { return nil }
        let nearest = sim.nodes.min { a, b in
            dist(a.position, loc) < dist(b.position, loc)
        }
        guard let n = nearest, dist(n.position, loc) < 15 else { return nil }
        return data.nodes.first(where: { $0.id == n.id })
    }

    private func updateBacklinks(for node: GraphNode?) {
        guard let s = node, let store = store else {
            currentBacklinks = []
            return
        }
        Task {
            let ids = await store.metadataIndex.getBacklinks(for: s.id)
            currentBacklinks = data.nodes.filter { ids.contains($0.id) }
        }
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
    }
}
