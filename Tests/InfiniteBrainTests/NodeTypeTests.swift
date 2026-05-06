import XCTest
@testable import InfiniteBrainCore

final class NodeTypeTests: XCTestCase {
    func testAllSixteenNodeTypesPresent() {
        XCTAssertEqual(NodeType.allCases.count, 16)
    }

    func testAllTenEdgeTypesPresent() {
        XCTAssertEqual(EdgeType.allCases.count, 10)
    }
}
