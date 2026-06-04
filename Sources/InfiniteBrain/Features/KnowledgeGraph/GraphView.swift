import SwiftUI
import GraphKit
import InfiniteBrainCore

/// Knowledge Graph view — mirrors CodeGraphView's HSplitView layout so the two
/// graphs feel like siblings. Left panel: canvas with toolbar + color legend.
/// Right panel: sources index + selected-node detail (user-resizable via the
/// native split-view divider).
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

    // Display controls — mirrors Code Graph's toggles.
    @State private var showLabels: Bool = false
    @State private var filterKind: CGNodeKind? = nil
    @State private var graphExpanded: Bool = false
    @State private var showDetailPanel: Bool = true

    var body: some View {
        HSplitView {
            canvasPanel
                .frame(minWidth: 400, maxWidth: .infinity)

            if showDetailPanel {
                detailSidebar
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { if graphExpanded { expandedOverlay } }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showDetailPanel.toggle() }
                } label: {
                    Image(systemName: "sidebar.right")
                        .symbolVariant(showDetailPanel ? .fill : .none)
                }
                .help(showDetailPanel ? "Hide Detail Panel" : "Show Detail Panel")
            }
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

    // MARK: - Canvas Panel (left side — toolbar + graph + legend)

    private var canvasPanel: some View {
        VStack(spacing: 0) {
            canvasToolbar
            Divider()
            ZStack {
                Color(NSColor.windowBackgroundColor)
                if cgData.nodes.isEmpty {
                    emptyState
                } else {
                    CodeGraphCanvas(
                        data: cgData,
                        selected: $selected,
                        focusedNode: $focused,
                        showLabels: showLabels,
                        highlightKind: filterKind,
                        onNodeOpen: nil
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var canvasToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.brand)
                Text("Knowledge Graph").font(.callout.weight(.semibold))

                if !fullData.nodes.isEmpty {
                    Divider().frame(height: 14)

                    Toggle(isOn: $showLabels) {
                        Label("Labels", systemImage: showLabels ? "text.bubble.fill" : "text.bubble")
                            .font(.caption)
                    }
                    .toggleStyle(.switch).controlSize(.small)

                    Divider().frame(height: 14)

                    Text("\(cgData.nodes.count) / \(fullData.nodes.count) nodes")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                if !grouping.childrenBySource.isEmpty {
                    Button { expandAll() } label: {
                        Image(systemName: "rectangle.expand.vertical")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Expand all sources")

                    Button { collapseAll() } label: {
                        Image(systemName: "rectangle.compress.vertical")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Collapse all sources")
                }

                Button { Task { await reload() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Reload graph")

                if !cgData.nodes.isEmpty {
                    Button { graphExpanded = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Expand graph to full window")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            // Color legend — clickable kind filters
            if !cgData.nodes.isEmpty {
                Divider()
                colorLegend
                    .padding(.horizontal, 16).padding(.vertical, 6)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    /// Clickable filter legend — tap a kind to highlight; tap again to clear.
    private var colorLegend: some View {
        let presentKinds = Array(Set(fullData.nodes.map(\.kind)))
            .sorted { $0.rawValue < $1.rawValue }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presentKinds, id: \.self) { kind in
                    let isActive = filterKind == kind
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            filterKind = isActive ? nil : kind
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(CGPalette.color(for: kind))
                                .frame(width: 8, height: 8)
                            Text(kind.displayName)
                                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isActive
                                      ? CGPalette.color(for: kind).opacity(0.15)
                                      : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(isActive
                                              ? CGPalette.color(for: kind).opacity(0.4)
                                              : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(isActive ? "Showing only \(kind.displayName) — click to clear" : "Show only \(kind.displayName)")
                }
            }
        }
        .frame(height: 22)
    }

    // MARK: - Detail Sidebar (right side — sources + node detail)

    private var detailSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sources section
            if !grouping.childrenBySource.isEmpty {
                sourcesSection
                Divider()
            }

            // Selected node detail (only when a node is clicked)
            if let s = selected,
               let note = notes.first(where: { $0.id == s.id }) {
                nodeDetail(note: note)
            } else {
                Spacer()
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Sources section

    private var sourcesSection: some View {
        let sources = notes.filter { $0.type == .source }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SOURCES")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(sources.count)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sources, id: \.id) { src in
                        sourceRow(src)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
            .frame(maxHeight: 200)
        }
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
        .padding(.vertical, 3).padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isExpanded ? AppPalette.brand.opacity(0.06) : Color.clear)
        )
    }

    // MARK: - Node detail section

    @ViewBuilder
    private func nodeDetail(note: Note) -> some View {
        let nodeColor = CGPalette.color(for: CGNodeKind.from(note.type.rawValue))
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(nodeColor).frame(width: 10, height: 10)
                Text(note.title)
                    .font(.title3).lineLimit(2)
                Spacer()
            }
            Text(note.type.rawValue.capitalized.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(nodeColor)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(nodeColor.opacity(0.15)))

            Text(note.summary)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)

            if !currentBacklinks.isEmpty {
                Divider()
                Text("BACKLINKS")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(currentBacklinks) { link in
                            Button {
                                selected = cgData.nodes.first { $0.id == link.id }
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(CGPalette.color(for: CGNodeKind.from(link.type.rawValue)))
                                        .frame(width: 7, height: 7)
                                    Text(link.title)
                                        .font(.caption).lineLimit(2)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Expanded overlay

    private var expandedOverlay: some View {
        ZStack(alignment: .topTrailing) {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()
            CodeGraphCanvas(
                data: cgData,
                selected: $selected,
                focusedNode: $focused,
                showLabels: showLabels,
                highlightKind: filterKind,
                onNodeOpen: nil
            )
            Button { graphExpanded = false } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Close (Esc)")
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: graphExpanded)
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
        let canvasSize = CGSize(width: 1200, height: 900)
        let topInitial = CodeGraphLayout.compute(CGData(nodes: topNodes, edges: topEdges),
                                                 canvasSize: canvasSize)
        let settledTop = await Task.detached(priority: .userInitiated) {
            let sim = CGSimulation(data: topInitial)
            sim.settle(maxIterations: 200)
            return sim.appliedData(to: topInitial)
        }.value

        // Centre-normalise: shift all positions so the bounding box is centred
        // at (600, 450). This keeps the auto-fit in CodeGraphCanvas reliable
        // regardless of where the simulation drifted to.
        let xs = settledTop.nodes.map(\.position.x)
        let ys = settledTop.nodes.map(\.position.y)
        let cx = ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2
        let cy = ((ys.min() ?? 0) + (ys.max() ?? 0)) / 2
        let dx = canvasSize.width  / 2 - cx
        let dy = canvasSize.height / 2 - cy
        self.sourcePositions = Dictionary(uniqueKeysWithValues: settledTop.nodes.map {
            ($0.id, CGPoint(x: $0.position.x + dx, y: $0.position.y + dy))
        })

        // Default: all sources expanded so every note is visible.
        self.expandedSources = Set(grouping.childrenBySource.keys)
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
