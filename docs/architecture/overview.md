# Architecture Overview

InfiniteBrain is a SwiftUI macOS app that turns documents into an AI-readable
Obsidian knowledge graph. The graph follows the *Infinite Brain* schema: 16
node types, 10 semantic edge types, atomic notes 50–300 lines.

## Layered view

```
                     ┌──────────────────────────────────────┐
SwiftUI views        │ IngestView · VaultBrowser · GraphView │
                     │ QueryView                            │
                     └──────────────────────────────────────┘
                                      │
                     ┌────────────────┴───────────────────┐
ViewModels (@Observable)               │
                     └────────────────┬───────────────────┘
                                      │
                     ┌────────────────┴───────────────────┐
Services             │ Orchestrator · Reconciler           │
                     │ VaultStore · PDFExtractor · …       │
                     └────────────────┬───────────────────┘
                                      │
                     ┌────────────────┴───────────────────┐
SharedLLMKit         │ SkillRunner · LLMClient ·           │
                     │ SchemaValidator · EmbeddingProvider │
                     └────────────────┬───────────────────┘
                                      │
                     ┌────────────────┴───────────────────┐
Vault on disk        │ <vault>/notes/<type>/<id>--<…>.md   │
                     │ <vault>/inbox/                      │
                     │ <vault>/.infinitebrain/index.db     │
                     │ <vault>/.infinitebrain/skills/      │
                     └─────────────────────────────────────┘
```

## Source of truth

The vault folder is the source of truth. The SQLite sidecar at
`.infinitebrain/index.db` is a rebuildable cache: embeddings, content
hashes, full-text search, and ingest checkpoints. Deleting it triggers a
full re-index on next launch but loses no notes.

## Pipeline per file

`extract-pdf → atomize-text → (per unit) classify-node → summarize-note →
reconcile-note → {skip | improve-note | add + infer-edges} → write`.

See [pipeline.md](pipeline.md) for the full state machine.

## Quality model

Every LLM call goes through a SKILL.md file resolved by `SkillRunner`. Skills
declare an output schema; outputs that fail validation get one retry then
land in `.infinitebrain/quarantine/`. Cross-cutting policies live in
`Resources/rules/*.mdc` and are injected into every skill prompt by
`SkillRunner`.

This means quality is *configurable post-install*: users edit the SKILL.md
files in their vault to tune classification thresholds, edge inference
strictness, or summary style without rebuilding the app.
