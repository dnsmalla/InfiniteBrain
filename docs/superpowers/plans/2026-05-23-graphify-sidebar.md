# Graphify Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Code Graph" sidebar tab that runs the external Graphify CLI on a user-picked folder, parses its `graph.json`, renders it via a shared `GraphCanvas`, and opens source files on node click.

**Architecture:** Reuse `GraphData` / `GraphSimulation`. Extend `NodeType` (open struct) and `EdgeType` (closed enum) additively. Add an optional `metadata: [String:String]?` to `GraphNode` for file URLs. Extract a pure `GraphCanvas` view from the existing `GraphView` so both knowledge and code graphs share rendering. Wrap Graphify in a `Process`-based runner behind a `ProcessLauncher` protocol for testability.

**Tech Stack:** Swift 5.9 / SwiftUI / XCTest / SwiftPM (macOS 14+). External tool: `graphify` (Python, `uv tool install graphifyy`).

**Design spec:** [docs/superpowers/specs/2026-05-23-graphify-sidebar-design.md](../specs/2026-05-23-graphify-sidebar-design.md)

---

## Task 1: Extend `NodeType` with code-graph constants

**Files:**
- Modify: `Sources/InfiniteBrainCore/Models/NodeType.swift`
- Test: `Tests/InfiniteBrainTests/NodeTypeTests.swift`

- [ ] **Step 1: Add the failing test**

Append to `Tests/InfiniteBrainTests/NodeTypeTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the test (expect failure)**

```bash
cd /Users/dinsmallade/InfiniteBrain
swift test --filter NodeTypeTests/testCodeGraphNodeTypeConstants
```

Expected: FAIL with `value of type 'NodeType.Type' has no member 'codeFile'`.

- [ ] **Step 3: Add the constants**

In `Sources/InfiniteBrainCore/Models/NodeType.swift`, add four constants below `.custom` and extend `allCases`:

```swift
    public static let custom: NodeType = "custom"

    // Code-graph types (Graphify integration)
    public static let codeFile:   NodeType = "code_file"
    public static let codeSymbol: NodeType = "code_symbol"
    public static let codeModule: NodeType = "code_module"
    public static let docPage:    NodeType = "doc_page"

    public static var allCases: [NodeType] {
        [.pillar, .decision, .concept, .question, .playbook, .task, .event,
         .pattern, .hypothesis, .fact, .source, .bookmark, .note, .contact,
         .reference, .custom,
         .codeFile, .codeSymbol, .codeModule, .docPage]
    }
```

- [ ] **Step 4: Run the test (expect pass)**

```bash
swift test --filter NodeTypeTests
```

Expected: all NodeType tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/InfiniteBrainCore/Models/NodeType.swift Tests/InfiniteBrainTests/NodeTypeTests.swift
git commit -m "feat(core): add code-graph NodeType constants"
```

---

## Task 2: Extend `EdgeType` with code-graph cases

**Files:**
- Modify: `Sources/InfiniteBrainCore/Models/EdgeType.swift`
- Test: `Tests/InfiniteBrainTests/EdgeTypeTests.swift` (new)

- [ ] **Step 1: Create the failing test file**

Create `Tests/InfiniteBrainTests/EdgeTypeTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the test (expect failure)**

```bash
swift test --filter EdgeTypeTests
```

Expected: FAIL with `type 'EdgeType' has no member 'imports'`.

- [ ] **Step 3: Add the cases**

Edit `Sources/InfiniteBrainCore/Models/EdgeType.swift`:

```swift
public enum EdgeType: String, Codable, CaseIterable, Sendable {
    case supports
    case contradicts
    case dependsOn = "depends_on"
    case derivedFrom = "derived_from"
    case relatedTo = "related_to"
    case partOf = "part_of"
    case precededBy = "preceded_by"
    case followedBy = "followed_by"
    case authored
    case tagging

    // Code-graph relationships (Graphify integration)
    case imports
    case calls
    case references
    case defines
}
```

- [ ] **Step 4: Run the test (expect pass)**

```bash
swift test --filter EdgeTypeTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/InfiniteBrainCore/Models/EdgeType.swift Tests/InfiniteBrainTests/EdgeTypeTests.swift
git commit -m "feat(core): add code-graph EdgeType cases"
```

---

## Task 3: Add optional `metadata` to `GraphNode`

**Files:**
- Modify: `Sources/InfiniteBrainCore/Graph/GraphLayout.swift:6-15`
- Test: `Tests/InfiniteBrainTests/GraphNodeMetadataTests.swift` (new)

The new field is **optional** and the existing init keeps its old signature; a second init accepts metadata so no caller breaks.

- [ ] **Step 1: Add the failing test**

Create `Tests/InfiniteBrainTests/GraphNodeMetadataTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import InfiniteBrainCore

final class GraphNodeMetadataTests: XCTestCase {
    func testLegacyInitLeavesMetadataNil() {
        let n = GraphNode(id: "1", title: "t", type: .concept, summary: "s",
                          position: .zero)
        XCTAssertNil(n.metadata)
    }

