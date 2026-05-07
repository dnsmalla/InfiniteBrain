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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                vaultCard
                providerCard
                if settings.provider == .anthropic {
                    apiKeyCard
                }
                Spacer(minLength: 32)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                settings.vaultPath = url
            }
        }
        .onAppear { hydrate() }
    }

    // MARK: - Cards

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings").font(.title.bold())
            Text("Configure your vault and the AI backend that runs every skill call.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var vaultCard: some View {
        Card(title: "Vault", systemImage: "folder") {
            HStack(spacing: 10) {
                if let path = settings.vaultPath?.path {
                    Text(path)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)
                } else {
                    Text("No vault selected")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Choose…") { showingPicker = true }
                    .controlSize(.regular)
            }
            Text("Notes are stored as Obsidian-compatible markdown. The first ingest copies editable skills into the vault sidecar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var providerCard: some View {
        Card(title: "LLM provider", systemImage: "cpu") {
            Picker("Backend", selection: providerBinding) {
                ForEach(LLMProviderKind.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            providerStatus
                .padding(.top, 4)
        }
    }

    private var apiKeyCard: some View {
        Card(title: "Anthropic API key", systemImage: "key") {
            SecureField("sk-ant-…", text: $apiKeyDraft)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
            HStack(spacing: 10) {
                Button("Save key") { saveKey() }
                    .controlSize(.regular)
                    .disabled(apiKeyDraft.isEmpty)
                if apiKeySaved {
                    Label("saved", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
                if let e = apiKeyError {
                    Text(e).foregroundStyle(.red).font(.callout)
                }
            }
            Text("Stored in the macOS Keychain (service: co.infinitebrain.app). Never written to disk.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var providerStatus: some View {
        if settings.provider == .anthropic {
            statusRow(.info, "Cloud Claude — requires an API key below.")
        } else if let exec = settings.provider.executableName,
                  let path = CLILocator.find(exec) {
            statusRow(.ok, "Found `\(exec)` at \(path)")
        } else if let exec = settings.provider.executableName {
            statusRow(.warn, "`\(exec)` not on PATH — install it or pick another provider.")
        }
    }

    private enum StatusKind { case ok, warn, info }
    private func statusRow(_ kind: StatusKind, _ text: String) -> some View {
        HStack(spacing: 6) {
            switch kind {
            case .ok:   Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .warn: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .info: Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Wiring

    private var providerBinding: Binding<LLMProviderKind> {
        Binding(get: { settings.provider }, set: { settings.provider = $0 })
    }

    private func hydrate() {
        do { apiKeyDraft = (try settings.apiKey()) ?? "" }
        catch { apiKeyError = error.localizedDescription }
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

/// Standard rounded card used by the settings panes. Title row at top with an
/// icon, then the supplied content. Uses the system material so it picks up
/// light/dark mode automatically.
struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }
}
