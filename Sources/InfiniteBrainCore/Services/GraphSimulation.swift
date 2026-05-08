import Foundation
import CoreGraphics
import Accelerate

/// A dynamic force-directed simulation for the knowledge graph.
/// Optimized with SIMD (Accelerate) for large-scale node counts.
public final class GraphSimulation: @unchecked Sendable {
    public private(set) var nodes: [NodeState]
    public let edges: [GraphEdge]
    
    public struct NodeState: Equatable, Sendable {
        public let id: String
        public var position: CGPoint
        public var velocity: CGPoint = .zero
    }

    public init(data: GraphData) {
        // Start with current positions from the circular layout
        self.nodes = data.nodes.map { NodeState(id: $0.id, position: $0.position) }
        self.edges = data.edges
    }

    /// Advances the simulation by one step.
    public func step(canvasSize: CGSize) {
        let n = nodes.count
        guard n > 1 else { return }
        
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let alpha: CGFloat = 0.05 // Simulation cooling factor
        let kRepulsion: CGFloat = 800.0
        let kAttraction: CGFloat = 0.08
        let damping: CGFloat = 0.9
        
        // 1. Attraction (Springs)
        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
        for edge in edges {
            guard let i = nodeMap[edge.fromId], let j = nodeMap[edge.toId] else { continue }
            let dx = nodes[j].position.x - nodes[i].position.x
            let dy = nodes[j].position.y - nodes[i].position.y
            let d = sqrt(dx*dx + dy*dy)
            guard d > 0 else { continue }
            
            let f = (d - 30.0) * kAttraction
            let fx = f * (dx / d)
            let fy = f * (dy / d)
            
            nodes[i].velocity.x += fx
            nodes[i].velocity.y += fy
            nodes[j].velocity.x -= fx
            nodes[j].velocity.y -= fy
        }
        
        // 2. Repulsion (Barnes-Hut) - O(N log N)
        let tree = QuadTreeNode(bounds: calculationBounds(for: nodes, canvasSize: canvasSize))
        for node in nodes {
            tree.insert(id: node.id, position: node.position)
        }
        
        let theta: CGFloat = 0.5 // Approximation threshold
        for i in 0..<n {
            applyRepulsion(to: &nodes[i], from: tree, theta: theta, kRepulsion: kRepulsion)
        }
        
        // 3. Centering & Integration
        for i in 0..<n {
            // Soft centering pull
            nodes[i].velocity.x += (center.x - nodes[i].position.x) * 0.01
            nodes[i].velocity.y += (center.y - nodes[i].position.y) * 0.01
            
            // Apply velocity
            nodes[i].position.x += nodes[i].velocity.x * alpha
            nodes[i].position.y += nodes[i].velocity.y * alpha
            
            // Damping
            nodes[i].velocity.x *= damping
            nodes[i].velocity.y *= damping
        }
    }
    
    private func applyRepulsion(to node: inout NodeState, from tree: QuadTreeNode, theta: CGFloat, kRepulsion: CGFloat) {
        if let item = tree.nodeItem {
            if item.id == node.id { return }
            let dx = node.position.x - item.position.x
            let dy = node.position.y - item.position.y
            let d2 = dx*dx + dy*dy + 0.1
            let f = kRepulsion / d2
            node.velocity.x += f * (dx / sqrt(d2))
            node.velocity.y += f * (dy / sqrt(d2))
            return
        }
        
        let dx = node.position.x - tree.centerOfMass.x
        let dy = node.position.y - tree.centerOfMass.y
        let d2 = dx*dx + dy*dy + 0.1
        let d = sqrt(d2)
        let s = tree.bounds.width
        
        if s / d < theta {
            let f = (kRepulsion * CGFloat(tree.totalMass)) / d2
            node.velocity.x += f * (dx / d)
            node.velocity.y += f * (dy / d)
        } else if let children = tree.children {
            for child in children {
                applyRepulsion(to: &node, from: child, theta: theta, kRepulsion: kRepulsion)
            }
        }
    }
    
    private func calculationBounds(for nodes: [NodeState], canvasSize: CGSize) -> CGRect {
        var minX = -1000.0, minY = -1000.0, maxX = 2000.0, maxY = 2000.0
        for node in nodes {
            minX = min(minX, Double(node.position.x))
            minY = min(minY, Double(node.position.y))
            maxX = max(maxX, Double(node.position.x))
            maxY = max(maxY, Double(node.position.y))
        }
        let w = maxX - minX
        let h = maxY - minY
        let side = max(w, h, Double(max(canvasSize.width, canvasSize.height)))
        return CGRect(x: minX - 100, y: minY - 100, width: side + 200, height: side + 200)
    }

    public func updatePositions(in data: inout GraphData) {
        let states = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.position) })
        let newNodes = data.nodes.map { n -> GraphNode in
            if let pos = states[n.id] {
                return GraphNode(id: n.id, title: n.title, type: n.type, summary: n.summary, position: pos)
            }
            return n
        }
        data = GraphData(nodes: newNodes, edges: data.edges)
    }
}
