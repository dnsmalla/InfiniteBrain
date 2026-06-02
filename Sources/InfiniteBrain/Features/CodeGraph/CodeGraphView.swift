import SwiftUI
import AppKit
import InfiniteBrainCore

@MainActor
struct CodeGraphView: View {
    @State private var targetFolder: URL?       = CodeGraphView.defaultFolder()
    @State private var status:       Status     = .idle
    @State private var fullData:     CGData     = .empty
    @State private var displayData:  CGData     = .empty
    @State private var selectedNode: CGNode?
    @State private var runTask:      Task<Void, Never>?
    @State private var showSymbols:  Bool       = false
    @State private var graphExpanded: Bool      = false
    @State private var showControlsPanel: Bool  = true
    @State private var showItemsPanel:    Bool  = true
    @State private var codeArtifacts: [UAHelpers.CodeArtifact] = []

    private let runner = UARunner()
    private let store  = UAStore()

    enum Status: Equatable {
        case idle
        case running
        case loaded(nodeCount: Int, edgeCount: Int)
        case error(String)
        case binaryMissing
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
                    Button(action: runUA) {
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
                Text("Generating graph…").font(.caption).foregroundStyle(.secondary)
            }
        case .loaded(let n, let e):
            Label("\(n) nodes · \(e) edges", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .error(let m):
            Label(m, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red)
                .lineLimit(3).truncationMode(.tail)
        case .binaryMissing:
            VStack(alignment: .leading, spacing: 6) {
                Label("understand-anything not found",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                Text(UARunner.installHint)
                    .font(.caption).foregroundStyle(.secondary)
                Button("Copy install command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(UARunner.installHint, forType: .string)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    // MARK: - Panel 2: Files & Symbols

    private var itemsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("FILES & SYMBOLS")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !codeArtifacts.isEmpty {
                    Text("\(codeArtifacts.count) files")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()

            if codeArtifacts.isEmpty {
                VStack {
                    Spacer()
                    Text("Generate graph to populate.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: nodeSelectionBinding) {
                    ForEach(codeArtifacts) { artifact in
                        Section {
                            ForEach(artifact.symbols) { sym in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(CGPalette.color(for: sym.node.kind))
                                        .frame(width: 7, height: 7)
                                    Text(sym.node.title)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    if let line = sym.node.metadata["line"] {
                                        Text(line)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary.opacity(0.7))
                                    }
                                }
                                .tag(sym.node.id)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(artifact.fileNode.title)
                                    .font(.callout.weight(.semibold))
                                    .tag(artifact.fileNode.id)
                            }
                        }
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
                    .frame(minHeight: 120, idealHeight: 180, maxHeight: 200)
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
            Text(detailBodyForNode(node))
                .font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func detailBodyForNode(_ node: CGNode) -> String {
        let outgoing = fullData.edges.filter { $0.fromId == node.id }
        let incoming = fullData.edges.filter { $0.toId   == node.id }
        var parts: [String] = []
        if !outgoing.isEmpty { parts.append("→ \(outgoing.count) outgoing") }
        if !incoming.isEmpty { parts.append("← \(incoming.count) incoming") }
        if let kind    = node.metadata["ua_type"]  { parts.append("kind: \(kind)") }
        if let summary = node.metadata["summary"]  { parts.append(summary) }
        if let tags    = node.metadata["tags"]     { parts.append("tags: \(tags)") }
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

    private func runUA() {
        guard let target = targetFolder else { return }
        status  = .running
        runTask = Task {
            let result = await runner.run(targetFolder: target)
            switch result {
            case .success(let jsonURL):
                defer { try? FileManager.default.removeItem(at: jsonURL) }
                do {
                    let raw    = try Data(contentsOf: jsonURL)
                    let parsed = try UAParser.parse(data: raw, repoRoot: target)
                    try? store.save(graphJSON: raw, for: target,
                                    nodeCount: parsed.nodes.count,
                                    edgeCount: parsed.edges.count,
                                    toolVersion: "1.0.0")
                    let laid = CodeGraphLayout.compute(
                        parsed,
                        canvasSize: UAHelpers.layoutSize(for: parsed.nodes.count))
                    self.selectedNode  = nil
                    self.fullData      = laid
                    self.codeArtifacts = UAHelpers.collectCodeArtifacts(laid)
                    self.status        = .loaded(nodeCount: parsed.nodes.count,
                                                 edgeCount: parsed.edges.count)
                } catch let UAError.parseFailed(msg) {
                    self.status = .error("Parse failed: \(msg)")
                } catch {
                    self.status = .error("Parse failed: \(error)")
                }
            case .failure(.binaryMissing):
                self.status = .binaryMissing
            case .failure(.runFailed(let code, let tail)):
                self.status = .error("understand-anything exited \(code): \(tail.suffix(160))")
            case .failure(.noOutput):
                self.status = .error("understand-anything produced no output.")
            case .failure(.parseFailed(let m)):
                self.status = .error("Parse failed: \(m)")
            case .failure(.unsupportedSchema(let v)):
                self.status = .error("Unsupported schema v\(v)")
            case .failure(.nodeVersionTooOld(let v)):
                self.status = .error("Node.js too old: \(v)")
            case .failure(.folderNotWritable(let p)):
                self.status = .error("Folder not writable: \(p)")
            case .failure(.cancelled):
                self.status = .idle
            }
        }
    }

    private func loadCachedIfAvailable() {
        guard let target = targetFolder,
              let raw    = store.loadGraphJSON(for: target),
              let parsed = try? UAParser.parse(data: raw, repoRoot: target) else { return }
        let laid = CodeGraphLayout.compute(
            parsed,
            canvasSize: UAHelpers.layoutSize(for: parsed.nodes.count))
        self.selectedNode  = nil
        self.fullData      = laid
        self.codeArtifacts = UAHelpers.collectCodeArtifacts(laid)
        if let meta = store.lastRun(for: target) {
            self.status = .loaded(nodeCount: meta.nodeCount, edgeCount: meta.edgeCount)
        }
    }

    private func recomputeDisplayData() {
        if showSymbols {
            displayData = fullData
            return
        }
        let filesOnly: Set<CGNodeKind> = [.file, .module, .docPage]
        let kept    = fullData.nodes.filter { filesOnly.contains($0.kind) }
        let keptIds = Set(kept.map(\.id))
        let edges   = fullData.edges.filter {
            keptIds.contains($0.fromId) && keptIds.contains($0.toId) }
        displayData = CGData(nodes: kept, edges: edges)
    }

    private func openNode(_ node: CGNode) {
        guard let urlString = node.metadata["fileURL"],
              let fileURL   = URL(string: urlString),
              let root      = targetFolder else { return }
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") || filePath == rootPath else { return }
        NSWorkspace.shared.open(fileURL)
    }
}
