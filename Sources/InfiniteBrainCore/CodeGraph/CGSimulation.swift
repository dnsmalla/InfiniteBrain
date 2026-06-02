import Foundation
import CoreGraphics

/// Force-directed physics for the code graph. Uses the QuadTreeNode (Barnes-Hut)
/// already in InfiniteBrainCore — same approach as GraphSimulation but typed to
/// CGData/CGNode/CGEdge. Settle-then-freeze workflow:
///   1. Call `settle()` in a detached background task.
///   2. Call `appliedData(to:)` on the main actor to publish new positions.
public final class CGSimulation: @unchecked Sendable {

    public struct NodeState: Sendable {
        public let id: String
        public var position: CGPoint
        public var velocity: CGPoint = .zero
    }

    public private(set) var nodes: [NodeState]
    private let edges: [CGEdge]

    public init(data: CGData) {
        // Apply a tiny deterministic jitter so superimposed nodes have a repulsion
        // direction to act on. Uses index as seed to keep output reproducible.
        self.nodes = data.nodes.enumerated().map { idx, n in
            let angle = CGFloat(idx) * 2.399963 // golden-angle spread
            let nudge: CGFloat = 0.5
            let jittered = CGPoint(x: n.position.x + cos(angle) * nudge,
                                   y: n.position.y + sin(angle) * nudge)
            return NodeState(id: n.id, position: jittered)
        }
        self.edges = data.edges
    }

    /// Run up to `maxIterations` ticks, stopping early when all velocities
    /// drop below `threshold`. Safe to call off the main actor.
    public func settle(maxIterations: Int = 200, threshold: CGFloat = 0.4) {
        guard nodes.count > 1 else { return }
        for i in 0..<maxIterations {
            tick()
            if i > 30 {
                let maxV = nodes.reduce(CGFloat(0)) { acc, s in
                    max(acc, abs(s.velocity.x), abs(s.velocity.y))
                }
                if maxV < threshold { break }
            }
        }
    }

    /// One physics step. Public for testing.
    public func tick() {
        let n = nodes.count
        guard n > 1 else { return }

        let alpha:       CGFloat = 0.05
        let kRepulsion:  CGFloat = 900.0
        let kAttraction: CGFloat = 0.07
        let restLength:  CGFloat = 80.0
        let damping:     CGFloat = 0.88
        let center = CGPoint(x: 600, y: 400)

        // Spring attraction along edges
        let idxById = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
        for e in edges {
            guard let i = idxById[e.fromId], let j = idxById[e.toId] else { continue }
            let dx = nodes[j].position.x - nodes[i].position.x
            let dy = nodes[j].position.y - nodes[i].position.y
            let d  = max(hypot(dx, dy), 0.1)
            let f  = (d - restLength) * kAttraction
            let fx = f * (dx / d), fy = f * (dy / d)
            nodes[i].velocity.x += fx; nodes[i].velocity.y += fy
            nodes[j].velocity.x -= fx; nodes[j].velocity.y -= fy
        }

        // Barnes-Hut repulsion
        var minX = nodes[0].position.x, minY = nodes[0].position.y
        var maxX = minX, maxY = minY
        for s in nodes {
            minX = min(minX, s.position.x); minY = min(minY, s.position.y)
            maxX = max(maxX, s.position.x); maxY = max(maxY, s.position.y)
        }
        let side   = max(maxX - minX, maxY - minY, 800)
        let bounds = CGRect(x: minX - 50, y: minY - 50,
                            width: side + 100, height: side + 100)
        let tree = QuadTreeNode(bounds: bounds)
        for s in nodes { tree.insert(id: s.id, position: s.position) }
        for i in 0..<n {
            applyRepulsion(to: &nodes[i], tree: tree, theta: 0.5, k: kRepulsion)
        }

        // Centering + integrate
        for i in 0..<n {
            nodes[i].velocity.x += (center.x - nodes[i].position.x) * 0.008
            nodes[i].velocity.y += (center.y - nodes[i].position.y) * 0.008
            nodes[i].position.x += nodes[i].velocity.x * alpha
            nodes[i].position.y += nodes[i].velocity.y * alpha
            nodes[i].velocity.x *= damping
            nodes[i].velocity.y *= damping
        }
    }

    private func applyRepulsion(to node: inout NodeState,
                                tree: QuadTreeNode,
                                theta: CGFloat, k: CGFloat) {
        if let item = tree.nodeItem {
            guard item.id != node.id else { return }
            let dx = node.position.x - item.position.x
            let dy = node.position.y - item.position.y
            let d2 = dx*dx + dy*dy + 0.1
            let f  = k / d2
            node.velocity.x += f * (dx / sqrt(d2))
            node.velocity.y += f * (dy / sqrt(d2))
            return
        }
        let dx = node.position.x - tree.centerOfMass.x
        let dy = node.position.y - tree.centerOfMass.y
        let d2 = dx*dx + dy*dy + 0.1
        let d  = sqrt(d2)
        if tree.bounds.width / d < theta {
            let f = (k * CGFloat(tree.totalMass)) / d2
            node.velocity.x += f * (dx / d)
            node.velocity.y += f * (dy / d)
        } else if let children = tree.children {
            for child in children {
                applyRepulsion(to: &node, tree: child, theta: theta, k: k)
            }
        }
    }

    /// Returns a new CGData with every node at its simulated position.
    /// Edges, layers, tour, and all metadata are preserved unchanged.
    public func appliedData(to data: CGData) -> CGData {
        let posMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.position) })
        let updated = data.nodes.map { n in
            CGNode(id: n.id, title: n.title, kind: n.kind,
                   position: posMap[n.id] ?? n.position,
                   metadata: n.metadata)
        }
        return CGData(nodes: updated, edges: data.edges,
                      layers: data.layers, tour: data.tour)
    }
}
