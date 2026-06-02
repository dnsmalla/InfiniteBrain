import SwiftUI
import AppKit
import InfiniteBrainCore

@MainActor
struct CodeGraphView: View {
    @State private var targetFolder: URL?      = CodeGraphView.defaultFolder()
    @State private var status:       Status    = .idle
    @State private var fullData:     CGData    = .empty
    @State private var displayData:  CGData    = .empty
    @State private var selectedNode: CGNode?
    @State private var runTask:      Task<Void, Never>?
    @State private var showSymbols:  Bool      = false
    @State private var graphExpanded: Bool     = false
    @State private var showControlsPanel: Bool = true
    @State private var showItemsPanel:    Bool = true
    @State private var noteArtifacts: [UAHelpers.CodeArtifact] = []

    private let store = UAStore()

    enum Status: Equatable {
        case idle
        case running
        case loaded(nodeCount: Int, edgeCount: Int)
        case error(String)
    }

    var body: some View {
        HSplitView {
            if showControlsPanel {
                controlsPanel
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
            }
            if showItemsPanel {
                itemsPanel
                    .frame(minWidth: 220, idealWidth: 280, maxWidth: 380)
            }
            canvasPanel
                .frame(minWidth: 360, maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { if graphExpanded { expandedOverlay } }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showControlsPanel.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                        .symbolVariant(showControlsPanel ? .fill : .none)
                }
                .help(showControlsPanel ? "Hide Controls" : "Show Controls")

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showItemsPanel.toggle() }
                } label: {
                    Image(systemName: "sidebar.squares.left")
                        .symbolVariant(showItemsPanel ? .fill : .none)
                }
                .help(showItemsPanel ? "Hide Files" : "Show Files")
            }
        }
        .onAppear(perform: loadCachedIfAvailable)
        .onDisappear { runTask?.cancel() }
        .onChange(of: fullData)    { _, _ in recomputeDisplayData() }
        .onChange(of: showSymbols) { _, _ in recomputeDisplayData() }
    }

    // MARK: - Panel 1: Controls

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("FOLDER")
                    .font(.caption).foregroundStyle(.secondary)

                Button { pickFolder() } label: {
                    HStack {
                        Image(systemName: "folder")
                        Text(targetFolder?.lastPathComponent ?? "Choose folder…")
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                    }
                }
                .buttonStyle(.bordered)

                Divider()

                HStack(spacing: 8) {
                    Button(action: runScan) {
                        Label("Generate Graph", systemImage: "play.fill")
                            .font(.callout)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.brand)
                    .disabled(targetFolder == nil || status == .running)

                    if status == .running {
                        Button("Cancel") { runTask?.cancel() }
                            .buttonStyle(.bordered)
                    }
                }

                statusBlock
            }
            .padding(12)

            Divider()
            Spacer()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var statusBlock: some View {
        switch status {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Scanning…").font(.caption).foregroundStyle(.secondary)
            }
        case .loaded(let n, let e):
            Label("\(n) nodes · \(e) edges", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .error(let m):
            Label(m, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red)
                .lineLimit(3).truncationMode(.tail)
        }
    }

    // MARK: - Panel 2: Generated Notes

    private var itemsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("GENERATED NOTES")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !noteArtifacts.isEmpty {
                    Text("\(noteArtifacts.count) notes")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()

            if noteArtifacts.isEmpty {
                VStack {
                    Spacer()
                    Text("Generate graph to create notes.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: nodeSelectionBinding) {
                    ForEach(noteArtifacts) { artifact in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(CGPalette.color(for: .docPage))
                                .frame(width: 7, height: 7)
                            Text(artifact.fileNode.title)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                        }
                        .tag(artifact.fileNode.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Panel 3: Canvas + Detail

    private var canvasPanel: some View {
        VStack(spacing: 0) {
            canvasToolbar
            Divider()
            ZStack {
                Color(NSColor.windowBackgroundColor)
                if displayData.nodes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("No code graph yet").font(.title3)
                        Text("Pick a folder on the left, then click Generate Graph.")
                            .font(.body).foregroundStyle(.secondary)
                    }
                } else {
                    CodeGraphCanvas(data: displayData,
                                    selected: $selectedNode,
                                    onNodeOpen: openNode)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !displayData.nodes.isEmpty {
                Divider()
                detailPanel
                    .frame(minHeight: 120,
                           idealHeight: selectedNode?.kind == .docPage ? 340 : 180,
                           maxHeight:   selectedNode?.kind == .docPage ? 400 : 200)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var canvasToolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppPalette.brand)
            Text("Code Graph").font(.callout.weight(.semibold))

            if !fullData.nodes.isEmpty {
                Divider().frame(height: 14)
                Toggle(isOn: $showSymbols) {
                    Label("Symbols", systemImage: showSymbols ? "function" : "doc")
                        .font(.caption)
                }
                .toggleStyle(.switch).controlSize(.small)
                Divider().frame(height: 14)
                Text("\(displayData.nodes.count) / \(fullData.nodes.count) nodes")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !displayData.nodes.isEmpty {
                Button { graphExpanded = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Expand graph to full window")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Detail panel

    @ViewBuilder
    private var detailPanel: some View {
        if let node = selectedNode {
            detailContent(for: node)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("Select a node to inspect").font(.title3)
                Text("Click a node in the graph, or a row in the Files panel.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    @ViewBuilder
    private func detailContent(for node: CGNode) -> some View {
        let nodeColor = CGPalette.color(for: node.kind)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(nodeColor).frame(width: 10, height: 10)
                Text(node.title).font(.title3).lineLimit(1).truncationMode(.middle)
                Text(node.kind.displayName.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(nodeColor)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(nodeColor.opacity(0.15)))
                Spacer()
                if node.metadata["fileURL"] != nil {
                    Button("Open") { openNode(node) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            if let source = node.metadata["source_file"] {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10)).foregroundStyle(.secondary.opacity(0.7))
                    Text(source)
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    if let line = node.metadata["line"] {
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    if let lang = node.metadata["language"] {
                        Text(lang).font(.caption)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            // Generated note: show its auto-generated markdown content.
            // Repo .md file: read from disk.
            // Code node: show connectivity summary.
            if node.kind == .docPage {
                let content: String = {
                    if let cached = node.metadata["note_content"] { return cached }
                    if let urlStr = node.metadata["fileURL"],
                       let url = URL(string: urlStr),
                       let text = try? String(contentsOf: url, encoding: .utf8) { return text }
                    return ""
                }()
                if content.isEmpty {
                    Text("No content.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        Text((try? AttributedString(markdown: content)) ?? AttributedString(content))
                            .font(.system(.caption))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text(detailBodyForNode(node))
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func detailBodyForNode(_ node: CGNode) -> String {
        let out = fullData.edges.filter { $0.fromId == node.id }
        let inc = fullData.edges.filter { $0.toId   == node.id }
        var parts: [String] = []
        if !out.isEmpty { parts.append("→ \(out.count) outgoing") }
        if !inc.isEmpty { parts.append("← \(inc.count) incoming") }
        if let lang = node.metadata["language"] { parts.append("lang: \(lang)") }
        if let loc  = node.metadata["loc"]      { parts.append("\(loc) lines") }
        return parts.isEmpty ? "No additional details." : parts.joined(separator: " · ")
    }

    // MARK: - Expanded overlay

    private var expandedOverlay: some View {
        ZStack(alignment: .topTrailing) {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()
            CodeGraphCanvas(data: displayData, selected: $selectedNode, onNodeOpen: openNode)
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

    // MARK: - Bindings

    private var nodeSelectionBinding: Binding<String?> {
        Binding(
            get: { selectedNode?.id },
            set: { newID in
                guard let id = newID,
                      let node = fullData.nodes.first(where: { $0.id == id }) else {
                    selectedNode = nil; return
                }
                if !showSymbols, node.kind == .symbol { showSymbols = true }
                selectedNode = node
            }
        )
    }

    // MARK: - Actions

    private static func defaultFolder() -> URL? {
        if let stored = UserDefaults.standard.url(forKey: "CodeGraph.lastFolder") { return stored }
        var cur = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            if FileManager.default.fileExists(
                atPath: cur.appendingPathComponent("Package.swift").path) { return cur }
            cur.deleteLastPathComponent()
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles          = false
        panel.canChooseDirectories    = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            targetFolder = url
            UserDefaults.standard.set(url, forKey: "CodeGraph.lastFolder")
        }
    }

    private func runScan() {
        guard let target = targetFolder else { return }
        status  = .running
        runTask = Task {
            let scanner = StructureScanner(launcher: SystemProcessLauncher())
            let scan    = await scanner.scan(repoRoot: target)
            if Task.isCancelled { self.status = .idle; return }

            // Build structural code graph (file + symbol + import edges)
            let codeGraph = StructureGraphBuilder.build(scan, repoRoot: target)

            // Generate one .md note per code file; returns nodes + writes to disk
            let noteNodes = CodeNoteWriter.generateNoteNodes(scan: scan, repoRoot: target)
            let docEdges: [CGEdge] = noteNodes.compactMap { note in
                guard let src = note.metadata["source_code_file"] else { return nil }
                return CGEdge(fromId: note.id, toId: "file:\(src)", kind: .documents)
            }

            let combined = CGData(
                nodes: codeGraph.nodes + noteNodes,
                edges: codeGraph.edges + docEdges
            )
            let laid = CodeGraphLayout.compute(
                combined,
                canvasSize: UAHelpers.layoutSize(for: combined.nodes.count))

            self.selectedNode  = nil
            self.fullData      = laid
            self.noteArtifacts = UAHelpers.collectNoteArtifacts(laid)
            self.status        = .loaded(nodeCount: codeGraph.nodes.count,
                                         edgeCount: codeGraph.edges.count)
        }
    }

    private func loadCachedIfAvailable() {
        // Notes are regenerated on each scan run; nothing to restore from cache.
        // Just restore the status label if a prior run exists.
        guard let target = targetFolder,
              let meta = store.lastRun(for: target) else { return }
        self.status = .loaded(nodeCount: meta.nodeCount, edgeCount: meta.edgeCount)
    }

    private func recomputeDisplayData() {
        // Canvas shows only code structure — generated notes live in the panel.
        let showInCanvas: Set<CGNodeKind> = showSymbols
            ? [.file, .module, .classType, .function]
            : [.file, .module]
        // Exclude note nodes (they have source_code_file metadata)
        let kept    = fullData.nodes.filter {
            showInCanvas.contains($0.kind) && $0.metadata["source_code_file"] == nil
        }
        let keptIds = Set(kept.map(\.id))
        let edges   = fullData.edges.filter {
            keptIds.contains($0.fromId) && keptIds.contains($0.toId)
        }
        displayData = CGData(nodes: kept, edges: edges)
    }

    private func openNode(_ node: CGNode) {
        guard let urlString = node.metadata["fileURL"] else { return }

        // Construct a reliable file URL — absoluteString round-trips cleanly on
        // plain paths, but fall back to fileURLWithPath for any edge cases.
        let fileURL: URL
        if urlString.hasPrefix("file://"), let u = URL(string: urlString) {
            fileURL = u
        } else {
            fileURL = URL(fileURLWithPath: urlString)
        }

        // Security: only open files under the selected folder.
        if let root = targetFolder {
            let rootPath = root.standardizedFileURL.path
            let filePath = fileURL.standardizedFileURL.path
            guard filePath.hasPrefix(rootPath + "/") || filePath == rootPath else { return }
        }

        // Reveal + select in Finder — always works immediately.
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    // Minimal Codable type used just for cache metadata serialisation.
    private struct CachedGraph: Codable {
        let nodes: Int
        let edges: Int
    }
}
