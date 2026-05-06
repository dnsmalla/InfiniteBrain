import Foundation

public protocol LLMClient: Sendable {
    func complete(
        system: String,
        user: String,
        responseSchema: [String: Any]?
    ) async throws -> String
}
