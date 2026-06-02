import Foundation

/// The semantic edge types. 10 knowledge-graph types plus 4 code-graph types.
public enum EdgeType: String, Codable, CaseIterable, Sendable {
    case supports
    case contradicts
    case dependsOn = "depends_on"
    case derivedFrom = "derived_from"
    case relatedTo = "related_to"
    case partOf = "part_of"
    case precededBy = "preceded_by"
    case followedBy = "followed_by"
    case authored
    case tagging

    // Code-graph relationships (UA stack)
    case imports
    case calls
    case references
    case defines
}

public struct Edge: Codable, Hashable, Sendable {
    public let type: EdgeType
    public let target: String          // target note id
    public let evidence: String?       // short justification, optional
}
