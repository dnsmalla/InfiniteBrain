import XCTest
@testable import InfiniteBrainCore

final class GraphLayoutTests: XCTestCase {
    func testEmptyInputProducesEmptyGraph() {
        let g = GraphLayout.compute(notes: [], canvasSize: .init(width: 800, height: 600))
        XCTAssertTrue(g.nodes.isEmpty)
        XCTAssertTrue(g.edges.isEmpty)
    }

    func testNodeCountMatchesNoteCountAndPositionsAreInsideCanvas() {
        let notes = (0..<20).map { i in
            Note(
                id: "01J\(String(format: "%023d", i))",
                type: NodeType.allCases[i % NodeType.allCases.count],
                title: "n\(i)", summary: "s\(i)", body: "b",
                edges: [], sources: [], contentHash: "h",
                version: 1, createdAt: Date(), updatedAt: Date()
            )
        }
        let size = CGSize(width: 800, height: 600)
        let g = GraphLayout.compute(notes: notes, canvasSize: size)
        XCTAssertEqual(g.nodes.count, 20)
        for n in g.nodes {
            XCTAssertGreaterThan(n.position.x, 0)
            XCTAssertLessThan(n.position.x, size.width)
            XCTAssertGreaterThan(n.position.y, 0)
            XCTAssertLessThan(n.position.y, size.height)
        }
    }

    func testEdgesAreOnlyEmittedWhenBothEndpointsArePresent() {
        let factId = "01JFACT0000000000000000001"
        let decId  = "01JDEC00000000000000000002"
        let notes = [
            Note(id: factId, type: .fact, title: "f", summary: "s", body: "b",
                 edges: [], sources: [], contentHash: "h", version: 1,
                 createdAt: Date(), updatedAt: Date()),
            Note(id: decId, type: .decision, title: "d", summary: "s", body: "b",
                 edges: [
                    Edge(type: .supports, target: factId, evidence: nil),
                    Edge(type: .supports, target: "MISSING", evidence: nil),  // dangling
                 ],
                 sources: [], contentHash: "h", version: 1,
                 createdAt: Date(), updatedAt: Date()),
        ]
        let g = GraphLayout.compute(notes: notes, canvasSize: .init(width: 400, height: 400))
        XCTAssertEqual(g.edges.count, 1, "must drop the dangling edge")
        XCTAssertEqual(g.edges.first?.fromId, decId)
        XCTAssertEqual(g.edges.first?.toId, factId)
    }
}
