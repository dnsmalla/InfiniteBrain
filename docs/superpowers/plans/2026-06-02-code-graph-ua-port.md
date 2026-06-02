# Code Graph — Understand-Anything Port — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace InfiniteBrain's graphify-backed CodeGraph tab with a port of meet-notes' 3-panel UA-powered code graph, styled to match InfiniteBrain.

**Architecture:** Add new UA types/parser/layout/store/runner to InfiniteBrainCore; replace the graphify files; port meet-notes' canvas and 3-panel view into InfiniteBrain's Features/CodeGraph, stripping ThemeStore/LibraryItemStore in favour of AppPalette and NSOpenPanel. No other feature is touched.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14, SPM, XCTest, `understand-anything` CLI (npm)

---

## File Map

**InfiniteBrainCore/CodeGraph/ — add:**
- `Sources/InfiniteBrainCore/CodeGraph/CodeGraphModels.swift`
- `Sources/InfiniteBrainCore/CodeGraph/UAError.swift`
- `Sources/InfiniteBrainCore/CodeGraph/UAParser.swift`
- `Sources/InfiniteBrainCore/CodeGraph/CodeGraphLayout.swift`
- `Sources/InfiniteBrainCore/CodeGraph/UAStore.swift`
- `Sources/InfiniteBrainCore/CodeGraph/UARunner.swift`

**InfiniteBrainCore/CodeGraph/ — delete:**
- `Sources/InfiniteBrainCore/CodeGraph/GraphifyRunner.swift`
- `Sources/InfiniteBrainCore/CodeGraph/GraphifyParser.swift`
- `Sources/InfiniteBrainCore/CodeGraph/GraphifyStore.swift`
- `Sources/InfiniteBrainCore/CodeGraph/GraphifyError.swift`

**InfiniteBrainCore/CodeGraph/ — keep:**
- `Sources/InfiniteBrainCore/CodeGraph/ProcessLauncher.swift` *(unchanged)*

**InfiniteBrain/Features/CodeGraph/ — add/replace:**
- `Sources/InfiniteBrain/Features/CodeGraph/UAHelpers.swift` *(new)*
- `Sources/InfiniteBrain/Features/CodeGraph/CodeGraphCanvas.swift` *(new)*
- `Sources/InfiniteBrain/Features/CodeGraph/CodeGraphView.swift` *(replace)*

**Tests — replace:**
- `Tests/InfiniteBrainTests/GraphifyParserTests.swift` → `UAParserTests.swift`
- `Tests/InfiniteBrainTests/GraphifyRunnerTests.swift` → `UARunnerTests.swift`
- `Tests/InfiniteBrainTests/GraphifyStoreTests.swift`  → `UAStoreTests.swift`

**Fixtures — replace (UA schema):**
- `Tests/InfiniteBrainTests/Fixtures/CodeGraph/simple.json`
- `Tests/InfiniteBrainTests/Fixtures/CodeGraph/unknown-kinds.json`
- `Tests/InfiniteBrainTests/Fixtures/CodeGraph/bad-schema.json`

---

## Task 1 — CodeGraphModels + UAError

**Files:**
- Create: `Sources/InfiniteBrainCore/CodeGraph/CodeGraphModels.swift`
- Create: `Sources/InfiniteBrainCore/CodeGraph/UAError.swift`

- [ ] **Step 1: Create CodeGraphModels.swift**

```swift
// Sources/InfiniteBrainCore/CodeGraph/CodeGraphModels.swift
import Foundation
import CoreGraphics
import SwiftUI

public enum CGNodeKind: String, Sendable, Hashable {
    case file, symbol, module, docPage
    case memoryDoc, memoryChunk
    case noteDecision, noteTask, noteQuestion, noteFact
    case noteConcept, notePlaybook, noteHypothesis, noteEvent, noteSource
    case function, classType, config, service, table, endpoint
    case pipeline, schemaNode, resource, domain, flow, step
    case article, entity, topic, claim
    case other
}

public extension CGNodeKind {
    var displayName: String {
        switch self {
        case .file:           return "File"
        case .symbol:         return "Symbol"
        case .module:         return "Module"
        case .docPage:        return "Doc"
        case .memoryDoc:      return "Document"
        case .memoryChunk:    return "Note"
        case .noteDecision:   return "Decision"
        case .noteTask:       return "Task"
        case .noteQuestion:   return "Question"
        case .noteFact:       return "Fact"
        case .noteConcept:    return "Concept"
        case .notePlaybook:   return "Playbook"
        case .noteHypothesis: return "Hypothesis"
        case .noteEvent:      return "Event"
        case .noteSource:     return "Source"
        case .function:       return "Function"
        case .classType:      return "Class"
        case .config:         return "Config"
        case .service:        return "Service"
        case .table:          return "Table"
        case .endpoint:       return "Endpoint"
        case .pipeline:       return "Pipeline"
        case .schemaNode:     return "Schema"
        case .resource:       return "Resource"
        case .domain:         return "Domain"
        case .flow:           return "Flow"
        case .step:           return "Step"
        case .article:        return "Article"
        case .entity:         return "Entity"
        case .topic:          return "Topic"
        case .claim:          return "Claim"
        case .other:          return "Other"
        }
    }
}

public enum CGEdgeKind: String, Sendable, Hashable {
    case imports, exports, contains, inherits, implements
    case calls, subscribes, publishes, middleware
    case readsFrom, writesTo, transforms, validates
    case dependsOn, testedBy, configures
    case relatedTo, similarTo
    case deploys, serves, provisions, triggers
    case migrates, documents, routes, definesSchema
    case containsFlow, flowStep, crossDomain
    case cites, contradicts, buildsOn, exemplifies, categorizedUnder, authoredBy
    case defines, references
}

public struct CGNode: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let kind: CGNodeKind
    public var position: CGPoint
    public let metadata: [String: String]

    public init(id: String, title: String, kind: CGNodeKind,
                position: CGPoint = .zero,
                metadata: [String: String] = [:]) {
        self.id = id; self.title = title; self.kind = kind
        self.position = position; self.metadata = metadata
    }
}

public struct CGEdge: Equatable, Sendable {
    public let fromId: String
    public let toId: String
    public let kind: CGEdgeKind

    public init(fromId: String, toId: String, kind: CGEdgeKind) {
        self.fromId = fromId; self.toId = toId; self.kind = kind
    }
}

public struct UALayer: Equatable, Sendable {
    public let id: String
    public let name: String
    public let nodeIds: [String]

    public init(id: String, name: String, nodeIds: [String]) {
        self.id = id; self.name = name; self.nodeIds = nodeIds
    }
}

public struct UATourStep: Equatable, Sendable {
    public let nodeId: String
    public let title: String
    public let body: String

    public init(nodeId: String, title: String, body: String) {
        self.nodeId = nodeId; self.title = title; self.body = body
    }
}

public struct CGData: Equatable, Sendable {
    public let nodes: [CGNode]
    public let edges: [CGEdge]
    public let layers: [UALayer]
    public let tour: [UATourStep]

    public init(nodes: [CGNode], edges: [CGEdge],
                layers: [UALayer] = [], tour: [UATourStep] = []) {
        self.nodes = nodes; self.edges = edges
        self.layers = layers; self.tour = tour
    }
    public static let empty = CGData(nodes: [], edges: [])
}

/// Stable colour per node kind. Used in views — lives here so UAParser
/// tests can validate kind mapping without a separate colour file.
public enum CGPalette {
    public static func color(for kind: CGNodeKind) -> Color {
        switch kind {
        case .file:           return .blue
        case .symbol:         return .purple
        case .module:         return .orange
        case .docPage:        return .green
        case .memoryDoc:      return .indigo
        case .memoryChunk:    return .mint
        case .noteDecision:   return .red
        case .noteTask:       return .orange
        case .noteQuestion:   return .yellow
        case .noteFact:       return .green
        case .noteConcept:    return .cyan
        case .notePlaybook:   return .blue
        case .noteHypothesis: return .purple
        case .noteEvent:      return .pink
        case .noteSource:     return .brown
        case .function:       return Color(red: 0.2, green: 0.6, blue: 0.9)
        case .classType:      return Color(red: 0.6, green: 0.2, blue: 0.8)
        case .config:         return Color(red: 0.5, green: 0.5, blue: 0.5)
        case .service:        return Color(red: 0.0, green: 0.7, blue: 0.5)
        case .table:          return Color(red: 0.8, green: 0.5, blue: 0.1)
        case .endpoint:       return Color(red: 0.9, green: 0.3, blue: 0.3)
        case .pipeline:       return Color(red: 0.3, green: 0.5, blue: 0.9)
        case .schemaNode:     return Color(red: 0.7, green: 0.4, blue: 0.1)
        case .resource:       return Color(red: 0.1, green: 0.5, blue: 0.3)
        case .domain:         return Color(red: 0.9, green: 0.6, blue: 0.1)
        case .flow:           return Color(red: 0.4, green: 0.8, blue: 0.8)
        case .step:           return Color(red: 0.6, green: 0.8, blue: 0.4)
        case .article:        return Color(red: 0.4, green: 0.6, blue: 0.2)
        case .entity:         return Color(red: 0.8, green: 0.2, blue: 0.6)
        case .topic:          return Color(red: 0.2, green: 0.4, blue: 0.8)
        case .claim:          return Color(red: 0.9, green: 0.4, blue: 0.2)
        case .other:          return .gray
        }
    }
}
```