    func testInitWithMetadata() {
        let n = GraphNode(id: "1", title: "t", type: .codeFile, summary: "s",
                          position: .zero,
                          metadata: ["fileURL": "file:///tmp/a.swift"])
        XCTAssertEqual(n.metadata?["fileURL"], "file:///tmp/a.swift")
    }
}
```

- [ ] **Step 2: Run the test (expect failure)**

```bash
swift test --filter GraphNodeMetadataTests
```

Expected: FAIL with `extra argument 'metadata' in call` or similar.

- [ ] **Step 3: Add the field and second init**

Edit `Sources/InfiniteBrainCore/Graph/GraphLayout.swift`, replace the `GraphNode` struct (lines 6–15):

```swift
public struct GraphNode: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let type: NodeType
    public let summary: String
    public var position: CGPoint
    public let metadata: [String: String]?

    public init(id: String, title: String, type: NodeType, summary: String, position: CGPoint) {
        self.id = id; self.title = title; self.type = type; self.summary = summary
        self.position = position; self.metadata = nil
    }

    public init(id: String, title: String, type: NodeType, summary: String, position: CGPoint, metadata: [String: String]?) {
        self.id = id; self.title = title; self.type = type; self.summary = summary
        self.position = position; self.metadata = metadata
    }
}
```

- [ ] **Step 4: Run all tests (expect pass; existing GraphLayoutTests must still pass)**

```bash
swift test
```

Expected: full suite PASSES.

- [ ] **Step 5: Commit**

```bash
git add Sources/InfiniteBrainCore/Graph/GraphLayout.swift Tests/InfiniteBrainTests/GraphNodeMetadataTests.swift
git commit -m "feat(core): add optional metadata to GraphNode"
```

---

## Task 4: Define `GraphifyError` and `ProcessLauncher` protocol

**Files:**
- Create: `Sources/InfiniteBrainCore/CodeGraph/GraphifyError.swift`
- Create: `Sources/InfiniteBrainCore/CodeGraph/ProcessLauncher.swift`

- [ ] **Step 1: Create error type**

Create `Sources/InfiniteBrainCore/CodeGraph/GraphifyError.swift`:

```swift
import Foundation

public enum GraphifyError: Error, Equatable {
    case binaryMissing
    case runFailed(exitCode: Int32, stderrTail: String)
    case parseFailed(message: String)
    case unsupportedSchema(version: String)
    case cancelled
}
```

- [ ] **Step 2: Create the launcher protocol**

Create `Sources/InfiniteBrainCore/CodeGraph/ProcessLauncher.swift`:

```swift
import Foundation

/// Minimal seam for unit testing GraphifyRunner without spawning processes.
public protocol ProcessLauncher: Sendable {
    /// Returns (exitCode, stdoutData, stderrData). Throws on cancellation.
    func run(executable: URL, arguments: [String], environment: [String: String]?) async throws -> (Int32, Data, Data)
}

public struct SystemProcessLauncher: ProcessLauncher {
    public init() {}

    public func run(executable: URL, arguments: [String], environment: [String: String]?) async throws -> (Int32, Data, Data) {
        try await withCheckedThrowingContinuation { cont in
            let proc = Process()
            proc.executableURL = executable
            proc.arguments = arguments
            if let env = environment { proc.environment = env }
            let outPipe = Pipe(); let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            proc.terminationHandler = { p in
                let out = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let err = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                cont.resume(returning: (p.terminationStatus, out ?? Data(), err ?? Data()))
            }
            do { try proc.run() } catch { cont.resume(throwing: error) }
        }
    }
}
```

- [ ] **Step 3: Build to confirm compilation**

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/InfiniteBrainCore/CodeGraph/
git commit -m "feat(codegraph): add GraphifyError and ProcessLauncher seam"
```

---

## Task 5: `GraphifyParser` with golden fixtures

**Files:**
- Create: `Sources/InfiniteBrainCore/CodeGraph/GraphifyParser.swift`
- Create: `Tests/InfiniteBrainTests/Fixtures/CodeGraph/simple.json`
- Create: `Tests/InfiniteBrainTests/Fixtures/CodeGraph/unknown-kinds.json`
- Create: `Tests/InfiniteBrainTests/Fixtures/CodeGraph/bad-schema.json`
- Create: `Tests/InfiniteBrainTests/GraphifyParserTests.swift`
- Modify: `Package.swift` (add fixtures resource to test target)

Schema assumed (pinned, version `"1"`):

```json
{
  "version": "1",
  "nodes": [
    {"id": "n1", "kind": "file",     "name": "App.swift",   "path": "/repo/App.swift"},
    {"id": "n2", "kind": "class",    "name": "App",         "path": "/repo/App.swift", "line": 10},
    {"id": "n3", "kind": "function", "name": "main",        "path": "/repo/App.swift", "line": 30}
  ],
  "edges": [
    {"from": "n2", "to": "n3", "kind": "defines"},
    {"from": "n1", "to": "n2", "kind": "defines"}
  ]
}
```

- [ ] **Step 1: Add fixtures**

Create `Tests/InfiniteBrainTests/Fixtures/CodeGraph/simple.json` with the schema above.

Create `Tests/InfiniteBrainTests/Fixtures/CodeGraph/unknown-kinds.json`:

```json
{"version":"1",
 "nodes":[
   {"id":"a","kind":"unicorn","name":"u","path":"/x.swift"},
   {"id":"b","kind":"markdown_section","name":"Intro","path":"/README.md"}
 ],
 "edges":[
   {"from":"a","to":"b","kind":"teleports"}
 ]}
```

Create `Tests/InfiniteBrainTests/Fixtures/CodeGraph/bad-schema.json`:

