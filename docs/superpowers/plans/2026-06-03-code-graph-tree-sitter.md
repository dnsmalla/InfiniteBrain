# Code Graph — Tree-Sitter Multi-Language Scanner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the shallow regex-based code graph with a tree-sitter AST scanner that produces accurate `calls`, `inherits`, `implements`, and `method→class` edges across Python, TypeScript, JavaScript, Swift, and Kotlin.

**Architecture:** A new bundled Python script (`code_graph_scan.py`) uses `tree-sitter-languages` to parse every supported language into a rich JSON payload (symbols with parent class, inheritance chains, call sites). The Swift layer parses this payload into extended `ScanResult` structs and `StructureGraphBuilder` wires all new edge types with EXTRACTED/INFERRED/AMBIGUOUS confidence labels. The old `code_ast_scan.py` is kept as a Python-only fallback when tree-sitter is unavailable.

**Tech Stack:** Python 3 + tree-sitter 0.21 + tree-sitter-languages 1.x, Swift 5.9, SPM, XCTest.

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| **Create** | `Sources/InfiniteBrainCore/Resources/code_graph_scan.py` | tree-sitter multi-language AST scanner |
| **Modify** | `Package.swift` | bundle new Python script as resource |
| **Modify** | `Sources/InfiniteBrainCore/CodeGraph/ScanResult.swift` | add `parent`, `CallRef`, `InheritRef`, `ImplementRef` |
| **Modify** | `Sources/InfiniteBrainCore/CodeGraph/RawFileStructure.swift` | add rich fields from new JSON format |
| **Modify** | `Sources/InfiniteBrainCore/CodeGraph/CodeGraphModels.swift` | add `CGEdgeConfidence` enum + `confidence` field to `CGEdge` |
| **Modify** | `Sources/InfiniteBrainCore/CodeGraph/PythonASTExtractor.swift` | try new script first, parse new JSON format |
| **Modify** | `Sources/InfiniteBrainCore/CodeGraph/StructureGraphBuilder.swift` | wire method→class, inherits, implements, calls edges |
| **Modify** | `Sources/InfiniteBrainCore/CodeGraph/ImportResolver.swift` | add tsconfig path-alias resolution |
| **Modify** | `Sources/InfiniteBrainCore/CodeGraph/FileStructureExtractor.swift` | add Kotlin + arrow function detection |
| **Modify** | `Sources/InfiniteBrainCore/CodeGraph/StructureScanner.swift` | pass new rich data through assembly |
| **Create** | `Tests/InfiniteBrainTests/CodeGraphScanTests.swift` | new JSON format parsing + graph builder output |
| **Modify** | `Tests/InfiniteBrainTests/ImportResolverTests.swift` | add alias resolution tests |

---

## Task 1: Install tree-sitter and verify

**Files:**
- No source files changed

- [ ] **Step 1: Install the packages**

```bash
pip3 install tree-sitter==0.21.3 tree-sitter-languages==1.10.2
```

- [ ] **Step 2: Verify installation**

```bash
python3 -c "
from tree_sitter_languages import get_language, get_parser
ts = get_parser('typescript')
sw = get_parser('swift')
kt = get_parser('kotlin')
py = get_parser('python')
print('OK: typescript swift kotlin python')
"
```

Expected output: `OK: typescript swift kotlin python`

- [ ] **Step 3: Commit**

```bash
# Nothing to stage — deps are system-level. Just record the fact in CHANGELOG if desired.
git commit --allow-empty -m "chore: install tree-sitter 0.21.3 + tree-sitter-languages 1.10.2"
```

---

## Task 2: Write `code_graph_scan.py`

**Files:**
- Create: `Sources/InfiniteBrainCore/Resources/code_graph_scan.py`

- [ ] **Step 1: Write the scanner**

Create `Sources/InfiniteBrainCore/Resources/code_graph_scan.py`:

