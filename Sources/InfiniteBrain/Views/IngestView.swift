import SwiftUI
import InfiniteBrainCore
import UniformTypeIdentifiers

struct IngestView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var ingest: IngestViewModel
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            dropZone
            if !ingest.droppedFiles.isEmpty { fileList }
            controls
            Divider()
            log
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ingest documents")
                .font(.title.bold())
            Text("Drag PDFs, text, or markdown files in. The pipeline atomises, classifies, summarises, and writes Obsidian-compatible notes into your vault.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            VStack(spacing: 8) {
                Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                Text("Drop files here")
                    .font(.headline)
                Text("PDF · Markdown · Plain text")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 170)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
    }

    private var fileList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ingest.droppedFiles, id: \.self) { url in
                    HStack(spacing: 8) {
                        Image(systemName: icon(for: url))
                            .foregroundStyle(.secondary)
                        Text(url.lastPathComponent).font(.callout)
                        Spacer()
                        Text(byteSize(of: url))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .frame(maxHeight: 130)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                ingest.toggle(settings: settings)
            } label: {
                if ingest.isRunning {
                    Label("Stop", systemImage: "stop.fill").frame(minWidth: 80)
                } else {
                    Label("Run", systemImage: "play.fill").frame(minWidth: 80)
                }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(ingest.isRunning ? .red : .accentColor)
            .disabled(!ingest.isRunning && ingest.droppedFiles.isEmpty)

            Button("Clear", role: .destructive) { ingest.clear() }
                .disabled(ingest.isRunning)

            if ingest.isRunning {
                ProgressView().controlSize(.small)
            }
            Spacer()
            if let r = ingest.lastResult {
                ResultPill(result: r)
            }
        }
    }

    private var log: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Activity")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if ingest.log.isEmpty {
                        Text("Run an ingest to see progress here.")
                            .font(.callout).foregroundStyle(.tertiary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(Array(ingest.log.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(.callout, design: .monospaced))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(minHeight: 120)
        }
    }

    // MARK: - Helpers

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                Task { @MainActor in
                    if let url { ingest.add([url]) }
                }
            }
        }
        return true
    }

    private func icon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":          return "doc.fill"
        case "md", "markdown": return "doc.richtext"
        case "txt":          return "doc.plaintext"
        default:             return "doc"
        }
    }

    private func byteSize(of url: URL) -> String {
        let n = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: Int64(n))
    }
}

private struct ResultPill: View {
    let result: IngestResult
    var body: some View {
        HStack(spacing: 8) {
            stat(result.added,       "added",     color: .green)
            stat(result.improved,    "improved",  color: .blue)
            stat(result.skipped,     "skipped",   color: .secondary)
            if result.quarantined > 0 {
                stat(result.quarantined, "quarantined", color: .orange)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(.background.secondary, in: Capsule())
    }
    private func stat(_ n: Int, _ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(n)").bold().foregroundStyle(color)
            Text(label).foregroundStyle(.secondary)
        }
    }
}