```json
{"version":"99","nodes":[],"edges":[]}
```

- [ ] **Step 2: Wire fixtures into the test target**

Edit `Package.swift`, replace the `.testTarget` block:

```swift
        .testTarget(
            name: "InfiniteBrainTests",
            dependencies: ["InfiniteBrainCore"],
            path: "Tests/InfiniteBrainTests",
            resources: [
                .copy("Fixtures")
            ]
        )
```

- [ ] **Step 3: Add the failing test**

Create `Tests/InfiniteBrainTests/GraphifyParserTests.swift`:

```swift
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
```

- [ ] **Step 4: Run the test (expect failure)**

```bash
swift test --filter GraphifyParserTests
```

Expected: FAIL — `GraphifyParser` doesn't exist.

- [ ] **Step 5: Implement the parser**

Create `Sources/InfiniteBrainCore/CodeGraph/GraphifyParser.swift`:

```swift
import Foundation
import CoreGraphics

public enum GraphifyParser {
    public static let supportedSchemaVersion = "1"

    private struct RawGraph: Decodable {
        let version: String
        let nodes: [RawNode]
        let edges: [RawEdge]
    }
    private struct RawNode: Decodable {
        let id: String
        let kind: String
        let name: String
        let path: String?
        let line: Int?
        let language: String?
    }
    private struct RawEdge: Decodable {
        let from: String
        let to: String
        let kind: String
    }

    public static func parse(data: Data) throws -> GraphData {
        let raw: RawGraph
        do {
            raw = try JSONDecoder().decode(RawGraph.self, from: data)
        } catch {
            throw GraphifyError.parseFailed(message: String(describing: error))
        }
        guard raw.version == supportedSchemaVersion else {
            throw GraphifyError.unsupportedSchema(version: raw.version)
        }

        let nodes: [GraphNode] = raw.nodes.map { rn in
            let (type, originalKind) = mapNodeKind(rn.kind)
            var meta: [String: String] = [:]
            if let p = rn.path { meta["fileURL"] = URL(fileURLWithPath: p).absoluteString }
            if let l = rn.line { meta["line"] = String(l) }
            if let lang = rn.language { meta["language"] = lang }
            if let original = originalKind { meta["graphify_kind"] = original }
            return GraphNode(
                id: rn.id, title: rn.name, type: type, summary: "",
                position: .zero,
                metadata: meta.isEmpty ? nil : meta
            )
        }
        let edges: [GraphEdge] = raw.edges.map { re in
            GraphEdge(fromId: re.from, toId: re.to, type: mapEdgeKind(re.kind))
        }
        return GraphData(nodes: nodes, edges: edges)
    }

    private static func mapNodeKind(_ k: String) -> (NodeType, String?) {
        switch k {
        case "file":                       return (.codeFile, nil)
        case "class", "struct",
             "function", "method":         return (.codeSymbol, nil)
        case "module", "package":          return (.codeModule, nil)
        case "markdown_section", "doc":    return (.docPage, nil)
        default:                           return (.custom, k)
        }
    }

    private static func mapEdgeKind(_ k: String) -> EdgeType {
        switch k {
        case "imports":              return .imports
        case "calls":                return .calls
        case "references", "uses":   return .references
        case "defines", "declares":  return .defines
        default:                     return .relatedTo
        }
    }
}
```

- [ ] **Step 6: Run the test (expect pass)**

```bash
swift test --filter GraphifyParserTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/InfiniteBrainCore/CodeGraph/GraphifyParser.swift \
        Tests/InfiniteBrainTests/Fixtures/ \
        Tests/InfiniteBrainTests/GraphifyParserTests.swift \
        Package.swift
git commit -m "feat(codegraph): add GraphifyParser with golden fixtures"
```

---

## Task 6: `GraphifyStore` (disk cache)

**Files:**
- Create: `Sources/InfiniteBrainCore/CodeGraph/GraphifyStore.swift`
- Create: `Tests/InfiniteBrainTests/GraphifyStoreTests.swift`

- [ ] **Step 1: Add the failing test**

Create `Tests/InfiniteBrainTests/GraphifyStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the test (expect failure)**

```bash
swift test --filter GraphifyStoreTests
```

Expected: FAIL — `GraphifyStore` doesn't exist.

- [ ] **Step 3: Implement the store**

Create `Sources/InfiniteBrainCore/CodeGraph/GraphifyStore.swift`:

```swift
import Foundation
import CryptoKit

public struct RunMetadata: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let nodeCount: Int
    public let edgeCount: Int
    public let graphifyVersion: String
}

public final class GraphifyStore {
    private let baseDirectory: URL
    private let fm = FileManager.default

    public init(baseDirectory: URL? = nil) {
        if let b = baseDirectory {
            self.baseDirectory = b
        } else {
            let appSupport = try! FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
            self.baseDirectory = appSupport
                .appendingPathComponent("InfiniteBrain", isDirectory: true)
                .appendingPathComponent("CodeGraph", isDirectory: true)
        }
    }

