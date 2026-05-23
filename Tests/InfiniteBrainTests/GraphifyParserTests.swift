import XCTest
@testable import InfiniteBrainCore

final class GraphifyParserTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/CodeGraph/\(name)", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testParsesSimpleGraph() throws {
        let data = try fixture("simple")
        let result = try GraphifyParser.parse(data: data)
        XCTAssertEqual(result.nodes.count, 3)
        XCTAssertEqual(result.edges.count, 2)

        let file = try XCTUnwrap(result.nodes.first { $0.id == "n1" })
        XCTAssertEqual(file.type, .codeFile)
        XCTAssertEqual(file.title, "App.swift")
        XCTAssertEqual(file.metadata?["fileURL"], "file:///repo/App.swift")

        let cls = try XCTUnwrap(result.nodes.first { $0.id == "n2" })
        XCTAssertEqual(cls.type, .codeSymbol)
        XCTAssertEqual(cls.metadata?["line"], "10")

        let definesEdge = try XCTUnwrap(result.edges.first { $0.fromId == "n2" && $0.toId == "n3" })
        XCTAssertEqual(definesEdge.type, .defines)
    }

    func testUnknownKindsMapToFallbacks() throws {
        let data = try fixture("unknown-kinds")
        let result = try GraphifyParser.parse(data: data)
        XCTAssertEqual(result.nodes.first { $0.id == "a" }?.type, .custom)
        XCTAssertEqual(result.nodes.first { $0.id == "a" }?.metadata?["graphify_kind"], "unicorn")
        XCTAssertEqual(result.nodes.first { $0.id == "b" }?.type, .docPage)
        XCTAssertEqual(result.edges.first?.type, .relatedTo)
    }

    func testUnsupportedSchemaThrows() throws {
        let data = try fixture("bad-schema")
        XCTAssertThrowsError(try GraphifyParser.parse(data: data)) { err in
            guard case GraphifyError.unsupportedSchema(let v) = err else {
                return XCTFail("expected unsupportedSchema, got \(err)")
            }
            XCTAssertEqual(v, "99")
        }
    }

    func testEmptyGraph() throws {
        let data = #"{"version":"1","nodes":[],"edges":[]}"#.data(using: .utf8)!
        let result = try GraphifyParser.parse(data: data)
        XCTAssertTrue(result.nodes.isEmpty)
        XCTAssertTrue(result.edges.isEmpty)
    }
}
