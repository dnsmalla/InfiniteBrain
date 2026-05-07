import SwiftUI
import InfiniteBrainCore

struct VaultBrowser: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var ingest: IngestViewModel
    @State private var notesByType: [(type: NodeType, files: [URL])] = []
    @State private var selectedFile: URL?
    @State private var preview: String = ""
    @State private var query: String = ""

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 280, idealWidth: 320)
            previewPane
                .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                TextField("Filter…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: ingest.lastResult) { _, _ in refresh() }
        .onChange(of: selectedFile) { _, new in
            if let new { preview = (try? String(contentsOf: new, encoding: .utf8)) ?? "" }
        }
    }

    // MARK: - Sections

    private var list: some View {
        Group {
            if filtered.isEmpty {
                emptyState
            } else {
                List(selection: $selectedFile) {
                    ForEach(filtered, id: \.type) { group in
                        Section {
                            ForEach(group.files, id: \.self) { url in
                                row(for: url)
                                    .tag(url as URL?)
                            }
                        } header: {
                            HStack {
                                Text(group.type.rawValue.capitalized)
                                    .font(.caption.smallCaps())
                                Spacer()
                                Text("\(group.files.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private func row(for url: URL) -> some View {
        HStack(spacing: 6) {
            if Self.fileNeedsReview(url) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("Low confidence — review and re-classify")
            }
            Text(displayName(url))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var previewPane: some View {
        Group {
            if selectedFile == nil {
                VStack(spacing: 6) {
                    Image(systemName: "doc.text").font(.system(size: 32, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Select a note to preview").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if let url = selectedFile, let breadcrumb = Self.sourceBreadcrumb(for: url) {
                        HStack(spacing: 6) {
                            Image(systemName: "books.vertical")
                                .foregroundStyle(.tertiary)
                            Text("from")
                                .foregroundStyle(.tertiary)
                            Text(breadcrumb)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial)
                        Divider()
                    }
                    ScrollView {
                        Text(preview)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(20)
                    }
                }
            }
        }
        .background(.background.secondary)
    }

    /// Pulls the source folder name from a note's path and humanises it.
    /// Returns nil for notes in the legacy `notes/<type>/*.md` layout.
    private static func sourceBreadcrumb(for url: URL) -> String? {
        let parts = url.pathComponents
        guard let notesIdx = parts.firstIndex(of: "notes"),
              notesIdx + 2 < parts.count else { return nil }
        let folder = parts[notesIdx + 1]
        // Skip if the immediate child of notes/ is a NodeType (legacy layout).
        if NodeType(rawValue: folder) != nil { return nil }
        return folder
            .replacingOccurrences(of: "-pdf", with: ".pdf")
            .replacingOccurrences(of: "-", with: " ")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical").font(.largeTitle).foregroundStyle(.tertiary)
            Text(settings.vaultPath == nil ? "Choose a vault folder in Settings" : "Vault is empty — try ingesting a file")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var filtered: [(type: NodeType, files: [URL])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return notesByType }
        return notesByType.compactMap { group in
            let matches = group.files.filter { displayName($0).lowercased().contains(q) }
            return matches.isEmpty ? nil : (group.type, matches)
        }
    }

    private static func fileNeedsReview(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 4096)) ?? Data()
        let head = String(data: data, encoding: .utf8) ?? ""
        return head.contains("needs_review: true")
    }

    private func displayName(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        if let dashes = name.range(of: "--") {
            return String(name[dashes.upperBound...]).replacingOccurrences(of: "-", with: " ")
        }
        return name
    }

    /// Walks both layouts:
    ///   • per-source: `notes/<source-slug>/<type>/<id>--<slug>.md`
    ///   • legacy:     `notes/<type>/<id>--<slug>.md`
    /// and groups every found note by its NodeType.
    private func refresh() {
        guard let root = settings.vaultPath else { notesByType = []; return }
        let notes = root.appendingPathComponent("notes")
        let fm = FileManager.default
        var grouped: [NodeType: [URL]] = [:]

        guard let topLevel = try? fm.contentsOfDirectory(at: notes, includingPropertiesForKeys: [.isDirectoryKey]) else {
            notesByType = []; return
        }
        for dir in topLevel {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if let type = NodeType(rawValue: dir.lastPathComponent) {
                // Legacy: `notes/<type>/*.md`
                addMarkdownFiles(in: dir, to: &grouped, as: type)
            } else {
                // Per-source: `notes/<source-slug>/<type>/*.md`
                let typeDirs = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
                for typeDir in typeDirs {
                    guard let type = NodeType(rawValue: typeDir.lastPathComponent) else { continue }
                    addMarkdownFiles(in: typeDir, to: &grouped, as: type)
                }
            }
        }
        notesByType = NodeType.allCases.compactMap { t in
            guard let files = grouped[t], !files.isEmpty else { return nil }
            return (t, files.sorted { $0.lastPathComponent < $1.lastPathComponent })
        }
    }

    private func addMarkdownFiles(in dir: URL, to grouped: inout [NodeType: [URL]], as type: NodeType) {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let mds = files.filter { $0.pathExtension == "md" }
        if mds.isEmpty { return }
        grouped[type, default: []].append(contentsOf: mds)
    }
}
