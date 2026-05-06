import Foundation

/// An atomic note. Persisted as a markdown file with YAML frontmatter.
public struct Note: Codable, Identifiable, Sendable {
    public let id: String              // ULID, stable across renames
    public var type: NodeType
    public var title: String
    public var summary: String         // ≤ ~50 tokens, one sentence
    public var body: String            // 50–300 lines of markdown
    public var edges: [Edge]
    public var sources: [String]       // source note ids (PDFs, URLs, …)
    public var contentHash: String     // sha256 of body, for dedupe
    public var version: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var supersededBy: String?   // optional pointer to newer note id
}
