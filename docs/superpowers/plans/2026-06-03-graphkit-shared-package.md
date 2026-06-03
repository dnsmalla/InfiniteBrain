# GraphKit — Shared Graph Engine Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Extract the duplicated, drifted graph engine (code→graph + text→graph) out of both InfiniteBrain and meet-notes into one standalone, versioned SPM package `GraphKit`, so a single update propagates to every consumer.

**Architecture:** A new platform-light SPM library `GraphKit` (Foundation/CoreGraphics/CryptoKit + Yams; **no SwiftUI**) holds the canonical models, scanners, builder, parsers, incremental cache, and text→graph layer. InfiniteBrain and meet-notes depend on it; each app keeps only its own SwiftUI canvas/layout/views. Engine takes the *union of the best* of both repos: InfiniteBrain's tree-sitter scanner + `CGEdgeConfidence`, plus meet-notes' `MemoryGenerator`/`MemoryNotesWriter` (text→graph) and `Fingerprint`/`ScanCache` (incremental caching).

**Tech Stack:** Swift 5.9, SwiftPM, XCTest, Yams, Python 3 + tree-sitter (bundled resource).

**Distribution:** Develop with a local `.package(path:)` dependency for fast iteration; publish to GitHub and pin via `.package(url:, from:)` as the final step (Phase 4, requires explicit go-ahead before any push).

---

## Canonical-source decisions (where divergence exists)

| Component | Winner | Why |
|---|---|---|
| `CGEdge` + `CGEdgeConfidence` | **InfiniteBrain** | meet-notes lacks the confidence field; engine keeps it (default `.extracted`) |
| `FileStructureExtractor`, `PythonASTExtractor`, `StructureScanner`, `StructureGraphBuilder`, `ImportResolver`, `code_graph_scan.py` | **InfiniteBrain** | tree-sitter + path-alias + Kotlin + arrow-fn support; meet-notes is the old regex version |
| `MemoryGenerator`, `MemoryNotesWriter` (text→graph) | **meet-notes** | InfiniteBrain has no text→graph |
| `Fingerprint`, `ScanCache` (incremental cache) | **meet-notes** | InfiniteBrain re-scans every run |
| `CGNodeKind` / `CGEdgeKind` enums | **union** | take all cases from both; they're ~identical, verify by diff |
| `UAParser`, `UAStore`, `UAError` | either (identical) | keep one copy |
| `CGPalette` (SwiftUI `Color`) | **excluded** | stays per-app (UI); engine has no SwiftUI |
| `CGSimulation`, `CodeGraphLayout` (layout math) | **per-app** | per chosen "Engine" scope, layout/canvas stay in each app |

---

## File Map

**New package** at `/Users/dinsmallade/Desktop/GraphKit/`:

| Path | Source | Notes |
|---|---|---|
| `Package.swift` | new | library `GraphKit`, Yams dep, resources, test target |
| `Sources/GraphKit/Models/CodeGraphModels.swift` | IB, minus `CGPalette` | CGNode/CGEdge/CGData/Kinds/Confidence/UALayer/UATourStep |
| `Sources/GraphKit/Scan/ScanResult.swift` | IB | |
| `Sources/GraphKit/Scan/RawFileStructure.swift` | IB | |
| `Sources/GraphKit/Scan/FileStructureExtractor.swift` | IB | tree-sitter-aware |
| `Sources/GraphKit/Scan/PythonASTExtractor.swift` | IB | rich + fallback; `Bundle.module` |
| `Sources/GraphKit/Scan/StructureScanner.swift` | IB | |
| `Sources/GraphKit/Scan/ImportResolver.swift` | IB | aliases |
| `Sources/GraphKit/Scan/ProcessLauncher.swift` | IB | |
| `Sources/GraphKit/Build/StructureGraphBuilder.swift` | IB | confidence edges |
| `Sources/GraphKit/Cache/Fingerprint.swift` | meet-notes | |
| `Sources/GraphKit/Cache/ScanCache.swift` | meet-notes | |
| `Sources/GraphKit/Text/MemoryGenerator.swift` | meet-notes | needs Yams |
| `Sources/GraphKit/Text/MemoryNotesWriter.swift` | meet-notes | |
| `Sources/GraphKit/Notes/CodeNoteWriter.swift` | IB | reconcile w/ meet-notes CodeNoteGenerator |
| `Sources/GraphKit/Parse/UAParser.swift` | either | |
| `Sources/GraphKit/Parse/UAStore.swift` | either | |
| `Sources/GraphKit/Parse/UAError.swift` | either | |
| `Sources/GraphKit/Resources/code_ast_scan.py` | IB | bundled |
| `Sources/GraphKit/Resources/code_graph_scan.py` | IB | bundled |
| `Tests/GraphKitTests/*` | IB CodeGraph tests + new text→graph tests | |

