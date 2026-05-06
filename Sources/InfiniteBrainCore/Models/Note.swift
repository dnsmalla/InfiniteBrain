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
    public var needsReview: Bool       // set when classification confidence is low

    public init(
        id: String,
        type: NodeType,
        title: String,
        summary: String,
        body: String,
        edges: [Edge],
        sources: [String],
        contentHash: String,
        version: Int,
        createdAt: Date,
        updatedAt: Date,
        supersededBy: String? = nil,
        needsReview: Bool = false
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.summary = summary
        self.body = body
        self.edges = edges
        self.sources = sources
        self.contentHash = contentHash
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.supersededBy = supersededBy
        self.needsReview = needsReview
    }
}
