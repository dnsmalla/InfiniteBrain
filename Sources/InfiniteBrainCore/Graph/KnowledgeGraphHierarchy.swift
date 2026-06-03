import Foundation
import CoreGraphics
import GraphKit

/// Pure logic for the source-level expand/collapse Knowledge Graph.
///
/// The vault groups every derived note under the `Source` note it came from
/// (`note.sources[0]`). This turns the flat note set into a two-level hierarchy
/// — Source → derived Notes — and computes the visible subgraph + child layout
/// for a given expand/hide state. No SwiftUI; unit-testable.
public enum KnowledgeGraphHierarchy {

    /// Top-level entries and their children.
    public struct Grouping: Equatable, Sendable {
        /// Top-level node ids shown when everything is collapsed: source notes
        /// plus any "loose" notes that have no source.
        public let topLevelIds: [String]
        /// Source id → derived note ids.
        public let childrenBySource: [String: [String]]

        public init(topLevelIds: [String], childrenBySource: [String: [String]]) {
            self.topLevelIds = topLevelIds
            self.childrenBySource = childrenBySource
        }
    }

    /// Minimal note shape needed for grouping.
    public struct NoteRef: Equatable, Sendable {
        public let id: String
        public let isSource: Bool
        public let sourceId: String?   // first entry of note.sources, if any
        public init(id: String, isSource: Bool, sourceId: String?) {
            self.id = id; self.isSource = isSource; self.sourceId = sourceId
        }
    }

    /// Build the grouping. A note is a child of `sourceId` when that source
    /// exists; otherwise (no source, or source missing) it is top-level.
    public static func group(_ notes: [NoteRef]) -> Grouping {
        let sourceIdSet = Set(notes.filter { $0.isSource }.map { $0.id })
        var children: [String: [String]] = [:]
        var topLevel: [String] = []

        for note in notes {
            if note.isSource {
                topLevel.append(note.id)
            } else if let sid = note.sourceId, sourceIdSet.contains(sid) {
                children[sid, default: []].append(note.id)
            } else {
                topLevel.append(note.id)   // loose note
            }
        }
        return Grouping(topLevelIds: topLevel, childrenBySource: children)
    }

    /// Node ids visible for a given state: top-level entries not hidden, plus
    /// children of sources that are expanded and not hidden.
    public static func visibleNodeIds(grouping: Grouping,
                                      expanded: Set<String>,
                                      hidden: Set<String>) -> Set<String> {
        var visible = Set(grouping.topLevelIds.filter { !hidden.contains($0) })
        for (source, kids) in grouping.childrenBySource
        where expanded.contains(source) && !hidden.contains(source) {
            visible.formUnion(kids)
        }
        return visible
    }

    /// Filter `full` to the visible nodes and the edges between them.
    public static func visibleSubgraph(full: CGData,
                                       grouping: Grouping,
                                       expanded: Set<String>,
                                       hidden: Set<String>) -> CGData {
        let visible = visibleNodeIds(grouping: grouping, expanded: expanded, hidden: hidden)
        let nodes = full.nodes.filter { visible.contains($0.id) }
        let edges = full.edges.filter { visible.contains($0.fromId) && visible.contains($0.toId) }
        return CGData(nodes: nodes, edges: edges)
    }

    /// Positions for child nodes arranged in a ring around `center`. Radius
    /// grows with child count so dense sources don't overlap. Deterministic
    /// (angles spread evenly starting at -90°).
    public static func bloom(childIds: [String],
                             around center: CGPoint,
                             baseRadius: CGFloat = 90) -> [String: CGPoint] {
        guard !childIds.isEmpty else { return [:] }
        let n = childIds.count
        let radius = baseRadius + CGFloat(max(0, n - 6)) * 12
        var out: [String: CGPoint] = [:]
        let start = -CGFloat.pi / 2
        for (i, id) in childIds.enumerated() {
            let angle = start + (2 * .pi) * CGFloat(i) / CGFloat(n)
            out[id] = CGPoint(x: center.x + radius * cos(angle),
                              y: center.y + radius * sin(angle))
        }
        return out
    }
}
