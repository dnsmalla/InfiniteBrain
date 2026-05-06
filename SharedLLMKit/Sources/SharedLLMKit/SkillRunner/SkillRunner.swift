import Foundation

/// Loads a SKILL.md file, runs it through the configured LLMClient, and
/// validates the output against the declared output schema. Retries once on
/// schema-validation failure with the validation error appended.
public actor SkillRunner {
    public let client: LLMClient
    public let skillsRoot: URL

    public init(client: LLMClient, skillsRoot: URL) {
        self.client = client
        self.skillsRoot = skillsRoot
    }

    public func run(_ skillName: String, input: [String: Any]) async throws -> [String: Any] {
        fatalError("not yet implemented")
    }
}
