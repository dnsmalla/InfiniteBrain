// Tests/InfiniteBrainTests/UAParserTests.swift
import XCTest
@testable import InfiniteBrainCore

final class UAParserTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: "/repo")

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/CodeGraph/\(name)", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testParsesSimpleGraph() throws {
        let data = try fixture("simple")
        let result = try UAParser.parse(data: data, repoRoot: repoRoot)
        XCTAssertEqual(result.nodes.count, 3)
        XCTAssertEqual(result.edges.count, 2)

        let file = try XCTUnwrap(result.nodes.first { $0.id == "file:App.swift" })
        XCTAssertEqual(file.kind, .file)
        XCTAssertEqual(file.title, "App.swift")
        XCTAssertTrue(file.metadata["fileURL"]?.contains("App.swift") == true)

        let cls = try XCTUnwrap(result.nodes.first { $0.id == "cls:App" })
        XCTAssertEqual(cls.kind, .classType)
        XCTAssertEqual(cls.metadata["line"], "L10-L50")

        let edge = try XCTUnwrap(result.edges.first { $0.fromId == "cls:App" })
        XCTAssertEqual(edge.kind, .contains)
    }

    func testUnknownNodeTypesMapsToOther() throws {
        let data = try fixture("unknown-kinds")
        let result = try UAParser.parse(data: data, repoRoot: repoRoot)
        XCTAssertEqual(result.nodes.first { $0.id == "a" }?.kind, .other)
        XCTAssertEqual(result.nodes.first { $0.id == "b" }?.kind, .function)
        XCTAssertEqual(result.edges.first?.kind, .relatedTo)
    }

    func testMissingNodesFieldThrows() {
        let data = #"{"version":"1.0.0"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try UAParser.parse(data: data, repoRoot: repoRoot)) { err in
            guard case UAError.parseFailed = err else {
                return XCTFail("expected parseFailed, got \(err)")
            }
        }
    }

    func testEmptyGraphParsesClean() throws {
        let data = #"{"version":"1.0.0","nodes":[],"edges":[]}"#.data(using: .utf8)!
        let result = try UAParser.parse(data: data, repoRoot: repoRoot)
        XCTAssertTrue(result.nodes.isEmpty)
        XCTAssertTrue(result.edges.isEmpty)
    }

    func testLayersAndTourParsed() throws {
        let json = """
        {
          "version": "1.0.0",
          "nodes": [{"id":"n1","type":"file","name":"Foo.swift","filePath":"Foo.swift"}],
          "edges": [],
          "layers": [{"id":"l1","name":"Core","description":"Core layer","nodeIds":["n1"]}],
          "tour":   [{"order":1,"title":"Start","description":"Entry point","nodeIds":["n1"]}]
        }
        """.data(using: .utf8)!
        let result = try UAParser.parse(data: json, repoRoot: repoRoot)
        XCTAssertEqual(result.layers.count, 1)
        XCTAssertEqual(result.layers[0].name, "Core")
        XCTAssertEqual(result.tour.count, 1)
        XCTAssertEqual(result.tour[0].title, "Start")
        XCTAssertEqual(result.tour[0].nodeId, "n1")
    }

    func testLineRangeSingleEntry() throws {
        let json = """
        {"version":"1.0.0",
         "nodes":[{"id":"f","type":"function","name":"go","filePath":"a.swift","lineRange":[5]}],
         "edges":[]}
        """.data(using: .utf8)!
        let result = try UAParser.parse(data: json, repoRoot: repoRoot)
        XCTAssertEqual(result.nodes.first?.metadata["line"], "L5")
    }

    func testRelativeFilePathResolvedAgainstRepoRoot() throws {
        let root = URL(fileURLWithPath: "/workspace/myrepo")
        let json = """
        {"version":"1.0.0",
         "nodes":[{"id":"f","type":"file","name":"Foo.swift","filePath":"Sources/Foo.swift"}],
         "edges":[]}
        """.data(using: .utf8)!
        let result = try UAParser.parse(data: json, repoRoot: root)
        let fileURL = try XCTUnwrap(result.nodes.first?.metadata["fileURL"])
        XCTAssertEqual(fileURL, "file:///workspace/myrepo/Sources/Foo.swift")
    }
}