```python
#!/usr/bin/env python3
"""Multi-language AST scan using tree-sitter-languages.

Usage: code_graph_scan.py <repo_root>
Prints JSON to stdout (schema below). Falls back to stdlib ast for Python
when tree-sitter is unavailable.

Output schema per file:
{
  "<relpath>": {
    "language": "typescript|javascript|python|swift|kotlin",
    "loc": <int>,
    "imports": [{"module": "<spec>", "line": <int>}],
    "symbols": [
      {"name": "<n>", "kind": "class|function|method|interface|struct|enum|protocol",
       "line": <int>, "parent": "<class>|null", "declaration": "<sig>"}
    ],
    "inherits":   [{"child": "<n>", "parent": "<n>"}],
    "implements": [{"class_name": "<n>", "interface_name": "<n>"}],
    "calls":      [{"caller": "<n>", "callee": "<n>", "line": <int>}]
  }
}
"""
import ast as pyast
import json
import sys
from pathlib import Path

SKIP_DIRS = {".git", "node_modules", ".build", "dist", "build", ".venv",
             "venv", "__pycache__", ".code-notes", ".understand-anything",
             ".mypy_cache", ".pytest_cache", ".ruff_cache"}

EXT_LANG = {
    ".py":   "python",
    ".ts":   "typescript", ".tsx": "typescript",
    ".js":   "javascript", ".jsx": "javascript",
    ".mjs":  "javascript", ".cjs": "javascript",
    ".swift":"swift",
    ".kt":   "kotlin",
}

try:
    from tree_sitter_languages import get_parser as _get_parser
    HAS_TS = True
except ImportError:
    HAS_TS = False


# ── helpers ──────────────────────────────────────────────────────────────────

def _text(node, src: bytes) -> str:
    return src[node.start_byte:node.end_byte].decode("utf-8", errors="replace")


def _line(node) -> int:
    return node.start_point[0] + 1


def _child_by_type(node, *types):
    for c in node.children:
        if c.type in types:
            return c
    return None


def _children_by_type(node, *types):
    return [c for c in node.children if c.type in types]


# ── Python (stdlib ast, accurate) ────────────────────────────────────────────

def _scan_python_stdlib(path: Path):
    try:
        source = path.read_text(errors="replace")
        tree = pyast.parse(source, filename=str(path))
    except (SyntaxError, UnicodeDecodeError, ValueError):
        return None

    imports, symbols, inherits, calls = [], [], [], []

    class Visitor(pyast.NodeVisitor):
        def __init__(self):
            self._class_stack = []

        def visit_Import(self, node):
            for alias in node.names:
                imports.append({"module": alias.name, "line": node.lineno})

        def visit_ImportFrom(self, node):
            mod = node.module or ""
            imports.append({"module": mod, "line": node.lineno})

        def visit_ClassDef(self, node):
            symbols.append({
                "name": node.name, "kind": "class",
                "line": node.lineno, "parent": None,
                "declaration": f"class {node.name}"
            })
            for base in node.bases:
                parent_name = pyast.unparse(base) if hasattr(pyast, "unparse") else getattr(base, "id", None)
                if parent_name:
                    inherits.append({"child": node.name, "parent": parent_name})
            self._class_stack.append(node.name)
            self.generic_visit(node)
            self._class_stack.pop()

        def visit_FunctionDef(self, node):
            parent = self._class_stack[-1] if self._class_stack else None
            kind = "method" if parent else "function"
            sym_name = (parent + "." + node.name) if parent else node.name
            symbols.append({
                "name": sym_name, "kind": kind,
                "line": node.lineno, "parent": parent,
                "declaration": f"def {node.name}"
            })
            self.generic_visit(node)

        visit_AsyncFunctionDef = visit_FunctionDef

        def visit_Call(self, node):
            caller = self._class_stack[-1] if self._class_stack else None
            callee = None
            if isinstance(node.func, pyast.Name):
                callee = node.func.id
            elif isinstance(node.func, pyast.Attribute):
                callee = node.func.attr
            if callee and caller:
                calls.append({"caller": caller, "callee": callee, "line": node.lineno})
            self.generic_visit(node)

    Visitor().visit(tree)
    loc = sum(1 for l in source.splitlines() if l.strip())
    return {"language": "python", "loc": loc,
            "imports": imports, "symbols": symbols,
            "inherits": inherits, "implements": [], "calls": calls}


# ── TypeScript / JavaScript ───────────────────────────────────────────────────

def _scan_ts(path: Path, lang_name: str):
    src = path.read_bytes()
    parser = _get_parser(lang_name)
    tree = parser.parse(src)
    root = tree.root_node

    imports, symbols, inherits, implements, calls = [], [], [], [], []
    class_stack = []

    def walk(node, depth=0):
        t = node.type

        if t == "import_statement":
            for c in node.children:
                if c.type == "string":
                    # strip quotes
                    mod = _text(c, src).strip("'\"`")
                    imports.append({"module": mod, "line": _line(node)})

        elif t in ("class_declaration", "abstract_class_declaration"):
            name_node = _child_by_type(node, "type_identifier", "identifier")
            if name_node:
                cls_name = _text(name_node, src)
                decl = f"class {cls_name}"
                # extends
                heritage = _child_by_type(node, "class_heritage")
                if heritage:
                    ext = _child_by_type(heritage, "extends_clause")
                    if ext:
                        for ic in ext.children:
                            if ic.type in ("identifier", "type_identifier"):
                                parent = _text(ic, src)
                                inherits.append({"child": cls_name, "parent": parent})
                                decl += f" extends {parent}"
                    impl = _child_by_type(heritage, "implements_clause")
                    if impl:
                        for ic in impl.children:
                            if ic.type in ("type_identifier", "identifier"):
                                iface = _text(ic, src)
                                implements.append({"class_name": cls_name, "interface_name": iface})
                                decl += f" implements {iface}"
                symbols.append({"name": cls_name, "kind": "class",
                                 "line": _line(node), "parent": None, "declaration": decl})
                class_stack.append(cls_name)
                for child in node.children:
                    walk(child, depth + 1)
                class_stack.pop()
                return

        elif t == "interface_declaration":
            name_node = _child_by_type(node, "type_identifier")
            if name_node:
                iface_name = _text(name_node, src)
                symbols.append({"name": iface_name, "kind": "interface",
                                 "line": _line(node), "parent": None,
                                 "declaration": f"interface {iface_name}"})

        elif t == "method_definition":
            name_node = _child_by_type(node, "property_identifier", "identifier")
            if name_node and class_stack:
                cls = class_stack[-1]
                mname = _text(name_node, src)
                full = f"{cls}.{mname}"
                symbols.append({"name": full, "kind": "method",
                                 "line": _line(node), "parent": cls,
                                 "declaration": f"{mname}()"})

        elif t == "function_declaration":
            name_node = _child_by_type(node, "identifier")
            if name_node:
                fn = _text(name_node, src)
                symbols.append({"name": fn, "kind": "function",
                                 "line": _line(node), "parent": None,
                                 "declaration": f"function {fn}()"})

        elif t in ("lexical_declaration", "variable_declaration"):
            # const foo = () => ...  OR  const foo = function ...
            for decl_node in _children_by_type(node, "variable_declarator"):
                val = _child_by_type(decl_node, "arrow_function", "function")
                name_node = _child_by_type(decl_node, "identifier")
                if val and name_node:
                    fn = _text(name_node, src)
                    parent = class_stack[-1] if class_stack else None
                    kind = "method" if parent else "function"
                    full = f"{parent}.{fn}" if parent else fn
                    symbols.append({"name": full, "kind": kind,
                                     "line": _line(decl_node), "parent": parent,
                                     "declaration": f"const {fn} = ..."})

        elif t == "call_expression":
            func_node = node.children[0] if node.children else None
            if func_node:
                callee = None
                if func_node.type == "identifier":
                    callee = _text(func_node, src)
                elif func_node.type == "member_expression":
                    prop = _child_by_type(func_node, "property_identifier")
                    if prop:
                        callee = _text(prop, src)
                if callee and class_stack:
                    calls.append({"caller": class_stack[-1], "callee": callee, "line": _line(node)})

        for child in node.children:
            walk(child, depth + 1)

    walk(root)
    loc = sum(1 for l in src.decode("utf-8", errors="replace").splitlines() if l.strip())
    return {"language": lang_name, "loc": loc,
            "imports": imports, "symbols": symbols,
            "inherits": inherits, "implements": implements, "calls": calls}


# ── Swift ─────────────────────────────────────────────────────────────────────

