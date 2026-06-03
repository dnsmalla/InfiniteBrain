#!/usr/bin/env python3
"""Multi-language AST scan using tree-sitter-languages.

Usage: code_graph_scan.py <repo_root>
Prints JSON to stdout (schema below). Falls back to stdlib ast for Python
when tree-sitter is unavailable. Swift files are skipped (handled by host).

Output schema per file:
{
  "<relpath>": {
    "language": "typescript|javascript|python|kotlin",
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
                parent_name = None
                if isinstance(base, pyast.Name):
                    parent_name = base.id
                elif isinstance(base, pyast.Attribute):
                    parent_name = base.attr
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

    def walk(node):
        t = node.type

        if t == "import_statement":
            for c in node.children:
                if c.type == "string":
                    mod = _text(c, src).strip("'\"`")
                    imports.append({"module": mod, "line": _line(node)})

        elif t in ("class_declaration", "abstract_class_declaration"):
            name_node = _child_by_type(node, "type_identifier", "identifier")
            if name_node:
                cls_name = _text(name_node, src)
                decl = f"class {cls_name}"
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
                    walk(child)
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
            if func_node and class_stack:
                callee = None
                if func_node.type == "identifier":
                    callee = _text(func_node, src)
                elif func_node.type == "member_expression":
                    prop = _child_by_type(func_node, "property_identifier")
                    if prop:
                        callee = _text(prop, src)
                if callee:
                    calls.append({"caller": class_stack[-1], "callee": callee, "line": _line(node)})

        for child in node.children:
            walk(child)

    walk(root)
    loc = sum(1 for l in src.decode("utf-8", errors="replace").splitlines() if l.strip())
    return {"language": lang_name, "loc": loc,
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

def scan_file(path: Path):
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
