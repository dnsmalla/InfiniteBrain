import Foundation

/// Parsed representation of a SKILL.md file. The frontmatter declares the
/// skill's name, description, model, and input/output schemas; the body is the
/// system prompt.
public struct Skill: Sendable {
    public struct Manifest: Codable, Sendable {
        public let name: String
        public let description: String
        public let model: String?
        public let inputs: [String: String]?      // field → JSON-schema fragment
        public let outputs: [String: String]?
    }

    public let manifest: Manifest
    public let body: String                       // system prompt
    public let sourceURL: URL
}
