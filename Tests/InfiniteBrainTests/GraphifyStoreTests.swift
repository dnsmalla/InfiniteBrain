import XCTest
@testable import InfiniteBrainCore

final class GraphifyStoreTests: XCTestCase {
    private var tmp: URL!
    private var store: GraphifyStore!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("graphify-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        store = GraphifyStore(baseDirectory: tmp)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testSaveAndLoadRoundTrip() throws {
        let target = URL(fileURLWithPath: "/some/project")
        let data = #"{"version":"1","nodes":[],"edges":[]}"#.data(using: .utf8)!
        try store.save(graphJSON: data, for: target, nodeCount: 0, edgeCount: 0, graphifyVersion: "test")
        let loaded = try XCTUnwrap(store.loadGraphJSON(for: target))
        XCTAssertEqual(loaded, data)
        let meta = try XCTUnwrap(store.lastRun(for: target))
        XCTAssertEqual(meta.graphifyVersion, "test")
    }

    func testHashIsStableAcrossInstances() {
        let target = URL(fileURLWithPath: "/some/project")
        XCTAssertEqual(GraphifyStore.directoryName(for: target),
                       GraphifyStore.directoryName(for: target))
    }
}
