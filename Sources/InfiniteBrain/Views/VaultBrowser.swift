import SwiftUI
import InfiniteBrainCore

struct VaultBrowser: View {
    @EnvironmentObject var settings: AppSettings
    @State private var notesByType: [(type: NodeType, files: [URL])] = []
    @State private var selectedFile: URL?
    @State private var preview: String = ""

    var body: some View {
        HSplitView {
            List(selection: $selectedFile) {
                ForEach(notesByType, id: \.type) { group in
                    Section(group.type.rawValue.capitalized) {
                        ForEach(group.files, id: \.self) { url in
                            HStack(spacing: 4) {
                                if Self.fileNeedsReview(url) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.yellow)
                                        .help("Low confidence — review and re-classify")
                                }
                                Text(displayName(url))
                            }
                            .tag(url as URL?)
                        }
                    }
                }
            }
            .frame(minWidth: 280)

            ScrollView {
                Text(preview)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: selectedFile) { _, new in
            if let new { preview = (try? String(contentsOf: new, encoding: .utf8)) ?? "" }
        }
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
        }
    }

    private static func fileNeedsReview(_ url: URL) -> Bool {
        // Cheap scan of the frontmatter for the `needs_review: true` line.
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
