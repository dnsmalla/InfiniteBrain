#!/usr/bin/env python3
"""Deterministic AST scan for a repo's Python files.

Usage: code_ast_scan.py <repo_root>
Prints JSON to stdout: { "<relpath>": {imports, symbols, loc}, ... }
  imports: [{"module": "<dotted>", "name": "<imported name or null>"}]
  symbols: [{"name": "<n>", "kind": "function|class|method", "line": <int>}]
  loc:     <non-empty line count>
Pure stdlib (ast/json/sys/pathlib). Files that fail to parse are skipped.
"""
import ast
import json
import sys
from pathlib import Path

SKIP_DIRS = {".git", "node_modules", ".build", "dist", "build", ".venv",
             "venv", "__pycache__", ".code-notes", ".understand-anything",
             ".mypy_cache", ".pytest_cache", ".ruff_cache"}


def analyze(path: Path):
    try:
        source = path.read_text(errors="replace")
        tree = ast.parse(source, filename=str(path))
    except (SyntaxError, UnicodeDecodeError, ValueError):
        return None

    imports = []
    symbols = []
    for node in ast.iter_child_nodes(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imports.append({"module": alias.name, "name": None})
        elif isinstance(node, ast.ImportFrom):
            mod = node.module or ""
            for alias in node.names:
                imports.append({"module": mod, "name": alias.name})
        elif isinstance(node, ast.ClassDef):
            symbols.append({"name": node.name, "kind": "class", "line": node.lineno})
            for item in node.body:
                if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    symbols.append({"name": node.name + "." + item.name,
                                    "kind": "method", "line": item.lineno})
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            symbols.append({"name": node.name, "kind": "function", "line": node.lineno})

    loc = sum(1 for line in source.splitlines() if line.strip())
    return {"imports": imports, "symbols": symbols, "loc": loc}


def main():
    if len(sys.argv) < 2:
        print("{}")
        return
    root = Path(sys.argv[1])
    out = {}
    for py in root.rglob("*.py"):
        if any(part in SKIP_DIRS for part in py.parts):
            continue
        result = analyze(py)
        if result is not None:
            out[str(py.relative_to(root))] = result
    print(json.dumps(out))


if __name__ == "__main__":
    main()
