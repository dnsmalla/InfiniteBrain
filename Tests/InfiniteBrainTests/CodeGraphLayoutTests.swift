import XCTest
import GraphKit
@testable import InfiniteBrainCore

final class CodeGraphLayoutTests: XCTestCase {
    func testNodesReceiveNonZeroPositions() {
        let nodes = (0..<6).map { i in
            CGNode(id: "n\(i)", title: "Node\(i)", kind: i % 2 == 0 ? .file : .function)
        }
        let input = CGData(nodes: nodes, edges: [])
        let result = CodeGraphLayout.compute(input, canvasSize: CGSize(width: 800, height: 600))
        XCTAssertEqual(result.nodes.count, 6)
        XCTAssertTrue(result.nodes.allSatisfy { $0.position != .zero })
    }

    func testEdgeToMissingNodeIsDropped() {
        let nodes = [CGNode(id: "a", title: "A", kind: .file),
                     CGNode(id: "b", title: "B", kind: .module)]
        let edges = [CGEdge(fromId: "a", toId: "b",       kind: .imports),
                     CGEdge(fromId: "a", toId: "missing", kind: .imports)]
        let input = CGData(nodes: nodes, edges: edges)
        let result = CodeGraphLayout.compute(input, canvasSize: CGSize(width: 800, height: 600))
        XCTAssertEqual(result.edges.count, 1)
        XCTAssertEqual(result.edges[0].fromId, "a")
        XCTAssertEqual(result.edges[0].toId,   "b")
    }

    func testEmptyInputReturnsEmpty() {
        let result = CodeGraphLayout.compute(.empty, canvasSize: CGSize(width: 800, height: 600))
        XCTAssertTrue(result.nodes.isEmpty)
        XCTAssertTrue(result.edges.isEmpty)
    }

    func testNodesStayWithinCanvas() {
        let nodes = (0..<20).map { i in
            CGNode(id: "n\(i)", title: "N\(i)", kind: .file)
        }
        let canvas = CGSize(width: 600, height: 400)
        let result = CodeGraphLayout.compute(CGData(nodes: nodes, edges: []), canvasSize: canvas)
        for node in result.nodes {
            XCTAssertTrue(node.position.x >= 0 && node.position.x <= canvas.width,
                          "x \(node.position.x) out of bounds")
            XCTAssertTrue(node.position.y >= 0 && node.position.y <= canvas.height,
                          "y \(node.position.y) out of bounds")
        }
    }
}
