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

    // Hierarchy (source → derived notes) — see KnowledgeGraphHierarchy.
    @State private var fullData: CGData = .empty
    @State private var grouping = KnowledgeGraphHierarchy.Grouping(topLevelIds: [], childrenBySource: [:])
    @State private var sourcePositions: [String: CGPoint] = [:]
    @State private var expandedSources: Set<String> = []
    @State private var hiddenSources: Set<String> = []

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
                if !grouping.childrenBySource.isEmpty { sourcesPanel }
                sidebar
            }
            .padding(24)
        }
        .onAppear { Task { await reload() } }
        .onChange(of: ingest.lastResult) { _, _ in Task { await reload() } }
        .onChange(of: selected) { _, new in
            updateBacklinks(for: new)
            // Clicking a source node toggles its expansion.
            if let id = new?.id, grouping.childrenBySource[id] != nil {
                toggleExpand(id)
            }
        }
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

            if !grouping.childrenBySource.isEmpty {
                Divider().frame(height: 16)
                Button { expandAll() } label: {
                    Image(systemName: "plus.magnifyingglass").frame(width: 32, height: 32)
                }
                .buttonStyle(.plain).help("Expand all sources")
                Button { collapseAll() } label: {
                    Image(systemName: "minus.magnifyingglass").frame(width: 32, height: 32)
                }
                .buttonStyle(.plain).help("Collapse all sources")
            }

            Divider().frame(height: 16)

            Text("\(cgData.nodes.count) / \(fullData.nodes.count) Nodes")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(AppPalette.border, lineWidth: 1))
    }

    // MARK: - Sources panel (index / level control)

    private var sourcesPanel: some View {
        let sources = notes.filter { $0.type == .source }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sources")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                Spacer()
                Text("\(sources.count)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sources, id: \.id) { src in
                        sourceRow(src)
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .padding(16)
        .frame(width: 260)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppPalette.border, lineWidth: 1))
    }

    @ViewBuilder
    private func sourceRow(_ src: Note) -> some View {
        let count = grouping.childrenBySource[src.id]?.count ?? 0
        let isExpanded = expandedSources.contains(src.id)
        let isHidden = hiddenSources.contains(src.id)
        HStack(spacing: 6) {
            Button { toggleExpand(src.id) } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
            .disabled(isHidden || count == 0)

            Circle().fill(CGPalette.color(for: .noteSource)).frame(width: 7, height: 7)

            Text(src.title)
                .font(.system(.caption, design: .rounded))
                .lineLimit(1).truncationMode(.middle)
                .foregroundStyle(isHidden ? .tertiary : .primary)
            Spacer(minLength: 4)
            Text("\(count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Button { toggleHidden(src.id) } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 10))
                    .foregroundStyle(isHidden ? .tertiary : .secondary)
            }
            .buttonStyle(.plain)
            .help(isHidden ? "Show source" : "Hide source")
        }
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
        self.fullData = CGData(nodes: nodes, edges: edges)

        // Build the source → notes grouping.
        let refs = loaded.map { n in
            KnowledgeGraphHierarchy.NoteRef(
                id: n.id, isSource: n.type == .source, sourceId: n.sources.first)
        }
        self.grouping = KnowledgeGraphHierarchy.group(refs)

        // Lay out only the top-level (sources + loose) nodes so the collapsed
        // index spreads cleanly; children bloom around these stable positions.
        let topIds = Set(grouping.topLevelIds)
        let topNodes = nodes.filter { topIds.contains($0.id) }
        let topEdges = edges.filter { topIds.contains($0.fromId) && topIds.contains($0.toId) }
        let topInitial = CodeGraphLayout.compute(CGData(nodes: topNodes, edges: topEdges),
                                                 canvasSize: CGSize(width: 1200, height: 900))
        let settledTop = await Task.detached(priority: .userInitiated) {
            let sim = CGSimulation(data: topInitial)
            sim.settle(maxIterations: 200)
            return sim.appliedData(to: topInitial)
        }.value
        self.sourcePositions = Dictionary(uniqueKeysWithValues: settledTop.nodes.map { ($0.id, $0.position) })

        // Default: everything collapsed (clean index).
        self.expandedSources = []
        self.hiddenSources = []
        recomputeDisplay()
        try? await newStore.saveMetadata()
    }

    // MARK: - Hierarchy display

    private func recomputeDisplay() {
        let sub = KnowledgeGraphHierarchy.visibleSubgraph(
            full: fullData, grouping: grouping,
            expanded: expandedSources, hidden: hiddenSources)

        var positions = sourcePositions
        for src in expandedSources where !hiddenSources.contains(src) {
            let kids = grouping.childrenBySource[src] ?? []
            let center = sourcePositions[src] ?? .zero
            for (id, p) in KnowledgeGraphHierarchy.bloom(childIds: kids, around: center) {
                positions[id] = p
            }
        }

        let placed = sub.nodes.map { node -> CGNode in
            var n = node
            if let p = positions[node.id] { n.position = p }
            return n
        }
        cgData = CGData(nodes: placed, edges: sub.edges)
    }

    private func toggleExpand(_ id: String) {
        if expandedSources.contains(id) { expandedSources.remove(id) }
        else { expandedSources.insert(id) }
        recomputeDisplay()
    }

    private func toggleHidden(_ id: String) {
        if hiddenSources.contains(id) { hiddenSources.remove(id) }
        else { hiddenSources.insert(id) }
        recomputeDisplay()
    }

    private func expandAll() {
        expandedSources = Set(grouping.childrenBySource.keys)
        recomputeDisplay()
    }

    private func collapseAll() {
        expandedSources = []
        recomputeDisplay()
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