- [ ] **Step 2: Create UAError.swift**

```swift
// Sources/InfiniteBrainCore/CodeGraph/UAError.swift
import Foundation

public enum UAError: Error, Equatable {
    case binaryMissing
    case nodeVersionTooOld(found: String)
    case folderNotWritable(path: String)
    case runFailed(exitCode: Int32, stderrTail: String)
    case noOutput
    case parseFailed(message: String)
    case unsupportedSchema(version: String)
    case cancelled
}
```

- [ ] **Step 3: Build to verify new types compile**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && swift build 2>&1 | tail -20
```

Expected: build succeeds (graphify files still present; new files add no conflicts).

- [ ] **Step 4: Commit**

```bash
git add Sources/InfiniteBrainCore/CodeGraph/CodeGraphModels.swift \
        Sources/InfiniteBrainCore/CodeGraph/UAError.swift
git commit -m "feat(code-graph): add CGData model types and UAError"
```

---

## Task 2 — Fixtures + UAParser + UAParserTests

**Files:**
- Modify: `Tests/InfiniteBrainTests/Fixtures/CodeGraph/simple.json`
- Modify: `Tests/InfiniteBrainTests/Fixtures/CodeGraph/unknown-kinds.json`
- Modify: `Tests/InfiniteBrainTests/Fixtures/CodeGraph/bad-schema.json`
- Create: `Sources/InfiniteBrainCore/CodeGraph/UAParser.swift`
- Modify: `Tests/InfiniteBrainTests/GraphifyParserTests.swift` → rename + rewrite as UAParserTests

- [ ] **Step 1: Update simple.json to UA schema**

```json
{
  "version": "1.0.0",
  "nodes": [
    {"id": "file:App.swift", "type": "file",     "name": "App.swift", "filePath": "App.swift"},
    {"id": "cls:App",        "type": "class",     "name": "App",       "filePath": "App.swift", "lineRange": [10, 50]},
    {"id": "fn:main",        "type": "function",  "name": "main",      "filePath": "App.swift", "lineRange": [30, 40]}
  ],
  "edges": [
    {"source": "file:App.swift", "target": "cls:App",  "type": "contains"},
    {"source": "cls:App",        "target": "fn:main",  "type": "contains"}
  ],
  "layers": [],
  "tour": []
}
```

- [ ] **Step 2: Update unknown-kinds.json**

```json
{
  "version": "1.0.0",
  "nodes": [
    {"id": "a", "type": "unicorn",   "name": "u", "filePath": "x.swift"},
    {"id": "b", "type": "function",  "name": "doThing", "filePath": "x.swift"}
  ],
  "edges": [
    {"source": "a", "target": "b", "type": "teleports"}
  ],
  "layers": [],
  "tour": []
}
```

- [ ] **Step 3: Update bad-schema.json** (keep as is — version field is all that matters for the missing-nodes test)

```json
{"version":"99","nodes":[],"edges":[]}
```

- [ ] **Step 4: Write UAParserTests.swift** (rename GraphifyParserTests.swift in place)

Replace the entire contents of `Tests/InfiniteBrainTests/GraphifyParserTests.swift` with:

```swift
// Tests/InfiniteBrainTests/GraphifyParserTests.swift
// NOTE: file kept at old path so git history is preserved; content is now UAParser tests.
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
        // unknown edge type maps to .relatedTo
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
```

- [ ] **Step 5: Run tests — expect compilation failure** (UAParser doesn't exist yet)

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && swift test --filter UAParserTests 2>&1 | head -20
```

Expected: error: `cannot find type 'UAParser' in scope`

- [ ] **Step 6: Create UAParser.swift**

