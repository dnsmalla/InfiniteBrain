// GraphNodeMetadataTests now tests CGNode metadata — the unified node type
// used by both the Code Graph and Knowledge Graph. GraphNode was removed
// when GraphView migrated to CGData.
import XCTest
import CoreGraphics
@testable import InfiniteBrainCore

final class GraphNodeMetadataTests: XCTestCase {

    func testDefaultMetadataIsEmpty() {
        let n = CGNode(id: "1", title: "t", kind: .noteConcept, position: .zero)
        XCTAssertTrue(n.metadata.isEmpty)
    }

    func testMetadataRoundTrips() {
        let n = CGNode(id: "1", title: "t", kind: .file, position: .zero,
                       metadata: ["fileURL": "file:///tmp/a.swift"])
        XCTAssertEqual(n.metadata["fileURL"], "file:///tmp/a.swift")
    }

    func testKnowledgeGraphKindMapping() {
        // Verify that all vault NodeType raw values map to a known CGNodeKind.
        let vaultTypes = ["decision", "concept", "question", "task", "hypothesis",
                          "fact", "source", "playbook", "event", "pillar",
                          "note", "contact", "reference", "custom"]
        for raw in vaultTypes {
            let kind = CGNodeKind.from(raw)
            XCTAssertNotEqual(kind, .file,
                              "\(raw) should map to a knowledge-graph kind, not .file")
        }
    }

    func testCodeFileTypesMapCorrectly() {
        XCTAssertEqual(CGNodeKind.from("code_file"),   .file)
        XCTAssertEqual(CGNodeKind.from("code_symbol"), .symbol)
        XCTAssertEqual(CGNodeKind.from("code_module"), .module)
        XCTAssertEqual(CGNodeKind.from("doc_page"),    .docPage)
    }

    func testUnknownTypesMapsToOther() {
        XCTAssertEqual(CGNodeKind.from("totally_unknown"), .other)
    }
}
