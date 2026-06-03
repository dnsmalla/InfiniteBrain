import SwiftUI
import GraphKit
import InfiniteBrainCore

/// Knowledge Graph view — uses the same CGData / CodeGraphCanvas / CGSimulation
/// infrastructure as the Code Graph so there is one shared canvas renderer.
/// Vault notes are converted to CGData on load; the underlying notes model
/// (Note, NodeType, VaultStore) is left unchanged.
@MainActor
struct GraphView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var ingest: IngestViewModel

    @State private var cgData:   CGData  = .empty
    @State private var selected: CGNode? = nil
    @State private var focused:  CGNode? = nil
    @State private var loading = false
    @State private var store: VaultStore?
    @State private var notes: [Note] = []
    @State private var currentBacklinks: [Note] = []

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Canvas
            if cgData.nodes.isEmpty {
                emptyState
            } else {
                CodeGraphCanvas(
                    data: cgData,
                    selected: $selected,
                    focusedNode: $focused,
                    showLabels: true,
                    onNodeOpen: nil
                )
            }

            // Toolbar + sidebar overlay
            VStack(alignment: .trailing, spacing: 12) {
                toolbar
                sidebar
            }
            .padding(24)
        }
        .onAppear { Task { await reload() } }
        .onChange(of: ingest.lastResult) { _, _ in Task { await reload() } }
        .onChange(of: selected) { _, new in updateBacklinks(for: new) }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            if loading {
                ProgressView("Loading graph…")
            } else {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 48)).foregroundStyle(.secondary)
                Text("No knowledge graph yet").font(.title3)
                Text("Ingest notes to build the graph.")
                    .font(.body).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 4) {
            Button(action: { Task { await reload() } }) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .help("Reload graph")

            Divider().frame(height: 16)

            Text("\(cgData.nodes.count) Nodes")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(AppPalette.border, lineWidth: 1))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let s = selected,
               let note = notes.first(where: { $0.id == s.id }) {
                // Selected node info
                Text(note.title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)
                Text(note.summary)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)

                if !currentBacklinks.isEmpty {
                    Divider()
                    Text("Backlinks")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(currentBacklinks) { link in
                                Button {
                                    selected = cgData.nodes.first { $0.id == link.id }
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(CGPalette.color(for: CGNodeKind.from(link.type.rawValue)))
                                            .frame(width: 8, height: 8)
                                        Text(link.title).font(.caption).lineLimit(2)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else {
                // Legend
                Text("Knowledge Graph")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                Divider()
                ForEach(CGNodeKind.knowledgeGraphKinds, id: \.self) { kind in
                    HStack {
                        Circle()
                            .fill(CGPalette.color(for: kind))
                            .frame(width: 10, height: 10)
                            .shadow(color: CGPalette.color(for: kind).opacity(0.6), radius: 3)
                        Text(kind.displayName)
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
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
    }

    // MARK: - Data loading

    private func reload() async {
        guard let root = settings.vaultPath else { return }
        loading = true
        defer { loading = false }

        let vault    = Vault(root: root)
        let newStore = VaultStore(vault: vault)
        self.store   = newStore

        guard await newStore.metadataIndex.load() else { return }
        let loaded = (try? await newStore.allNotes()) ?? []
        guard !loaded.isEmpty else { return }
        self.notes = loaded

        // Convert vault Notes → CGData
        let noteIds = Set(loaded.map(\.id))
        let nodes: [CGNode] = loaded.map { n in
            CGNode(id: n.id, title: n.title,
                   kind: CGNodeKind.from(n.type.rawValue),
                   position: .zero)
        }
        let edges: [CGEdge] = loaded.flatMap { n in
            n.edges.compactMap { e -> CGEdge? in
                guard noteIds.contains(e.target) else { return nil }
                return CGEdge(fromId: n.id, toId: e.target, kind: .relatedTo)
            }
        }
        let raw = CGData(nodes: nodes, edges: edges)

        // Circular initial positions then physics settle (same pipeline as Code Graph)
        let initial = CodeGraphLayout.compute(raw, canvasSize: CGSize(width: 1200, height: 900))
        let settled = await Task.detached(priority: .userInitiated) {
            let sim = CGSimulation(data: initial)
            sim.settle(maxIterations: 200)
            return sim.appliedData(to: initial)
        }.value

        self.cgData = settled
        try? await newStore.saveMetadata()
    }

    private func updateBacklinks(for node: CGNode?) {
        guard let s = node, let store = store else {
            currentBacklinks = []; return
        }
        Task {
            let ids = await store.metadataIndex.getBacklinks(for: s.id)
            currentBacklinks = notes.filter { ids.contains($0.id) }
        }
    }
}