    public static func directoryName(for target: URL) -> String {
        let path = target.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func dir(for target: URL) throws -> URL {
        let d = baseDirectory.appendingPathComponent(Self.directoryName(for: target), isDirectory: true)
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    public func save(graphJSON: Data, for target: URL, nodeCount: Int, edgeCount: Int, graphifyVersion: String) throws {
        let d = try dir(for: target)
        try graphJSON.write(to: d.appendingPathComponent("graph.json"), options: .atomic)
        let meta = RunMetadata(timestamp: Date(), nodeCount: nodeCount, edgeCount: edgeCount, graphifyVersion: graphifyVersion)
        let metaData = try JSONEncoder().encode(meta)
        try metaData.write(to: d.appendingPathComponent("meta.json"), options: .atomic)
    }

    public func loadGraphJSON(for target: URL) -> Data? {
        let url = baseDirectory
            .appendingPathComponent(Self.directoryName(for: target), isDirectory: true)
            .appendingPathComponent("graph.json")
        return try? Data(contentsOf: url)
    }

    public func lastRun(for target: URL) -> RunMetadata? {
        let url = baseDirectory
            .appendingPathComponent(Self.directoryName(for: target), isDirectory: true)
            .appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RunMetadata.self, from: data)
    }
}
```

- [ ] **Step 4: Run the test (expect pass)**

```bash
swift test --filter GraphifyStoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/InfiniteBrainCore/CodeGraph/GraphifyStore.swift Tests/InfiniteBrainTests/GraphifyStoreTests.swift
git commit -m "feat(codegraph): add GraphifyStore disk cache"
```

---

## Task 7: `GraphifyRunner` with mockable launcher

**Files:**
- Create: `Sources/InfiniteBrainCore/CodeGraph/GraphifyRunner.swift`
- Create: `Tests/InfiniteBrainTests/GraphifyRunnerTests.swift`

- [ ] **Step 1: Add the failing test**

Create `Tests/InfiniteBrainTests/GraphifyRunnerTests.swift`:

```swift
import XCTest
@testable import InfiniteBrainCore

final class GraphifyRunnerTests: XCTestCase {
    final class MockLauncher: ProcessLauncher, @unchecked Sendable {
        var capturedExecutable: URL?
        var capturedArgs: [String] = []
        var exitCode: Int32 = 0
        var stdout: Data = Data()
        var stderr: Data = Data()
        var writeJSONToOutPath: Data? = nil

        func run(executable: URL, arguments: [String], environment: [String: String]?) async throws -> (Int32, Data, Data) {
            capturedExecutable = executable
            capturedArgs = arguments
            if let payload = writeJSONToOutPath,
               let i = arguments.firstIndex(of: "--json-out"),
               i + 1 < arguments.count {
                try payload.write(to: URL(fileURLWithPath: arguments[i + 1]))
            }
            return (exitCode, stdout, stderr)
        }
    }

    func testInvokesGraphifyWithExpectedArgs() async throws {
        let launcher = MockLauncher()
        let payload = #"{"version":"1","nodes":[],"edges":[]}"#.data(using: .utf8)!
        launcher.writeJSONToOutPath = payload
        let runner = GraphifyRunner(launcher: launcher, binaryURL: URL(fileURLWithPath: "/fake/graphify"))

        let jsonURL = try await runner.run(targetFolder: URL(fileURLWithPath: "/repo")).get()

        XCTAssertEqual(launcher.capturedExecutable, URL(fileURLWithPath: "/fake/graphify"))
        XCTAssertEqual(launcher.capturedArgs.first, "extract")
        XCTAssertTrue(launcher.capturedArgs.contains("--json-out"))
        XCTAssertTrue(launcher.capturedArgs.contains("--quiet"))
        XCTAssertEqual(try Data(contentsOf: jsonURL), payload)
    }

    func testBinaryMissingWhenNoneResolvable() async throws {
        let runner = GraphifyRunner(launcher: MockLauncher(), binaryURL: nil)
        let res = await runner.run(targetFolder: URL(fileURLWithPath: "/repo"))
        XCTAssertEqual(res, .failure(.binaryMissing))
    }

    func testRunFailedSurfacesExitCodeAndStderrTail() async throws {
        let launcher = MockLauncher()
        launcher.exitCode = 2
        launcher.stderr = Data("boom\nbang\n".utf8)
        let runner = GraphifyRunner(launcher: launcher, binaryURL: URL(fileURLWithPath: "/fake/graphify"))
        let res = await runner.run(targetFolder: URL(fileURLWithPath: "/repo"))
        guard case .failure(.runFailed(let code, let tail)) = res else {
            return XCTFail("expected runFailed, got \(res)")
        }
        XCTAssertEqual(code, 2)
        XCTAssertTrue(tail.contains("boom"))
    }

    func testInstallHintLiteralIsCorrect() {
        // Guard against a typo: graphify CLI is installed as `graphifyy` (double-y).
        XCTAssertEqual(GraphifyRunner.installHint, "uv tool install graphifyy")
    }
}
```

- [ ] **Step 2: Run the test (expect failure)**

```bash
swift test --filter GraphifyRunnerTests
```

Expected: FAIL — `GraphifyRunner` doesn't exist.

- [ ] **Step 3: Implement the runner**

Create `Sources/InfiniteBrainCore/CodeGraph/GraphifyRunner.swift`:

```swift
import Foundation

public final class GraphifyRunner {
    public static let installHint = "uv tool install graphifyy"
    private static let fallbackPaths = [
        "/opt/homebrew/bin/graphify",
        "/usr/local/bin/graphify",
        NSString(string: "~/.local/bin/graphify").expandingTildeInPath
    ]

