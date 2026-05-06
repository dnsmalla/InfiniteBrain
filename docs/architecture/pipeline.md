# Ingest pipeline

```
file dropped in inbox/
        │
        ▼
┌──────────────┐
│ extract-pdf  │   raw PDFKit text → cleaned text + headings
└──────┬───────┘
       ▼
┌──────────────┐
│ atomize-text │   cleaned text → [AtomicUnit] (50–300 lines each)
└──────┬───────┘
       │  for each unit (concurrency 4):
       ▼
┌──────────────┐
│ classify-node│   unit → NodeType + confidence
└──────┬───────┘
       ▼
┌──────────────┐
│ summarize    │   unit → ≤50-token summary
└──────┬───────┘
       ▼
┌──────────────┐
│ reconcile    │   summary + nearest K vault notes → skip | improve | add
└─┬──────┬──────┘
  │      │
  │      ├── skip:    log decision, drop unit
  │      │
  │      ├── improve: improve-note(existing, candidate)
  │      │            → VaultStore.update; bump version
  │      │
  └──────┴── add: VaultStore.write(new) → infer-edges → patchEdges
```

After every stage, a checkpoint row is written to `ingest_checkpoint` so
crashes resume without re-running completed stages.
