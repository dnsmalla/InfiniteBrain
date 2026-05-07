import SwiftUI
import InfiniteBrainCore

@main
struct InfiniteBrainApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var ingest = IngestViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(ingest)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}

enum AppSection: String, Hashable, CaseIterable, Identifiable {
    case ingest, vault, graph, query, settings
    var id: Self { self }

    var label: String {
        switch self {
        case .ingest:   return "Ingest"
        case .vault:    return "Vault"
        case .graph:    return "Graph"
        case .query:    return "Query"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .ingest:   return "tray.and.arrow.down.fill"
        case .vault:    return "books.vertical.fill"
        case .graph:    return "circle.hexagongrid.fill"
        case .query:    return "sparkles.rectangle.stack.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var section: AppSection? = .ingest

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            ZStack(alignment: .bottom) {
                detail
                StatusBar()
            }
            .navigationTitle(section?.label ?? "")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text("InfiniteBrain")
                        .font(.headline)
                    Text("v\(Self.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)

            List(selection: $section) {
                ForEach(AppSection.allCases) { s in
                    Label(s.label, systemImage: s.systemImage)
                        .tag(s as AppSection?)
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch section ?? .ingest {
        case .ingest:   IngestView()
        case .vault:    VaultBrowser()
        case .graph:    GraphView()
        case .query:    QueryView()
        case .settings: SettingsView()
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

/// Always-visible status row at the bottom of the detail pane: vault folder,
/// provider, and a quick configured/not state. Mirrors the bottom-status
/// pattern used by professional macOS apps (Xcode, Mail, Notes).
struct StatusBar: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 14) {
            if let vault = settings.vaultPath {
                Label(vault.lastPathComponent, systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Label("No vault", systemImage: "folder.badge.questionmark")
                    .foregroundStyle(.orange)
            }
            Divider().frame(height: 12)
            Label(settings.provider.displayName, systemImage: "cpu")
            Spacer()
            if !settings.isConfigured {
                Label("Setup incomplete", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }
}
