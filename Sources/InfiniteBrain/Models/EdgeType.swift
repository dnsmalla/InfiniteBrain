import Foundation

/// The 10 semantic edge types.
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
}

public struct Edge: Codable, Hashable, Sendable {
    public let type: EdgeType
    public let target: String          // target note id
    public let evidence: String?       // short justification, optional
}
