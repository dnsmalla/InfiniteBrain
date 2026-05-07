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
                ScrollView {
                    Text(preview)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(20)
                }
            }
        }
        .background(.background.secondary)
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

    private func refresh() {
        guard let root = settings.vaultPath else { notesByType = []; return }
        let notes = root.appendingPathComponent("notes")
        let fm = FileManager.default
        var grouped: [NodeType: [URL]] = [:]
        guard let typeDirs = try? fm.contentsOfDirectory(at: notes, includingPropertiesForKeys: nil) else {
            notesByType = []; return
        }
        for dir in typeDirs {
            guard let type = NodeType(rawValue: dir.lastPathComponent) else { continue }
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            grouped[type] = files.filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        notesByType = NodeType.allCases.compactMap { t in
            guard let files = grouped[t], !files.isEmpty else { return nil }
            return (t, files)
        }
    }
}
