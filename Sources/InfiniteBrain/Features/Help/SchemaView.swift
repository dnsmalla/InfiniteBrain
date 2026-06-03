import SwiftUI
import GraphKit
import InfiniteBrainCore

/// Shim kept so HelpView's existing `SchemaView.color(for:)` call compiles
/// without churn. Delegates to `CGPalette` via the shared `CGNodeKind.from`
/// converter — no separate `NodePalette` needed.
enum SchemaView {
    static func color(for type: NodeType) -> Color {
        CGPalette.color(for: CGNodeKind.from(type.rawValue))
    }
}
