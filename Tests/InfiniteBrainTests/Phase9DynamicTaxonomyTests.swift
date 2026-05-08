import XCTest
@testable import InfiniteBrainCore

final class Phase9DynamicTaxonomyTests: XCTestCase {
    func testCustomNodeTypeRoundTrip() throws {
        let type: NodeType = "legal-clause"
        let note = Note(
            id: "test-123",
            type: type,
            title: "Indemnity Clause",
            summary: "Standard indemnity for third-party claims.",
            body: "The parties agree to indemnify...",
            edges: [],
            sources: [],
            contentHash: "hash-123",
            version: 1,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let serialized = NoteSerializer.serialize(note)
        XCTAssertTrue(serialized.contains("type: legal-clause"))
        
        let parsed = try NoteSerializer.parse(serialized)
        XCTAssertEqual(parsed.type, type)
        XCTAssertEqual(parsed.type.rawValue, "legal-clause")
    }
    
    func testLegacyNodeTypeConsistency() throws {
        // Verify standard constants still work
        let type = NodeType.pillar
        XCTAssertEqual(type.rawValue, "pillar")
        XCTAssertEqual(type, "pillar")
    }
}
