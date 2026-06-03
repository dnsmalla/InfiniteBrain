# Code Graph

The Code Graph tab visualizes the structure of a code repository as an interactive
graph. Scanning is fully built in via the shared [GraphKit](https://github.com/dnsmalla/graph-kit)
package — no external CLI to install.

## Prerequisite: tree-sitter (for the rich scanner)

The rich multi-language scanner shells out to a bundled Python script that needs
tree-sitter on the **system** `python3` (the one found on your `PATH`):

```bash
pip3 install tree-sitter==0.21.3 tree-sitter-languages==1.10.2
```

With it, Code Graph parses Python, TypeScript, JavaScript, and Kotlin via tree-sitter
(Swift is parsed by a built-in line scanner). Without it, scanning gracefully falls
back to Python-only stdlib `ast` — Python graphs lose call/inheritance edges and
TS/JS/Kotlin produce no graph.

## Usage

1. Open **Code Graph** in the sidebar.
2. Click the folder button to pick a repository.
3. Click **Generate Graph**.
4. Toggle **Symbols** to show class/function nodes and their `calls`/`inherits`/`implements` edges.
5. Click a node to inspect it; use **Open** to reveal the underlying file.

## What gets extracted

- **Nodes:** files, classes/structs/enums/protocols/interfaces, functions, methods.
- **Edges:** `contains` (file→symbol, method→class), `imports` (file→file, resolving
  relative paths and `tsconfig` path aliases), `calls`, `inherits`, `implements`.
- **Confidence:** each edge is `EXTRACTED` (from source), `INFERRED` (e.g. call sites),
  or `AMBIGUOUS`.

## Caching

Each folder's parsed structure is cached at
`~/Library/Application Support/GraphKit/CodeGraph/<hash>/` and in the repo's
`.code-notes/scan-cache.json`. Re-running re-parses only files whose content changed.

## Troubleshooting

- **Empty graph for a TS/JS/Kotlin repo** — tree-sitter isn't installed on the
  `python3` that InfiniteBrain finds. Install it (see above) and regenerate.
- **No `calls`/`inherits` edges on a Python repo** — same cause; the stdlib fallback
  doesn't emit those.