```swift
// Sources/InfiniteBrainCore/CodeGraph/UAParser.swift
import Foundation
import CoreGraphics

public enum UAParser {

    // MARK: - Raw Decodable types (private)

    private struct RawGraph: Decodable {
        let version: String?
        let nodes: [RawNode]?
        let edges: [RawEdge]?
        let layers: [RawLayer]?
        let tour: [RawTourStep]?
    }
    private struct RawNode: Decodable {
        let id: String
        let type: String?
        let name: String?
        let filePath: String?
        let lineRange: [Int]?
        let summary: String?
        let tags: [String]?
        let complexity: String?
    }
    private struct RawEdge: Decodable {
        let source: String
        let target: String
        let type: String
        let direction: String?
        let weight: Double?
    }
    private struct RawLayer: Decodable {
        let id: String
        let name: String
        let description: String?
        let nodeIds: [String]
    }
    private struct RawTourStep: Decodable {
        let order: Int?
        let title: String?
        let description: String?
        let nodeIds: [String]?
        let languageLesson: String?
    }

    // MARK: - Public entry point

    /// Decode understand-anything's `knowledge-graph.json` into `CGData`.
    /// `repoRoot` converts relative `filePath` values to absolute `file://` URLs.
    public static func parse(data: Data, repoRoot: URL) throws -> CGData {
        let raw: RawGraph
        do { raw = try JSONDecoder().decode(RawGraph.self, from: data) }
        catch { throw UAError.parseFailed(message: error.localizedDescription) }

        guard let rawNodes = raw.nodes else {
            throw UAError.parseFailed(message: "knowledge-graph.json has no `nodes` field")
        }
        let rawEdges  = raw.edges  ?? []
        let rawLayers = raw.layers ?? []
        let rawTour   = raw.tour   ?? []

        let nodes: [CGNode] = rawNodes.map { rn in
            let kind = mapNodeType(rn.type)
            var meta: [String: String] = [:]

            if let fp = rn.filePath, !fp.isEmpty {
                let abs = resolveFileURL(filePath: fp, repoRoot: repoRoot)
                meta["fileURL"] = abs.absoluteString
                let rootPath = repoRoot.standardizedFileURL.path
                let absPath  = abs.standardizedFileURL.path
                meta["source_file"] = absPath.hasPrefix(rootPath + "/")
                    ? String(absPath.dropFirst(rootPath.count + 1))
                    : fp
            }
            if let lr = rn.lineRange {
                meta["line"] = lr.count >= 2 ? "L\(lr[0])-L\(lr[1])" : "L\(lr[0])"
            }
            if let s = rn.summary,    !s.isEmpty { meta["summary"]    = s }
            if let c = rn.complexity, !c.isEmpty { meta["complexity"] = c }
            if let t = rn.tags,       !t.isEmpty { meta["tags"]       = t.joined(separator: ", ") }
            if let t = rn.type,       !t.isEmpty { meta["ua_type"]    = t }

            return CGNode(id: rn.id, title: rn.name ?? rn.id,
                          kind: kind, position: .zero, metadata: meta)
        }

        let edges: [CGEdge] = rawEdges.map { re in
            CGEdge(fromId: re.source, toId: re.target, kind: mapEdgeType(re.type))
        }

        let layers: [UALayer] = rawLayers.map { rl in
            UALayer(id: rl.id, name: rl.name, nodeIds: rl.nodeIds)
        }

        let tour: [UATourStep] = rawTour
            .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
            .compactMap { rt in
                guard let nodeId = rt.nodeIds?.first else { return nil }
                return UATourStep(nodeId: nodeId,
                                  title: rt.title ?? "Step \(rt.order ?? 0)",
                                  body:  rt.description ?? rt.languageLesson ?? "")
            }

        return CGData(nodes: nodes, edges: edges, layers: layers, tour: tour)
    }

    // MARK: - Type mapping (internal for testability)

    public static func mapNodeType(_ raw: String?) -> CGNodeKind {
        switch (raw ?? "").lowercased() {
        case "file":                      return .file
        case "module", "package":         return .module
        case "document", "doc":           return .docPage
        case "function", "func":          return .function
        case "class", "struct":           return .classType
        case "config", "configuration":   return .config
        case "service":                   return .service
        case "table":                     return .table
        case "endpoint", "api":           return .endpoint
        case "pipeline":                  return .pipeline
        case "schema":                    return .schemaNode
        case "resource":                  return .resource
        case "domain":                    return .domain
        case "flow":                      return .flow
        case "step":                      return .step
        case "article":                   return .article
        case "entity":                    return .entity
        case "topic":                     return .topic
        case "claim":                     return .claim
        case "symbol", "method", "interface": return .symbol
        default:                          return .other
        }
    }

    public static func mapEdgeType(_ raw: String) -> CGEdgeKind {
        switch raw.lowercased() {
        case "imports":                   return .imports
        case "exports":                   return .exports
        case "contains":                  return .contains
        case "inherits", "extends", "extends_from": return .inherits
        case "implements":                return .implements
        case "calls", "invokes":          return .calls
        case "subscribes", "listens":     return .subscribes
        case "publishes", "emits":        return .publishes
        case "middleware":                return .middleware
        case "reads_from", "readsfrom", "reads": return .readsFrom
        case "writes_to", "writesto", "writes":  return .writesTo
        case "transforms":                return .transforms
        case "validates":                 return .validates
        case "depends_on", "dependson", "uses", "requires": return .dependsOn
        case "tested_by", "testedby", "tests":   return .testedBy
        case "configures":                return .configures
        case "related_to", "relatedto":   return .relatedTo
        case "similar_to", "similarto":   return .similarTo
        case "deploys":                   return .deploys
        case "serves":                    return .serves
        case "provisions":                return .provisions
        case "triggers":                  return .triggers
        case "migrates":                  return .migrates
        case "documents":                 return .documents
        case "routes":                    return .routes
        case "defines_schema":            return .definesSchema
        case "contains_flow":             return .containsFlow
        case "flow_step":                 return .flowStep
        case "cross_domain":              return .crossDomain
        case "cites":                     return .cites
        case "contradicts", "opposes":    return .contradicts
        case "builds_on", "buildson", "extends_idea": return .buildsOn
        case "exemplifies", "illustrates": return .exemplifies
        case "categorized_under", "tagged": return .categorizedUnder
        case "authored_by", "written_by": return .authoredBy
        case "defines", "method", "case_of": return .defines
        case "references":                return .references
        default:                          return .relatedTo
        }
    }

    /// Resolve a `filePath` from understand-anything to an absolute file URL
    /// anchored at `repoRoot`. Handles relative, absolute-matching, and
    /// stale-absolute (rebases by repo directory name).
    public static func resolveFileURL(filePath: String, repoRoot: URL) -> URL {
        if !filePath.hasPrefix("/") {
            return repoRoot.appendingPathComponent(filePath, isDirectory: false)
        }
        let rootPath = repoRoot.standardizedFileURL.path
        if filePath.hasPrefix(rootPath + "/") || filePath == rootPath {
            return URL(fileURLWithPath: filePath)
        }
        let needle = "/\(repoRoot.lastPathComponent)/"
        if let range = filePath.range(of: needle, options: .backwards) {
            return repoRoot.appendingPathComponent(
                String(filePath[range.upperBound...]), isDirectory: false)
        }
        return URL(fileURLWithPath: filePath)
    }
}
```

- [ ] **Step 7: Run UAParser tests — expect pass**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && swift test --filter UAParserTests 2>&1 | tail -15
```

Expected:
```
Test Suite 'UAParserTests' passed
Executed 7 tests, with 0 failures
```

- [ ] **Step 8: Commit**

```bash
git add Sources/InfiniteBrainCore/CodeGraph/UAParser.swift \
        Tests/InfiniteBrainTests/GraphifyParserTests.swift \
        Tests/InfiniteBrainTests/Fixtures/CodeGraph/simple.json \
        Tests/InfiniteBrainTests/Fixtures/CodeGraph/unknown-kinds.json \
        Tests/InfiniteBrainTests/Fixtures/CodeGraph/bad-schema.json
git commit -m "feat(code-graph): add UAParser + update fixtures to UA schema"
```

---

## Task 3 — CodeGraphLayout + tests

**Files:**
- Create: `Sources/InfiniteBrainCore/CodeGraph/CodeGraphLayout.swift`
- Create: `Tests/InfiniteBrainTests/CodeGraphLayoutTests.swift`

- [ ] **Step 1: Write failing test**

Create `Tests/InfiniteBrainTests/CodeGraphLayoutTests.swift`:

```swift
import XCTest
@testable import InfiniteBrainCore

final class CodeGraphLayoutTests: XCTestCase {
    func testNodesReceiveNonZeroPositions() {
        let nodes = (0..<6).map { i in
            CGNode(id: "n\(i)", title: "Node\(i)", kind: i % 2 == 0 ? .file : .function)
        }
        let input = CGData(nodes: nodes, edges: [])
        let result = CodeGraphLayout.compute(input, canvasSize: CGSize(width: 800, height: 600))
        XCTAssertEqual(result.nodes.count, 6)
        XCTAssertTrue(result.nodes.allSatisfy { $0.position != .zero })
    }

    func testEdgeToMissingNodeIsDropped() {
        let nodes = [CGNode(id: "a", title: "A", kind: .file),
                     CGNode(id: "b", title: "B", kind: .module)]
        let edges = [CGEdge(fromId: "a", toId: "b",       kind: .imports),
                     CGEdge(fromId: "a", toId: "missing", kind: .imports)]
        let input = CGData(nodes: nodes, edges: edges)
        let result = CodeGraphLayout.compute(input, canvasSize: CGSize(width: 800, height: 600))
        XCTAssertEqual(result.edges.count, 1)
        XCTAssertEqual(result.edges[0].fromId, "a")
        XCTAssertEqual(result.edges[0].toId,   "b")
    }

    func testEmptyInputReturnsEmpty() {
        let result = CodeGraphLayout.compute(.empty, canvasSize: CGSize(width: 800, height: 600))
        XCTAssertTrue(result.nodes.isEmpty)
        XCTAssertTrue(result.edges.isEmpty)
    }

    func testNodesStayWithinCanvas() {
        let nodes = (0..<20).map { i in
            CGNode(id: "n\(i)", title: "N\(i)", kind: .file)
        }
        let canvas = CGSize(width: 600, height: 400)
        let result = CodeGraphLayout.compute(CGData(nodes: nodes, edges: []), canvasSize: canvas)
        for node in result.nodes {
            XCTAssertTrue(node.position.x >= 0 && node.position.x <= canvas.width,
                          "x \(node.position.x) out of bounds")
            XCTAssertTrue(node.position.y >= 0 && node.position.y <= canvas.height,
                          "y \(node.position.y) out of bounds")
        }
    }
}
```

- [ ] **Step 2: Run — expect failure**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && swift test --filter CodeGraphLayoutTests 2>&1 | head -10
```

Expected: `error: cannot find type 'CodeGraphLayout'`

- [ ] **Step 3: Create CodeGraphLayout.swift**

```swift
// Sources/InfiniteBrainCore/CodeGraph/CodeGraphLayout.swift
// Static type-clustered circular layout. No physics dependency.
// Each CGNodeKind gets a pie slice; nodes within a slice spread
// across three concentric rings for readability at high counts.
import Foundation
import CoreGraphics

