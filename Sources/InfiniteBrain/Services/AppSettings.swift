import Foundation

/// User-facing app configuration: the chosen vault folder and the Anthropic
/// API key. Vault path lives in UserDefaults; the API key lives in the
/// Keychain. Both are injectable so tests can substitute fakes.
public final class AppSettings: ObservableObject, @unchecked Sendable {
    private static let vaultPathKey = "vaultPath"
    private static let apiKeyKey = "anthropicAPIKey"

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    @Published public private(set) var vaultPathStorage: String?

    public init(defaults: UserDefaults = .standard, keychain: KeychainStore = SystemKeychain()) {
        self.defaults = defaults
        self.keychain = keychain
        self.vaultPathStorage = defaults.string(forKey: Self.vaultPathKey)
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

    public func apiKey() throws -> String? {
        try keychain.get(Self.apiKeyKey)
    }

    public func setAPIKey(_ value: String?) throws {
        try keychain.set(value, forKey: Self.apiKeyKey)
    }

    public var isConfigured: Bool {
        guard vaultPath != nil else { return false }
        return ((try? apiKey()) ?? nil)?.isEmpty == false
    }
}