    private let launcher: ProcessLauncher
    private let binaryURL: URL?

    public init(launcher: ProcessLauncher = SystemProcessLauncher(),
                binaryURL: URL? = GraphifyRunner.resolveBinary()) {
        self.launcher = launcher
        self.binaryURL = binaryURL
    }

    public static func resolveBinary() -> URL? {
        // Try `which graphify` via PATH.
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("graphify")
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        for p in fallbackPaths {
            if FileManager.default.isExecutableFile(atPath: p) {
                return URL(fileURLWithPath: p)
            }
        }
        return nil
    }

    /// Runs `graphify extract <folder>` and returns the URL to the generated `graph.json`.
    public func run(targetFolder: URL) async -> Result<URL, GraphifyError> {
        guard let bin = binaryURL else { return .failure(.binaryMissing) }
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("graphify-run-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        } catch {
            return .failure(.runFailed(exitCode: -1, stderrTail: "failed to create temp dir: \(error)"))
        }
        let outJSON = tmpDir.appendingPathComponent("graph.json")
        let args = ["extract", targetFolder.path, "--json-out", outJSON.path, "--quiet"]

        do {
            let (exit, _, stderr) = try await launcher.run(executable: bin, arguments: args, environment: nil)
            if exit != 0 {
                let tail = String(data: stderr.suffix(800), encoding: .utf8) ?? ""
                return .failure(.runFailed(exitCode: exit, stderrTail: tail))
            }
            guard FileManager.default.fileExists(atPath: outJSON.path) else {
                return .failure(.parseFailed(message: "graphify produced no output at \(outJSON.path)"))
            }
            return .success(outJSON)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.runFailed(exitCode: -1, stderrTail: String(describing: error)))
        }
    }
}
```

- [ ] **Step 4: Run the test (expect pass)**

```bash
swift test --filter GraphifyRunnerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/InfiniteBrainCore/CodeGraph/GraphifyRunner.swift Tests/InfiniteBrainTests/GraphifyRunnerTests.swift
git commit -m "feat(codegraph): add GraphifyRunner with injectable launcher"
```

---

## Task 8: Extract `GraphCanvas` from `GraphView` (refactor)

This task lands as a refactor *before* any code-graph UI is wired in, so existing knowledge-graph tests gate the change.

**Files:**
- Create: `Sources/InfiniteBrain/CoreUI/GraphCanvas.swift`
- Modify: `Sources/InfiniteBrain/Features/KnowledgeGraph/GraphView.swift`

- [ ] **Step 1: Identify the rendering region**

In [GraphView.swift](../../../Sources/InfiniteBrain/Features/KnowledgeGraph/GraphView.swift), the rendering is inside the `ZStack { GeometryReader { TimelineView { Canvas { ... } } } }` plus the `.gesture(...)` and zoom/pan state. Extract the Canvas + gestures + zoom/pan state into a new view.

- [ ] **Step 2: Create the pure renderer**

Create `Sources/InfiniteBrain/CoreUI/GraphCanvas.swift`:

```swift
import SwiftUI
import InfiniteBrainCore

@MainActor
public struct GraphCanvas: View {
    public let data: GraphData
    public let simulation: GraphSimulation
    @Binding public var selected: GraphNode?
    public var isSimulating: Bool = true
    public var onTick: (() -> Void)? = nil      // called each animation frame (host can persist positions)
    public var onNodeOpen: ((GraphNode) -> Void)? = nil

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    public init(data: GraphData,
                simulation: GraphSimulation,
                selected: Binding<GraphNode?>,
                isSimulating: Bool = true,
                onTick: (() -> Void)? = nil,
                onNodeOpen: ((GraphNode) -> Void)? = nil) {
        self.data = data
        self.simulation = simulation
        self._selected = selected
        self.isSimulating = isSimulating
        self.onTick = onTick
        self.onNodeOpen = onNodeOpen
    }

