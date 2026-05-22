import SwiftUI
import InfiniteBrainCore

enum NodePalette {
    static func color(for type: NodeType) -> Color {
        switch type {
        case .pillar:    return Color(red: 0.00, green: 0.40, blue: 0.90)   // Deep Blue
        case .decision:  return Color(red: 0.90, green: 0.10, blue: 0.10)   // Rich Red
        case .concept:   return Color(red: 0.50, green: 0.00, blue: 0.80)   // Deep Purple
        case .question:  return Color(red: 0.85, green: 0.55, blue: 0.00)   // Dark Amber
        case .playbook:  return Color(red: 0.00, green: 0.60, blue: 0.50)   // Deep Teal
        case .task:      return Color(red: 0.85, green: 0.00, blue: 0.50)   // Deep Pink
        case .event:     return Color(red: 0.40, green: 0.70, blue: 0.00)   // Forest Lime
        case .pattern:   return Color(red: 0.85, green: 0.40, blue: 0.00)   // Burnt Orange
        case .hypothesis:return Color(red: 0.00, green: 0.55, blue: 0.80)   // Steel Blue
        case .fact:      return Color(red: 0.00, green: 0.65, blue: 0.25)   // Racing Green
        case .source:    return Color(red: 0.40, green: 0.40, blue: 0.50)   // Slate
        case .bookmark:  return Color(red: 0.80, green: 0.30, blue: 0.35)   // Dark Coral
        case .note:      return Color(red: 0.30, green: 0.30, blue: 0.35)   // Gunmetal
        case .contact:   return Color(red: 0.75, green: 0.60, blue: 0.00)   // Ochre Gold
        case .reference: return Color(red: 0.25, green: 0.25, blue: 0.75)   // Deep Indigo
        case .custom:    return Color(red: 0.75, green: 0.00, blue: 0.55)   // Magenta
        default:         return AppPalette.brand
        }
    }
}
