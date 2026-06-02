// GraphLayoutTests now covers CodeGraphLayout — the unified layout used by
// both the Code Graph and the Knowledge Graph. GraphLayout (the old
// Note-based variant) was removed when GraphView migrated to CGData.
import XCTest
@testable import InfiniteBrainCore

final class GraphLayoutTests: XCTestCase {

    func testEmptyInputProducesEmptyGraph() {
        let result = CodeGraphLayout.compute(.empty, canvasSize: CGSize(width: 800, height: 600))
        XCTAssertTrue(result.nodes.isEmpty)
        XCTAssertTrue(result.edges.isEmpty)
    }

    func testNodeCountPreservedAndPositionsInsideCanvas() {
        let nodes = (0..<20).map { i in
            CGNode(id: "\(i)", title: "N\(i)",
                   kind: i % 2 == 0 ? .file : .noteConcept)
        }
        let canvas = CGSize(width: 800, height: 600)
        let result = CodeGraphLayout.compute(CGData(nodes: nodes, edges: []),
                                             canvasSize: canvas)
        XCTAssertEqual(result.nodes.count, 20)
        for n in result.nodes {
            XCTAssertGreaterThan(n.position.x, 0)
            XCTAssertLessThan(n.position.x, canvas.width)
            XCTAssertGreaterThan(n.position.y, 0)
            XCTAssertLessThan(n.position.y, canvas.height)
        }
    }

    func testDanglingEdgesDropped() {
        let a = CGNode(id: "a", title: "A", kind: .file)
        let b = CGNode(id: "b", title: "B", kind: .file)
        let edges = [
            CGEdge(fromId: "a", toId: "b",       kind: .imports),   // valid
            CGEdge(fromId: "a", toId: "MISSING",  kind: .imports),  // dangling
        ]
        let result = CodeGraphLayout.compute(CGData(nodes: [a, b], edges: edges),
                                             canvasSize: CGSize(width: 400, height: 400))
        XCTAssertEqual(result.edges.count, 1, "dangling edge must be dropped")
        XCTAssertEqual(result.edges.first?.fromId, "a")
        XCTAssertEqual(result.edges.first?.toId,   "b")
    }
}
