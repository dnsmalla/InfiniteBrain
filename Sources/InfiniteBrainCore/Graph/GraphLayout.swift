import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct GraphNode: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let type: NodeType
    public let summary: String
    public var position: CGPoint
    public let metadata: [String: String]?

    public init(id: String, title: String, type: NodeType, summary: String, position: CGPoint) {
        self.id = id; self.title = title; self.type = type; self.summary = summary
        self.position = position; self.metadata = nil
    }

    public init(id: String, title: String, type: NodeType, summary: String, position: CGPoint, metadata: [String: String]?) {
        self.id = id; self.title = title; self.type = type; self.summary = summary
        self.position = position; self.metadata = metadata
    }
}

public struct GraphEdge: Equatable, Sendable {
    public let fromId: String
    public let toId: String
    public let type: EdgeType
    public init(fromId: String, toId: String, type: EdgeType) {
        self.fromId = fromId; self.toId = toId; self.type = type
    }
}

public struct GraphData: Equatable, Sendable {
    public let nodes: [GraphNode]
    public let edges: [GraphEdge]
    public init(nodes: [GraphNode], edges: [GraphEdge]) {
        self.nodes = nodes; self.edges = edges
    }
}

/// Pure layout function. Maps notes onto a circular type-clustered layout:
/// each NodeType gets a slice of the circle, notes within a type spread along
/// the slice arc on three concentric rings. Dangling edges (target missing
/// from the input) are dropped.
public enum GraphLayout {
    public static func compute(notes: [Note], canvasSize: CGSize) -> GraphData {
        guard !notes.isEmpty,
              canvasSize.width > 0, canvasSize.height > 0
        else { return GraphData(nodes: [], edges: []) }

        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let maxRadius = min(canvasSize.width, canvasSize.height) / 2 * 0.85

        let activeTypes = Array(Set(notes.map(\.type))).sorted { $0.rawValue < $1.rawValue }
        let grouped = Dictionary(grouping: notes) { $0.type }
        let sliceAngle = 2 * .pi / Double(max(1, activeTypes.count))

        var graphNodes: [GraphNode] = []
        graphNodes.reserveCapacity(notes.count)

        for (typeIdx, type) in activeTypes.enumerated() {
            guard let group = grouped[type], !group.isEmpty else { continue }
            // Sector spans [centerAngle - sliceAngle/2, centerAngle + sliceAngle/2].
            // Subtract π/2 so type 0 starts at the top of the canvas.
            let centerAngle = sliceAngle * Double(typeIdx) - .pi / 2
            let n = group.count
            // Use 70% of the slice so neighbouring sectors don't visually merge.
            let usable = sliceAngle * 0.7

            for (i, note) in group.enumerated() {
                let t: Double = n > 1 ? Double(i) / Double(n - 1) : 0.5
                let angle = centerAngle - usable / 2 + usable * t
                // Three concentric rings keep large groups visually readable.
                let ring = i % 3
                let r = maxRadius * (0.5 + 0.5 * Double(ring + 1) / 3)
                let x = center.x + cos(angle) * r
                let y = center.y + sin(angle) * r
                graphNodes.append(GraphNode(
                    id: note.id,
                    title: note.title,
                    type: note.type,
                    summary: note.summary,
                    position: CGPoint(x: x, y: y)
                ))
            }
        }

        let presentIds = Set(graphNodes.map(\.id))
        var graphEdges: [GraphEdge] = []
        for note in notes where presentIds.contains(note.id) {
            for edge in note.edges where presentIds.contains(edge.target) {
                graphEdges.append(GraphEdge(
                    fromId: note.id,
                    toId: edge.target,
                    type: edge.type
                ))
            }
        }

        return GraphData(nodes: graphNodes, edges: graphEdges)
    }
}