**InfiniteBrain edits:** add GraphKit dep; delete 14 `CodeGraph/*` engine files (keep `CGSimulation.swift`, `CodeGraphLayout.swift`, and a new per-app `CGPalette.swift`); add `import GraphKit` to 4 files; move `CGPalette` into the app.

**meet-notes edits:** add GraphKit dep; delete the engine files from `CodeGraph/` + `CodeNotes/` (keep app-specific `BugReport`, `QAEntry`, `BugStatus+UI`, `CodeNoteService`, `CodeGraphLayout`, views, and a per-app `CGPalette`); add `import GraphKit` to ~4 files; gains tree-sitter + confidence for free.

---

## Phase 1 — Create GraphKit (standalone, builds + tests green)

### Task 1.1: Scaffold the package

- [ ] **Step 1: Create directories**

```bash
mkdir -p /Users/dinsmallade/Desktop/GraphKit/Sources/GraphKit/{Models,Scan,Build,Cache,Text,Notes,Parse,Resources}
mkdir -p /Users/dinsmallade/Desktop/GraphKit/Tests/GraphKitTests
```

- [ ] **Step 2: Write `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GraphKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "GraphKit", targets: ["GraphKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "GraphKit",
            dependencies: ["Yams"],
            path: "Sources/GraphKit",
            resources: [
                .copy("Resources/code_ast_scan.py"),
                .copy("Resources/code_graph_scan.py"),
            ]
        ),
        .testTarget(
            name: "GraphKitTests",
            dependencies: ["GraphKit"],
            path: "Tests/GraphKitTests"
        ),
    ]
)
```

- [ ] **Step 3: git init + .gitignore**

```bash
cd /Users/dinsmallade/Desktop/GraphKit
git init
printf '.build/\n.swiftpm/\n.DS_Store\n*.xcodeproj\n.venv/\n' > .gitignore
```

- [ ] **Step 4: Commit scaffold**

```bash
cd /Users/dinsmallade/Desktop/GraphKit
git add Package.swift .gitignore
git commit -m "chore: scaffold GraphKit SPM package"
```

### Task 1.2: Copy engine source from InfiniteBrain

- [ ] **Step 1: Copy the InfiniteBrain engine files (verbatim) into GraphKit**

```bash
IB=/Users/dinsmallade/Desktop/InfiniteBrain/Sources/InfiniteBrainCore/CodeGraph
GK=/Users/dinsmallade/Desktop/GraphKit/Sources/GraphKit
cp "$IB/CodeGraphModels.swift"        "$GK/Models/"
cp "$IB/ScanResult.swift"             "$GK/Scan/"
cp "$IB/RawFileStructure.swift"       "$GK/Scan/"
cp "$IB/FileStructureExtractor.swift" "$GK/Scan/"
cp "$IB/PythonASTExtractor.swift"     "$GK/Scan/"
cp "$IB/StructureScanner.swift"       "$GK/Scan/"
cp "$IB/ImportResolver.swift"         "$GK/Scan/"
cp "$IB/ProcessLauncher.swift"        "$GK/Scan/"
cp "$IB/StructureGraphBuilder.swift"  "$GK/Build/"
cp "$IB/CodeNoteWriter.swift"         "$GK/Notes/"
cp "$IB/UAParser.swift"               "$GK/Parse/"
cp "$IB/UAStore.swift"                "$GK/Parse/"
cp "$IB/UAError.swift"                "$GK/Parse/"
cp /Users/dinsmallade/Desktop/InfiniteBrain/Sources/InfiniteBrainCore/Resources/code_ast_scan.py   "$GK/Resources/"
cp /Users/dinsmallade/Desktop/InfiniteBrain/Sources/InfiniteBrainCore/Resources/code_graph_scan.py "$GK/Resources/"
```

