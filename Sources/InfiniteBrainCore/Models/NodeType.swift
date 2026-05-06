import Foundation

/// The 16 node types in the InfiniteBrain knowledge graph.
public enum NodeType: String, Codable, CaseIterable, Sendable {
    case pillar
    case decision
    case concept
    case question
    case playbook
    case task
    case event
    case pattern
    case hypothesis
    case fact
    case source
    case bookmark
    case note
    case contact
    case reference
    case custom
}
