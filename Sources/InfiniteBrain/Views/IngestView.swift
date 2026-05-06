import SwiftUI
import InfiniteBrainCore
import UniformTypeIdentifiers

struct IngestView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var ingest: IngestViewModel
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ingest")
                .font(.title2.bold())

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundColor(isTargeted ? .accentColor : .secondary)
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 28))
                    Text("Drop PDFs, .md, or .txt files here")
                        .font(.callout)
                    Text("\(ingest.droppedFiles.count) queued")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 140)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)

            if !ingest.droppedFiles.isEmpty {
                ScrollView { fileList }
                    .frame(maxHeight: 120)
            }

            HStack {
                Button("Run") {
                    Task { await ingest.run(settings: settings) }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(ingest.isRunning || ingest.droppedFiles.isEmpty)

                Button("Clear") { ingest.clear() }
                    .disabled(ingest.isRunning)

                if ingest.isRunning {
                    ProgressView().controlSize(.small)
                    Text("Running…").foregroundStyle(.secondary)
                }
                Spacer()
                if let r = ingest.lastResult {
                    Text("added \(r.added) · improved \(r.improved) · skipped \(r.skipped)")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }

            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(ingest.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.body, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ingest.droppedFiles, id: \.self) { url in
                HStack {
                    Image(systemName: "doc")
                    Text(url.lastPathComponent).font(.callout)
                    Spacer()
                }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var pending = providers.count
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                Task { @MainActor in
                    if let url { ingest.add([url]) }
                    pending -= 1
                }
            }
        }
        return true
    }
}
