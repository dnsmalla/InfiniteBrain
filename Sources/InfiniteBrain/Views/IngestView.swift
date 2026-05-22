import SwiftUI
import InfiniteBrainCore
import UniformTypeIdentifiers

struct IngestView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var ingest: IngestViewModel
    @State private var isTargeted = false
    @State private var showingWipeConfirm = false
    @State private var showingUsageDetails = false

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
        VStack(alignment: .leading, spacing: 8) {
            Text("Ingest Knowledge")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            
            Text("Transform documents into atomic research notes using semantic analysis.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var dropZone: some View {
        ZStack {
            if isTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppPalette.brand.opacity(0.1))
                    .shadow(color: AppPalette.brand.opacity(0.2), radius: 15, y: 5)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
            }
            
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [6]))
                .foregroundStyle(isTargeted ? AppPalette.brand : Color.primary.opacity(0.1))
            
            VStack(spacing: 12) {
                Image(systemName: isTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                    .symbolEffect(.bounce, value: isTargeted)
                
                Text(isTargeted ? "Drop to Ingest" : "Drag files here")
                    .font(.system(.headline, design: .rounded))
                Text("PDF · EPUB · Markdown · Text")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 180)
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
            .tint(ingest.isRunning ? .red : AppPalette.brand)
            .disabled(!ingest.isRunning && ingest.droppedFiles.isEmpty)

            Button {
                showingWipeConfirm = true
            } label: {
                Label("Re-ingest", systemImage: "arrow.counterclockwise.circle")
            }
            .help("Delete all notes and the checkpoint for the dropped file(s), then re-run.")
            .disabled(ingest.isRunning || ingest.droppedFiles.isEmpty)

            Button("Clear", role: .destructive) { ingest.clear() }
                .disabled(ingest.isRunning)

            if ingest.isRunning {
                ProgressView().controlSize(.small)
            }
            Spacer()
            if let r = ingest.lastResult {
                ResultPill(result: r)
                if ingest.usageSummary != nil {
                    Button {
                        showingUsageDetails = true
                    } label: {
                        Image(systemName: "chart.bar.doc.horizontal")
                    }
                    .buttonStyle(.bordered)
                    .help("View cost and token usage")
                }
            }
        }
        .sheet(isPresented: $showingUsageDetails) {
            UsageDetailsView(summary: ingest.usageSummary)
                .frame(minWidth: 400, minHeight: 300)
        }
        .confirmationDialog(
            "Re-ingest will delete all notes and the checkpoint for the dropped file(s), then run from scratch.",
            isPresented: $showingWipeConfirm,
            titleVisibility: .visible
        ) {
            Button("Wipe and re-ingest", role: .destructive) {
                Task {
                    await ingest.wipePrevious(settings: settings)
                    ingest.toggle(settings: settings)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var log: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activity Log")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if ingest.log.isEmpty {
                        Text("Awaiting input...")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(Array(ingest.log.enumerated()), id: \.offset) { _, line in
                            LogRow(text: line)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .frame(minHeight: 140)
            .background(AppPalette.surface.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppPalette.border, lineWidth: 1)
            )
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
            BadgeView("\(result.added) added", color: .green)
            BadgeView("\(result.improved) improved", color: .blue)
            BadgeView("\(result.skipped) skipped", color: .secondary)
            if result.quarantined > 0 {
                BadgeView("\(result.quarantined) quarantined", color: .orange)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(.ultraThinMaterial))
    }
}

private struct LogRow: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 10, weight: .bold))
                .padding(.top, 4)
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.9))
        }
    }
    
    private var icon: String {
        if text.contains("→") { return "arrow.right.circle.fill" }
        if text.contains("✅") || text.contains("done") { return "checkmark.circle.fill" }
        if text.contains("⚠️") || text.contains("error") { return "exclamationmark.triangle.fill" }
        if text.contains("⏹") { return "stop.circle.fill" }
        return "circle.fill"
    }
    
    private var color: Color {
        if text.contains("error") { return .red }
        if text.contains("→") { return .accentColor }
        if text.contains("✅") || text.contains("done") { return .green }
        return .secondary.opacity(0.5)
    }
}

private struct UsageDetailsView: View {
    let summary: UsageSummary?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let s = summary {
                    HStack(spacing: 30) {
                        stat("Cost", "$\(String(format: "%.4f", s.totalCost))", color: .green)
                        stat("Tokens", "\(s.totalTokens)", color: .blue)
                        stat("API Calls", "\(s.totalCalls)", color: .orange)
                    }
                    .padding()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Breakdown").font(.headline)
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                            GridRow {
                                Text("Metric")
                                Text("Value").gridColumnAlignment(.trailing)
                            }
                            .font(.caption.bold()).foregroundStyle(.secondary)
                            
                            Divider()
                            
                            GridRow { Text("Input Tokens"); Text("\(s.inputTokens)") }
                            GridRow { Text("Output Tokens"); Text("\(s.outputTokens)") }
                        }
                    }
                    .padding()
                } else {
                    Text("No usage data available").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Ingest Telemetry")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
    
    private func stat(_ label: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).foregroundStyle(color)
        }
    }
}
