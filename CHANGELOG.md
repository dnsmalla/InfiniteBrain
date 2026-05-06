# Changelog

## [0.2.0] — 2026-05-06

- VaultInitializer seeds `inbox/`, `notes/`, and copies bundled skills + rules
  into `<vault>/.infinitebrain/` on first ingest. User-edited skills are
  preserved across re-runs.
- Edge inference: after every `add` the orchestrator calls `infer-edges`
  with the new note + nearest candidates, and persists returned edges into
  the note's frontmatter.
- New `answer-question` skill and `QueryService` provide single-pass
  retrieval-augmented answering: embed the question, take top-K nearest
  notes, hand them to the skill, return answer + cited ids.
- QueryView wires the service end-to-end with a text field, Cmd-Return
  shortcut, and citation list.

## [0.1.0] — 2026-05-06

- Initial scaffold: SwiftUI app shell, SharedLLMKit local package, skill +
  rule files for the full ingest pipeline, sidecar SQLite schema docs.
