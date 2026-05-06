import Foundation

public struct AnthropicClient: LLMClient {
    public let apiKey: String
    public let model: String

    public init(apiKey: String, model: String = "claude-sonnet-4-6") {
        self.apiKey = apiKey
        self.model = model
    }

    public func complete(
        system: String,
        user: String,
        responseSchema: [String: Any]? = nil
    ) async throws -> String {
        fatalError("not yet implemented")
    }
}
