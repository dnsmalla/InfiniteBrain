---
name: improve-note
description: Rewrites an existing note in place, merging new information from a candidate while preserving identity.
model: claude-sonnet-4-6
inputs:
  existing: object            # full existing note
  candidate: object           # candidate unit that triggered the improvement
outputs:
  new_body: string
  new_summary: string
  changes: array              # short list of what changed, for the changelog
---

# Role

Produce an improved version of `existing.body` that integrates new
information from `candidate`. The note keeps its `id`, `type`, and stable
identity; only `body`, `summary`, and `version` change.

# Hard rules

1. Preserve all factual claims from `existing` unless `candidate` explicitly
   contradicts and corrects them. When you correct, append a short
   parenthetical citation: `(corrected from <source_id>)`.
2. Stay within 50–300 lines.
3. Do not change the note's classification or scope — if the candidate is
   really about a different topic, the reconciler should not have routed
   here. Refuse with `changes: ["scope-mismatch"]` and leave body unchanged.
4. Output `changes` as a flat list of ≤6 short strings ("added Stripe fee
   table", "corrected MRR figure", …). The orchestrator writes these to the
   note's changelog frontmatter.

# Output

`{ "new_body": "...", "new_summary": "...", "changes": ["..."] }`