public enum CodeGraphLayout {
    public static func compute(_ raw: CGData, canvasSize: CGSize) -> CGData {
        guard !raw.nodes.isEmpty,
              canvasSize.width > 0, canvasSize.height > 0 else { return .empty }

        let center    = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let maxRadius = min(canvasSize.width, canvasSize.height) / 2 * 0.85

        let activeKinds = Array(Set(raw.nodes.map(\.kind))).sorted { $0.rawValue < $1.rawValue }
        let grouped     = Dictionary(grouping: raw.nodes) { $0.kind }
        let sliceAngle  = 2 * Double.pi / Double(max(1, activeKinds.count))

        var laidOut: [CGNode] = []
        laidOut.reserveCapacity(raw.nodes.count)

        for (kindIdx, kind) in activeKinds.enumerated() {
            guard let group = grouped[kind], !group.isEmpty else { continue }
            let centerAngle = sliceAngle * Double(kindIdx) - .pi / 2
            let usable = sliceAngle * 0.7
            let n = group.count
            for (i, node) in group.enumerated() {
                let t: Double = n > 1 ? Double(i) / Double(n - 1) : 0.5
                let angle = centerAngle - usable / 2 + usable * t
                let ring  = i % 3
                let r     = maxRadius * (0.5 + 0.5 * Double(ring + 1) / 3)
                let x     = center.x + cos(angle) * r
                let y     = center.y + sin(angle) * r
                laidOut.append(CGNode(id: node.id, title: node.title, kind: node.kind,
                                      position: CGPoint(x: x, y: y), metadata: node.metadata))
            }
        }

        let presentIds = Set(laidOut.map(\.id))
        let edges = raw.edges.filter { presentIds.contains($0.fromId) && presentIds.contains($0.toId) }
        return CGData(nodes: laidOut, edges: edges, layers: raw.layers, tour: raw.tour)
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && swift test --filter CodeGraphLayoutTests 2>&1 | tail -10
```

Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/InfiniteBrainCore/CodeGraph/CodeGraphLayout.swift \
        Tests/InfiniteBrainTests/CodeGraphLayoutTests.swift
git commit -m "feat(code-graph): add CodeGraphLayout static circular layout"
```

---

## Task 4 — UAStore + tests

**Files:**
- Create: `Sources/InfiniteBrainCore/CodeGraph/UAStore.swift`
- Modify: `Tests/InfiniteBrainTests/GraphifyStoreTests.swift` → replace with UAStoreTests

- [ ] **Step 1: Write failing test** (replace GraphifyStoreTests.swift contents)

```swift
// Tests/InfiniteBrainTests/GraphifyStoreTests.swift
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
        try store.save(graphJSON: json, for: target,
                       nodeCount: 0, edgeCount: 0, toolVersion: "1.0.0")
        XCTAssertEqual(store.loadGraphJSON(for: target), json)
    }

    func testLastRunMetadata() throws {
        try store.save(graphJSON: Data(), for: target,
                       nodeCount: 5, edgeCount: 3, toolVersion: "2.1.0")
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
        try store.save(graphJSON: Data("x".utf8), for: target,
                       nodeCount: 1, edgeCount: 0, toolVersion: "1.0")
        store.invalidate(for: target)
        XCTAssertNil(store.loadGraphJSON(for: target))
    }

    func testDifferentTargetsHaveSeparateEntries() throws {
        let a = URL(fileURLWithPath: "/repo/a")
        let b = URL(fileURLWithPath: "/repo/b")
        let jsonA = Data("A".utf8)
        let jsonB = Data("B".utf8)
        try store.save(graphJSON: jsonA, for: a, nodeCount: 1, edgeCount: 0, toolVersion: "1.0")
        try store.save(graphJSON: jsonB, for: b, nodeCount: 2, edgeCount: 0, toolVersion: "1.0")
        XCTAssertEqual(store.loadGraphJSON(for: a), jsonA)
        XCTAssertEqual(store.loadGraphJSON(for: b), jsonB)
    }
}
```

- [ ] **Step 2: Run — expect failure**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && swift test --filter UAStoreTests 2>&1 | head -10
```

Expected: `error: cannot find type 'UAStore'`

- [ ] **Step 3: Create UAStore.swift**

```swift
// Sources/InfiniteBrainCore/CodeGraph/UAStore.swift
import Foundation
import CryptoKit

public struct UARunMetadata: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let nodeCount: Int
    public let edgeCount: Int
    public let toolVersion: String
}

public final class UAStore {
    private let baseDirectory: URL
    private let fm = FileManager.default

    public init(baseDirectory: URL? = nil) {
        if let b = baseDirectory {
            self.baseDirectory = b
        } else {
            let appSupport = (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true))
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.baseDirectory = appSupport
                .appendingPathComponent("InfiniteBrain", isDirectory: true)
                .appendingPathComponent("CodeGraph",     isDirectory: true)
        }
    }