- [ ] **Step 2: Remove `CGPalette` from the copied `CodeGraphModels.swift`**

In `Sources/GraphKit/Models/CodeGraphModels.swift`: delete the entire `public enum CGPalette { ... }` block AND change the file's imports from `import Foundation / CoreGraphics / SwiftUI` to just `import Foundation` + `import CoreGraphics`. (CGPoint comes from CoreGraphics; no SwiftUI needed once CGPalette is gone.)

- [ ] **Step 3: Build (will fail until text/cache added, but catches model errors)**

```bash
cd /Users/dinsmallade/Desktop/GraphKit && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected at this stage: `Build complete!` (these IB files only need Foundation/CoreGraphics/CryptoKit + Bundle.module, all available).

- [ ] **Step 4: Commit**

```bash
cd /Users/dinsmallade/Desktop/GraphKit
git add Sources/GraphKit
git commit -m "feat: import code→graph engine from InfiniteBrain (tree-sitter scanner + confidence)"
```

### Task 1.3: Add text→graph + cache from meet-notes

- [ ] **Step 1: Copy the meet-notes-only files**

```bash
MN=/Users/dinsmallade/Desktop/meet-notes/mac/Sources/MeetNotesMac
GK=/Users/dinsmallade/Desktop/GraphKit/Sources/GraphKit
cp "$MN/CodeGraph/MemoryGenerator.swift"  "$GK/Text/"
cp "$MN/CodeGraph/MemoryNotesWriter.swift" "$GK/Text/"
cp "$MN/CodeNotes/Fingerprint.swift"      "$GK/Cache/"
cp "$MN/CodeNotes/ScanCache.swift"        "$GK/Cache/"
```

- [ ] **Step 2: Reconcile model enums (union of cases)**

Diff meet-notes' `CGNodeKind`/`CGEdgeKind` against the copied InfiniteBrain ones. Add any case present in meet-notes but missing in GraphKit (and its `displayName`). Read both files; if identical, no change. Record any additions in the commit message.

- [ ] **Step 3: Build and fix compile errors**

```bash
cd /Users/dinsmallade/Desktop/GraphKit && swift build 2>&1 | grep -E "error:|Build complete"
```

Likely fixes: `MemoryGenerator` may reference types/helpers not copied (e.g. a `MemoryStore`); resolve by copying the missing engine-level helper or inlining. Do NOT pull in app-specific types (BugReport, QAEntry). If `MemoryGenerator` needs `MemoryStore.swift`, copy it into `Cache/` or `Text/`. Iterate until `Build complete!`.

- [ ] **Step 4: Commit**

```bash
cd /Users/dinsmallade/Desktop/GraphKit
git add Sources/GraphKit
git commit -m "feat: add text→graph (MemoryGenerator/Writer) + incremental cache (Fingerprint/ScanCache) from meet-notes"
```

### Task 1.4: Port tests

- [ ] **Step 1: Copy InfiniteBrain's engine tests, fix imports**

```bash
IBT=/Users/dinsmallade/Desktop/InfiniteBrain/Tests/InfiniteBrainTests
GKT=/Users/dinsmallade/Desktop/GraphKit/Tests/GraphKitTests
cp "$IBT/CodeGraphScanTests.swift" "$IBT/ImportResolverTests.swift" \
   "$IBT/CodeGraphLayoutTests.swift" "$IBT/CGSimulationTests.swift" \
   "$IBT/GraphifyParserTests.swift" "$IBT/GraphNodeMetadataTests.swift" "$GKT/" 2>/dev/null || true
