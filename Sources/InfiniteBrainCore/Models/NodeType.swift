import Foundation

/// A flexible node type in the InfiniteBrain knowledge graph.
public struct NodeType: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
    
    public static let pillar: NodeType = "pillar"
    public static let decision: NodeType = "decision"
    public static let concept: NodeType = "concept"
    public static let question: NodeType = "question"
    public static let playbook: NodeType = "playbook"
    public static let task: NodeType = "task"
    public static let event: NodeType = "event"
    public static let pattern: NodeType = "pattern"
    public static let hypothesis: NodeType = "hypothesis"
    public static let fact: NodeType = "fact"
    public static let source: NodeType = "source"
    public static let bookmark: NodeType = "bookmark"
    public static let note: NodeType = "note"
    public static let contact: NodeType = "contact"
    public static let reference: NodeType = "reference"
    public static let custom: NodeType = "custom"

    // Code-graph types (UA stack)
    public static let codeFile: NodeType = "code_file"
    public static let codeSymbol: NodeType = "code_symbol"
    public static let codeModule: NodeType = "code_module"
    public static let docPage: NodeType = "doc_page"

    public static var allCases: [NodeType] {
        [.pillar, .decision, .concept, .question, .playbook, .task, .event,
         .pattern, .hypothesis, .fact, .source, .bookmark, .note, .contact,
         .reference, .custom,
         .codeFile, .codeSymbol, .codeModule, .docPage]
    }
}
