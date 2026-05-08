import SwiftUI
import InfiniteBrainCore

/// Single source of truth for the 16-colour NodeType palette. Used by
/// `GraphView` for node rendering, by `HelpView`'s node-type cards, and
/// by `SchemaView`'s legacy color accessor (kept as a thin shim).
///
/// Hand-picked: distinguishable as small dots on a default macOS
/// window background, light + dark mode.
enum NodePalette {
    static func color(for type: NodeType) -> Color {
        switch type {
        case .pillar:    return Color(red: 0.30, green: 0.55, blue: 0.85)   // blue
        case .decision:  return Color(red: 0.85, green: 0.40, blue: 0.30)   // brick
        case .concept:   return Color(red: 0.50, green: 0.35, blue: 0.80)   // violet
        case .question:  return Color(red: 0.95, green: 0.65, blue: 0.20)   // amber
        case .playbook:  return Color(red: 0.20, green: 0.70, blue: 0.55)   // teal
        case .task:      return Color(red: 0.85, green: 0.55, blue: 0.85)   // pink
        case .event:     return Color(red: 0.55, green: 0.75, blue: 0.30)   // olive
        case .pattern:   return Color(red: 0.70, green: 0.45, blue: 0.20)   // ochre
        case .hypothesis:return Color(red: 0.30, green: 0.65, blue: 0.85)   // sky
        case .fact:      return Color(red: 0.25, green: 0.65, blue: 0.35)   // green
        case .source:    return Color(red: 0.45, green: 0.45, blue: 0.55)   // slate
        case .bookmark:  return Color(red: 0.95, green: 0.45, blue: 0.55)   // coral
        case .note:      return Color(red: 0.60, green: 0.60, blue: 0.60)   // grey
        case .contact:   return Color(red: 0.90, green: 0.75, blue: 0.40)   // gold
        case .reference: return Color(red: 0.40, green: 0.40, blue: 0.70)   // indigo
        case .custom:    return Color(red: 0.80, green: 0.30, blue: 0.55)   // magenta
        }
    }
}