    public static func directoryName(for target: URL) -> String {
        let path = target.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func dir(for target: URL) throws -> URL {
        let d = baseDirectory.appendingPathComponent(
            Self.directoryName(for: target), isDirectory: true)
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    public func save(graphJSON: Data, for target: URL,
                     nodeCount: Int, edgeCount: Int, toolVersion: String) throws {
        let d = try dir(for: target)
        try graphJSON.write(to: d.appendingPathComponent("knowledge-graph.json"), options: .atomic)
        let meta = UARunMetadata(timestamp: Date(), nodeCount: nodeCount,
                                 edgeCount: edgeCount, toolVersion: toolVersion)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(meta).write(to: d.appendingPathComponent("meta.json"), options: .atomic)
    }

    public func loadGraphJSON(for target: URL) -> Data? {
        let url = baseDirectory
            .appendingPathComponent(Self.directoryName(for: target), isDirectory: true)
            .appendingPathComponent("knowledge-graph.json")
        return try? Data(contentsOf: url)
    }

    public func invalidate(for target: URL) {
        let dir = baseDirectory
            .appendingPathComponent(Self.directoryName(for: target), isDirectory: true)
        try? fm.removeItem(at: dir)
    }

    public func lastRun(for target: URL) -> UARunMetadata? {
        let url = baseDirectory
            .appendingPathComponent(Self.directoryName(for: target), isDirectory: true)
            .appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(UARunMetadata.self, from: data)
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && swift test --filter UAStoreTests 2>&1 | tail -10
```

Expected: `Executed 5 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/InfiniteBrainCore/CodeGraph/UAStore.swift \
        Tests/InfiniteBrainTests/GraphifyStoreTests.swift
git commit -m "feat(code-graph): add UAStore disk cache"
```

---

## Task 5 — UARunner + tests

**Files:**
- Create: `Sources/InfiniteBrainCore/CodeGraph/UARunner.swift`
- Modify: `Tests/InfiniteBrainTests/GraphifyRunnerTests.swift` → replace with UARunnerTests

- [ ] **Step 1: Write failing test** (replace GraphifyRunnerTests.swift contents)

```swift
// Tests/InfiniteBrainTests/GraphifyRunnerTests.swift
import XCTest
@testable import InfiniteBrainCore

final class UARunnerTests: XCTestCase {

    // Reuse the MockLauncher pattern from the old GraphifyRunnerTests.
    final class MockLauncher: ProcessLauncher, @unchecked Sendable {
        var capturedExecutable: URL?
        var capturedArgs: [String] = []
        var exitCode: Int32 = 0
        var stdout: Data = Data()
        var stderr: Data = Data()
        var writeJSONToOutPath: Data? = nil

        func run(executable: URL, arguments: [String],
                 environment: [String: String]?) async throws -> (Int32, Data, Data) {
            capturedExecutable = executable
            capturedArgs = arguments
            if let payload = writeJSONToOutPath,
               let i = arguments.firstIndex(of: "--json-out"),
               i + 1 < arguments.count {
                let outURL = URL(fileURLWithPath: arguments[i + 1])
                try FileManager.default.createDirectory(
                    at: outURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try payload.write(to: outURL)
            }
            return (exitCode, stdout, stderr)
        }
    }

    func testBinaryMissingWhenNoneResolvable() async {
        let runner = UARunner(launcher: MockLauncher(), binaryURL: nil)
        let res = await runner.run(targetFolder: URL(fileURLWithPath: "/repo"))
        XCTAssertEqual(res, .failure(.binaryMissing))
    }

    func testInvokesUnderstandAnythingWithExpectedArgs() async throws {
        let launcher = MockLauncher()
        let payload  = #"{"version":"1.0.0","nodes":[],"edges":[]}"#.data(using: .utf8)!
        launcher.writeJSONToOutPath = payload
        let runner = UARunner(launcher: launcher,
                              binaryURL: URL(fileURLWithPath: "/fake/understand-anything"))

        let jsonURL = try await runner.run(targetFolder: URL(fileURLWithPath: "/repo")).get()
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        XCTAssertEqual(launcher.capturedExecutable,
                       URL(fileURLWithPath: "/fake/understand-anything"))
        XCTAssertEqual(launcher.capturedArgs.first, "extract")
        XCTAssertTrue(launcher.capturedArgs.contains("/repo"))
        XCTAssertTrue(launcher.capturedArgs.contains("--json-out"))
        XCTAssertEqual(try Data(contentsOf: jsonURL), payload)
    }

    func testRunFailedSurfacesExitCodeAndStderr() async {
        let launcher = MockLauncher()
        launcher.exitCode = 1
        launcher.stderr   = Data("something went wrong\n".utf8)
        let runner = UARunner(launcher: launcher,
                              binaryURL: URL(fileURLWithPath: "/fake/understand-anything"))
        let res = await runner.run(targetFolder: URL(fileURLWithPath: "/repo"))
        guard case .failure(.runFailed(let code, let tail)) = res else {
            return XCTFail("expected .runFailed, got \(res)")
        }
        XCTAssertEqual(code, 1)
        XCTAssertTrue(tail.contains("wrong"))
    }

    func testExitZeroButNoOutputReportsNoOutput() async {
        let launcher = MockLauncher()
        launcher.exitCode          = 0
        launcher.writeJSONToOutPath = nil
        let runner = UARunner(launcher: launcher,
                              binaryURL: URL(fileURLWithPath: "/fake/understand-anything"))
        let res = await runner.run(targetFolder: URL(fileURLWithPath: "/repo"))
        XCTAssertEqual(res, .failure(.noOutput))
    }

    func testSafeTailHandlesMidCodepointTruncation() {
        let s    = String(repeating: "héllo ", count: 200)
        let data = Data(s.utf8)
        let tail = UARunner.safeTail(data, maxBytes: 50)
        XCTAssertFalse(tail.isEmpty)
        XCTAssertNotNil(tail.data(using: .utf8))
    }

    func testSafeTailUnderLimitReturnsFullString() {
        XCTAssertEqual(UARunner.safeTail(Data("short".utf8), maxBytes: 800), "short")
    }
}
```

- [ ] **Step 2: Run — expect failure**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && swift test --filter UARunnerTests 2>&1 | head -10
```

Expected: `error: cannot find type 'UARunner'`

- [ ] **Step 3: Create UARunner.swift**

```swift
// Sources/InfiniteBrainCore/CodeGraph/UARunner.swift
import Foundation

public final class UARunner {
    public static let installHint = "npm install -g understand-anything"

    private static let fallbackPaths: [String] = [
        "/opt/homebrew/bin/understand-anything",
        "/usr/local/bin/understand-anything",
        NSString(string: "~/.local/bin/understand-anything").expandingTildeInPath
    ]

    private let launcher: ProcessLauncher
    private let binaryURL: URL?

    public init(launcher: ProcessLauncher = SystemProcessLauncher(),
                binaryURL: URL? = UARunner.resolveBinary()) {
        self.launcher  = launcher
        self.binaryURL = binaryURL
    }

    public static func resolveBinary() -> URL? {
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(dir))
                    .appendingPathComponent("understand-anything")
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        for p in fallbackPaths where FileManager.default.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    /// Runs `understand-anything extract <folder> --json-out <path>` and returns
    /// a stable URL to the generated `knowledge-graph.json`.
    public func run(targetFolder: URL) async -> Result<URL, UAError> {
        guard let bin = binaryURL else { return .failure(.binaryMissing) }

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ua-run-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        } catch {
            return .failure(.runFailed(exitCode: -1,
                                       stderrTail: "failed to create temp dir: \(error)"))
        }

        let outJSON = tmpDir.appendingPathComponent("knowledge-graph.json")
        let args    = ["extract", targetFolder.path, "--json-out", outJSON.path]

        defer { try? FileManager.default.removeItem(at: tmpDir) }

        do {
            let (exit, _, stderr) = try await launcher.run(
                executable: bin, arguments: args, environment: nil)
            if exit != 0 {
                return .failure(.runFailed(exitCode: exit,
                                           stderrTail: Self.safeTail(stderr, maxBytes: 800)))
            }
            guard FileManager.default.fileExists(atPath: outJSON.path) else {
                return .failure(.noOutput)
            }
            let stable = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ua-\(UUID().uuidString).json")
            do {
                try FileManager.default.copyItem(at: outJSON, to: stable)
                return .success(stable)
            } catch {
                return .failure(.parseFailed(message: "failed to stage output: \(error)"))
            }
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.runFailed(exitCode: -1, stderrTail: String(describing: error)))
        }
    }

    /// Return the last `maxBytes` of `data` decoded as UTF-8, stepping forward
    /// past any continuation bytes to land on a valid codepoint boundary.
    public static func safeTail(_ data: Data, maxBytes: Int) -> String {
        guard data.count > maxBytes else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        var start = data.count - maxBytes
        let limit = min(start + 4, data.count)
        while start < limit, (data[start] & 0xC0) == 0x80 { start += 1 }
        return String(data: data.subdata(in: start..<data.count), encoding: .utf8) ?? ""
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && swift test --filter UARunnerTests 2>&1 | tail -10
```

Expected: `Executed 6 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/InfiniteBrainCore/CodeGraph/UARunner.swift \
        Tests/InfiniteBrainTests/GraphifyRunnerTests.swift
git commit -m "feat(code-graph): add UARunner (understand-anything CLI wrapper)"
```

---

## Task 6 — Delete graphify files

**Files:**
- Delete: `Sources/InfiniteBrainCore/CodeGraph/GraphifyRunner.swift`
- Delete: `Sources/InfiniteBrainCore/CodeGraph/GraphifyParser.swift`
- Delete: `Sources/InfiniteBrainCore/CodeGraph/GraphifyStore.swift`
- Delete: `Sources/InfiniteBrainCore/CodeGraph/GraphifyError.swift`

- [ ] **Step 1: Delete the four graphify source files**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain
rm Sources/InfiniteBrainCore/CodeGraph/GraphifyRunner.swift \
   Sources/InfiniteBrainCore/CodeGraph/GraphifyParser.swift \
   Sources/InfiniteBrainCore/CodeGraph/GraphifyStore.swift \
   Sources/InfiniteBrainCore/CodeGraph/GraphifyError.swift
```

- [ ] **Step 2: Build — will fail because CodeGraphView still references graphify types**

```bash
swift build 2>&1 | grep error | head -20
```

Expected: errors in `CodeGraphView.swift` referencing `GraphifyRunner`, `GraphifyParser`, `GraphifyStore`, `GraphifyError`.

> This is expected. The view replacement in Task 8 will resolve these. Keep a note of every error line.

- [ ] **Step 3: Run full test suite to confirm core tests pass (ignoring app build)**

```bash
swift test 2>&1 | grep -E "passed|failed|error" | head -20
```

Expected: `UAParserTests passed`, `UAStoreTests passed`, `UARunnerTests passed`, `CodeGraphLayoutTests passed`. Build errors only in the `InfiniteBrain` (app) target.

- [ ] **Step 4: Commit deletions**

```bash
git rm Sources/InfiniteBrainCore/CodeGraph/GraphifyRunner.swift \
       Sources/InfiniteBrainCore/CodeGraph/GraphifyParser.swift \
       Sources/InfiniteBrainCore/CodeGraph/GraphifyStore.swift \
       Sources/InfiniteBrainCore/CodeGraph/GraphifyError.swift
git commit -m "chore(code-graph): remove graphify files (replaced by UA stack)"
```

---

## Task 7 — UAHelpers + CodeGraphCanvas

**Files:**
- Create: `Sources/InfiniteBrain/Features/CodeGraph/UAHelpers.swift`
- Create: `Sources/InfiniteBrain/Features/CodeGraph/CodeGraphCanvas.swift`

- [ ] **Step 1: Create UAHelpers.swift**

```swift
// Sources/InfiniteBrain/Features/CodeGraph/UAHelpers.swift
import Foundation
import CoreGraphics
import InfiniteBrainCore

enum UAHelpers {

    struct CodeArtifact: Identifiable {
        let fileNode: CGNode
        let symbols: [CodeSymbol]
        var id: String { fileNode.id }
    }

    struct CodeSymbol: Identifiable {
        let node: CGNode
        var id: String { node.id }
    }

    /// Group nodes by their `metadata["source_file"]` for the Files & Symbols panel.
    static func collectCodeArtifacts(_ g: CGData) -> [CodeArtifact] {
        var bySource: [String: [CodeSymbol]] = [:]
        var fileHeaderByPath: [String: CGNode] = [:]

        for node in g.nodes {
            guard let source = node.metadata["source_file"], !source.isEmpty else { continue }
            if isPanelNoise(node) { continue }
            if node.kind == .file {
                fileHeaderByPath[source] = node
            } else if !isHeadingChunk(node) {
                bySource[source, default: []].append(CodeSymbol(node: node))
            }
        }

        let allPaths = Set(bySource.keys).union(fileHeaderByPath.keys)
        let basenameCounts = Dictionary(
            grouping: allPaths,
            by: { ($0 as NSString).lastPathComponent }
        ).mapValues(\.count)

        return allPaths.sorted().compactMap { path -> CodeArtifact? in
            let raw = bySource[path] ?? []
            var seen = Set<String>()
            let syms = raw.sorted { $0.node.title < $1.node.title }.filter { sym in
                let key = "\(sym.node.title)|\(sym.node.metadata["line"] ?? "")"
                return seen.insert(key).inserted
            }
            guard !syms.isEmpty else { return nil }

            let basename = (path as NSString).lastPathComponent
            let title    = (basenameCounts[basename] ?? 0) > 1 ? path : basename
            let header: CGNode = fileHeaderByPath[path].map { node in
                CGNode(id: node.id, title: title, kind: node.kind,
                       position: node.position, metadata: node.metadata)
            } ?? CGNode(id: "file:" + path, title: title, kind: .file,
                        position: .zero, metadata: ["source_file": path])
            return CodeArtifact(fileNode: header, symbols: syms)
        }
    }

    static func isPanelNoise(_ node: CGNode) -> Bool {
        let t = node.title
        if t.hasPrefix("code:") { return true }
        if t.hasPrefix(".") && t.hasSuffix("()") {
            return !t.dropFirst().dropLast(2).contains(".")
        }
        return false
    }

    static func isHeadingChunk(_ node: CGNode) -> Bool {
        guard node.kind == .docPage || node.kind == .memoryChunk else { return false }
        guard let line = node.metadata["line"] else { return false }
        return line != "L1"
    }

    /// Canvas size that scales with node count so concentric rings stay readable.
    static func layoutSize(for nodeCount: Int) -> CGSize {
        let base:  CGFloat = 1200
        let extra: CGFloat = CGFloat(max(0, nodeCount - 100)) * 4
        let side = min(base + extra, 8000)
        return CGSize(width: side, height: side * 0.7)
    }

    /// Longest common leading path prefix across all inputs.
    static func commonAncestor(_ paths: [String]) -> String {
        guard !paths.isEmpty else { return "" }
        let split = paths.map { $0.split(separator: "/").map(String.init) }
        guard let first = split.first else { return "" }
        var common: [String] = []
        for (idx, comp) in first.enumerated() {
            if split.allSatisfy({ idx < $0.count && $0[idx] == comp }) {
                common.append(comp)
            } else { break }
        }
        return "/" + common.joined(separator: "/")
    }
}
```

- [ ] **Step 2: Create CodeGraphCanvas.swift**

```swift
// Sources/InfiniteBrain/Features/CodeGraph/CodeGraphCanvas.swift
// Pure renderer for CGData. Pan, zoom, single-click select, double-click open.
// Auto-fits to viewport on each new graph load (fingerprint guard).
import SwiftUI
import InfiniteBrainCore

@MainActor
struct CodeGraphCanvas: View {
    let data: CGData
    @Binding var selected: CGNode?
    var onNodeOpen: ((CGNode) -> Void)? = nil

    @State private var scale:       CGFloat = 1.0
    @State private var lastScale:   CGFloat = 1.0
    @State private var offset:      CGSize  = .zero
    @State private var lastOffset:  CGSize  = .zero
    @State private var canvasSize:  CGSize  = .zero
    @State private var lastFitFingerprint: Int = 0
    @State private var nodePositions: [String: CGPoint] = [:]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                Canvas { ctx, size in
                    let viewport = CGRect(x: -offset.width  / scale,
                                         y: -offset.height / scale,
                                         width:  size.width  / scale,
                                         height: size.height / scale)
                    let visible = viewport.insetBy(dx: -40, dy: -40)
                    ctx.concatenate(CGAffineTransform(translationX: offset.width, y: offset.height))
                    ctx.concatenate(CGAffineTransform(scaleX: scale, y: scale))

                    for e in data.edges {
                        guard let p1 = nodePositions[e.fromId],
                              let p2 = nodePositions[e.toId] else { continue }
                        if !visible.contains(p1) && !visible.contains(p2) { continue }
                        var path = Path(); path.move(to: p1); path.addLine(to: p2)
                        let related = (e.fromId == selected?.id || e.toId == selected?.id)
                        ctx.stroke(path,
                                   with: .color(related ? AppPalette.brand : Color.secondary.opacity(0.3)),
                                   lineWidth: (related ? 2.0 : 0.8) / max(scale, 0.5))
                    }

                    for n in data.nodes {
                        if !visible.contains(n.position) { continue }
                        let isSel  = n.id == selected?.id
                        let baseR: CGFloat = isSel ? 10 : 5
                        let r = max(baseR, baseR / (scale * 0.5))
                        let rect = CGRect(x: n.position.x - r, y: n.position.y - r,
                                          width: r * 2, height: r * 2)
                        ctx.fill(Path(ellipseIn: rect),
                                 with: .color(CGPalette.color(for: n.kind)))
                        if isSel {
                            ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -4/scale, dy: -4/scale)),
                                       with: .color(AppPalette.brand),
                                       lineWidth: 3.0 / max(scale, 0.5))
                        }
                    }
                }
                .background(Color(NSColor.windowBackgroundColor))
                .gesture(panZoomGesture)
                .gesture(tapGestures)
                .onAppear {
                    canvasSize = geo.size
                    rebuildPositions()
                    fitIfNewGraph(in: geo.size)
                }
                .onChange(of: geo.size) { _, new in canvasSize = new }
                .onChange(of: data) { _, _ in
                    rebuildPositions()
                    fitIfNewGraph(in: canvasSize)
                }
                .onChange(of: selected) { _, new in
                    centerOnSelected(new, canvas: geo.size)
                }
            }
            controls.padding(12)
        }
    }

    // MARK: - Floating controls

    private var controls: some View {
        HStack(spacing: 4) {
            iconBtn("viewfinder",        "Fit graph") { fit(animated: true, in: canvasSize, force: true) }
            iconBtn("plus.magnifyingglass",  "Zoom in")  { withAnimation(.easeInOut(duration: 0.18)) { scale = min(4, scale * 1.25) } }
            iconBtn("minus.magnifyingglass", "Zoom out") { withAnimation(.easeInOut(duration: 0.18)) { scale = max(0.05, scale * 0.8) } }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.separator, lineWidth: 1))
    }

    @ViewBuilder
    private func iconBtn(_ icon: String, _ tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tip)
    }

    // MARK: - Gestures

    private var panZoomGesture: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { v in
                    let delta = v / lastScale; lastScale = v
                    scale = max(0.05, min(4.0, scale * delta))
                }
                .onEnded { _ in lastScale = 1.0 },
            DragGesture()
                .onChanged { v in
                    let delta = CGSize(width:  v.translation.width  - lastOffset.width,
                                       height: v.translation.height - lastOffset.height)
                    lastOffset = v.translation
                    offset = CGSize(width: offset.width + delta.width,
                                    height: offset.height + delta.height)
                }
                .onEnded { _ in lastOffset = .zero }
        )
    }

    private var tapGestures: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { e in
                let w = worldPoint(from: e.location)
                if let hit = hitTest(w) { onNodeOpen?(hit) }
            }
            .exclusively(before:
                SpatialTapGesture()
                    .onEnded { e in selected = hitTest(worldPoint(from: e.location)) }
            )
    }

    private func worldPoint(from pt: CGPoint) -> CGPoint {
        CGPoint(x: (pt.x - offset.width)  / scale,
                y: (pt.y - offset.height) / scale)
    }

    // MARK: - Fit helpers

    private func rebuildPositions() {
        nodePositions = Dictionary(uniqueKeysWithValues: data.nodes.map { ($0.id, $0.position) })
    }

    private func fitIfNewGraph(in size: CGSize) {
        let fp = fingerprint(of: data)
        guard fp != lastFitFingerprint else { return }
        lastFitFingerprint = fp
        fit(animated: false, in: size, force: true)
    }

    private func fit(animated: Bool, in size: CGSize, force: Bool) {
        guard size.width > 0, size.height > 0, !data.nodes.isEmpty else { return }
        let xs = data.nodes.map { $0.position.x }
        let ys = data.nodes.map { $0.position.y }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return }
        let s = min(size.width * 0.9 / max(maxX - minX, 1),
                    size.height * 0.9 / max(maxY - minY, 1))
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        let tOff = CGSize(width: size.width / 2 - cx * s, height: size.height / 2 - cy * s)
        let apply = { self.scale = max(0.05, min(4.0, s)); self.offset = tOff }
        if animated { withAnimation(.easeInOut(duration: 0.25)) { apply() } } else { apply() }
        _ = force
    }

    private func centerOnSelected(_ node: CGNode?, canvas size: CGSize) {
        guard let node, size.width > 0, size.height > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            offset = CGSize(width:  size.width  / 2 - node.position.x * scale,
                            height: size.height / 2 - node.position.y * scale)
        }
    }

    private func fingerprint(of d: CGData) -> Int {
        var h = Hasher()
        h.combine(d.nodes.count); h.combine(d.edges.count)
        if let f = d.nodes.first?.id { h.combine(f) }
        if let l = d.nodes.last?.id  { h.combine(l) }
        return h.finalize()
    }

    private func hitTest(_ point: CGPoint) -> CGNode? {
        let radius: CGFloat = 16 / max(scale, 0.5)
        var best: (CGNode, CGFloat)?
        for n in data.nodes {
            let dx = n.position.x - point.x, dy = n.position.y - point.y
            let d  = sqrt(dx * dx + dy * dy)
            if d < radius, d < (best?.1 ?? .infinity) { best = (n, d) }
        }
        return best?.0
    }
}
```

- [ ] **Step 3: Build to verify both files compile**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && swift build 2>&1 | grep -E "error:|Build complete" | head -20
```

