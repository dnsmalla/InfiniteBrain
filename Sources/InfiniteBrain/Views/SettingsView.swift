import SwiftUI
import InfiniteBrainCore
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var apiKeyDraft: String = ""
    @State private var apiKeySaved: Bool = false
    @State private var showingPicker = false
    @State private var apiKeyError: String?

    var body: some View {
        Form {
            Section("Vault") {
                HStack {
                    Text(settings.vaultPath?.path ?? "(none chosen)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(settings.vaultPath == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { showingPicker = true }
                }
                Text("Notes will be written into this folder as Obsidian-compatible markdown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Anthropic API") {
                SecureField("sk-ant-…", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save key") { saveKey() }
                        .disabled(apiKeyDraft.isEmpty)
                    if apiKeySaved {
                        Text("✓ saved").foregroundStyle(.secondary)
                    }
                    if let e = apiKeyError {
                        Text(e).foregroundStyle(.red)
                    }
                }
                Text("Stored in the macOS Keychain (service: co.infinitebrain.app).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                settings.vaultPath = url
            }
        }
        .onAppear { hydrate() }
    }

    private func hydrate() {
        do {
            apiKeyDraft = (try settings.apiKey()) ?? ""
        } catch {
            apiKeyError = error.localizedDescription
        }
    }

    private func saveKey() {
        do {
            try settings.setAPIKey(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
            apiKeySaved = true
            apiKeyError = nil
        } catch {
            apiKeyError = error.localizedDescription
            apiKeySaved = false
        }
    }
}
