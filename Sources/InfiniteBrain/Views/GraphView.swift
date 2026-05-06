import SwiftUI
import InfiniteBrainCore

struct GraphView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var data: GraphData = .init(nodes: [], edges: [])
    @State private var selected: GraphNode?
    @State private var loading = false
    @State private var canvasSize: CGSize = .init(width: 800, height: 600)

    var body: some View {
        HSplitView {
            GeometryReader { geo in
                ZStack {
                    Canvas { ctx, size in
                        // Edges first so nodes draw on top.
                        for e in data.edges {
                            guard let from = node(id: e.fromId), let to = node(id: e.toId) else { continue }
                            var path = Path()
                            path.move(to: from.position)
                            path.addLine(to: to.position)
                            ctx.stroke(path, with: .color(.secondary.opacity(0.25)), lineWidth: 0.6)
                        }
                        // Nodes.
                        for n in data.nodes {
                            let r: CGFloat = n.id == selected?.id ? 8 : 5
                            let rect = CGRect(x: n.position.x - r, y: n.position.y - r, width: r*2, height: r*2)
                            ctx.fill(Path(ellipseIn: rect), with: .color(Self.color(for: n.type)))
                            if n.id == selected?.id {
                                let ring = Path(ellipseIn: rect.insetBy(dx: -3, dy: -3))
                                ctx.stroke(ring, with: .color(.primary.opacity(0.6)), lineWidth: 1.5)
                            }
                        }
                    }
                    .background(Color(nsColor: .windowBackgroundColor))
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { event in
                                selected = hitTest(event.location)
                            }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        canvasSize = geo.size
                        Task { await reload() }
                    }
                    .onChange(of: geo.size) { _, new in
                        canvasSize = new
                        data = GraphLayout.compute(notes: notesCache, canvasSize: new)
                    }

                    if loading {
                        ProgressView().controlSize(.large)
                    } else if data.nodes.isEmpty {
                        Text("No notes yet — ingest something from the Ingest tab.")
                            .foregroundStyle(.secondary)
                    }
                }
                .toolbar {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await reload() }
                    }
                    Text("\(data.nodes.count) notes · \(data.edges.count) edges")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 480, minHeight: 360)

            sidebar
                .frame(width: 280)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        Group {
            if let s = selected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(Self.color(for: s.type)).frame(width: 10, height: 10)
                        Text(s.type.rawValue).font(.caption.smallCaps()).foregroundStyle(.secondary)
                    }
                    Text(s.title).font(.headline)
                    Text(s.summary).font(.callout)
                    Text(s.id).font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Legend").font(.headline)
                    ForEach(NodeType.allCases, id: \.self) { t in
                        HStack(spacing: 6) {
                            Circle().fill(Self.color(for: t)).frame(width: 10, height: 10)
                            Text(t.rawValue).font(.callout)
                        }
                    }
                    Spacer()
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
    }

    // MARK: - Loading

    @State private var notesCache: [Note] = []

    private func reload() async {
        guard let root = settings.vaultPath else { return }
        loading = true
        defer { loading = false }
        let store = VaultStore(vault: Vault(root: root))
        let notes = (try? await store.allNotes()) ?? []
        notesCache = notes
        data = GraphLayout.compute(notes: notes, canvasSize: canvasSize)
    }

    private func node(id: String) -> GraphNode? {
        data.nodes.first(where: { $0.id == id })
    }

    private func hitTest(_ loc: CGPoint) -> GraphNode? {
        let nearest = data.nodes.min { a, b in
            Self.dist(a.position, loc) < Self.dist(b.position, loc)
        }
        guard let n = nearest, Self.dist(n.position, loc) < 12 else { return nil }
        return n
    }

    private static func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
    }

    // MARK: - Palette

    /// Hand-picked palette: 16 colours that survive being printed as small
    /// dots next to each other on a default macOS window background.
    private static func color(for type: NodeType) -> Color {
        switch type {
        case .pillar:    return Color(red: 0.30, green: 0.55, blue: 0.85)   // blue
        case .decision:  return Color(red: 0.85, green: 0.40, blue: 0.30)   // brick
        case .concept:   return Color(red: 0.50, green: 0.35, blue: 0.80)   // violet
        case .question:  return Color(red: 0.95, green: 0.65, blue: 0.20)   // amber
        case .playbook:  return Color(red: 0.20, green: 0.70, blue: 0.55)   // teal
        case .task:      return Color(red: 0.85, green: 0.55, blue: 0.85)   // pink
        case .event:     return Color(red: 0.55, green: 0.75, blue: 0.30)   // olive
        case .pattern:   return Color(red: 0.70, green: 0.45, blue: 0.20)   // ochre
        case .hypothesis:return Color(red: 0.30, green: 0.65, blue: 0.85)   // sky
        case .fact:      return Color(red: 0.25, green: 0.65, blue: 0.35)   // green
        case .source:    return Color(red: 0.45, green: 0.45, blue: 0.55)   // slate
        case .bookmark:  return Color(red: 0.95, green: 0.45, blue: 0.55)   // coral
        case .note:      return Color(red: 0.60, green: 0.60, blue: 0.60)   // grey
        case .contact:   return Color(red: 0.90, green: 0.75, blue: 0.40)   // gold
        case .reference: return Color(red: 0.40, green: 0.40, blue: 0.70)   // indigo
        case .custom:    return Color(red: 0.80, green: 0.30, blue: 0.55)   // magenta
        }
    }
}
