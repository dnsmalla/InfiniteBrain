import XCTest
@testable import InfiniteBrainCore

final class CGSimulationTests: XCTestCase {

    func testSettleSpreadsSuperimposedNodes() {
        let nodes = (0..<5).map { i in
            CGNode(id: "n\(i)", title: "N\(i)", kind: .file,
                   position: CGPoint(x: 300, y: 300))
        }
        let data = CGData(nodes: nodes, edges: [])
        let sim  = CGSimulation(data: data)
        sim.settle(maxIterations: 80)
        let result = sim.appliedData(to: data)
        let uniquePositions = Set(result.nodes.map {
            "\(Int($0.position.x / 10)),\(Int($0.position.y / 10))"
        })
        XCTAssertGreaterThan(uniquePositions.count, 1,
                             "Superimposed nodes must spread after settle")
    }

    func testConnectedNodesDontFlyInfinitelyFar() {
        let n0 = CGNode(id: "n0", title: "A", kind: .file, position: CGPoint(x:   0, y:   0))
        let n1 = CGNode(id: "n1", title: "B", kind: .file, position: CGPoint(x: 800, y: 800))
        let edges = [CGEdge(fromId: "n0", toId: "n1", kind: .imports)]
        let data  = CGData(nodes: [n0, n1], edges: edges)
        let sim   = CGSimulation(data: data)
        sim.settle(maxIterations: 200)
        let result = sim.appliedData(to: data)
        let a = result.nodes.first { $0.id == "n0" }!.position
        let b = result.nodes.first { $0.id == "n1" }!.position
        let dist = hypot(b.x - a.x, b.y - a.y)
        XCTAssertLessThan(dist, 1200,
                          "Edge spring should pull connected nodes closer than 1200pt")
    }

    func testEmptyGraphHandledGracefully() {
        let sim = CGSimulation(data: .empty)
        sim.settle()
        let result = sim.appliedData(to: .empty)
        XCTAssertTrue(result.nodes.isEmpty)
    }

    func testAppliedDataPreservesEdgesAndMetadata() {
        let n = CGNode(id: "n0", title: "Foo", kind: .file, position: .zero,
                       metadata: ["source_file": "foo.swift"])
        let e = CGEdge(fromId: "n0", toId: "n0", kind: .imports)
        let data = CGData(nodes: [n], edges: [e])
        let sim  = CGSimulation(data: data)
        sim.settle(maxIterations: 1)
        let result = sim.appliedData(to: data)
        XCTAssertEqual(result.edges.count, 1)
        XCTAssertEqual(result.nodes.first?.metadata["source_file"], "foo.swift")
    }
}
