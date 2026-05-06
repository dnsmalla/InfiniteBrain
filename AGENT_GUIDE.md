# Agent guide

This project is built around an **agents-and-skills** pattern. Every LLM
call is a named skill defined as a markdown file. Quality is tuned by
editing those files, not by changing Swift code.

## Where things live

| Concern | Path |
|---|---|
| Pipeline stages (skills) | `Sources/InfiniteBrain/Resources/skills/<name>/SKILL.md` |
| Cross-cutting rules | `Sources/InfiniteBrain/Resources/rules/*.mdc` |
| Skill execution | `SharedLLMKit/Sources/SharedLLMKit/SkillRunner/` |
| Stage sequencing | `Sources/InfiniteBrain/Services/Orchestrator.swift` |
| User-editable copies | `<vault>/.infinitebrain/skills/` (after first launch) |

## Adding a new skill

1. Create `Sources/InfiniteBrain/Resources/skills/<new-name>/SKILL.md`.
2. Declare `inputs:` and `outputs:` in the frontmatter — these become the
   JSON schemas SkillRunner validates against.
3. Wire it into `Orchestrator` at the right point in the pipeline.
4. Add a test in `Tests/InfiniteBrainTests/`.

## Editing a skill in production

Open `<vault>/.infinitebrain/skills/<name>/SKILL.md` and edit. The next
ingest run picks it up. The bundled copy in the app is a fallback used
only when the vault copy is missing.
