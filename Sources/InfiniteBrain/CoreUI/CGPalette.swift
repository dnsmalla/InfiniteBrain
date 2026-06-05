import SwiftUI
import GraphKit

/// App-level color palette for graph node kinds. Lives in the app target
/// (not GraphKit) so the shared engine stays free of SwiftUI/presentation.
public enum CGPalette {
    public static func color(for kind: CGNodeKind) -> Color {
        switch kind {
        case .file:           return .blue
        case .symbol:         return .purple
        case .module:         return .orange
        case .docPage:        return .green
        case .memoryDoc:      return .indigo
        case .memoryChunk:    return .mint
        case .noteDecision:   return .red
        case .noteTask:       return .orange
        case .noteQuestion:   return .yellow
        case .noteFact:       return .green
        case .noteConcept:    return .cyan
        case .notePlaybook:   return .blue
        case .noteHypothesis: return .purple
        case .noteEvent:      return .pink
        case .noteSource:     return .brown
        case .function:       return Color(red: 0.2, green: 0.6, blue: 0.9)
        case .classType:      return Color(red: 0.6, green: 0.2, blue: 0.8)
        case .config:         return Color(red: 0.5, green: 0.5, blue: 0.5)
        case .service:        return Color(red: 0.0, green: 0.7, blue: 0.5)
        case .table:          return Color(red: 0.8, green: 0.5, blue: 0.1)
        case .endpoint:       return Color(red: 0.9, green: 0.3, blue: 0.3)
        case .pipeline:       return Color(red: 0.3, green: 0.5, blue: 0.9)
        case .schemaNode:     return Color(red: 0.7, green: 0.4, blue: 0.1)
        case .resource:       return Color(red: 0.1, green: 0.5, blue: 0.3)
        case .domain:         return Color(red: 0.9, green: 0.6, blue: 0.1)
        case .flow:           return Color(red: 0.4, green: 0.8, blue: 0.8)
        case .step:           return Color(red: 0.6, green: 0.8, blue: 0.4)
        case .article:        return Color(red: 0.4, green: 0.6, blue: 0.2)
        case .entity:         return Color(red: 0.8, green: 0.2, blue: 0.6)
        case .topic:          return Color(red: 0.2, green: 0.4, blue: 0.8)
        case .claim:          return Color(red: 0.9, green: 0.4, blue: 0.2)
        case .other:          return .gray
        // Future-proof: GraphKit may add node kinds (e.g. skill, agent) in a minor
        // release; render any unknown kind neutrally rather than failing to compile.
        @unknown default:     return .gray
        }
    }
}
