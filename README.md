# InfiniteBrain

**Drop a PDF in. Get a smart, searchable knowledge base out.**

InfiniteBrain is a macOS app that reads your documents and turns them into a
"second brain" you can actually ask questions to. It's based on the Infinite
Brain idea: instead of saving long, messy notes in folders, the app breaks
each document into small, focused pieces and labels them so an AI can find
exactly what you need without re-reading everything.

The output is plain markdown in a folder — fully compatible with Obsidian,
your text editor, or `git`. Nothing is locked into a database.

---

## What it does, in plain English

```
   you drop a file              app does the work               result in your vault
┌───────────────────────┐     ┌─────────────────────┐      ┌─────────────────────────┐
│  report.pdf           │ ──▶ │  read PDF           │ ──▶  │  notes/decision/01J...  │
│  meeting-notes.txt    │     │  split into pieces  │      │  notes/fact/01J...      │
│  research.md          │     │  label each piece   │      │  notes/question/01J...  │
└───────────────────────┘     │  summarise          │      │  notes/playbook/01J...  │
                              │  link to old notes  │      │  ...                    │
                              │  skip duplicates    │      └─────────────────────────┘
                              └─────────────────────┘                 │
                                                                      ▼
                                                          ┌─────────────────────────┐
                                                          │  ask: "what did we      │
                                                          │  decide about pricing?" │
                                                          │  → answer with citations│
                                                          └─────────────────────────┘
```

Each piece (an "atomic note") gets one of **16 labels** — *Decision*, *Fact*,
*Question*, *Playbook*, *Hypothesis*, etc. — so when you (or the AI) look
something up, it knows exactly what kind of thing it's looking at. Notes are
also connected with **10 relationship types** like *supports*, *contradicts*,
*depends on*, *part of*. That's the "brain" part: it's a graph, not a pile.

---

## Why it works

Most note apps store one long document per topic. To answer a question, the
AI has to read the whole thing — slow and expensive.

InfiniteBrain stores **many small, labelled notes**, each with a one-sentence
summary at the top. To answer a question, the app:

1. Embeds your question into a vector
2. Finds the handful of notes most similar to it
3. Reads only those notes
4. Cites the ones it actually used

Result: faster answers, cheaper API bills, and you can audit every claim
back to a source note.

---

## Quick start (GUI)

```bash
git clone https://github.com/dnsmalla/InfiniteBrain.git
cd InfiniteBrain
swift run InfiniteBrain
```

Then in the app:

1. **Settings tab** → choose an empty folder for your vault, paste an
   Anthropic API key (stored in macOS Keychain).
2. **Ingest tab** → drag PDFs, `.md`, or `.txt` files in, click **Run**.
3. **Vault tab** → browse the notes the app made, grouped by type.
4. **Query tab** → ask a question, get an answer with citations.

