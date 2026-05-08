import Foundation
import CoreGraphics

/// A node in the spatial QuadTree. Used for Barnes-Hut force calculation.
public final class QuadTreeNode {
    public let bounds: CGRect
    public var centerOfMass: CGPoint = .zero
    public var totalMass: Double = 0
    public var nodeItem: (id: String, position: CGPoint)? // Leaf node if not nil
    
    public var children: [QuadTreeNode]? // NW, NE, SW, SE
    
    public init(bounds: CGRect) {
        self.bounds = bounds
    }
    
    public func insert(id: String, position: CGPoint) {
        guard bounds.contains(position) else { return }
        
        if children == nil && nodeItem == nil {
            // Empty leaf, just store the item
            nodeItem = (id, position)
            centerOfMass = position
            totalMass = 1
            return
        }
        
        if children == nil {
            // Was a leaf, now needs to split
            subdivide()
            if let item = nodeItem {
                insertIntoChildren(id: item.id, position: item.position)
                nodeItem = nil
            }
        }
        
        insertIntoChildren(id: id, position: position)
        updateMass(at: position)
    }
    
    private func subdivide() {
        let w = bounds.width / 2
        let h = bounds.height / 2
        let x = bounds.minX
        let y = bounds.minY
        
        children = [
            QuadTreeNode(bounds: CGRect(x: x, y: y, width: w, height: h)),       // NW
            QuadTreeNode(bounds: CGRect(x: x + w, y: y, width: w, height: h)),   // NE
            QuadTreeNode(bounds: CGRect(x: x, y: y + h, width: w, height: h)),   // SW
            QuadTreeNode(bounds: CGRect(x: x + w, y: y + h, width: w, height: h)) // SE
        ]
    }
    
    private func insertIntoChildren(id: String, position: CGPoint) {
        children?.forEach { $0.insert(id: id, position: position) }
    }
    
    private func updateMass(at position: CGPoint) {
        let newTotal = totalMass + 1
        centerOfMass.x = CGFloat((Double(centerOfMass.x) * totalMass + Double(position.x)) / newTotal)
        centerOfMass.y = CGFloat((Double(centerOfMass.y) * totalMass + Double(position.y)) / newTotal)
        totalMass = newTotal
    }
}
