import XCTest
@testable import InfiniteBrainCore

final class EdgeTypeTests: XCTestCase {
    func testCodeGraphEdgeCases() {
        XCTAssertEqual(EdgeType.imports.rawValue, "imports")
        XCTAssertEqual(EdgeType.calls.rawValue, "calls")
        XCTAssertEqual(EdgeType.references.rawValue, "references")
        XCTAssertEqual(EdgeType.defines.rawValue, "defines")
    }

    func testEdgeTypeAllCasesIncludesNew() {
        let all = Set(EdgeType.allCases)
        XCTAssertTrue(all.isSuperset(of: [.imports, .calls, .references, .defines]))
    }

    func testEdgeTypeRoundTripsThroughJSON() throws {
        for c in EdgeType.allCases {
            let json = try JSONEncoder().encode(c)
            let back = try JSONDecoder().decode(EdgeType.self, from: json)
            XCTAssertEqual(c, back)
        }
    }
}
