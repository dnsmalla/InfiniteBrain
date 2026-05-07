import SwiftUI
import InfiniteBrainCore

/// Shared colour palette for the 16 NodeType cases. Used by GraphView's
/// node rendering and the Help window's node-type cards. The Schema view
/// itself was retired in favour of the Help window — its content moved
/// there as the "16 Node Types" / "10 Edge Types" sections.
enum SchemaView {
    static func color(for type: NodeType) -> Color {
        switch type {
        case .pillar:    return Color(red: 0.30, green: 0.55, blue: 0.85)
        case .decision:  return Color(red: 0.85, green: 0.40, blue: 0.30)
        case .concept:   return Color(red: 0.50, green: 0.35, blue: 0.80)
        case .question:  return Color(red: 0.95, green: 0.65, blue: 0.20)
        case .playbook:  return Color(red: 0.20, green: 0.70, blue: 0.55)
        case .task:      return Color(red: 0.85, green: 0.55, blue: 0.85)
        case .event:     return Color(red: 0.55, green: 0.75, blue: 0.30)
        case .pattern:   return Color(red: 0.70, green: 0.45, blue: 0.20)
        case .hypothesis:return Color(red: 0.30, green: 0.65, blue: 0.85)
        case .fact:      return Color(red: 0.25, green: 0.65, blue: 0.35)
        case .source:    return Color(red: 0.45, green: 0.45, blue: 0.55)
        case .bookmark:  return Color(red: 0.95, green: 0.45, blue: 0.55)
        case .note:      return Color(red: 0.60, green: 0.60, blue: 0.60)
        case .contact:   return Color(red: 0.90, green: 0.75, blue: 0.40)
        case .reference: return Color(red: 0.40, green: 0.40, blue: 0.70)
        case .custom:    return Color(red: 0.80, green: 0.30, blue: 0.55)
        }
    }
}
