import XCTest
@testable import InfiniteBrainCore

final class NodeTypeTests: XCTestCase {
    func testAllTwentyNodeTypesPresent() {
        XCTAssertEqual(NodeType.allCases.count, 20)
    }

    func testAllTenEdgeTypesPresent() {
        XCTAssertEqual(EdgeType.allCases.count, 10)
    }

    func testCodeGraphNodeTypeConstants() {
        XCTAssertEqual(NodeType.codeFile.rawValue, "code_file")
        XCTAssertEqual(NodeType.codeSymbol.rawValue, "code_symbol")
        XCTAssertEqual(NodeType.codeModule.rawValue, "code_module")
        XCTAssertEqual(NodeType.docPage.rawValue, "doc_page")
        let all = NodeType.allCases
        XCTAssertTrue(all.contains(.codeFile))
        XCTAssertTrue(all.contains(.codeSymbol))
        XCTAssertTrue(all.contains(.codeModule))
        XCTAssertTrue(all.contains(.docPage))
    }
}