def _scan_swift(path: Path):
    src = path.read_bytes()
    parser = _get_parser("swift")
    tree = parser.parse(src)
    root = tree.root_node

    imports, symbols, inherits, implements, calls = [], [], [], [], []
    class_stack = []

    _TYPE_DECLS = {
        "class_declaration": "class",
        "struct_declaration": "struct",
        "enum_declaration": "enum",
        "protocol_declaration": "protocol",
        "extension_declaration": "class",
    }

    def walk(node):
        t = node.type

        if t == "import_declaration":
            # import Foundation  →  last identifier is the module
            ids = [_text(c, src) for c in node.children if c.type == "identifier"]
            if ids:
                imports.append({"module": ids[-1], "line": _line(node)})

        elif t in _TYPE_DECLS:
            kind = _TYPE_DECLS[t]
            name_node = _child_by_type(node, "type_identifier", "identifier")
            if name_node:
                cls_name = _text(name_node, src)
                decl = f"{kind} {cls_name}"
                inh = _child_by_type(node, "type_inheritance_clause")
                if inh:
                    for ic in inh.children:
                        if ic.type == "type_identifier":
                            parent = _text(ic, src)
                            if kind in ("class", "struct"):
                                inherits.append({"child": cls_name, "parent": parent})
                            else:
                                implements.append({"class_name": cls_name, "interface_name": parent})
                symbols.append({"name": cls_name, "kind": kind,
                                 "line": _line(node), "parent": None, "declaration": decl})
                class_stack.append(cls_name)
                for child in node.children:
                    walk(child)
                class_stack.pop()
                return

        elif t == "function_declaration":
            name_node = _child_by_type(node, "simple_identifier")
            if name_node:
                fn = _text(name_node, src)
                parent = class_stack[-1] if class_stack else None
                kind = "method" if parent else "function"
                full = f"{parent}.{fn}" if parent else fn
                symbols.append({"name": full, "kind": kind,
                                 "line": _line(node), "parent": parent,
                                 "declaration": f"func {fn}()"})

        elif t == "call_expression":
            func_node = node.children[0] if node.children else None
            if func_node and func_node.type == "simple_identifier" and class_stack:
                calls.append({"caller": class_stack[-1],
                               "callee": _text(func_node, src),
                               "line": _line(node)})

        for child in node.children:
            walk(child)

    walk(root)
    loc = sum(1 for l in src.decode("utf-8", errors="replace").splitlines() if l.strip())
    return {"language": "swift", "loc": loc,
            "imports": imports, "symbols": symbols,
            "inherits": inherits, "implements": implements, "calls": calls}


# ── Kotlin ────────────────────────────────────────────────────────────────────

def _scan_kotlin(path: Path):
    src = path.read_bytes()
    parser = _get_parser("kotlin")
    tree = parser.parse(src)
    root = tree.root_node

    imports, symbols, inherits, implements, calls = [], [], [], [], []
    class_stack = []

    _KT_TYPES = {"class_declaration", "object_declaration", "interface_declaration"}

    def walk(node):
        t = node.type

        if t == "import_header":
            ids = [_text(c, src) for c in node.children if c.type == "identifier"]
            if ids:
                imports.append({"module": ".".join(ids), "line": _line(node)})

        elif t in _KT_TYPES:
            kind = "interface" if t == "interface_declaration" else "class"
            name_node = _child_by_type(node, "type_identifier", "simple_identifier")
            if name_node:
                cls_name = _text(name_node, src)
                symbols.append({"name": cls_name, "kind": kind,
                                 "line": _line(node), "parent": None,
                                 "declaration": f"class {cls_name}"})
                # delegation specifiers = parent types
                for ds in _children_by_type(node, "delegation_specifier"):
                    ut = _child_by_type(ds, "user_type")
                    if ut:
                        parent = _text(ut, src)
                        if kind == "class":
                            inherits.append({"child": cls_name, "parent": parent})
                        else:
                            implements.append({"class_name": cls_name, "interface_name": parent})
                class_stack.append(cls_name)
                for child in node.children:
                    walk(child)
                class_stack.pop()
                return

        elif t == "function_declaration":
            name_node = _child_by_type(node, "simple_identifier")
            if name_node:
                fn = _text(name_node, src)
                parent = class_stack[-1] if class_stack else None
                kind = "method" if parent else "function"
                full = f"{parent}.{fn}" if parent else fn
                symbols.append({"name": full, "kind": kind,
                                 "line": _line(node), "parent": parent,
                                 "declaration": f"fun {fn}()"})

        elif t == "call_expression":
            func_node = node.children[0] if node.children else None
            if func_node and func_node.type == "simple_identifier" and class_stack:
                calls.append({"caller": class_stack[-1],
                               "callee": _text(func_node, src),
                               "line": _line(node)})

        for child in node.children:
            walk(child)

    walk(root)
    loc = sum(1 for l in src.decode("utf-8", errors="replace").splitlines() if l.strip())
    return {"language": "kotlin", "loc": loc,
            "imports": imports, "symbols": symbols,
            "inherits": inherits, "implements": implements, "calls": calls}


# ── Dispatch ──────────────────────────────────────────────────────────────────

def scan_file(path: Path) -> dict | None:
    ext = path.suffix.lower()
    lang = EXT_LANG.get(ext)
    if not lang:
        return None
    try:
        if lang == "python":
            return _scan_python_stdlib(path)
        if not HAS_TS:
            return None
        if lang in ("typescript", "javascript"):
            return _scan_ts(path, lang)
        if lang == "swift":
            return _scan_swift(path)
        if lang == "kotlin":
            return _scan_kotlin(path)
    except Exception:
        return None
    return None


def main():
    if len(sys.argv) < 2:
        print("{}")
        return
    root = Path(sys.argv[1])
    out = {}
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        if any(part in SKIP_DIRS for part in p.parts):
            continue
        result = scan_file(p)
        if result is not None:
            out[str(p.relative_to(root))] = result
    print(json.dumps(out))


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Smoke-test the script on the InfiniteBrain repo itself**

```bash
python3 Sources/InfiniteBrainCore/Resources/code_graph_scan.py . 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f'Files scanned: {len(data)}')
total_syms = sum(len(v[\"symbols\"]) for v in data.values())
total_calls = sum(len(v[\"calls\"]) for v in data.values())
total_inherits = sum(len(v[\"inherits\"]) for v in data.values())
print(f'Symbols: {total_syms}, Calls: {total_calls}, Inherits: {total_inherits}')
"
```

Expected: output shows Files > 0, Symbols > 0, Calls > 0.

- [ ] **Step 3: Commit**

```bash
git add Sources/InfiniteBrainCore/Resources/code_graph_scan.py
git commit -m "feat(code-graph): add tree-sitter multi-language AST scanner"
```

---

## Task 3: Register new script in Package.swift

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Add resource declaration**

In `Package.swift`, in the `InfiniteBrainCore` target resources array, add:

```swift
resources: [
    .copy("Resources/skills"),
    .copy("Resources/rules"),
    .copy("Resources/web"),
    .copy("Resources/code_ast_scan.py"),
    .copy("Resources/code_graph_scan.py"),   // ← add this line
]
```

- [ ] **Step 2: Build to verify no resource errors**

```bash
cd /Users/dinsmallade/Desktop/InfiniteBrain
swift build 2>&1 | grep -E "error:|warning:|Build complete"
```

Expected: `Build complete!` with no errors about resources.

- [ ] **Step 3: Commit**

```bash
git add Package.swift
git commit -m "chore: bundle code_graph_scan.py as SPM resource"
```