Expected: only errors in `CodeGraphView.swift` (still referencing graphify types). UAHelpers and CodeGraphCanvas compile cleanly.

- [ ] **Step 4: Commit**

```bash
git add Sources/InfiniteBrain/Features/CodeGraph/UAHelpers.swift \
        Sources/InfiniteBrain/Features/CodeGraph/CodeGraphCanvas.swift
git commit -m "feat(code-graph): add UAHelpers + CodeGraphCanvas (no ThemeStore)"
```

---

## Task 8 — Replace CodeGraphView

**Files:**
- Modify: `Sources/InfiniteBrain/Features/CodeGraph/CodeGraphView.swift` *(full replacement)*

- [ ] **Step 1: Replace the entire file**

```swift
// Sources/InfiniteBrain/Features/CodeGraph/CodeGraphView.swift
import SwiftUI
import AppKit
import InfiniteBrainCore

@MainActor
struct CodeGraphView: View {
    @State private var targetFolder: URL?       = CodeGraphView.defaultFolder()
    @State private var status:       Status     = .idle
    @State private var fullData:     CGData     = .empty
    @State private var displayData:  CGData     = .empty
    @State private var selectedNode: CGNode?
    @State private var runTask:      Task<Void, Never>?
    @State private var showSymbols:  Bool       = false
    @State private var graphExpanded: Bool      = false
    @State private var showControlsPanel: Bool  = true
    @State private var showItemsPanel:    Bool  = true
    @State private var codeArtifacts: [UAHelpers.CodeArtifact] = []

    private let runner = UARunner()
    private let store  = UAStore()

    enum Status: Equatable {
        case idle
        case running
        case loaded(nodeCount: Int, edgeCount: Int)
        case error(String)
        case binaryMissing
    }

    var body: some View {
        HSplitView {
            if showControlsPanel {
                controlsPanel
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
            }
            if showItemsPanel {
                itemsPanel
                    .frame(minWidth: 220, idealWidth: 280, maxWidth: 380)
            }
            canvasPanel
                .frame(minWidth: 360, maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { if graphExpanded { expandedOverlay } }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showControlsPanel.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                        .symbolVariant(showControlsPanel ? .fill : .none)
                }
                .help(showControlsPanel ? "Hide Controls" : "Show Controls")

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showItemsPanel.toggle() }
                } label: {
                    Image(systemName: "sidebar.squares.left")
                        .symbolVariant(showItemsPanel ? .fill : .none)
                }
                .help(showItemsPanel ? "Hide Files" : "Show Files")
            }
        }
        .onAppear(perform: loadCachedIfAvailable)
        .onDisappear { runTask?.cancel() }
        .onChange(of: fullData)   { _, _ in recomputeDisplayData() }
        .onChange(of: showSymbols) { _, _ in recomputeDisplayData() }
    }

    // MARK: - Panel 1: Controls

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("FOLDER")
                    .font(.caption).foregroundStyle(.secondary)

                Button { pickFolder() } label: {
                    HStack {
                        Image(systemName: "folder")
                        Text(targetFolder?.lastPathComponent ?? "Choose folder…")
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                    }
                }
                .buttonStyle(.bordered)

                Divider()

                HStack(spacing: 8) {
                    Button(action: runUA) {
                        Label("Generate Graph", systemImage: "play.fill")
                            .font(.callout)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.brand)
                    .disabled(targetFolder == nil || status == .running)

                    if status == .running {
                        Button("Cancel") { runTask?.cancel() }
                            .buttonStyle(.bordered)
                    }
                }

                statusBlock
            }
            .padding(12)

            Divider()
            Spacer()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var statusBlock: some View {
        switch status {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Generating graph…").font(.caption).foregroundStyle(.secondary)
            }
        case .loaded(let n, let e):
            Label("\(n) nodes · \(e) edges", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .error(let m):
            Label(m, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red)
                .lineLimit(3).truncationMode(.tail)
        case .binaryMissing:
            VStack(alignment: .leading, spacing: 6) {
                Label("understand-anything not found",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                Text(UARunner.installHint)
                    .font(.caption).foregroundStyle(.secondary)
                Button("Copy install command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(UARunner.installHint, forType: .string)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    // MARK: - Panel 2: Files & Symbols

    private var itemsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("FILES & SYMBOLS")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !codeArtifacts.isEmpty {
                    Text("\(codeArtifacts.count) files")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()

            if codeArtifacts.isEmpty {
                VStack {
                    Spacer()
                    Text("Generate graph to populate.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: nodeSelectionBinding) {
                    ForEach(codeArtifacts) { artifact in
                        Section {
                            ForEach(artifact.symbols) { sym in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(CGPalette.color(for: sym.node.kind))
                                        .frame(width: 7, height: 7)
                                    Text(sym.node.title)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    if let line = sym.node.metadata["line"] {
                                        Text(line)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary.opacity(0.7))
                                    }
                                }
                                .tag(sym.node.id)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(artifact.fileNode.title)
                                    .font(.callout.weight(.semibold))
                                    .tag(artifact.fileNode.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Panel 3: Canvas + Detail

    private var canvasPanel: some View {
        VStack(spacing: 0) {
            canvasToolbar
            Divider()
            ZStack {
                Color(NSColor.windowBackgroundColor)
                if displayData.nodes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("No code graph yet").font(.title3)
                        Text("Pick a folder on the left, then click Generate Graph.")
                            .font(.body).foregroundStyle(.secondary)
                    }
                } else {
                    CodeGraphCanvas(data: displayData,
                                    selected: $selectedNode,
                                    onNodeOpen: openNode)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !displayData.nodes.isEmpty {
                Divider()
                detailPanel
                    .frame(minHeight: 120, idealHeight: 180, maxHeight: 200)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var canvasToolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppPalette.brand)
            Text("Code Graph").font(.callout.weight(.semibold))

            if !fullData.nodes.isEmpty {
                Divider().frame(height: 14)
                Toggle(isOn: $showSymbols) {
                    Label("Symbols", systemImage: showSymbols ? "function" : "doc")
                        .font(.caption)
                }
                .toggleStyle(.switch).controlSize(.small)
                Divider().frame(height: 14)
                Text("\(displayData.nodes.count) / \(fullData.nodes.count) nodes")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !displayData.nodes.isEmpty {
                Button { graphExpanded = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Expand graph to full window")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Detail panel

    @ViewBuilder
    private var detailPanel: some View {
        if let node = selectedNode {
            detailContent(for: node)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("Select a node to inspect").font(.title3)
                Text("Click a node in the graph, or a row in the Files panel.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    @ViewBuilder
    private func detailContent(for node: CGNode) -> some View {
        let nodeColor = CGPalette.color(for: node.kind)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(nodeColor).frame(width: 10, height: 10)
                Text(node.title).font(.title3).lineLimit(1).truncationMode(.middle)
                Text(node.kind.displayName.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(nodeColor)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(nodeColor.opacity(0.15)))
                Spacer()
                if node.metadata["fileURL"] != nil {
                    Button("Open") { openNode(node) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            if let source = node.metadata["source_file"] {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10)).foregroundStyle(.secondary.opacity(0.7))
                    Text(source)
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    if let line = node.metadata["line"] {
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    if let lang = node.metadata["language"] {
                        Text(lang).font(.caption)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            Text(detailBodyForNode(node))
                .font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func detailBodyForNode(_ node: CGNode) -> String {
        let outgoing = fullData.edges.filter { $0.fromId == node.id }
        let incoming = fullData.edges.filter { $0.toId   == node.id }
        var parts: [String] = []
        if !outgoing.isEmpty { parts.append("→ \(outgoing.count) outgoing") }
        if !incoming.isEmpty { parts.append("← \(incoming.count) incoming") }
        if let kind    = node.metadata["ua_type"]   { parts.append("kind: \(kind)") }
        if let summary = node.metadata["summary"]   { parts.append(summary) }
        if let tags    = node.metadata["tags"]       { parts.append("tags: \(tags)") }
        return parts.isEmpty ? "No additional details." : parts.joined(separator: " · ")
    }

    // MARK: - Expanded overlay

    private var expandedOverlay: some View {
        ZStack(alignment: .topTrailing) {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()
            CodeGraphCanvas(data: displayData, selected: $selectedNode, onNodeOpen: openNode)
            Button { graphExpanded = false } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Close (Esc)")
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: graphExpanded)
    }

    // MARK: - Bindings

    private var nodeSelectionBinding: Binding<String?> {
        Binding(
            get: { selectedNode?.id },
            set: { newID in
                guard let id = newID,
                      let node = fullData.nodes.first(where: { $0.id == id }) else {
                    selectedNode = nil; return
                }
                if !showSymbols, node.kind == .symbol { showSymbols = true }
                selectedNode = node
            }
        )
    }

    // MARK: - Actions

    private static func defaultFolder() -> URL? {
        if let stored = UserDefaults.standard.url(forKey: "CodeGraph.lastFolder") { return stored }
        var cur = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            if FileManager.default.fileExists(
                atPath: cur.appendingPathComponent("Package.swift").path) { return cur }
            cur.deleteLastPathComponent()
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles        = false
        panel.canChooseDirectories  = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            targetFolder = url
            UserDefaults.standard.set(url, forKey: "CodeGraph.lastFolder")
        }
    }

    private func runUA() {
        guard let target = targetFolder else { return }
        status  = .running
        runTask = Task {
            let result = await runner.run(targetFolder: target)
            switch result {
            case .success(let jsonURL):
                defer { try? FileManager.default.removeItem(at: jsonURL) }
                do {
                    let raw    = try Data(contentsOf: jsonURL)
                    let parsed = try UAParser.parse(data: raw, repoRoot: target)
                    try? store.save(graphJSON: raw, for: target,
                                    nodeCount: parsed.nodes.count,
                                    edgeCount: parsed.edges.count,
                                    toolVersion: "1.0.0")
                    let laid = CodeGraphLayout.compute(
                        parsed,
                        canvasSize: UAHelpers.layoutSize(for: parsed.nodes.count))
                    self.selectedNode    = nil
                    self.fullData        = laid
                    self.codeArtifacts   = UAHelpers.collectCodeArtifacts(laid)
                    self.status          = .loaded(nodeCount: parsed.nodes.count,
                                                   edgeCount: parsed.edges.count)
                } catch let UAError.parseFailed(msg) {
                    self.status = .error("Parse failed: \(msg)")
                } catch {
                    self.status = .error("Parse failed: \(error)")
                }
            case .failure(.binaryMissing):
                self.status = .binaryMissing
            case .failure(.runFailed(let code, let tail)):
                self.status = .error("understand-anything exited \(code): \(tail.suffix(160))")
            case .failure(.noOutput):
                self.status = .error("understand-anything produced no output.")
            case .failure(.parseFailed(let m)):
                self.status = .error("Parse failed: \(m)")
            case .failure(.unsupportedSchema(let v)):
                self.status = .error("Unsupported schema v\(v)")
            case .failure(.nodeVersionTooOld(let v)):
                self.status = .error("Node.js too old: \(v)")
            case .failure(.folderNotWritable(let p)):
                self.status = .error("Folder not writable: \(p)")
            case .failure(.cancelled):
                self.status = .idle
            }
        }
    }

    private func loadCachedIfAvailable() {
        guard let target = targetFolder,
              let raw    = store.loadGraphJSON(for: target),
              let parsed = try? UAParser.parse(data: raw, repoRoot: target) else { return }
        let laid = CodeGraphLayout.compute(
            parsed,
            canvasSize: UAHelpers.layoutSize(for: parsed.nodes.count))
        self.selectedNode  = nil
        self.fullData      = laid
        self.codeArtifacts = UAHelpers.collectCodeArtifacts(laid)
        if let meta = store.lastRun(for: target) {
            self.status = .loaded(nodeCount: meta.nodeCount, edgeCount: meta.edgeCount)
        }
    }

    private func recomputeDisplayData() {
        if showSymbols {
            displayData = fullData
            return
        }
        let filesOnly: Set<CGNodeKind> = [.file, .module, .docPage]
        let kept    = fullData.nodes.filter { filesOnly.contains($0.kind) }
        let keptIds = Set(kept.map(\.id))
        let edges   = fullData.edges.filter {
            keptIds.contains($0.fromId) && keptIds.contains($0.toId) }
        displayData = CGData(nodes: kept, edges: edges)
    }

    private func openNode(_ node: CGNode) {
        guard let urlString = node.metadata["fileURL"],
              let fileURL   = URL(string: urlString),
              let root      = targetFolder else { return }
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") || filePath == rootPath else { return }
        NSWorkspace.shared.open(fileURL)
    }
}
```

