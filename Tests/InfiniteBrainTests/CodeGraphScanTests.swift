import XCTest
@testable import InfiniteBrainCore

final class CodeGraphScanTests: XCTestCase {

    // MARK: - PythonASTExtractor.parseRich

    func testParseRichExtractsSymbolWithParent() throws {
        let json = """
        {
          "src/service.ts": {
            "language": "typescript", "loc": 20,
            "imports": [{"module": "./base", "line": 1}],
            "symbols": [
              {"name": "UserService", "kind": "class",  "line": 3,  "parent": null, "declaration": "class UserService"},
              {"name": "UserService.fetch", "kind": "method", "line": 5, "parent": "UserService", "declaration": "fetch()"}
            ],
            "inherits":   [{"child": "UserService", "parent": "BaseService"}],
            "implements": [{"class_name": "UserService", "interface_name": "IService"}],
            "calls":      [{"caller": "UserService", "callee": "parse", "line": 6}]
          }
        }
        """.data(using: .utf8)!

        let raws = try PythonASTExtractor.parseRich(json)
        XCTAssertEqual(raws.count, 1)
        let r = raws[0]
        XCTAssertEqual(r.language, "typescript")
        XCTAssertEqual(r.symbols.count, 2)

        let method = r.symbols.first { $0.kind == "method" }
        XCTAssertEqual(method?.parent, "UserService")
        XCTAssertEqual(method?.name, "UserService.fetch")

        XCTAssertEqual(r.inherits.count, 1)
        XCTAssertEqual(r.inherits[0].child, "UserService")
        XCTAssertEqual(r.inherits[0].parent, "BaseService")

        XCTAssertEqual(r.implements.count, 1)
        XCTAssertEqual(r.implements[0].className, "UserService")
        XCTAssertEqual(r.implements[0].interfaceName, "IService")

        XCTAssertEqual(r.calls.count, 1)
        XCTAssertEqual(r.calls[0].caller, "UserService")
        XCTAssertEqual(r.calls[0].callee, "parse")
    }

    // MARK: - StructureGraphBuilder method→class edge

    func testMethodLinkedToClassNotFile() {
        let symbols: [ScanResult.Symbol] = [
            .init(name: "UserService",       kind: "class",  line: 1),
            .init(name: "UserService.fetch", kind: "method", line: 5,
                  declaration: "fetch()", parent: "UserService"),
        ]
        let scan = ScanResult(
            files: [.init(path: "src/service.ts", language: "typescript", loc: 10)],
            imports: [:],
            symbols: ["src/service.ts": symbols]
        )
        let data = StructureGraphBuilder.build(scan, repoRoot: URL(fileURLWithPath: "/repo"))

        let classNode  = data.nodes.first { $0.kind == .classType }
        let methodNode = data.nodes.first { $0.title == "UserService.fetch" }
        XCTAssertNotNil(classNode,  "class node must exist")
        XCTAssertNotNil(methodNode, "method node must exist")

        let containsEdge = data.edges.first {
            $0.fromId == classNode?.id && $0.toId == methodNode?.id && $0.kind == .contains
        }
        XCTAssertNotNil(containsEdge, "method should be linked to class via contains edge")

        let fileEdge = data.edges.first {
            $0.fromId == "file:src/service.ts" && $0.toId == methodNode?.id
        }
        XCTAssertNil(fileEdge, "method should NOT be directly linked to file")
    }

    func testInheritsEdgeCreated() {
        let symbols: [ScanResult.Symbol] = [
            .init(name: "BaseService", kind: "class", line: 1),
            .init(name: "UserService", kind: "class", line: 10),
        ]
        let scan = ScanResult(
            files: [.init(path: "src/s.ts", language: "typescript", loc: 20)],
            imports: [:],
            symbols: ["src/s.ts": symbols],
            inherits: ["src/s.ts": [.init(child: "UserService", parent: "BaseService")]]
        )
        let data = StructureGraphBuilder.build(scan, repoRoot: URL(fileURLWithPath: "/repo"))

        let edge = data.edges.first { $0.kind == .inherits }
        XCTAssertNotNil(edge, "inherits edge must exist")
        XCTAssertEqual(edge?.confidence, .extracted)
    }

    func testImplementsEdgeCreated() {
        let symbols: [ScanResult.Symbol] = [
            .init(name: "IService",    kind: "interface", line: 1),
            .init(name: "UserService", kind: "class",     line: 10),
        ]
        let scan = ScanResult(
            files: [.init(path: "src/s.ts", language: "typescript", loc: 20)],
            imports: [:],
            symbols: ["src/s.ts": symbols],
            implements: ["src/s.ts": [.init(className: "UserService", interfaceName: "IService")]]
        )
        let data = StructureGraphBuilder.build(scan, repoRoot: URL(fileURLWithPath: "/repo"))

        let edge = data.edges.first { $0.kind == .implements }
        XCTAssertNotNil(edge, "implements edge must exist")
        XCTAssertEqual(edge?.confidence, .extracted)
    }

    func testCallsEdgeIsInferred() {
        let symbols: [ScanResult.Symbol] = [
            .init(name: "Parser",      kind: "class", line: 1),
            .init(name: "UserService", kind: "class", line: 10),
        ]
        let scan = ScanResult(
            files: [.init(path: "src/s.ts", language: "typescript", loc: 20)],
            imports: [:],
            symbols: ["src/s.ts": symbols],
            calls: ["src/s.ts": [.init(caller: "UserService", callee: "Parser", line: 15)]]
        )
        let data = StructureGraphBuilder.build(scan, repoRoot: URL(fileURLWithPath: "/repo"))

        let edge = data.edges.first { $0.kind == .calls }
        XCTAssertNotNil(edge, "calls edge must exist")
        XCTAssertEqual(edge?.confidence, .inferred)
    }

    func testImportEdgeConfidenceIsExtracted() {
        let scan = ScanResult(
            files: [.init(path: "a.ts", language: "typescript", loc: 5),
                    .init(path: "b.ts", language: "typescript", loc: 5)],
            imports: ["a.ts": ["b.ts"]],
            symbols: [:]
        )
        let data = StructureGraphBuilder.build(scan, repoRoot: URL(fileURLWithPath: "/repo"))
        let edge = data.edges.first { $0.kind == .imports }
        XCTAssertEqual(edge?.confidence, .extracted)
    }
}
