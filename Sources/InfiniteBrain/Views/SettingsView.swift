import SwiftUI
import InfiniteBrainCore
import SharedLLMKit
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

            Section("LLM provider") {
                Picker("Backend", selection: providerBinding) {
                    ForEach(LLMProviderKind.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.menu)
                providerStatus
            }

            if settings.provider == .anthropic {
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

    private var providerBinding: Binding<LLMProviderKind> {
        Binding(
            get: { settings.provider },
            set: { settings.provider = $0 }
        )
    }

    @ViewBuilder
    private var providerStatus: some View {
        if settings.provider == .anthropic {
            Text("Cloud Claude via the Anthropic API. Requires an API key below.")
                .font(.caption).foregroundStyle(.secondary)
        } else if let exec = settings.provider.executableName,
                  let path = CLILocator.find(exec) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Found `\(exec)` at \(path)")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        } else if let exec = settings.provider.executableName {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("`\(exec)` not found on PATH — install it or pick another provider.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
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
