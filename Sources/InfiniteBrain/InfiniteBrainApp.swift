import SwiftUI

@main
struct InfiniteBrainApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.titleBar)
    }
}

struct ContentView: View {
    var body: some View {
        Text("InfiniteBrain — scaffold")
            .font(.title2)
            .padding()
    }
}
