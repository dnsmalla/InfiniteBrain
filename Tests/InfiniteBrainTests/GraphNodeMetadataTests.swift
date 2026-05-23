import XCTest
import CoreGraphics
@testable import InfiniteBrainCore

final class GraphNodeMetadataTests: XCTestCase {
    func testLegacyInitLeavesMetadataNil() {
        let n = GraphNode(id: "1", title: "t", type: .concept, summary: "s",
                          position: .zero)
        XCTAssertNil(n.metadata)
    }

    func testInitWithMetadata() {
        let n = GraphNode(id: "1", title: "t", type: .codeFile, summary: "s",
                          position: .zero,
                          metadata: ["fileURL": "file:///tmp/a.swift"])
        XCTAssertEqual(n.metadata?["fileURL"], "file:///tmp/a.swift")
    }
}
