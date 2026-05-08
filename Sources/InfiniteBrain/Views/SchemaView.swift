import SwiftUI
import InfiniteBrainCore

/// Legacy accessor for the node-type colour palette. The full Schema view
/// retired into the Help window in 0.24; this shim stays so HelpView can
/// keep its existing `SchemaView.color(for:)` call without churn. New
/// code should use `NodePalette.color(for:)` directly.
enum SchemaView {
    static func color(for type: NodeType) -> Color { NodePalette.color(for: type) }
}
