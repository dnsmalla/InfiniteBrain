import SwiftUI
import InfiniteBrainCore

@main
struct InfiniteBrainApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var ingest   = IngestViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(ingest)
                // 700 × 480 works well on a 13" MacBook Air
                .frame(minWidth: 700, minHeight: 480)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .help) { HelpMenuButton() }
        }

        WindowGroup("InfiniteBrain Help", id: "help") {
            HelpView().frame(minWidth: 760, minHeight: 540)
        }
        .defaultSize(width: 900, height: 680)
    }
}

private struct HelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("InfiniteBrain Help") { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
    }
}

// MARK: - App section

enum AppSection: String, Hashable, CaseIterable, Identifiable {
    case ingest, vault, graph, codeGraph, query, drafting, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .ingest:    return "Ingest"
        case .vault:     return "Vault"
        case .graph:     return "Knowledge Graph"
        case .codeGraph: return "Code Graph"
        case .query:     return "Query"
        case .drafting:  return "Drafting Room"
        case .settings:  return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .ingest:    return "tray.and.arrow.down.fill"
        case .vault:     return "books.vertical.fill"
        case .graph:     return "circle.hexagongrid.fill"
        case .codeGraph: return "chevron.left.forwardslash.chevron.right"
        case .query:     return "sparkle.magnifyingglass"
        case .drafting:  return "pencil.and.scribble"
        case .settings:  return "gearshape.fill"
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var ingest:   IngestViewModel
    @State private var selection: AppSection? = .ingest

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
        } detail: {
            ZStack {
                switch selection ?? .ingest {
                case .ingest:    IngestView()
                case .vault:     VaultBrowser()
                case .graph:     GraphView()
                case .codeGraph: CodeGraphView()
                case .query:     QueryView()
                case .drafting:  DraftingRoom()
                case .settings:  SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onAppear { ingest.startWatcher(settings: settings) }
        .onChange(of: settings.vaultPath) { _, new in
            ingest.stopWatcher()
            if new != nil { ingest.startWatcher(settings: settings) }
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Binding var selection: AppSection?
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var ingest:   IngestViewModel

    /// Tracks actual rendered width — below compactThreshold we show icons only.
    @State private var sidebarWidth: CGFloat = 200
    private let compactThreshold: CGFloat = 140
    private var isCompact: Bool { sidebarWidth < compactThreshold }

    var body: some View {
        List(selection: $selection) {
            Section(isCompact ? "" : "Workspace") {
                row(.ingest)
                row(.vault)
            }
            Section(isCompact ? "" : "Graph") {
                row(.graph)
                row(.codeGraph)
            }
            Section(isCompact ? "" : "AI") {
                row(.query)
                row(.drafting)
            }
            Section(isCompact ? "" : "System") {
                row(.settings)
            }
        }
        .listStyle(.sidebar)
        // Measure actual width to trigger compact mode
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { sidebarWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in sidebarWidth = w }
            }
        )
        .safeAreaInset(edge: .top,    spacing: 0) { brandHeader }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer      }
        // Flexible sizing: collapses to icon-only rail at min
        .navigationSplitViewColumnWidth(min: 60, ideal: 210, max: 260)
        // ⌘1–⌘7 keyboard shortcuts
        .overlay(keyboardShortcuts)
    }

    // MARK: Row

    @ViewBuilder
    private func row(_ section: AppSection) -> some View {
        if isCompact {
            Image(systemName: section.icon)
                .font(.system(size: 16))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppPalette.brand)
                .frame(width: 22, height: 22)
                .tag(section)
                .help(section.label)
        } else {
            Label(section.label, systemImage: section.icon)
                .tag(section)
        }
    }

    // MARK: Brand header

    private var brandHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AppPalette.brand.opacity(0.14))
                    .frame(width: 26, height: 26)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppPalette.brand)
            }
            if !isCompact {
                Text("InfiniteBrain")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, isCompact ? 6 : 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .help(isCompact ? "InfiniteBrain" : "")
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                if isCompact {
                    // Compact: just the status dot
                    Circle()
                        .fill(settings.isConfigured ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                        .help(settings.isConfigured ? "Ready" : "Setup incomplete")
                } else {
                    // Full: vault name + provider + status
                    if let vault = settings.vaultPath {
                        Image(systemName: "folder.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(vault.lastPathComponent)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("No vault")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 4)
                    Circle()
                        .fill(settings.isConfigured ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                        .shadow(color: settings.isConfigured
                                ? .green.opacity(0.6) : .orange.opacity(0.6),
                                radius: 3)
                    Text(settings.isConfigured ? "Ready" : "Setup")
                        .font(.caption2)
                        .foregroundStyle(settings.isConfigured ? Color.primary : Color.orange)
                }
            }
            .padding(.horizontal, isCompact ? 0 : 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
        .background(.bar)
    }

    // MARK: Keyboard shortcuts (invisible)

    private var keyboardShortcuts: some View {
        let sections = AppSection.allCases
        return ZStack {
            ForEach(Array(sections.enumerated()), id: \.element) { idx, section in
                Button("") { selection = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")),
                                      modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
        }
    }
}