The first ingest also copies editable copies of all the AI prompts (called
"skills") into `<your-vault>/.infinitebrain/skills/`. You can tweak them
without rebuilding the app — see [Tuning the AI](#tuning-the-ai) below.

## Quick start (CLI)

A separate executable, `infb`, gives you the same pipeline from the
terminal — useful for batch ingesting a folder of PDFs or scripting the
brain into other tools.

```bash
swift build
export ANTHROPIC_API_KEY=sk-ant-…
export INFINITEBRAIN_VAULT=~/MyBrain

# create the vault folder + copy editable skills into it
swift run infb seed ~/MyBrain

# ingest one or many files
swift run infb ingest book.pdf chapter1.md notes.txt

# ask the brain a question
swift run infb query "what did we decide about pricing?"
```

Both `--vault` and `--api-key` flags work too if you don't want env vars.
Run `swift run infb help` for the full reference.

---

## What's in the box

| Folder | What it holds |
|---|---|
| `Sources/InfiniteBrain/` | The macOS app — Swift + SwiftUI |
| `Sources/InfiniteBrain/Resources/skills/` | One folder per pipeline stage. Each has a `SKILL.md` describing exactly what the AI should do |
| `Sources/InfiniteBrain/Resources/rules/` | Cross-cutting rules: output format, citation policy, token budget, quality bar |
| `SharedLLMKit/` | Standalone Swift package — talks to Claude, runs skills, validates output, computes embeddings |
| `Tests/` | unit + integration tests covering the parser, validator, vault round-trip, full ingest pipeline, query service, and graph layout (graph engine tests live in GraphKit) |
| `docs/` | Architecture overview, pipeline diagram, data model, ADRs |

---

## How a single file is processed

```
   ┌─────────────────────────────────┐
   │  extract-pdf                    │   PDFKit → cleaned text
   └────────────┬────────────────────┘
                ▼
   ┌─────────────────────────────────┐
   │  atomize-text                   │   text → many 50–300 line units
   └────────────┬────────────────────┘
                │   for each unit ↓
   ┌─────────────────────────────────┐
   │  classify-node                  │   pick 1 of 16 types
   └────────────┬────────────────────┘
                ▼
   ┌─────────────────────────────────┐
   │  summarize-note                 │   one-sentence summary
   └────────────┬────────────────────┘
                ▼
   ┌─────────────────────────────────┐
   │  reconcile-note                 │   skip / improve / add ?
   └────────────┬────────────────────┘
       skip ◀───┤
                │ improve ──▶ improve-note ──▶ rewrite existing note
                │
                │ add ──▶ infer-edges ──▶ write new note + edges
                ▼
       (next unit)
```

Every box on the diagram is one editable `SKILL.md` file. You can change
how the AI behaves at any stage by editing that file.

---

## The 16 note types

Each piece of information gets exactly one type:

`pillar` (foundational themes) · `decision` (choices made) · `concept`
(abstract ideas) · `question` (open inquiries) · `playbook` (SOPs) ·
`task` (actions) · `event` (occurrences) · `pattern` (recurring
observations) · `hypothesis` (theories to test) · `fact` (verified data) ·
`source` (origin documents) · `bookmark` (saved links) · `note` (general
captures) · `contact` (people) · `reference` (citations) · `custom`
(everything else)

## The 10 relationships

`supports` · `contradicts` · `depends_on` · `derived_from` · `related_to` ·
`part_of` · `preceded_by` · `followed_by` · `authored` · `tagging`

---

## What a note actually looks like

```markdown
---
id: 01JABCDEFGHJKMNPQRSTVWXYZ0
type: decision
title: No free tier for Indie plan
summary: We will not offer a free tier on the Indie plan because Stripe-fee economics break below $9 ARPU.
created_at: 2026-05-06T10:23:00Z
updated_at: 2026-05-06T10:23:00Z
version: 1
content_hash: sha256-…
sources: ["01JSRC..."]
edges:
  - type: supports
    target: "01JFACT..."
    evidence: "Stripe fee table shows $0.30 floor"
  - type: contradicts
    target: "01JHYP..."
    evidence: "Earlier hypothesis assumed flat 2.9% fees"
superseded_by: null
---

# No free tier for Indie plan

Body of the note here. 50–300 lines of focused content.
```

Open it in Obsidian, VS Code, or `cat`. It's just a file.

---

## Tuning the AI

Every AI call goes through a `SKILL.md` file. They live two places:

- **Bundled in the app** — `Sources/InfiniteBrain/Resources/skills/`
- **Copied into your vault on first run** — `<vault>/.infinitebrain/skills/`

The vault copy wins. So if you want the classifier to be stricter, or
summaries shorter, or edges to require more evidence — just edit the
markdown file. Next ingest picks it up. No rebuild.

The same is true for the cross-cutting rules in `<vault>/.infinitebrain/rules/`:

- `output-format.mdc` — note frontmatter schema
- `citation-policy.mdc` — facts/decisions must cite a source
- `token-budget.mdc` — input/output caps per stage
- `quality-bar.mdc` — when to retry, when to quarantine

---

## Build a `.app` and `.dmg`

```bash
./bin/build_app.sh           # produces .build/dist/InfiniteBrain.app + infb
./bin/build_app.sh --dmg     # also produces .build/dist/InfiniteBrain-x.y.z.dmg
./bin/build_app.sh --sign "Developer ID Application: Your Name (TEAMID)"
```

By default the app is signed ad-hoc (`-`), which is fine for local use.
Pass `--sign IDENTITY` to use a real signing identity from your Keychain.
Notarisation isn't wired up yet — for distribution you'd staple after
running `xcrun notarytool submit`.

---

## Status

- ✅ Full ingest pipeline (extract → atomize → classify → summarize →
  reconcile → infer edges → write)
- ✅ Embedding-based duplicate detection (Apple NaturalLanguage, offline)
- ✅ Single-pass question answering with citations
- ✅ macOS Keychain for the API key, vault path persisted in UserDefaults
- ⏳ Crash-resume checkpointing
- ⏳ Graph view
- ✅ Code Graph — visualize a repository's structure (files, classes, functions, `imports`/`calls`/`inherits`/`implements`) via the bundled tree-sitter scanner in [GraphKit](https://github.com/dnsmalla/graph-kit). See [docs/user-guide/code-graph.md](docs/user-guide/code-graph.md).
- ⏳ Code-signed `.dmg`

The graph engine lives in the shared [GraphKit](https://github.com/dnsmalla/graph-kit) package (pinned via SwiftPM). Code Graph's rich scanner needs tree-sitter on the system `python3`: `pip3 install tree-sitter==0.21.3 tree-sitter-languages==1.10.2` (without it, scanning falls back to Python-only stdlib `ast`).

Both packages build clean. CI runs on every push.

---

## License

[MIT](LICENSE)
