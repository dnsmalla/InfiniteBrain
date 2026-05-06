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
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        TabView {
            IngestView()
                .tabItem { Label("Ingest", systemImage: "tray.and.arrow.down") }
            VaultBrowser()
                .tabItem { Label("Vault", systemImage: "books.vertical") }
            QueryView()
                .tabItem { Label("Query", systemImage: "magnifyingglass") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .padding()
    }
}
