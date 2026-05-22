public struct LLMUsage: Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    
    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public protocol LLMClient: Sendable {
    func complete(
        system: String,
        user: String,
        responseSchema: [String: Any]?,
        onUsage: (@Sendable (LLMUsage) -> Void)?
    ) async throws -> String
}

public extension LLMClient {
    func complete(
        system: String, 
        user: String, 
        responseSchema: [String: Any]? = nil
    ) async throws -> String {
        try await complete(system: system, user: user, responseSchema: responseSchema, onUsage: nil)
    }
}