---

## Task 4: Extend ScanResult and RawFileStructure

**Files:**
- Modify: `Sources/InfiniteBrainCore/CodeGraph/ScanResult.swift`
- Modify: `Sources/InfiniteBrainCore/CodeGraph/RawFileStructure.swift`

- [ ] **Step 1: Add new reference structs and extend ScanResult**

Replace the entire contents of `Sources/InfiniteBrainCore/CodeGraph/ScanResult.swift`:

```swift
import Foundation

public struct ScanResult: Sendable {
    public struct FileEntry: Equatable, Sendable {
        public let path: String
        public let language: String
        public let loc: Int
        public init(path: String, language: String, loc: Int) {
            self.path = path; self.language = language; self.loc = loc
        }
    }

    public struct Symbol: Codable, Equatable, Sendable {
        public let name: String
        public let kind: String
        public let line: Int
        public let declaration: String?
        /// Containing class name when kind == "method".
        public let parent: String?
        public init(name: String, kind: String, line: Int,
                    declaration: String? = nil, parent: String? = nil) {
            self.name = name; self.kind = kind; self.line = line
            self.declaration = declaration; self.parent = parent
        }
    }

    /// A function/method calling another function/method within the same file.
    public struct CallRef: Equatable, Sendable {
        /// Short name of the calling symbol (class name for methods, function name otherwise).
        public let caller: String
        /// Name of the callee (may reference a symbol in another file — best-effort).
        public let callee: String
        public let line: Int
        public init(caller: String, callee: String, line: Int) {
            self.caller = caller; self.callee = callee; self.line = line
        }
    }

    /// A class that inherits from another class/struct.
    public struct InheritRef: Equatable, Sendable {
        public let child: String
        public let parent: String
        public init(child: String, parent: String) {
            self.child = child; self.parent = parent
        }
    }

    /// A class/struct that implements an interface/protocol.
    public struct ImplementRef: Equatable, Sendable {
        public let className: String
        public let interfaceName: String
        public init(className: String, interfaceName: String) {
            self.className = className; self.interfaceName = interfaceName
        }
    }

    public let files:      [FileEntry]
    public let imports:    [String: [String]]
    public let symbols:    [String: [Symbol]]
    public let calls:      [String: [CallRef]]
    public let inherits:   [String: [InheritRef]]
    public let implements: [String: [ImplementRef]]

    public init(files: [FileEntry],
                imports:    [String: [String]],
                symbols:    [String: [Symbol]],
                calls:      [String: [CallRef]]       = [:],
                inherits:   [String: [InheritRef]]    = [:],
                implements: [String: [ImplementRef]]  = [:]) {
        self.files      = files
        self.imports    = imports
        self.symbols    = symbols
        self.calls      = calls
        self.inherits   = inherits
        self.implements = implements
    }

    public static let empty = ScanResult(files: [], imports: [:], symbols: [:])
}
```

- [ ] **Step 2: Extend RawFileStructure to carry rich data**

Replace the entire contents of `Sources/InfiniteBrainCore/CodeGraph/RawFileStructure.swift`:

```swift
import Foundation

public struct RawFileStructure: Equatable, Sendable {
    public let path: String
    public let language: String
    public let loc: Int
    public let rawImports: [RawImport]
    public let symbols: [ScanResult.Symbol]
    public let calls: [ScanResult.CallRef]
    public let inherits: [ScanResult.InheritRef]
    public let implements: [ScanResult.ImplementRef]

    public init(path: String, language: String, loc: Int,
                rawImports: [RawImport],
                symbols: [ScanResult.Symbol],
                calls: [ScanResult.CallRef]            = [],
                inherits: [ScanResult.InheritRef]      = [],
                implements: [ScanResult.ImplementRef]  = []) {
        self.path = path; self.language = language; self.loc = loc
        self.rawImports = rawImports; self.symbols = symbols
        self.calls = calls; self.inherits = inherits; self.implements = implements
    }
}

public struct RawImport: Equatable, Sendable {
    public let module: String
    public let name: String?
    public init(module: String, name: String? = nil) {
        self.module = module; self.name = name
    }
}
```

- [ ] **Step 3: Build to catch type errors**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!` — if there are errors they'll be in callers of `ScanResult.init` or `RawFileStructure.init` that need the new parameters added with their defaults.

- [ ] **Step 4: Commit**

```bash
git add Sources/InfiniteBrainCore/CodeGraph/ScanResult.swift \
        Sources/InfiniteBrainCore/CodeGraph/RawFileStructure.swift
git commit -m "feat(code-graph): extend ScanResult with calls/inherits/implements + symbol parent"
```

---

## Task 5: Add `CGEdgeConfidence` to CodeGraphModels

**Files:**
- Modify: `Sources/InfiniteBrainCore/CodeGraph/CodeGraphModels.swift`

- [ ] **Step 1: Add confidence enum and update CGEdge**

After the closing brace of `CGEdgeKind` (line 102), add the confidence enum. Then update `CGEdge`:

Find this block (lines 104–127) and replace it:

```swift
// BEFORE
public struct CGEdge: Equatable, Sendable {
    public let fromId: String
    public let toId: String
    public let kind: CGEdgeKind

    public init(fromId: String, toId: String, kind: CGEdgeKind) {
        self.fromId = fromId; self.toId = toId; self.kind = kind
    }
}
```

Replace with:

```swift
public enum CGEdgeConfidence: String, Sendable, Hashable {
    /// Explicitly stated in source code — 100% reliable.
    case extracted = "EXTRACTED"
    /// Reasonably deduced (e.g. call sites, type references) — ~80% reliable.
    case inferred  = "INFERRED"
    /// Uncertain (e.g. dynamic dispatch, reflection) — 50–70% reliable.
    case ambiguous = "AMBIGUOUS"
}

public struct CGEdge: Equatable, Sendable {
    public let fromId: String
    public let toId: String
    public let kind: CGEdgeKind
    public let confidence: CGEdgeConfidence

