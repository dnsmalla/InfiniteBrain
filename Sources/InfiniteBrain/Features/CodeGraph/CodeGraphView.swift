import SwiftUI
import InfiniteBrainCore

@MainActor
struct CodeGraphView: View {
    @State private var targetFolder: URL? = CodeGraphView.defaultFolder()
    @State private var status: Status = .idle
    @State private var data: GraphData = .init(nodes: [], edges: [])
    @State private var simulation: GraphSimulation?
    @State private var selected: GraphNode?
    @State private var runTask: Task<Void, Never>?

    private let runner = GraphifyRunner()
    private let store = GraphifyStore()

    enum Status: Equatable {
        case idle
        case running
        case loaded(nodeCount: Int, edgeCount: Int)
        case error(String)
        case binaryMissing
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack {
                if let sim = simulation, !data.nodes.isEmpty {
                    GraphCanvas(
                        data: data,
                        simulation: sim,
                        selected: $selected,
                        onNodeOpen: openNode
                    )
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: loadCachedIfAvailable)
        .onDisappear { runTask?.cancel() }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                pickFolder()
            } label: {
                Label(targetFolder?.lastPathComponent ?? "Choose folder…", systemImage: "folder")
            }
            Button {
                runGraphify()
            } label: {
                Label("Run Graphify", systemImage: "play.fill")
            }
            .disabled(targetFolder == nil || status == .running)

            if status == .running {
                ProgressView().controlSize(.small)
                Button("Cancel") { runTask?.cancel() }
            }

            Spacer()
            statusLabel
        }
        .padding(12)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .idle:                          Text("Ready").foregroundStyle(.secondary)
        case .running:                       Text("Running graphify…").foregroundStyle(.secondary)
        case .loaded(let n, let e):          Text("\(n) nodes · \(e) edges").foregroundStyle(.secondary)
        case .error(let m):                  Text(m).foregroundStyle(.red).lineLimit(2).truncationMode(.tail)
        case .binaryMissing:
            HStack {
                Text("Graphify not installed.").foregroundStyle(.orange)
                Button("Copy install command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(GraphifyRunner.installHint, forType: .string)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No graph yet. Pick a folder and run Graphify.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private static func defaultFolder() -> URL? {
        var cur = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            if FileManager.default.fileExists(atPath: cur.appendingPathComponent("Package.swift").path) {
                return cur
            }
            cur.deleteLastPathComponent()
        }
        if let stored = UserDefaults.standard.url(forKey: "CodeGraph.lastFolder") { return stored }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            targetFolder = url
            UserDefaults.standard.set(url, forKey: "CodeGraph.lastFolder")
        }
    }

    private func runGraphify() {
        guard let target = targetFolder else { return }
        status = .running
        runTask = Task {
            let result = await runner.run(targetFolder: target)
            switch result {
            case .success(let jsonURL):
                defer { try? FileManager.default.removeItem(at: jsonURL) }
                do {
                    let raw = try Data(contentsOf: jsonURL)
                    let parsed = try GraphifyParser.parse(data: raw)
                    try? store.save(graphJSON: raw, for: target,
                                    nodeCount: parsed.nodes.count, edgeCount: parsed.edges.count,
                                    graphifyVersion: GraphifyParser.supportedSchemaVersion)
                    self.selected = nil
                    self.data = laidOut(parsed)
                    self.simulation = GraphSimulation(data: self.data)
                    self.status = .loaded(nodeCount: parsed.nodes.count, edgeCount: parsed.edges.count)
                } catch let GraphifyError.unsupportedSchema(v) {
                    self.status = .error("Unsupported graphify schema v\(v)")
                } catch {
                    self.status = .error("Parse failed: \(error)")
                }
            case .failure(.binaryMissing):
                self.status = .binaryMissing
            case .failure(.runFailed(let code, let tail)):
                self.status = .error("graphify exited \(code): \(tail.suffix(160))")
            case .failure(.noOutput):
                self.status = .error("graphify produced no output.")
            case .failure(.parseFailed(let m)):
                self.status = .error("Parse failed: \(m)")
            case .failure(.unsupportedSchema(let v)):
                self.status = .error("Unsupported schema v\(v)")
            case .failure(.cancelled):
                self.status = .idle
            }
        }
    }

    private func loadCachedIfAvailable() {
        guard let target = targetFolder,
              let raw = store.loadGraphJSON(for: target),
              let parsed = try? GraphifyParser.parse(data: raw) else { return }
        self.selected = nil
        self.data = laidOut(parsed)
        self.simulation = GraphSimulation(data: self.data)
        if let meta = store.lastRun(for: target) {
            self.status = .loaded(nodeCount: meta.nodeCount, edgeCount: meta.edgeCount)
        }
    }

    private func laidOut(_ raw: GraphData) -> GraphData {
        // Reuse GraphLayout by synthesizing minimal Notes so positions cluster by type.
        let notes: [Note] = raw.nodes.map { n in
            Note(id: n.id, type: n.type, title: n.title, summary: n.summary, body: "",
                 edges: [], sources: [], contentHash: "",
                 version: 1, createdAt: Date(), updatedAt: Date())
        }
        let laid = GraphLayout.compute(notes: notes, canvasSize: CGSize(width: 1200, height: 800))
        let metaByID = Dictionary(uniqueKeysWithValues: raw.nodes.map { ($0.id, $0.metadata) })
        let merged = laid.nodes.map { gn in
            GraphNode(id: gn.id, title: gn.title, type: gn.type, summary: gn.summary,
                      position: gn.position, metadata: metaByID[gn.id] ?? nil)
        }
        return GraphData(nodes: merged, edges: raw.edges)
    }

    private func openNode(_ node: GraphNode) {
        guard let urlString = node.metadata?["fileURL"],
              let fileURL = URL(string: urlString),
              let root = targetFolder else { return }
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") || filePath == rootPath else { return }
        NSWorkspace.shared.open(fileURL)
    }
}
