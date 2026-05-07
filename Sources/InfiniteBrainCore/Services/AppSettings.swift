import Foundation
import SharedLLMKit

/// User-facing app configuration: vault folder, LLM provider choice, and
/// Anthropic API key. Vault path + provider live in UserDefaults; the API
/// key lives in the Keychain. Both stores are injectable so tests can
/// substitute fakes.
public final class AppSettings: ObservableObject, @unchecked Sendable {
    private static let vaultPathKey = "vaultPath"
    private static let apiKeyKey = "anthropicAPIKey"
    private static let providerKey = "llmProvider"

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    @Published public private(set) var vaultPathStorage: String?
    @Published public private(set) var providerRaw: String

    public init(defaults: UserDefaults = .standard, keychain: KeychainStore = SystemKeychain()) {
        self.defaults = defaults
        self.keychain = keychain
        self.vaultPathStorage = defaults.string(forKey: Self.vaultPathKey)
        if let saved = defaults.string(forKey: Self.providerKey) {
            self.providerRaw = saved
        } else {
            // First-run default: prefer an installed CLI over Anthropic API,
            // so users with `claude` installed don't have to add an API key
            // before they can do anything.
            self.providerRaw = Self.bestAvailableProvider(keychain: keychain).rawValue
        }
    }

    private static func bestAvailableProvider(keychain: KeychainStore) -> LLMProviderKind {
        // If a key is already in the keychain, default to the cloud API.
        if let key = (try? keychain.get(apiKeyKey)) ?? nil, !key.isEmpty {
            return .anthropic
        }
        // Otherwise pick the first locally-installed CLI, in preference order.
        for kind in [LLMProviderKind.claudeCLI, .codexCLI, .cursorCLI] {
            if LLMClientFactory.isAvailable(kind, apiKey: nil) { return kind }
        }
        return .anthropic
    }

    public var vaultPath: URL? {
        get { vaultPathStorage.map { URL(fileURLWithPath: $0) } }
        set {
            vaultPathStorage = newValue?.path
            if let path = newValue?.path {
                defaults.set(path, forKey: Self.vaultPathKey)
            } else {
                defaults.removeObject(forKey: Self.vaultPathKey)
            }
        }
    }

    public var provider: LLMProviderKind {
        get { LLMProviderKind(rawValue: providerRaw) ?? .anthropic }
        set {
            providerRaw = newValue.rawValue
            defaults.set(newValue.rawValue, forKey: Self.providerKey)
        }
    }

    public func apiKey() throws -> String? {
        try keychain.get(Self.apiKeyKey)
    }

    public func setAPIKey(_ value: String?) throws {
        try keychain.set(value, forKey: Self.apiKeyKey)
    }

    public var isConfigured: Bool {
        guard vaultPath != nil else { return false }
        let key = (try? apiKey()) ?? nil
        return LLMClientFactory.isAvailable(provider, apiKey: key)
    }
}
