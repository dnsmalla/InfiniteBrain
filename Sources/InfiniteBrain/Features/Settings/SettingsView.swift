import SwiftUI
import InfiniteBrainCore
import SharedLLMKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    @State private var apiKeyDraft  = ""
    @State private var apiKeySaved  = false
    @State private var apiKeyError: String?
    @State private var showingPicker = false
    @State private var vaultNoteCount: Int? = nil
    @State private var gitAvailable   = false
    @State private var pythonAvailable = false
    @State private var selectedTab: SettingsTab = .workspace

    enum SettingsTab: String, CaseIterable, Identifiable {
        case workspace, ai, codeGraph, shortcuts, about
        var id: String { rawValue }
        var label: String {
            switch self {
            case .workspace: return "Workspace"
            case .ai:        return "AI"
            case .codeGraph: return "Code Graph"
            case .shortcuts: return "Shortcuts"
            case .about:     return "About"
            }
        }
        var icon: String {
            switch self {
            case .workspace: return "folder.fill"
            case .ai:        return "cpu"
            case .codeGraph: return "chevron.left.forwardslash.chevron.right"
            case .shortcuts: return "keyboard"
            case .about:     return "info.circle.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker at top
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 18, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                            Text(tab.label)
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(selectedTab == tab ? AppPalette.brand : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedTab == tab
                                ? AppPalette.brand.opacity(0.08)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Content
            ScrollView {
                Group {
                    switch selectedTab {
                    case .workspace: workspaceSection
                    case .ai:        aiSection
                    case .codeGraph: codeGraphSection
                    case .shortcuts: shortcutsSection
                    case .about:     aboutSection
                    }
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fileImporter(isPresented: $showingPicker,
                      allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { settings.vaultPath = url }
        }
        .onAppear {
            hydrate()
            checkTools()
            countVaultNotes()
        }
    }

    // MARK: - Workspace

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Workspace", subtitle: "Your vault folder and live indexing status.")

            SettingsCard(title: "Vault", systemImage: "folder.fill") {
                if let vaultURL = settings.vaultPath {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(AppPalette.brand)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vaultURL.lastPathComponent)
                                .font(.callout.weight(.medium))
                            Text(vaultURL.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button("Reveal") {
                            NSWorkspace.shared.open(vaultURL)
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        Button("Change…") { showingPicker = true }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 16) {
                        statusPill(
                            icon: "checkmark.circle.fill",
                            label: vaultNoteCount.map { "\($0) notes" } ?? "Counting…",
                            color: .green
                        )
                        statusPill(
                            icon: settings.isConfigured
                                ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                            label: settings.isConfigured ? "Fully configured" : "AI not configured",
                            color: settings.isConfigured ? .green : .orange
                        )
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("No vault selected")
                            .font(.headline).foregroundStyle(.primary)
                        Text("Your notes are stored as Obsidian-compatible markdown files in a folder you choose.")
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Choose Vault Folder…") { showingPicker = true }
                            .buttonStyle(.borderedProminent)
                            .tint(AppPalette.brand)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                descriptionText("Notes are stored as plain markdown compatible with Obsidian, Logseq, and any text editor. The first ingest copies AI skills into the vault.")
            }
        }
    }

    // MARK: - AI Provider

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("AI Provider", subtitle: "Choose the model that powers every query, ingest, and drafting call.")

            SettingsCard(title: "Backend", systemImage: "cpu") {
                Picker("", selection: providerBinding) {
                    ForEach(LLMProviderKind.allCases, id: \.self) { p in
                        HStack {
                            Image(systemName: p.icon)
                            Text(p.displayName)
                        }.tag(p)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Divider().padding(.vertical, 4)
                providerStatusRow
            }

            if settings.provider == .anthropic {
                SettingsCard(title: "Anthropic API Key", systemImage: "key.fill") {
                    HStack(spacing: 8) {
                        SecureField("sk-ant-api03-…", text: $apiKeyDraft)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") { saveKey() }
                            .buttonStyle(.borderedProminent)
                            .tint(AppPalette.brand)
                            .disabled(apiKeyDraft.isEmpty)
                    }
                    if apiKeySaved {
                        statusPill(icon: "checkmark.seal.fill", label: "Key saved to Keychain", color: .green)
                    }
                    if let e = apiKeyError {
                        statusPill(icon: "xmark.circle.fill", label: e, color: .red)
                    }
                    descriptionText("Stored securely in the macOS Keychain (service: co.infinitebrain.app). Never written to disk or logs.")
                }
            }

            SettingsCard(title: "Pipeline Concurrency", systemImage: "bolt.fill") {
                HStack {
                    Text("Parallel units")
                        .font(.callout)
                    Spacer()
                    Text("\(settings.concurrency)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppPalette.brand)
                        .frame(minWidth: 28)
                    Stepper("", value: $settings.concurrency, in: 1...8)
                        .labelsHidden()
                        .onChange(of: settings.concurrency) { _, _ in settings.saveConcurrency() }
                }
                concurrencyDescription
            }
        }
    }

    @ViewBuilder
    private var providerStatusRow: some View {
        if settings.provider == .anthropic {
            let hasKey = (try? settings.apiKey())?.isEmpty == false
            statusPill(
                icon: hasKey ? "checkmark.circle.fill" : "key.slash.fill",
                label: hasKey ? "API key configured" : "API key required — enter it below",
                color: hasKey ? .green : .orange
            )
        } else if let exec = settings.provider.executableName {
            if let path = CLILocator.find(exec) {
                statusPill(icon: "checkmark.circle.fill",
                           label: "\(exec) found at \(path)", color: .green)
            } else {
                statusPill(icon: "exclamationmark.triangle.fill",
                           label: "\(exec) not found on PATH", color: .orange)
                Text("Install with: `\(settings.provider.installHint ?? "brew install \(exec)")`")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var concurrencyDescription: some View {
        let desc: String = {
            switch settings.concurrency {
            case 1:   return "Sequential — safest for free-tier API keys."
            case 2:   return "2 units — good default for most API tiers."
            case 3,4: return "\(settings.concurrency) units — solid throughput for standard API tiers."
            case 5,6: return "\(settings.concurrency) units — fast, but watch for rate-limit errors."
            default:  return "\(settings.concurrency) units — maximum speed, requires high API tier."
            }
        }()
        descriptionText(desc)
    }

    // MARK: - Code Graph

    private var codeGraphSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Code Graph", subtitle: "Tools used when generating the code graph from a repository.")

            SettingsCard(title: "Scanner Tools", systemImage: "wrench.and.screwdriver.fill") {
                VStack(spacing: 10) {
                    toolRow(name: "git",
                            description: "File enumeration via `git ls-files`. Required.",
                            available: gitAvailable)
                    Divider()
                    toolRow(name: "python3",
                            description: "AST scanner for Python files. Optional.",
                            available: pythonAvailable)
                }
                descriptionText("InfiniteBrain scans repos using git (no npm required). Python AST scanning is optional — Swift, TypeScript, and JavaScript files are handled natively.")
            }

            SettingsCard(title: "Generated Notes", systemImage: "doc.text.fill") {
                if let vault = settings.vaultPath {
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(".code-notes/")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open") {
                            let dir = vault.appendingPathComponent(".code-notes")
                            NSWorkspace.shared.open(dir)
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("Select a vault folder first.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                descriptionText("Notes are written to `<vault>/.code-notes/notes/` as plain markdown. `index.md` summarises the full repo. `graph.json` is machine-readable for LLM context.")
            }
        }
    }

    private func toolRow(name: String, description: String, available: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(available ? .green : .secondary)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.callout.weight(.medium))
                Text(description)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if available {
                Text("Found")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
            } else {
                Text("Not found")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
            }
        }
    }

    // MARK: - Shortcuts

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Keyboard Shortcuts", subtitle: "Learn the shortcuts available throughout the app.")

            SettingsCard(title: "Navigation", systemImage: "keyboard") {
                shortcutGrid([
                    ("⌘1", "Ingest"),
                    ("⌘2", "Vault"),
                    ("⌘3", "Knowledge Graph"),
                    ("⌘4", "Code Graph"),
                    ("⌘5", "Query"),
                    ("⌘6", "Drafting Room"),
                    ("⌘7", "Settings"),
                    ("⌘?", "Open Help"),
                ])
            }

            SettingsCard(title: "Code Graph Canvas", systemImage: "chevron.left.forwardslash.chevron.right") {
                shortcutGrid([
                    ("Single-click", "Select node — shows generated note"),
                    ("Double-click", "Focus mode — dims non-neighbours"),
                    ("Double-click (again)", "Clear focus"),
                    ("Drag node", "Reposition node"),
                    ("Drag canvas", "Pan"),
                    ("Pinch / scroll", "Zoom"),
                    ("Esc (toolbar ×)", "Clear focus"),
                ])
            }
        }
    }

    private func shortcutGrid(_ pairs: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { idx, pair in
                HStack {
                    Text(pair.1)
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(pair.0)
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color(NSColor.controlBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
                        )
                }
                .padding(.vertical, 7)
                if idx < pairs.count - 1 {
                    Divider()
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("About InfiniteBrain", subtitle: "Version info and helpful links.")

            SettingsCard(title: "Version", systemImage: "info.circle.fill") {
                infoRow("Version",    "0.26.0")
                Divider()
                infoRow("Build",      "Swift 5.9 · macOS 14+")
                Divider()
                infoRow("Vault format", "Obsidian-compatible markdown")
                Divider()
                infoRow("LLM",        settings.provider.displayName)
            }

            SettingsCard(title: "Resources", systemImage: "link") {
                VStack(spacing: 8) {
                    linkButton(label: "Open Help Guide", icon: "questionmark.circle",
                               action: { openWindow(id: "help") })
                    Divider()
                    linkButton(label: "View Schema Reference", icon: "doc.text.magnifyingglass",
                               action: { openWindow(id: "help") })
                }
            }

            SettingsCard(title: "License", systemImage: "checkmark.shield.fill") {
                Text("Copyright © 2026 Dinesh Malla. Released under the MIT License.")
                    .font(.callout).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout.weight(.medium))
        }
        .padding(.vertical, 2)
    }

    private func linkButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).foregroundStyle(AppPalette.brand)
                Text(label).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func statusPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color).font(.system(size: 12))
            Text(label).font(.callout).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func descriptionText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Logic

    private var providerBinding: Binding<LLMProviderKind> {
        Binding(get: { settings.provider }, set: { settings.provider = $0 })
    }

    private func hydrate() {
        do { apiKeyDraft = (try settings.apiKey()) ?? "" }
        catch { apiKeyError = error.localizedDescription }
    }

    private func saveKey() {
        apiKeyError = nil
        do {
            try settings.setAPIKey(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
            apiKeySaved = true
        } catch {
            apiKeyError = error.localizedDescription
            apiKeySaved = false
        }
    }

    private func checkTools() {
        func isAvailable(_ name: String) -> Bool {
            if let path = ProcessInfo.processInfo.environment["PATH"] {
                for dir in path.split(separator: ":") {
                    let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
                    if FileManager.default.isExecutableFile(atPath: candidate.path) { return true }
                }
            }
            for p in ["/opt/homebrew/bin/\(name)", "/usr/bin/\(name)", "/usr/local/bin/\(name)"] {
                if FileManager.default.isExecutableFile(atPath: p) { return true }
            }
            return false
        }
        gitAvailable    = isAvailable("git")
        pythonAvailable = isAvailable("python3")
    }

    private func countVaultNotes() {
        guard let vault = settings.vaultPath else { vaultNoteCount = 0; return }
        Task.detached(priority: .background) {
            let count = (try? FileManager.default.contentsOfDirectory(
                at: vault, includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles))
                .map { $0.filter { $0.pathExtension == "md" }.count } ?? 0
            await MainActor.run { vaultNoteCount = count }
        }
    }
}

// MARK: - Settings Card

struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 0.5)
        )
    }
}

// MARK: - LLMProviderKind helpers

private extension LLMProviderKind {
    var icon: String {
        switch self {
        case .anthropic: return "cloud.fill"
        case .claudeCLI: return "terminal.fill"
        case .codexCLI:  return "apple.terminal.fill"
        case .cursorCLI: return "cursorarrow.click.2"
        default:         return "cpu"
        }
    }
    var installHint: String? {
        switch self {
        case .claudeCLI: return "npm install -g @anthropic-ai/claude-code"
        case .codexCLI:  return "npm install -g @openai/codex"
        default:         return nil
        }
    }
}