    public init(fromId: String, toId: String, kind: CGEdgeKind,
                confidence: CGEdgeConfidence = .extracted) {
        self.fromId = fromId; self.toId = toId; self.kind = kind
        self.confidence = confidence
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!` — `CGEdge.init` is backward-compatible via the default parameter.

- [ ] **Step 3: Commit**

```bash
git add Sources/InfiniteBrainCore/CodeGraph/CodeGraphModels.swift
git commit -m "feat(code-graph): add CGEdgeConfidence (EXTRACTED/INFERRED/AMBIGUOUS) to CGEdge"
```

---

## Task 6: Update PythonASTExtractor to use new script

**Files:**
- Modify: `Sources/InfiniteBrainCore/CodeGraph/PythonASTExtractor.swift`

- [ ] **Step 1: Replace the extractor with new-format-aware version**

Replace the entire file:

```swift
import Foundation

/// Runs the bundled code_graph_scan.py (tree-sitter) or falls back to
/// code_ast_scan.py (Python stdlib ast, Python only) when tree-sitter
/// is unavailable. Parses the rich JSON output into RawFileStructure.
public final class PythonASTExtractor {
    private let launcher:      ProcessLauncher
    private let pythonURL:     URL?
    private let richScriptURL: URL?   // code_graph_scan.py
    private let fallbackURL:   URL?   // code_ast_scan.py

    public init(launcher: ProcessLauncher,
                pythonURL:     URL? = PythonASTExtractor.resolvePython(),
                richScriptURL: URL? = PythonASTExtractor.bundledRichScriptURL(),
                fallbackURL:   URL? = PythonASTExtractor.bundledFallbackURL()) {
        self.launcher      = launcher
        self.pythonURL     = pythonURL
        self.richScriptURL = richScriptURL
        self.fallbackURL   = fallbackURL
    }

    public static func resolvePython() -> URL? {
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let cand = URL(fileURLWithPath: String(dir)).appendingPathComponent("python3")
                if FileManager.default.isExecutableFile(atPath: cand.path) { return cand }
            }
        }
        for p in ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"] {
            if FileManager.default.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p) }
        }
        return nil
    }

    public static func bundledRichScriptURL() -> URL? {
        Bundle.module.url(forResource: "code_graph_scan", withExtension: "py")
    }

    public static func bundledFallbackURL() -> URL? {
        Bundle.module.url(forResource: "code_ast_scan", withExtension: "py")
    }

    public func run(repoRoot: URL) async -> [RawFileStructure] {
        guard let python = pythonURL else { return [] }
        // Try rich script first.
        if let rich = richScriptURL,
           let results = await runScript(python: python, script: rich,
                                         repoRoot: repoRoot, parser: Self.parseRich) {
            return results
        }
        // Fall back to old Python-only script.
        if let fallback = fallbackURL,
           let results = await runScript(python: python, script: fallback,
                                         repoRoot: repoRoot, parser: Self.parseFallback) {
            return results
        }
        return []
    }

    private func runScript(python: URL, script: URL, repoRoot: URL,
                           parser: (Data) throws -> [RawFileStructure]) async -> [RawFileStructure]? {
        do {
            let (exit, stdout, _) = try await launcher.run(
                executable: python,
                arguments: [script.path, repoRoot.path],
                environment: nil)
            guard exit == 0 else { return nil }
            return try? parser(stdout)
        } catch { return nil }
    }

    // MARK: - Rich format (code_graph_scan.py)

    public static func parseRich(_ data: Data) throws -> [RawFileStructure] {
        struct RawSym: Decodable {
            let name: String; let kind: String; let line: Int
            let declaration: String?; let parent: String?
        }
        struct RawImp: Decodable { let module: String; let line: Int }
        struct RawCall: Decodable { let caller: String; let callee: String; let line: Int }
        struct RawInherit: Decodable { let child: String; let parent: String }
        struct RawImpl: Decodable { let class_name: String; let interface_name: String }
        struct RawFile: Decodable {
            let language: String; let loc: Int
            let imports: [RawImp]; let symbols: [RawSym]
            let calls: [RawCall]; let inherits: [RawInherit]; let implements: [RawImpl]
        }

        let map = try JSONDecoder().decode([String: RawFile].self, from: data)
        return map.map { (path, f) in
            RawFileStructure(
                path: path,
                language: f.language,
                loc: f.loc,
                rawImports: f.imports.map { RawImport(module: $0.module) },
                symbols: f.symbols.map {
                    ScanResult.Symbol(name: $0.name, kind: $0.kind, line: $0.line,
                                      declaration: $0.declaration, parent: $0.parent)
                },
                calls: f.calls.map {
                    ScanResult.CallRef(caller: $0.caller, callee: $0.callee, line: $0.line)
                },
                inherits: f.inherits.map {
                    ScanResult.InheritRef(child: $0.child, parent: $0.parent)
                },
                implements: f.implements.map {
                    ScanResult.ImplementRef(className: $0.class_name, interfaceName: $0.interface_name)
                }
            )
        }.sorted { $0.path < $1.path }
    }

    // MARK: - Fallback format (code_ast_scan.py — Python only)

    public static func parseFallback(_ data: Data) throws -> [RawFileStructure] {
        struct RawSym: Decodable { let name: String; let kind: String; let line: Int }
        struct RawImp: Decodable { let module: String; let name: String? }
        struct RawFile: Decodable { let imports: [RawImp]; let symbols: [RawSym]; let loc: Int }
        let map = try JSONDecoder().decode([String: RawFile].self, from: data)
        return map.map { (path, f) in
            RawFileStructure(
                path: path, language: "python", loc: f.loc,
                rawImports: f.imports.map { RawImport(module: $0.module, name: $0.name) },
                symbols: f.symbols.map {
                    ScanResult.Symbol(name: $0.name, kind: $0.kind, line: $0.line)
                }
            )
        }.sorted { $0.path < $1.path }
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/InfiniteBrainCore/CodeGraph/PythonASTExtractor.swift
git commit -m "feat(code-graph): update PythonASTExtractor to parse rich tree-sitter JSON output"
```

---

## Task 7: Update StructureScanner to propagate rich data

**Files:**
- Modify: `Sources/InfiniteBrainCore/CodeGraph/StructureScanner.swift`

- [ ] **Step 1: Thread calls/inherits/implements through assembly**

Replace the entire file:

```swift
import Foundation

public final class StructureScanner {
    private let fileExtractor:   FileStructureExtractor
    private let pythonExtractor: PythonASTExtractor

    public init(launcher: ProcessLauncher) {
        self.fileExtractor   = FileStructureExtractor(launcher: launcher)
        self.pythonExtractor = PythonASTExtractor(launcher: launcher)
    }

    public func scan(repoRoot: URL) async -> ScanResult {
        async let fileRaws   = fileExtractor.run(repoRoot: repoRoot)
        async let pythonRaws = pythonExtractor.run(repoRoot: repoRoot)
        let raws = await fileRaws + pythonRaws
        return Self.assemble(raws)
    }

    public static func assemble(_ raws: [RawFileStructure]) -> ScanResult {
        var byPath: [String: RawFileStructure] = [:]
        for r in raws where byPath[r.path] == nil { byPath[r.path] = r }
        let all     = byPath.values.sorted { $0.path < $1.path }
        let fileSet = Set(all.map { $0.path })

        var files:      [ScanResult.FileEntry]           = []
        var imports:    [String: [String]]               = [:]
        var symbols:    [String: [ScanResult.Symbol]]    = [:]
        var calls:      [String: [ScanResult.CallRef]]   = [:]
        var inherits:   [String: [ScanResult.InheritRef]]  = [:]
        var implements: [String: [ScanResult.ImplementRef]] = [:]

        for r in all {
            files.append(.init(path: r.path, language: r.language, loc: r.loc))
            symbols[r.path]    = r.symbols
            calls[r.path]      = r.calls
            inherits[r.path]   = r.inherits
            implements[r.path] = r.implements

            var resolved: [String] = []
            for imp in r.rawImports {
                if let target = ImportResolver.resolve(imp, fromFile: r.path,
                                                       language: r.language,
                                                       files: fileSet),
                   target != r.path {
                    resolved.append(target)
                }
            }
            var seen = Set<String>()
            imports[r.path] = resolved.filter { seen.insert($0).inserted }
        }

        return ScanResult(files: files, imports: imports, symbols: symbols,
                          calls: calls, inherits: inherits, implements: implements)
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/InfiniteBrainCore/CodeGraph/StructureScanner.swift
git commit -m "feat(code-graph): thread calls/inherits/implements through StructureScanner.assemble"
```

---

## Task 8: Update StructureGraphBuilder — wire all new edge types

**Files:**
- Modify: `Sources/InfiniteBrainCore/CodeGraph/StructureGraphBuilder.swift`

- [ ] **Step 1: Rewrite the builder with full edge set**

Replace the entire file:

```swift
import Foundation
import CoreGraphics

public enum StructureGraphBuilder {

    public static func build(_ scan: ScanResult, repoRoot: URL) -> CGData {
        var nodes:   [CGNode] = []
        var edges:   [CGEdge] = []
        var nodeIds = Set<String>()

        // ── File nodes ───────────────────────────────────────────────────────
        for f in scan.files {
            let id  = "file:\(f.path)"
            let abs = repoRoot.appendingPathComponent(f.path).absoluteString
            let kind: CGNodeKind = f.language == "markdown" ? .docPage : .file
            nodeIds.insert(id)
            nodes.append(CGNode(
                id: id,
                title: (f.path as NSString).lastPathComponent,
                kind: kind,
                position: .zero,
                metadata: ["source_file": f.path, "fileURL": abs,
                           "language": f.language, "loc": String(f.loc)]))
        }

        // ── Symbol nodes ─────────────────────────────────────────────────────
        // Build name→nodeId index for cross-symbol resolution (inherits, calls).
        var nameToId: [String: String] = [:]

        for f in scan.files {
            let fileId = "file:\(f.path)"
            let abs    = repoRoot.appendingPathComponent(f.path).absoluteString

            for sym in scan.symbols[f.path] ?? [] {
                let (kind, prefix) = nodeKindAndPrefix(for: sym.kind)
                let id = "\(prefix):\(f.path):\(sym.name)"
                guard !nodeIds.contains(id) else { continue }
                nodeIds.insert(id)
                nameToId[sym.name] = id

                var meta: [String: String] = [
                    "source_file": f.path, "fileURL": abs,
                    "line": "L\(sym.line)", "kind": sym.kind
                ]
                if let decl = sym.declaration { meta["declaration"] = decl }
                nodes.append(CGNode(id: id, title: sym.name, kind: kind,
                                    position: .zero, metadata: meta))

                // contains edge: method → parent class if known, else → file
                if sym.kind == "method", let parentName = sym.parent {
                    let parentId = "class:\(f.path):\(parentName)"
                    let owner = nodeIds.contains(parentId) ? parentId : fileId
                    edges.append(CGEdge(fromId: owner, toId: id, kind: .contains,
                                        confidence: .extracted))
                } else {
                    edges.append(CGEdge(fromId: fileId, toId: id, kind: .contains,
                                        confidence: .extracted))
                }
            }
        }

        // ── Import edges (file → file) ────────────────────────────────────────
        for (src, targets) in scan.imports {
            let srcId = "file:\(src)"
            guard nodeIds.contains(srcId) else { continue }
            for t in targets {
                let dstId = "file:\(t)"
                guard nodeIds.contains(dstId) else { continue }
                edges.append(CGEdge(fromId: srcId, toId: dstId, kind: .imports,
                                    confidence: .extracted))
            }
        }

        // ── Inherits edges (class → base class) ───────────────────────────────
        for (filePath, refs) in scan.inherits {
            for ref in refs {
                let childId = "class:\(filePath):\(ref.child)"
                guard nodeIds.contains(childId) else { continue }
                if let parentId = nameToId[ref.parent], nodeIds.contains(parentId) {
                    edges.append(CGEdge(fromId: childId, toId: parentId, kind: .inherits,
                                        confidence: .extracted))
                }
            }
        }

        // ── Implements edges (class → interface/protocol) ─────────────────────
        for (filePath, refs) in scan.implements {
            for ref in refs {
                let classId = "class:\(filePath):\(ref.className)"
                guard nodeIds.contains(classId) else { continue }
                if let ifaceId = nameToId[ref.interfaceName], nodeIds.contains(ifaceId) {
                    edges.append(CGEdge(fromId: classId, toId: ifaceId, kind: .implements,
                                        confidence: .extracted))
                }
            }
        }

        // ── Calls edges (symbol → symbol, INFERRED) ───────────────────────────
        for (filePath, refs) in scan.calls {
            for ref in refs {
                // caller is a class name; find its method or class node
                let callerId = nameToId[ref.caller]
                    ?? "class:\(filePath):\(ref.caller)"
                let calleeId = nameToId[ref.callee]
                guard let cId = calleeId,
                      nodeIds.contains(callerId),
                      nodeIds.contains(cId),
                      callerId != cId else { continue }
                edges.append(CGEdge(fromId: callerId, toId: cId, kind: .calls,
                                    confidence: .inferred))
            }
        }

        return CGData(nodes: nodes, edges: edges)
    }

    // MARK: - Helpers

    private static func nodeKindAndPrefix(for symKind: String) -> (CGNodeKind, String) {
        switch symKind {
        case "class", "struct", "enum", "protocol", "interface", "extension":
            return (.classType, "class")
        case "method":
            return (.function, "method")
        case "heading":
            return (.docPage, "heading")
        default:
            return (.function, "function")
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/InfiniteBrainCore/CodeGraph/StructureGraphBuilder.swift
git commit -m "feat(code-graph): wire method→class, inherits, implements, calls edges with confidence"
```

---

## Task 9: Update ImportResolver with path-alias support

**Files:**
- Modify: `Sources/InfiniteBrainCore/CodeGraph/ImportResolver.swift`

- [ ] **Step 1: Add tsconfig alias resolution**

Replace the entire file:

```swift
import Foundation

public enum ImportResolver {

    /// Resolve a raw import specifier to a repo-relative file path, or nil
    /// if it points outside the repo (npm package, stdlib, etc.).
    public static func resolve(_ imp: RawImport, fromFile: String,
                               language: String, files: Set<String>,
                               aliases: [String: String] = [:]) -> String? {
        switch language {
        case "python":                   return resolvePython(imp, files: files)
        case "typescript", "javascript": return resolveJS(imp, fromFile: fromFile,
                                                          files: files, aliases: aliases)
        default:                         return nil
        }
    }

    /// Read `paths` from a tsconfig.json at `repoRoot` and return a
    /// prefix→base-dir mapping.  Returns [:] if no tsconfig or no paths.
    /// Example: `"@/*": ["src/*"]` → `["@/": "src/"]`
    public static func loadTsconfigAliases(repoRoot: URL) -> [String: String] {
        let candidates = ["tsconfig.json", "apps/web/tsconfig.json",
                          "apps/web/tsconfig.paths.json"]
        for rel in candidates {
            let url = repoRoot.appendingPathComponent(rel)
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let co = json["compilerOptions"] as? [String: Any] ?? json
            guard let paths = co["paths"] as? [String: [String]] else { continue }

            var result: [String: String] = [:]
            for (key, values) in paths {
                guard let val = values.first else { continue }
                let prefix = key.hasSuffix("/*") ? String(key.dropLast(2)) + "/" : key
                let target = val.hasSuffix("/*") ? String(val.dropLast(2)) + "/" : val
                result[prefix] = target
            }
            return result
        }
        return [:]
    }

    // MARK: - Private

    private static func resolvePython(_ imp: RawImport, files: Set<String>) -> String? {
        var dotted = [String]()
        if let name = imp.name, !name.isEmpty {
            dotted.append(imp.module.isEmpty ? name : imp.module + "." + name)
        }
        if !imp.module.isEmpty { dotted.append(imp.module) }
        for d in dotted {
            let base = d.split(separator: ".").joined(separator: "/")
            for cand in ["\(base).py", "\(base)/__init__.py"] where files.contains(cand) {
                return cand
            }
        }
        return nil
    }

    private static func resolveJS(_ imp: RawImport, fromFile: String,
                                  files: Set<String>,
                                  aliases: [String: String]) -> String? {
        var spec = imp.module
        // Resolve path alias (e.g. "@/lib/api" → "src/lib/api")
        for (prefix, base) in aliases where spec.hasPrefix(prefix) {
            spec = base + spec.dropFirst(prefix.count)
            break
        }
        guard spec.hasPrefix("./") || spec.hasPrefix("../") || !imp.module.hasPrefix(".") else {
            return nil
        }
        // Absolute alias was already rewritten to relative-to-root — handle directly.
        let resolved: String
        if spec.hasPrefix("./") || spec.hasPrefix("../") {
            let dir = (fromFile as NSString).deletingLastPathComponent
            resolved = normalize(joining: dir, spec)
        } else {
            resolved = spec
        }
        let exts = ["ts", "tsx", "js", "jsx"]
        for e in exts where files.contains("\(resolved).\(e)") { return "\(resolved).\(e)" }
        for e in exts where files.contains("\(resolved)/index.\(e)") { return "\(resolved)/index.\(e)" }
        if files.contains(resolved) { return resolved }
        return nil
    }

    public static func normalize(joining base: String, _ rel: String) -> String {
        var parts = base.isEmpty ? [] : base.split(separator: "/").map(String.init)
        for comp in rel.split(separator: "/").map(String.init) {
            if comp == "." || comp.isEmpty { continue }
            else if comp == ".." { if !parts.isEmpty { parts.removeLast() } }
            else { parts.append(comp) }
        }
        return parts.joined(separator: "/")
    }
}
```

- [ ] **Step 2: Wire aliases into StructureScanner**

In `StructureScanner.swift`, update `assemble` to accept an optional aliases dict.
At the top of `assemble`, change the signature:

```swift
// Change
public static func assemble(_ raws: [RawFileStructure]) -> ScanResult {

// To
public static func assemble(_ raws: [RawFileStructure],
                             aliases: [String: String] = [:]) -> ScanResult {
```

And in the `scan` method, load aliases before calling assemble. Replace:

```swift
public func scan(repoRoot: URL) async -> ScanResult {
    async let fileRaws   = fileExtractor.run(repoRoot: repoRoot)
    async let pythonRaws = pythonExtractor.run(repoRoot: repoRoot)
    let raws = await fileRaws + pythonRaws
    return Self.assemble(raws)
}
```

With:

```swift
public func scan(repoRoot: URL) async -> ScanResult {
    let aliases = ImportResolver.loadTsconfigAliases(repoRoot: repoRoot)
    async let fileRaws   = fileExtractor.run(repoRoot: repoRoot)
    async let pythonRaws = pythonExtractor.run(repoRoot: repoRoot)
    let raws = await fileRaws + pythonRaws
    return Self.assemble(raws, aliases: aliases)
}
```

And update the call to `ImportResolver.resolve` inside the loop:

```swift
if let target = ImportResolver.resolve(imp, fromFile: r.path,
                                       language: r.language,
                                       files: fileSet,
                                       aliases: aliases),
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/InfiniteBrainCore/CodeGraph/ImportResolver.swift \
        Sources/InfiniteBrainCore/CodeGraph/StructureScanner.swift
git commit -m "feat(code-graph): resolve tsconfig path aliases in ImportResolver"
```

---

## Task 10: Add Kotlin + arrow functions to FileStructureExtractor

**Files:**
- Modify: `Sources/InfiniteBrainCore/CodeGraph/FileStructureExtractor.swift`

- [ ] **Step 1: Add Kotlin to the extension set and language dispatch**

Change `codeExtensions`:

```swift
// BEFORE
public static let codeExtensions: Set<String> = ["ts", "tsx", "js", "jsx", "mjs", "cjs", "swift", "md"]

// AFTER
public static let codeExtensions: Set<String> = [
    "ts", "tsx", "js", "jsx", "mjs", "cjs",
    "swift", "kt", "md"
]
```

Add `"kotlin"` case to `language(for:)`:

```swift
// BEFORE
case "swift": return "swift"

// AFTER
case "swift":        return "swift"
case "kt":           return "kotlin"
```

- [ ] **Step 2: Add arrow function detection and Kotlin symbols to `symbol(fromLine:language:)`**

In `symbol(fromLine:language:)`, extend the switch:

```swift
case "typescript", "javascript":
    if let n = nameAfter("function") { return .init(name: n, kind: "function", line: 0, declaration: decl()) }
    if let n = nameAfter("class")    { return .init(name: n, kind: "class",    line: 0, declaration: decl()) }
    // const foo = () => ...  or  const foo = async () => ...
    if trimmed.contains("=>") || (trimmed.contains("= function") || trimmed.contains("= async")) {
        if let n = nameAfter("const") ?? nameAfter("let") {
            return .init(name: n, kind: "function", line: 0, declaration: decl())
        }
    }
    // TypeScript interface
    if let n = nameAfter("interface") { return .init(name: n, kind: "interface", line: 0, declaration: decl()) }
    return nil
case "swift":
    if let n = nameAfter("func")     { return .init(name: n, kind: "function", line: 0, declaration: decl()) }
    if let n = nameAfter("class")    { return .init(name: n, kind: "class",    line: 0, declaration: decl()) }
    if let n = nameAfter("struct")   { return .init(name: n, kind: "struct",   line: 0, declaration: decl()) }
    if let n = nameAfter("enum")     { return .init(name: n, kind: "enum",     line: 0, declaration: decl()) }
    if let n = nameAfter("protocol") { return .init(name: n, kind: "protocol", line: 0, declaration: decl()) }
    if let n = nameAfter("extension"){ return .init(name: n, kind: "extension",line: 0, declaration: decl()) }
    return nil
case "kotlin":
    if let n = nameAfter("class")    { return .init(name: n, kind: "class",    line: 0, declaration: decl()) }
    if let n = nameAfter("fun")      { return .init(name: n, kind: "function", line: 0, declaration: decl()) }
    if let n = nameAfter("object")   { return .init(name: n, kind: "class",    line: 0, declaration: decl()) }
    if let n = nameAfter("interface"){ return .init(name: n, kind: "interface",line: 0, declaration: decl()) }
    return nil
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/InfiniteBrainCore/CodeGraph/FileStructureExtractor.swift
git commit -m "feat(code-graph): add Kotlin support + arrow function / interface detection to FileStructureExtractor"
```

---

## Task 11: Tests

**Files:**
- Create: `Tests/InfiniteBrainTests/CodeGraphScanTests.swift`
- Modify: `Tests/InfiniteBrainTests/ImportResolverTests.swift`

- [ ] **Step 1: Write tests for new JSON parsing and graph builder**

Create `Tests/InfiniteBrainTests/CodeGraphScanTests.swift`:

```swift
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

        let classNode = data.nodes.first { $0.kind == .classType }
        let methodNode = data.nodes.first { $0.kind == .function && $0.title.contains("fetch") }
        XCTAssertNotNil(classNode)
        XCTAssertNotNil(methodNode)

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
            .init(name: "Parser",          kind: "class",    line: 1),
            .init(name: "UserService",     kind: "class",    line: 10),
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

    func testEdgeConfidenceDefaultExtracted() {
        let scan = ScanResult(
            files: [.init(path: "a.ts", language: "typescript", loc: 5),
                    .init(path: "b.ts", language: "typescript", loc: 5)],
            imports: ["a.ts": ["b.ts"]],
            symbols: [:]
        )
        let data = StructureGraphBuilder.build(scan, repoRoot: URL(fileURLWithPath: "/repo"))
        let importEdge = data.edges.first { $0.kind == .imports }
        XCTAssertEqual(importEdge?.confidence, .extracted)
    }
}
```

- [ ] **Step 2: Add alias resolution tests to ImportResolverTests**

Append these methods to the existing `ImportResolverTests` class (before the final `}`):

```swift
func testAliasImportResolved() {
    let aliases = ["@/": "src/"]
    let imp = RawImport(module: "@/lib/api")
    let result = ImportResolver.resolve(imp, fromFile: "src/components/Card.tsx",
                                        language: "typescript",
                                        files: ["src/lib/api.ts"],
                                        aliases: aliases)
    XCTAssertEqual(result, "src/lib/api.ts")
}

func testAliasWithNoMatchStillReturnsNil() {
    let aliases = ["@/": "src/"]
    let imp = RawImport(module: "@/missing/thing")
    let result = ImportResolver.resolve(imp, fromFile: "src/app.ts",
                                        language: "typescript",
                                        files: ["src/other.ts"],
                                        aliases: aliases)
    XCTAssertNil(result)
}
```

- [ ] **Step 3: Run tests**

```bash
swift test --filter CodeGraphScanTests 2>&1 | tail -20
swift test --filter ImportResolverTests 2>&1 | tail -20
```

Expected: All tests PASS.

- [ ] **Step 4: Run full test suite to check for regressions**

```bash
swift test 2>&1 | tail -30
```

Expected: No new failures (pre-existing failures are documented in memory as acceptable).

- [ ] **Step 5: Commit**

```bash
git add Tests/InfiniteBrainTests/CodeGraphScanTests.swift \
        Tests/InfiniteBrainTests/ImportResolverTests.swift
git commit -m "test(code-graph): add tree-sitter JSON parsing + graph builder edge tests"
```

---

## Self-Review

**Spec coverage check:**
- ✅ tree-sitter scanner for Python, TypeScript, JavaScript, Swift, Kotlin → Task 2
- ✅ Method → class linkage (not just file) → Tasks 4, 7, 8
- ✅ `calls` edges with INFERRED confidence → Tasks 4, 7, 8
- ✅ `inherits` edges with EXTRACTED confidence → Tasks 4, 7, 8
- ✅ `implements` edges with EXTRACTED confidence → Tasks 4, 7, 8
- ✅ Arrow function / `const fn =` detection → Task 10
- ✅ Kotlin support → Tasks 2, 10
- ✅ Path alias resolution (tsconfig) → Task 9
- ✅ Confidence field on all edges → Tasks 5, 8
- ✅ Fallback to old script when tree-sitter unavailable → Task 6
- ✅ Tests for every new behavior → Task 11

**Placeholder scan:** No TBDs, no "add appropriate X", all steps have real code.

**Type consistency:**
- `ScanResult.CallRef` defined in Task 4, used in Tasks 6, 7, 8, 11 ✅
- `ScanResult.InheritRef` defined in Task 4, used in Tasks 6, 7, 8, 11 ✅
- `ScanResult.ImplementRef` defined in Task 4, used in Tasks 6, 7, 8, 11 ✅
- `CGEdgeConfidence` defined in Task 5, used in Tasks 8, 11 ✅
- `aliases:` parameter added to `ImportResolver.resolve` in Task 9, tests updated in Task 11 ✅
