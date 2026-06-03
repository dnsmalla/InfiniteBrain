import XCTest
import CoreGraphics
import GraphKit
@testable import InfiniteBrainCore

final class KnowledgeGraphHierarchyTests: XCTestCase {
    typealias H = KnowledgeGraphHierarchy

    private func ref(_ id: String, source: Bool = false, src: String? = nil) -> H.NoteRef {
        H.NoteRef(id: id, isSource: source, sourceId: src)
    }

    func testGroupingSeparatesSourcesChildrenAndLoose() {
        let g = H.group([
            ref("S1", source: true),
            ref("a", src: "S1"),
            ref("b", src: "S1"),
            ref("loose"),                 // no source → top level
            ref("orphan", src: "MISSING"),// source not present → top level
        ])
        XCTAssertEqual(Set(g.topLevelIds), ["S1", "loose", "orphan"])
        XCTAssertEqual(g.childrenBySource["S1"].map(Set.init), ["a", "b"])
    }

    func testCollapsedShowsOnlyTopLevel() {
        let g = H.group([ref("S1", source: true), ref("a", src: "S1")])
        let visible = H.visibleNodeIds(grouping: g, expanded: [], hidden: [])
        XCTAssertEqual(visible, ["S1"])
    }

    func testExpandedShowsChildren() {
        let g = H.group([ref("S1", source: true), ref("a", src: "S1"), ref("b", src: "S1")])
        let visible = H.visibleNodeIds(grouping: g, expanded: ["S1"], hidden: [])
        XCTAssertEqual(visible, ["S1", "a", "b"])
    }

    func testHiddenSourceHidesItAndItsChildren() {
        let g = H.group([ref("S1", source: true), ref("a", src: "S1")])
        let visible = H.visibleNodeIds(grouping: g, expanded: ["S1"], hidden: ["S1"])
        XCTAssertTrue(visible.isEmpty)
    }

    func testVisibleSubgraphDropsEdgesToHiddenNodes() {
        let g = H.group([ref("S1", source: true), ref("a", src: "S1")])
        let full = CGData(
            nodes: [CGNode(id: "S1", title: "S1", kind: .noteSource),
                    CGNode(id: "a", title: "a", kind: .noteConcept)],
            edges: [CGEdge(fromId: "S1", toId: "a", kind: .contains)]
        )
        // collapsed: only S1 visible, edge S1→a dropped
        let collapsed = H.visibleSubgraph(full: full, grouping: g, expanded: [], hidden: [])
        XCTAssertEqual(collapsed.nodes.map(\.id), ["S1"])
        XCTAssertTrue(collapsed.edges.isEmpty)
        // expanded: both nodes + edge
        let expanded = H.visibleSubgraph(full: full, grouping: g, expanded: ["S1"], hidden: [])
        XCTAssertEqual(Set(expanded.nodes.map(\.id)), ["S1", "a"])
        XCTAssertEqual(expanded.edges.count, 1)
    }

    func testBloomPlacesChildrenAroundCenterAtRadius() {
        let center = CGPoint(x: 100, y: 100)
        let pos = H.bloom(childIds: ["a", "b", "c", "d"], around: center, baseRadius: 90)
        XCTAssertEqual(pos.count, 4)
        for (_, p) in pos {
            let d = hypot(p.x - center.x, p.y - center.y)
            XCTAssertEqual(d, 90, accuracy: 0.001, "each child sits on the ring radius")
        }
    }

    func testBloomEmptyForNoChildren() {
        XCTAssertTrue(H.bloom(childIds: [], around: .zero).isEmpty)
    }
}
