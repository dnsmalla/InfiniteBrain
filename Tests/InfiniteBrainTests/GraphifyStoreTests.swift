import XCTest
@testable import InfiniteBrainCore

final class UAStoreTests: XCTestCase {
    private var tempDir: URL!
    private var store: UAStore!
    private let target = URL(fileURLWithPath: "/some/repo/path")

    override func setUp() {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = UAStore(baseDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSaveAndLoadGraphJSON() throws {
        let json = #"{"version":"1.0.0","nodes":[],"edges":[]}"#.data(using: .utf8)!
        try store.save(graphJSON: json, for: target, nodeCount: 0, edgeCount: 0, toolVersion: "1.0.0")
        XCTAssertEqual(store.loadGraphJSON(for: target), json)
    }

    func testLastRunMetadata() throws {
        try store.save(graphJSON: Data(), for: target, nodeCount: 5, edgeCount: 3, toolVersion: "2.1.0")
        let meta = try XCTUnwrap(store.lastRun(for: target))
        XCTAssertEqual(meta.nodeCount, 5)
        XCTAssertEqual(meta.edgeCount, 3)
        XCTAssertEqual(meta.toolVersion, "2.1.0")
    }

    func testLoadMissingReturnsNil() {
        let unknown = URL(fileURLWithPath: "/nonexistent/path")
        XCTAssertNil(store.loadGraphJSON(for: unknown))
        XCTAssertNil(store.lastRun(for: unknown))
    }

    func testInvalidateRemovesCache() throws {
        try store.save(graphJSON: Data("x".utf8), for: target, nodeCount: 1, edgeCount: 0, toolVersion: "1.0")
        store.invalidate(for: target)
        XCTAssertNil(store.loadGraphJSON(for: target))
    }

    func testDifferentTargetsHaveSeparateEntries() throws {
        let a = URL(fileURLWithPath: "/repo/a")
        let b = URL(fileURLWithPath: "/repo/b")
        let jsonA = Data("A".utf8), jsonB = Data("B".utf8)
        try store.save(graphJSON: jsonA, for: a, nodeCount: 1, edgeCount: 0, toolVersion: "1.0")
        try store.save(graphJSON: jsonB, for: b, nodeCount: 2, edgeCount: 0, toolVersion: "1.0")
        XCTAssertEqual(store.loadGraphJSON(for: a), jsonA)
        XCTAssertEqual(store.loadGraphJSON(for: b), jsonB)
    }
}