- [ ] **Step 2: Build — expect clean**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Run full test suite**

```bash
swift test 2>&1 | tail -15
```

Expected: all pre-existing tests still pass, no regressions.

- [ ] **Step 4: Commit**

```bash
git add Sources/InfiniteBrain/Features/CodeGraph/CodeGraphView.swift
git commit -m "feat(code-graph): replace CodeGraphView with 3-panel UA-powered graph"
```

---

## Task 9 — Final verification

- [ ] **Step 1: Full build + test run**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain
swift build 2>&1 | tail -5
swift test  2>&1 | tail -10
```

Expected:
```
Build complete!
...
Executed N tests, with 0 failures
```

- [ ] **Step 2: Smoke test — launch app**

```bash
.build/arm64-apple-macosx/debug/InfiniteBrain
```

- [ ] **Step 3: Verify Code Graph tab**

1. Click **Code Graph** in the sidebar — 3-panel layout appears (Controls | Files & Symbols | Canvas).
2. **Binary missing state:** without `understand-anything` installed, click Generate → orange banner with install hint + copy button appears.
3. **Folder picker:** click the folder button → `NSOpenPanel` opens; selected folder name appears in the button.
4. **Cached load:** if `~/.../InfiniteBrain/CodeGraph/<hash>/knowledge-graph.json` exists from a previous run, the graph loads automatically on appear.
5. **Symbols toggle:** off shows only file-level nodes; on reveals function/class nodes.
6. **Expand:** click the expand icon → full-window overlay; Esc closes it.
7. **Node selection:** click a node → detail pane shows title, file path, line, connectivity counts.
8. **Double-click node:** file opens in the system default editor.
9. **Panel toggles:** toolbar left/right buttons collapse each side panel.
10. **Other tabs:** Vault, Knowledge Graph, Query, Drafting still open without errors.

- [ ] **Step 4: Verify no graphify references remain**

```bash
grep -r "Graphify\|graphify\|GraphifyRunner\|GraphifyParser\|GraphifyStore\|GraphifyError" \
     Sources/ Tests/ 2>/dev/null
```

Expected: no output.
