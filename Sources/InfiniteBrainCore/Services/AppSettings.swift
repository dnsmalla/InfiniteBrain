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
    private static let concurrencyKey = "concurrency"

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    @Published public private(set) var vaultPathStorage: String?
    @Published public private(set) var providerRaw: String
    @Published public var concurrency: Int

    public init(defaults: UserDefaults = .standard, keychain: KeychainStore = SystemKeychain()) {
        self.defaults = defaults
        self.keychain = keychain
        self.vaultPathStorage = defaults.string(forKey: Self.vaultPathKey)
        if let saved = defaults.string(forKey: Self.providerKey) {
            self.providerRaw = saved
        } else {
            // First-run default: prefer an installed CLI over Anthropic API.
            // We set providerRaw temporarily to satisfy initialization, 
            // then compute bestAvailableProvider after keychain is set.
            self.providerRaw = LLMProviderKind.anthropic.rawValue 
        }

        self.concurrency = defaults.integer(forKey: Self.concurrencyKey)
        if self.concurrency < 1 { self.concurrency = 2 } // Default
        
        // Re-compute best provider if this was first run
        if defaults.string(forKey: Self.providerKey) == nil {
            self.providerRaw = Self.bestAvailableProvider(keychain: keychain).rawValue
        }
    }

    public func saveConcurrency() {
        defaults.set(concurrency, forKey: Self.concurrencyKey)
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
