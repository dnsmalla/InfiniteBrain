import Foundation

/// User-facing LLM backend choice. Persisted in AppSettings, read by the
/// factory at runtime to instantiate the right LLMClient.
public enum LLMProviderKind: String, Codable, Sendable, CaseIterable {
    case anthropic    = "anthropic"
    case claudeCLI    = "claude-cli"
    case codexCLI     = "codex-cli"
    case cursorCLI    = "cursor-cli"

    public var displayName: String {
        switch self {
        case .anthropic: return "Anthropic API"
        case .claudeCLI: return "Claude Code CLI"
        case .codexCLI:  return "Codex CLI"
        case .cursorCLI: return "Cursor CLI"
        }
    }

    public var requiresAPIKey: Bool { self == .anthropic }

    public var executableName: String? {
        switch self {
        case .anthropic: return nil
        case .claudeCLI: return "claude"
        case .codexCLI:  return "codex"
        case .cursorCLI: return "cursor"
        }
    }
}

public enum LLMClientFactory {
    public enum FactoryError: Error, Equatable {
        case missingAPIKey
    }

    public static func make(provider: LLMProviderKind, apiKey: String?, gate: LLMGate = NoOpGate()) throws -> LLMClient {
        switch provider {
        case .anthropic:
            guard let apiKey, !apiKey.isEmpty else { throw FactoryError.missingAPIKey }
            return AnthropicClient(apiKey: apiKey, gate: gate)
        case .claudeCLI: return try ClaudeCLIClient()
        case .codexCLI:  return try CodexCLIClient()
        case .cursorCLI: return try CursorCLIClient()
        }
    }

    /// True iff the provider can be instantiated right now (CLI installed,
    /// API key present, etc.). Used by the GUI to gate the Run button.
    public static func isAvailable(_ provider: LLMProviderKind, apiKey: String?) -> Bool {
        switch provider {
        case .anthropic: return apiKey?.isEmpty == false
        case .claudeCLI, .codexCLI, .cursorCLI:
            guard let name = provider.executableName else { return false }
            return CLILocator.find(name) != nil
        }
    }
}