```

Then in every copied test file replace `@testable import InfiniteBrainCore` with `import GraphKit`. NOTE: `CGSimulationTests`/`CodeGraphLayoutTests` test layout types that are NOT in GraphKit — DELETE those two copied files (layout stays per-app). Keep `CodeGraphScanTests`, `ImportResolverTests`, `GraphifyParserTests`, `GraphNodeMetadataTests`.

- [ ] **Step 2: Add a text→graph test**

Create `Tests/GraphKitTests/MemoryGeneratorTests.swift`:

```swift
import XCTest
@testable import GraphKit

final class MemoryGeneratorTests: XCTestCase {
    func testGeneratesChunksFromMarkdownHeadings() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("gk-memtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let md = """
        # Title
        Intro text.

        ## Section A
        Body A with a [[Section B]] link.

        ## Section B
        Body B.
        """
        let file = tmp.appendingPathComponent("doc.md")
        try md.write(to: file, atomically: true, encoding: .utf8)

        let result = MemoryGenerator.generate(files: [file])
        XCTAssertGreaterThan(result.chunks.count, 0, "should chunk by heading")
        XCTAssertGreaterThan(result.graph.nodes.count, 0, "should produce graph nodes")
    }
}
```

- [ ] **Step 3: Run tests**

```bash
cd /Users/dinsmallade/Desktop/GraphKit && swift test 2>&1 | tail -15
```

Expected: all pass. Fix any namespace/init mismatches.

- [ ] **Step 4: Commit**

```bash
cd /Users/dinsmallade/Desktop/GraphKit
git add Tests
git commit -m "test: port engine tests + add text→graph coverage to GraphKit"
```

---

## Phase 2 — InfiniteBrain consumes GraphKit

### Task 2.1: Add dependency, delete local engine copies

- [ ] **Step 1: Add GraphKit (local path) to InfiniteBrain Package.swift**

In `dependencies:` add `.package(path: "../GraphKit")`. In the `InfiniteBrainCore` target `dependencies:` add `.product(name: "GraphKit", package: "GraphKit")`.

- [ ] **Step 2: Delete the engine files now owned by GraphKit**

```bash
CG=/Users/dinsmallade/Desktop/InfiniteBrain/Sources/InfiniteBrainCore/CodeGraph
rm "$CG/CodeGraphModels.swift" "$CG/ScanResult.swift" "$CG/RawFileStructure.swift" \
   "$CG/FileStructureExtractor.swift" "$CG/PythonASTExtractor.swift" "$CG/StructureScanner.swift" \
   "$CG/ImportResolver.swift" "$CG/ProcessLauncher.swift" "$CG/StructureGraphBuilder.swift" \
   "$CG/CodeNoteWriter.swift" "$CG/UAParser.swift" "$CG/UAStore.swift" "$CG/UAError.swift"
# Keep: CGSimulation.swift, CodeGraphLayout.swift (per-app layout)
```

Also remove the two python resources from `InfiniteBrainCore` (now provided by GraphKit's bundle):
```bash
rm /Users/dinsmallade/Desktop/InfiniteBrain/Sources/InfiniteBrainCore/Resources/code_ast_scan.py \
   /Users/dinsmallade/Desktop/InfiniteBrain/Sources/InfiniteBrainCore/Resources/code_graph_scan.py
```
And delete their two `.copy(...)` lines from InfiniteBrain Package.swift.

- [ ] **Step 3: Create per-app `CGPalette.swift`**

Create `Sources/InfiniteBrain/CoreUI/CGPalette.swift` (app target, can use SwiftUI) with the `CGPalette` enum that was removed from the model — `import SwiftUI` + `import GraphKit`, switch over `CGNodeKind` returning `Color`. (Copy the body from git history of the old CodeGraphModels.swift.)

- [ ] **Step 4: Add `import GraphKit` to the consumers**

Add `import GraphKit` to each of:
- `Sources/InfiniteBrainCore/Extraction/DocumentScanner.swift` (uses `ScanResult` — NOTE: this is meet-notes-style naming collision risk; verify it uses GraphKit's `ScanResult`, not its own. If DocumentScanner has its OWN `ScanResults` type, leave it; it's unrelated.)
- `Sources/InfiniteBrain/Features/KnowledgeGraph/GraphView.swift`
- `Sources/InfiniteBrain/Features/Help/SchemaView.swift`
- `Sources/InfiniteBrain/Features/QueryEngine/QueryView.swift`
- `Sources/InfiniteBrain/Features/CodeGraph/CodeGraphView.swift` and `CodeGraphCanvas.swift` (they use CGData/CGNode/StructureScanner/StructureGraphBuilder/CodeNoteWriter)
- `Sources/InfiniteBrainCore/CodeGraph/CGSimulation.swift`, `CodeGraphLayout.swift` (operate on CGData/CGNode)

- [ ] **Step 5: Build**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && swift build 2>&1 | grep -E "error:|Build complete"
```

Fix every "Cannot find type" by adding `import GraphKit` to that file. Iterate to `Build complete!`.

- [ ] **Step 6: Run tests**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && swift test 2>&1 | tail -20
```

Delete the InfiniteBrain test files that are now duplicated in GraphKit (`CodeGraphScanTests`, `ImportResolverTests`, `GraphifyParserTests`, `GraphNodeMetadataTests`) — keep `CGSimulationTests`/`CodeGraphLayoutTests` (layout is still per-app). Expected: green (allowing pre-existing unrelated failures).

- [ ] **Step 7: Build the app & smoke-test**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain && bash bin/build_app.sh 2>&1 | grep -E "error:|Build complete|built"
```

- [ ] **Step 8: Commit**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain
git add -A
git commit -m "refactor(code-graph): consume shared GraphKit package; delete local engine copies"
```

---

## Phase 3 — meet-notes consumes GraphKit

### Task 3.1: Add dependency, delete local engine copies, gain tree-sitter

- [ ] **Step 1: Add GraphKit to meet-notes Package.swift**

In `dependencies:` add `.package(path: "../../GraphKit")` (meet-notes Package.swift is at `mac/`, GraphKit is two levels up at Desktop). Add `.product(name: "GraphKit", package: "GraphKit")` to the `MeetNotesMac` target deps. Remove the `.copy("Resources/code_ast_scan.py")` line (now from GraphKit).

- [ ] **Step 2: Delete meet-notes engine files (keep app-specific ones)**

```bash
MN=/Users/dinsmallade/Desktop/meet-notes/mac/Sources/MeetNotesMac
rm "$MN/CodeGraph/CodeGraphModels.swift" "$MN/CodeGraph/ProcessLauncher.swift" \
   "$MN/CodeGraph/MemoryGenerator.swift" "$MN/CodeGraph/MemoryNotesWriter.swift" \
   "$MN/CodeGraph/UAParser.swift" "$MN/CodeGraph/UAStore.swift" "$MN/CodeGraph/UAError.swift"
rm "$MN/CodeNotes/ScanResult.swift" "$MN/CodeNotes/RawFileStructure.swift" \
   "$MN/CodeNotes/FileStructureExtractor.swift" "$MN/CodeNotes/PythonASTExtractor.swift" \
   "$MN/CodeNotes/StructureScanner.swift" "$MN/CodeNotes/StructureGraphBuilder.swift" \
   "$MN/CodeNotes/ImportResolver.swift" "$MN/CodeNotes/Fingerprint.swift" "$MN/CodeNotes/ScanCache.swift"
rm "$MN/Resources/code_ast_scan.py"
# Keep app-specific: CodeGraph/{BugReport,BugStatus+UI,QAEntry,CodeGraphLayout,MemoryStore?}.swift,
#   CodeNotes/{CodeNoteService,CodeNoteGenerator,CodeNoteError}.swift, Views/CodeGraph/*
```

NOTE on `MemoryStore.swift` and `CodeNoteGenerator.swift`: if Phase 1.3 pulled `MemoryStore` into GraphKit, delete it here too; otherwise keep it local. Decide during Phase 1 and keep this consistent.

- [ ] **Step 3: Create per-app `CGPalette.swift` for meet-notes**

If meet-notes' views use `CGPalette`, create `mac/Sources/MeetNotesMac/Views/CodeGraph/CGPalette.swift` (SwiftUI + `import GraphKit`) from its old model file's git history.

- [ ] **Step 4: Add `import GraphKit` to consumers**

Add to the ~4 meet-notes files that reference engine types: `Views/CodeGraph/CodeGraphCanvas.swift`, `Views/CodeGraph/UAGraphView.swift`, `Views/CodeGraph/UAHelpers.swift`, `CodeNotes/CodeNoteService.swift`, `CodeNotes/CodeNoteGenerator.swift`, `CodeGraph/CodeGraphLayout.swift`, plus any app file using `MemoryGenerator`.

- [ ] **Step 5: Reconcile API drift**

meet-notes called the old `CGEdge(fromId:toId:kind:)` — GraphKit's adds a defaulted `confidence:`, so old call sites still compile. But meet-notes' `StructureScanner.scan` signature or `MemoryGenerator` API may differ from GraphKit's. Fix call sites to match GraphKit's public API (e.g. `StructureScanner(launcher:).scan(repoRoot:)`). Build-driven: fix each error.

- [ ] **Step 6: Build**

```bash
cd /Users/dinsmallade/Desktop/meet-notes/mac && swift build 2>&1 | grep -E "error:|Build complete"
```

Iterate to `Build complete!`.

- [ ] **Step 7: Run tests**

```bash
cd /Users/dinsmallade/Desktop/meet-notes/mac && swift test 2>&1 | tail -20
```

Remove meet-notes engine tests now covered by GraphKit; fix remaining. Expected green.

- [ ] **Step 8: Commit**

```bash
cd /Users/dinsmallade/Desktop/meet-notes
git add -A
git commit -m "refactor(code-graph): consume shared GraphKit; delete local engine copies (gains tree-sitter + confidence)"
```

---

## Phase 4 — Publish & pin (REQUIRES EXPLICIT GO-AHEAD before any push)

- [ ] **Step 1: Create GitHub repo & push**

```bash
cd /Users/dinsmallade/Desktop/GraphKit
gh repo create dnsmalla/GraphKit --private --source=. --remote=origin --push
git tag 1.0.0 && git push origin 1.0.0
```

- [ ] **Step 2: Switch both apps from path to URL**

InfiniteBrain: `.package(url: "https://github.com/dnsmalla/GraphKit.git", from: "1.0.0")`.
meet-notes: same. Run `swift package resolve` in each; build + test both.

- [ ] **Step 3: Document the update workflow**

Add to both READMEs: "Graph engine lives in [GraphKit](https://github.com/dnsmalla/GraphKit). To update: change GraphKit, tag a release, then `swift package update GraphKit` in each app." Add `requirements.txt` note (tree-sitter) to GraphKit README.

- [ ] **Step 4: Commit docs in all three repos.**

---

## Self-Review

- ✅ Centralizes code→graph (IB tree-sitter) + text→graph (meet-notes MemoryGenerator) → Phase 1
- ✅ No SwiftUI in engine (CGPalette excluded, per-app) → Tasks 1.2, 2.1, 3.1
- ✅ Both apps consume one source; update once → Phase 4
- ✅ meet-notes gains tree-sitter + confidence automatically → Phase 3
- ✅ Layout/canvas stay per-app per chosen scope → kept in Tasks 2.1, 3.1
- ⚠️ Open risk: `MemoryGenerator` transitive deps (MemoryStore?) — resolved build-driven in Task 1.3
- ⚠️ Open risk: `ScanResult` naming collision with meet-notes `DocumentScanner.ScanResults` — verified in Task 2.1 Step 4
- ⚠️ Push to GitHub gated behind explicit go-ahead → Phase 4
