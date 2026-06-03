// Static type-clustered circular layout. No physics dependency.
// Each CGNodeKind gets a pie slice; nodes within a slice spread
// across three concentric rings for readability at high counts.
import Foundation
import GraphKit
import CoreGraphics

public enum CodeGraphLayout {
    public static func compute(_ raw: CGData, canvasSize: CGSize) -> CGData {
        guard !raw.nodes.isEmpty,
              canvasSize.width > 0, canvasSize.height > 0 else { return .empty }

        let center    = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let maxRadius = min(canvasSize.width, canvasSize.height) / 2 * 0.85

        let activeKinds = Array(Set(raw.nodes.map(\.kind))).sorted { $0.rawValue < $1.rawValue }
        let grouped     = Dictionary(grouping: raw.nodes) { $0.kind }
        let sliceAngle  = 2 * Double.pi / Double(max(1, activeKinds.count))

        var laidOut: [CGNode] = []
        laidOut.reserveCapacity(raw.nodes.count)

        for (kindIdx, kind) in activeKinds.enumerated() {
            guard let group = grouped[kind], !group.isEmpty else { continue }
            let centerAngle = sliceAngle * Double(kindIdx) - .pi / 2
            let usable = sliceAngle * 0.7
            let n = group.count
            for (i, node) in group.enumerated() {
                let t: Double = n > 1 ? Double(i) / Double(n - 1) : 0.5
                let angle = centerAngle - usable / 2 + usable * t
                let ring  = i % 3
                let r     = maxRadius * (0.5 + 0.5 * Double(ring + 1) / 3)
                let x     = center.x + cos(angle) * r
                let y     = center.y + sin(angle) * r
                laidOut.append(CGNode(id: node.id, title: node.title, kind: node.kind,
                                      position: CGPoint(x: x, y: y), metadata: node.metadata))
            }
        }

        let presentIds = Set(laidOut.map(\.id))
        let edges = raw.edges.filter { presentIds.contains($0.fromId) && presentIds.contains($0.toId) }
        return CGData(nodes: laidOut, edges: edges, layers: raw.layers, tour: raw.tour)
    }
}
