import XCTest
@testable import InfiniteBrainCore

final class Phase6OptimizationTests: XCTestCase {

    /// Verifies the Barnes-Hut quad-tree keeps each physics tick under the
    /// 33ms budget at high node counts. CGSimulation replaces the old
    /// GraphSimulation — same algorithm, unified types.
    func testQuadTreePerformance() {
        let nodeCount = 1000
        let nodes = (0..<nodeCount).map { i in
            CGNode(id: "\(i)", title: "Node \(i)", kind: .file,
                   position: CGPoint(x: CGFloat(i % 50) * 20,
                                     y: CGFloat(i / 50) * 20))
        }
        let data = CGData(nodes: nodes, edges: [])
        let simulation = CGSimulation(data: data)

        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<10 { simulation.tick() }
        let end = CFAbsoluteTimeGetCurrent()
        let avgTime = (end - start) / 10.0
        print("AVERAGE STEP TIME (1000 nodes): \(String(format: "%.4f", avgTime))s")
        XCTAssertLessThan(avgTime, 0.033,
                          "Physics step should stay under 33ms for 30fps baseline at 1000 nodes")
    }

    func testMetadataIndexPersistence() async throws {
        let fm = FileManager.default
        let tempURL = fm.temporaryDirectory.appendingPathComponent("test_meta.bin")
        defer { try? fm.removeItem(at: tempURL) }

        let index = MetadataIndex(storeURL: tempURL)
        let note = Note(
            id: "note1", type: .note, title: "Persistence Test",
            summary: "Testing binary save/load", body: "Hello World",
            edges: [Edge(type: .relatedTo, target: "target1", evidence: nil)],
            sources: ["source1"], contentHash: "hash1", version: 1,
            createdAt: Date(), updatedAt: Date()
        )

        await index.update(note)
        try await index.save()

        let index2 = MetadataIndex(storeURL: tempURL)
        let loaded = await index2.load()
        XCTAssertTrue(loaded)

        let entries = await index2.allEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id, "note1")
        XCTAssertEqual(entries[0].title, "Persistence Test")
        XCTAssertEqual(entries[0].edges.count, 1)
        XCTAssertEqual(entries[0].edges[0].targetId, "target1")

        let backlinks = await index2.getBacklinks(for: "source1")
        XCTAssertTrue(backlinks.contains("note1"))
    }
}