    public var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { _ in
                Canvas { ctx, size in
                    if isSimulating {
                        simulation.step(canvasSize: size)
                        onTick?()
                    }
                    let viewport = CGRect(x: -offset.width / scale, y: -offset.height / scale,
                                          width: size.width / scale, height: size.height / scale)
                    let visibleRect = viewport.insetBy(dx: -40, dy: -40)
                    ctx.concatenate(CGAffineTransform(translationX: offset.width, y: offset.height))
                    ctx.concatenate(CGAffineTransform(scaleX: scale, y: scale))

                    let nodePositions = Dictionary(uniqueKeysWithValues: simulation.nodes.map { ($0.id, $0.position) })
                    for e in simulation.edges {
                        guard let p1 = nodePositions[e.fromId], let p2 = nodePositions[e.toId] else { continue }
                        if !visibleRect.contains(p1) && !visibleRect.contains(p2) { continue }
                        var path = Path(); path.move(to: p1); path.addLine(to: p2)
                        let isRelated = (e.fromId == selected?.id || e.toId == selected?.id)
                        let opacity = isRelated ? 1.0 : 0.6
                        let width = (isRelated ? 3.0 : 1.5) / max(scale, 0.5)
                        ctx.stroke(path, with: .color(.primary.opacity(opacity)), lineWidth: width)
                    }
                    for n in simulation.nodes {
                        if !visibleRect.contains(n.position) { continue }
                        guard let full = data.nodes.first(where: { $0.id == n.id }) else { continue }
                        let isSelected = n.id == selected?.id
                        let baseR: CGFloat = isSelected ? 12 : 8
                        let r = max(baseR, baseR / (scale * 0.5))
                        let rect = CGRect(x: n.position.x - r, y: n.position.y - r, width: r*2, height: r*2)
                        let color = NodePalette.color(for: full.type)
                        ctx.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { v in scale = max(0.2, min(4.0, lastScale * v)) }
                            .onEnded { _ in lastScale = scale },
                        DragGesture()
                            .onChanged { v in
                                offset = CGSize(width: lastOffset.width + v.translation.width,
                                                height: lastOffset.height + v.translation.height)
                            }
                            .onEnded { _ in lastOffset = offset }
                    )
                )
                .onTapGesture(count: 2) { location in
                    if let hit = hitTest(at: location, in: geo.size) {
                        onNodeOpen?(hit)
                    }
                }
                .onTapGesture { location in
                    selected = hitTest(at: location, in: geo.size)
                }
            }
        }
    }

    private func hitTest(at point: CGPoint, in size: CGSize) -> GraphNode? {
        let worldX = (point.x - offset.width) / scale
        let worldY = (point.y - offset.height) / scale
        var best: (GraphNode, CGFloat)?
        let radius: CGFloat = 16 / scale
        for n in simulation.nodes {
            let dx = n.position.x - worldX, dy = n.position.y - worldY
            let d = sqrt(dx*dx + dy*dy)
            if d < radius, best == nil || d < best!.1 {
                if let full = data.nodes.first(where: { $0.id == n.id }) { best = (full, d) }
            }
        }
        return best?.0
    }
}
```

- [ ] **Step 3: Refactor `GraphView` to consume `GraphCanvas`**

In `Sources/InfiniteBrain/Features/KnowledgeGraph/GraphView.swift`, replace the `Canvas { ... }` block and its gestures with a `GraphCanvas` invocation. Keep all vault persistence (`persistPositions`, `notesCache`, `lastSaveTime`) and pass them via `onTick`:

```swift
GraphCanvas(
    data: data,
    simulation: simulation ?? GraphSimulation(data: data),
    selected: $selected,
    isSimulating: isSimulating,
    onTick: {
        if Date().timeIntervalSince(lastSaveTime) > 2.0 { persistPositions() }
    }
)
```

Remove the now-duplicate `scale`/`offset` state from `GraphView`. Keep `selected`, `data`, `loading`, `currentBacklinks`, `store`, `lastSaveTime`, `notesCache`, `simulation`, `isSimulating`.

- [ ] **Step 4: Build and run the full test suite**

```bash
swift build
swift test
```

Expected: full suite PASSES. No knowledge-graph behavior change.

- [ ] **Step 5: Manually smoke-test the knowledge graph**

```bash
swift run InfiniteBrain
```

Open the Knowledge Graph tab. Verify: nodes render, pan/zoom works, selection works, positions persist across app restart.

- [ ] **Step 6: Commit**

```bash
git add Sources/InfiniteBrain/CoreUI/GraphCanvas.swift Sources/InfiniteBrain/Features/KnowledgeGraph/GraphView.swift
git commit -m "refactor(ui): extract GraphCanvas pure renderer from GraphView"
```

---

## Task 9: Add `.codeGraph` tab to the sidebar

**Files:**
- Modify: `Sources/InfiniteBrain/App/InfiniteBrainApp.swift:52-94`

- [ ] **Step 1: Edit the Tab enum**

In [InfiniteBrainApp.swift:52-77](../../../Sources/InfiniteBrain/App/InfiniteBrainApp.swift), replace:

```swift
enum Tab: String, CaseIterable, Identifiable {
    case ingest, vault, graph, query, drafting, settings
    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .ingest: return "Ingest"
        case .vault: return "Vault"
        case .graph: return "Knowledge Graph"
        case .query: return "Query"
        case .drafting: return "Drafting Room"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .ingest: return "tray.and.arrow.down.fill"
        case .vault: return "books.vertical.fill"
        case .graph: return "circle.hexagongrid.fill"
        case .query: return "sparkle.magnifyingglass"
        case .drafting: return "pencil.and.scribble"
        case .settings: return "gearshape.fill"
        }
    }
}
```

with:

```swift
enum Tab: String, CaseIterable, Identifiable {
    case ingest, vault, graph, codeGraph, query, drafting, settings
    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .ingest: return "Ingest"
        case .vault: return "Vault"
        case .graph: return "Knowledge Graph"
        case .codeGraph: return "Code Graph"
        case .query: return "Query"
        case .drafting: return "Drafting Room"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .ingest: return "tray.and.arrow.down.fill"
        case .vault: return "books.vertical.fill"
        case .graph: return "circle.hexagongrid.fill"
        case .codeGraph: return "point.3.connected.trianglepath.dotted"
        case .query: return "sparkle.magnifyingglass"
        case .drafting: return "pencil.and.scribble"
        case .settings: return "gearshape.fill"
        }
    }
}
```

- [ ] **Step 2: Add the switch arm in the detail view**

In the same file, replace the `switch tab { ... }` block (lines 87–94) with:

```swift
switch tab {
case .ingest: IngestView()
case .vault: VaultBrowser()
case .graph: GraphView()
case .codeGraph: CodeGraphView()
case .query: QueryView()
case .drafting: DraftingRoom()
case .settings: SettingsView()
}
```

- [ ] **Step 3: Build (expect a compile error referring to `CodeGraphView`)**

```bash
swift build
```

Expected: FAIL — `CodeGraphView` not yet implemented. Task 10 fixes this.

- [ ] **Step 4: Do not commit yet**

The build is broken intentionally; commit happens after Task 10.

---

## Task 10: Build `CodeGraphView`

**Files:**
- Create: `Sources/InfiniteBrain/Features/CodeGraph/CodeGraphView.swift`

- [ ] **Step 1: Implement the view**

Create `Sources/InfiniteBrain/Features/CodeGraph/CodeGraphView.swift`:

```swift
import SwiftUI
import InfiniteBrainCore
import UniformTypeIdentifiers

