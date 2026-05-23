import SwiftUI
import InfiniteBrainCore

@main
struct InfiniteBrainApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var ingest = IngestViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .navigationTitle("InfiniteBrain v0.26.0")
                .environmentObject(settings)
                .environmentObject(ingest)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .help) {
                HelpMenuButton()
            }
        }

        // Standalone Help window. Opened via Help → InfiniteBrain Help
        // (Cmd-?) or from the Settings tab. Lives outside the main window
        // so the user can keep it open while ingesting.
        WindowGroup("InfiniteBrain Help", id: "help") {
            HelpView()
                .frame(minWidth: 880, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 720)
    }
}

/// SwiftUI doesn't let you put `openWindow` calls inside a CommandGroup
/// builder directly (no environment yet), so we wrap it in a tiny
/// helper view that pulls the action from the environment.
private struct HelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("InfiniteBrain Help") { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
    }
}

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var ingest: IngestViewModel
    
    @State private var selectedTab: Tab? = .ingest
    
    enum Tab: String, CaseIterable, Identifiable {
        case ingest, vault, graph, codeGraph, query, drafting, settings
        var id: String { self.rawValue }

        var label: String {
            switch self {
            case .ingest: return "Ingest"
            case .vault: return "Vault"
            case .graph: return "Knowledge Graph"
            case .codeGraph: return "Code Graph"
            case .query: return "Query"
            case .drafting: return "Drafting Room"
            case .settings: return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .ingest: return "tray.and.arrow.down.fill"
            case .vault: return "books.vertical.fill"
            case .graph: return "circle.hexagongrid.fill"
            case .codeGraph: return "point.3.connected.trianglepath.dotted"
            case .query: return "sparkle.magnifyingglass"
            case .drafting: return "pencil.and.scribble"
            case .settings: return "gearshape.fill"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selectedTab)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            ZStack(alignment: .bottom) {
                Group {
                    if let tab = selectedTab {
                        switch tab {
                        case .ingest: IngestView()
                        case .vault: VaultBrowser()
                        case .graph: GraphView()
                        case .codeGraph: CodeGraphView()
                        case .query: QueryView()
                        case .drafting: DraftingRoom()
                        case .settings: SettingsView()
                        }
                    } else {
                        Text("Select a view from the sidebar")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                StatusBar()
                    .padding(20)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onAppear {
            ingest.startWatcher(settings: settings)
        }
        .onChange(of: settings.vaultPath) { _, newValue in
            ingest.stopWatcher()
            if newValue != nil {
                ingest.startWatcher(settings: settings)
            }
        }
    }
}

private struct Sidebar: View {
    @Binding var selection: ContentView.Tab?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppPalette.brand.gradient)
                        .frame(width: 32, height: 32)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: -2) {
                    Text("Infinite")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Brain")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .opacity(0.6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 32)
            
            // Navigation Links
            VStack(spacing: 4) {
                ForEach(ContentView.Tab.allCases) { tab in
                    SidebarItem(tab: tab, isSelected: selection == tab) {
                        selection = tab
                    }
                }
            }
            .padding(.horizontal, 12)
            
            Spacer()
            
            // Pro Badge / Version
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("v0.26.0")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Capsule())
                    
                    Spacer()
                    
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Live Indexing")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .background(Divider(), alignment: .top)
        }
        .background(.ultraThinMaterial)
    }
}

private struct SidebarItem: View {
    let tab: ContentView.Tab
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16))
                    .frame(width: 24)
                    .foregroundStyle(isSelected ? .white : (isHovered ? AppPalette.brand : .secondary))
                
                Text(tab.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppPalette.brand.gradient)
                        .shadow(color: AppPalette.brand.opacity(0.3), radius: 4, y: 2)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Always-visible bottom status row: vault folder, active LLM provider, ready state.
struct StatusBar: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 16) {
            if let vault = settings.vaultPath {
                Label(vault.lastPathComponent, systemImage: "folder.fill")
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.primary)
            } else {
                Label("No vault", systemImage: "folder.badge.questionmark")
                    .foregroundStyle(.orange)
            }
            Divider().frame(height: 14)
            Label(settings.provider.displayName, systemImage: "cpu")
                .foregroundStyle(.secondary)
            Spacer()
            if settings.isConfigured {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                        .shadow(color: .green.opacity(0.8), radius: 4)
                    Text("Ready")
                        .foregroundStyle(.primary)
                }
            } else {
                Label("Setup incomplete", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.system(.caption, design: .rounded).weight(.medium))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        }
    }
}
