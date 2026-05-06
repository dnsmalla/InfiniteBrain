# InfiniteBrain

A macOS desktop app that turns PDFs and other documents into an AI-optimized
Obsidian knowledge graph — atomic notes, 16 node types, 10 semantic edge types.

Drop files in. The app extracts, atomizes, classifies, summarizes, and writes
Obsidian-compatible markdown into your vault. New documents are reconciled
against existing notes: duplicates are skipped, weaker notes are improved in
place, and genuinely new ideas get their own files.

## Status

Scaffolded. Pipeline stages are defined as skills in
`Sources/InfiniteBrain/Resources/skills/` but not yet wired through
`SharedLLMKit`. See [docs/architecture/overview.md](docs/architecture/overview.md).

## Layout

```
InfiniteBrain/
├── Package.swift
├── SharedLLMKit/                        # local Swift package
│   └── Sources/SharedLLMKit/
│       ├── Client/                      # LLM provider clients
│       ├── SkillRunner/                 # loads + runs SKILL.md files
│       ├── Schema/                      # JSON-schema validation
│       └── Embeddings/                  # local + remote embeddings
├── Sources/InfiniteBrain/
│   ├── InfiniteBrainApp.swift
│   ├── Models/                          # Note, NodeType, EdgeType, Vault
│   ├── Services/                        # Orchestrator, Reconciler, VaultStore, …
│   ├── ViewModels/
│   ├── Views/                           # IngestView, VaultBrowser, GraphView, QueryView
│   └── Resources/
│       ├── skills/                      # one folder per pipeline stage
│       └── rules/                       # cross-cutting policies (.mdc)
├── Tests/InfiniteBrainTests/
├── docs/
├── scripts/
└── bin/
```

## Build

```bash
swift build
./bin/build_app.sh        # produces InfiniteBrain.app + .dmg
```

## Configuring quality

Every LLM call routes through a skill in `Resources/skills/<name>/SKILL.md`.
On first launch the bundled skills are copied to
`<vault>/.infinitebrain/skills/` so you can edit them per-vault without
rebuilding the app. Cross-cutting rules live in `Resources/rules/*.mdc`.