@MainActor
struct CodeGraphView: View {
    @State private var targetFolder: URL? = CodeGraphView.defaultFolder()
    @State private var status: Status = .idle
    @State private var data: GraphData = .init(nodes: [], edges: [])
    @State private var simulation: GraphSimulation?
    @State private var selected: GraphNode?
    @State private var runTask: Task<Void, Never>?

    private let runner = GraphifyRunner()
    private let store = GraphifyStore()

    enum Status: Equatable {
        case idle
        case running
        case loaded(nodeCount: Int, edgeCount: Int)
        case error(String)
        case binaryMissing
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack {
                if let sim = simulation, !data.nodes.isEmpty {
                    GraphCanvas(
                        data: data,
                        simulation: sim,
                        selected: $selected,
                        onNodeOpen: openNode
                    )
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: loadCachedIfAvailable)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                pickFolder()
            } label: {
                Label(targetFolder?.lastPathComponent ?? "Choose folder…", systemImage: "folder")
            }
            Button {
                runGraphify()
            } label: {
                Label("Run Graphify", systemImage: "play.fill")
            }
            .disabled(targetFolder == nil || status == .running)

            if status == .running {
                ProgressView().controlSize(.small)
                Button("Cancel") { runTask?.cancel() }
            }

            Spacer()
            statusLabel
        }
        .padding(12)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .idle:                          Text("Ready").foregroundStyle(.secondary)
        case .running:                       Text("Running graphify…").foregroundStyle(.secondary)
        case .loaded(let n, let e):          Text("\(n) nodes · \(e) edges").foregroundStyle(.secondary)
        case .error(let m):                  Text(m).foregroundStyle(.red).lineLimit(2).truncationMode(.tail)
        case .binaryMissing:
            HStack {
                Text("Graphify not installed.").foregroundStyle(.orange)
                Button("Copy install command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(GraphifyRunner.installHint, forType: .string)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No graph yet. Pick a folder and run Graphify.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private static func defaultFolder() -> URL? {
        var cur = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            if FileManager.default.fileExists(atPath: cur.appendingPathComponent("Package.swift").path) {
                return cur
            }
            cur.deleteLastPathComponent()
        }
        if let stored = UserDefaults.standard.url(forKey: "CodeGraph.lastFolder") { return stored }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            targetFolder = url
            UserDefaults.standard.set(url, forKey: "CodeGraph.lastFolder")
        }
    }

    private func runGraphify() {
        guard let target = targetFolder else { return }
        status = .running
        runTask = Task {
            let result = await runner.run(targetFolder: target)
            switch result {
            case .success(let jsonURL):
                do {
                    let raw = try Data(contentsOf: jsonURL)
                    let parsed = try GraphifyParser.parse(data: raw)
                    try? store.save(graphJSON: raw, for: target,
                                    nodeCount: parsed.nodes.count, edgeCount: parsed.edges.count,
                                    graphifyVersion: GraphifyParser.supportedSchemaVersion)
                    self.data = laidOut(parsed)
                    self.simulation = GraphSimulation(data: self.data)
                    self.status = .loaded(nodeCount: parsed.nodes.count, edgeCount: parsed.edges.count)
                } catch let GraphifyError.unsupportedSchema(v) {
                    self.status = .error("Unsupported graphify schema v\(v)")
                } catch {
                    self.status = .error("Parse failed: \(error)")
                }
            case .failure(.binaryMissing):
                self.status = .binaryMissing
            case .failure(.runFailed(let code, let tail)):
                self.status = .error("graphify exited \(code): \(tail.suffix(160))")
            case .failure(.parseFailed(let m)):
                self.status = .error("Parse failed: \(m)")
            case .failure(.unsupportedSchema(let v)):
                self.status = .error("Unsupported schema v\(v)")
            case .failure(.cancelled):
                self.status = .idle
            }
        }
    }

    private func loadCachedIfAvailable() {
        guard let target = targetFolder,
              let raw = store.loadGraphJSON(for: target),
              let parsed = try? GraphifyParser.parse(data: raw) else { return }
        self.data = laidOut(parsed)
        self.simulation = GraphSimulation(data: self.data)
        if let meta = store.lastRun(for: target) {
            self.status = .loaded(nodeCount: meta.nodeCount, edgeCount: meta.edgeCount)
        }
    }

    private func laidOut(_ raw: GraphData) -> GraphData {
        // Reuse GraphLayout by synthesizing minimal Notes so positions cluster by type.
        let notes: [Note] = raw.nodes.map { n in
            Note(id: n.id, type: n.type, title: n.title, summary: n.summary, body: "",
                 edges: [], sources: [], contentHash: "",
                 version: 1, createdAt: Date(), updatedAt: Date())
        }
        let laid = GraphLayout.compute(notes: notes, canvasSize: CGSize(width: 1200, height: 800))
        // Re-attach metadata by id (GraphLayout doesn't preserve it).
        let metaByID = Dictionary(uniqueKeysWithValues: raw.nodes.map { ($0.id, $0.metadata) })
        let merged = laid.nodes.map { gn in
            GraphNode(id: gn.id, title: gn.title, type: gn.type, summary: gn.summary,
                      position: gn.position, metadata: metaByID[gn.id] ?? nil)
        }
        return GraphData(nodes: merged, edges: raw.edges)
    }

    private func openNode(_ node: GraphNode) {
        guard let urlString = node.metadata?["fileURL"],
              let fileURL = URL(string: urlString),
              let root = targetFolder else { return }
        // Containment guard: only open if the file resolves under the picked root.
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") || filePath == rootPath else { return }
        NSWorkspace.shared.open(fileURL)
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 3: Run the full test suite**

```bash
swift test
```

Expected: all tests PASS.

- [ ] **Step 4: Manual smoke test**

```bash
swift run InfiniteBrain
```

Verify:
- "Code Graph" appears in the sidebar with the dotted-triangle icon.
- Clicking it shows the empty state.
- If `graphify` is installed, "Run Graphify" produces a populated canvas.
- If `graphify` is NOT installed, status reads "Graphify not installed" with a copy-install-command button that puts `uv tool install graphifyy` on the clipboard.
- Double-clicking a node opens the file in the default editor (only when path is under the picked root).
- Re-opening the tab shows the cached graph without rerunning.

- [ ] **Step 5: Commit**

```bash
git add Sources/InfiniteBrain/App/InfiniteBrainApp.swift Sources/InfiniteBrain/Features/CodeGraph/
git commit -m "feat(ui): add Code Graph sidebar tab backed by Graphify"
```

---

## Task 11: User-facing docs

**Files:**
- Create: `docs/user-guide/code-graph.md`
- Modify: `README.md` (one line under features)

- [ ] **Step 1: Write the user guide**

Create `docs/user-guide/code-graph.md`:

```markdown
# Code Graph

The Code Graph tab visualizes the structure of a code repository as an interactive graph using the external [Graphify](https://github.com/safishamsi/graphify) CLI.

## Install Graphify

InfiniteBrain shells out to `graphify`. Install it once:

```bash
uv tool install graphifyy
```

(Note: package name is `graphifyy` with a double-y; binary is `graphify`.)

## Usage

1. Open **Code Graph** in the sidebar.
2. Click the folder button to pick a repository.
3. Click **Run Graphify**.
4. Click a node to select it; double-click to open the underlying file.

## Caching

Each folder's last graph is cached at `~/Library/Application Support/InfiniteBrain/CodeGraph/<hash>/`. Re-running overwrites.

## Troubleshooting

- **"Graphify not installed"** — click the copy-install-command button and run it in a terminal.
- **"Unsupported graphify schema vN"** — your installed `graphify` produces a JSON schema this build doesn't support. Pin `graphify` to a compatible version or upgrade InfiniteBrain.
```

- [ ] **Step 2: Link from README**

In `README.md`, add a bullet under the features list:

```markdown
- **Code Graph** — visualize a repository's structure (classes, calls, imports) via the Graphify CLI. See [docs/user-guide/code-graph.md](docs/user-guide/code-graph.md).
```

- [ ] **Step 3: Commit**

```bash
git add docs/user-guide/code-graph.md README.md
git commit -m "docs: add Code Graph user guide"
```

---

## Self-Review

Spec coverage check:
- Sidebar entry — Task 9 ✓
- GraphifyRunner — Task 7 ✓
- GraphifyParser with golden fixtures — Task 5 ✓
- GraphifyStore — Task 6 ✓
- CodeGraphView with folder picker, run button, status, cancel — Task 10 ✓
- Cross-link to Knowledge Graph (Settings toggle) — **deferred to v2** (intentionally out of this plan, matches spec's "optional, default off" framing — can be a follow-up task if you want it in v1)
- NodeType extension — Task 1 ✓
- EdgeType extension — Task 2 ✓
- GraphNode metadata — Task 3 ✓
- GraphCanvas refactor — Task 8 ✓
- Containment guard on `NSWorkspace.open` — Task 10 `openNode` ✓
- Install hint literal test — Task 7 ✓
- Schema version pinning — Task 5 ✓
- Error handling table — covered across Tasks 7 and 10 ✓
- Docs — Task 11 ✓

Type consistency: `GraphifyRunner.run` returns `Result<URL, GraphifyError>` consistently across Tasks 7 and 10. `GraphifyParser.parse(data:)` is called the same way in Tasks 5 and 10. `GraphifyStore` API matches between Tasks 6 and 10. `GraphifyRunner.installHint` is used in Tasks 7 and 10. ✓

No placeholders — every step has explicit file paths, commands, and (where code changes) full code blocks.

**One known gap, called out deliberately:** Cross-link Knowledge↔Code (spec §6) is not in this plan. The spec marks it default-off and optional; adding it here would double the surface and delay the working baseline. Recommend deferring to a follow-up plan after v1 ships.
