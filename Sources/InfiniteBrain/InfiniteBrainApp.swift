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
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowStyle(.titleBar)
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            TabView {
                IngestView()
                    .tabItem { Label("Ingest", systemImage: "tray.and.arrow.down") }
                VaultBrowser()
                    .tabItem { Label("Vault", systemImage: "books.vertical") }
                GraphView()
                    .tabItem { Label("Graph", systemImage: "circle.hexagongrid") }
                QueryView()
                    .tabItem { Label("Query", systemImage: "magnifyingglass") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            Divider()
            StatusBar()
        }
    }
}

/// Always-visible bottom status row: vault folder, active LLM provider, ready state.
struct StatusBar: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            if let vault = settings.vaultPath {
                Label(vault.lastPathComponent, systemImage: "folder")
                    .lineLimit(1).truncationMode(.middle)
            } else {
                Label("No vault", systemImage: "folder.badge.questionmark")
                    .foregroundStyle(.orange)
            }
            Divider().frame(height: 12)
            Label(settings.provider.displayName, systemImage: "cpu")
            Spacer()
            if settings.isConfigured {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Setup incomplete", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
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
