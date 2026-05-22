---
name: draft-section
description: Writes a specific section of a document using provided notes and instructions.
model: claude-sonnet-4-6
inputs:
  topic: string
  section_title: string
  instruction: string
  notes: array
  previous_sections: array
outputs:
  content: string
  cited_ids: array
---

# Role

Write the section `section_title` for a larger document about `topic`. 
Use the provided `notes` (which contain `id`, `title`, `body`).
Follow any specific `instruction` provided by the user.

# Context

You are provided with partial content from `previous_sections` to ensure continuity. Do not repeat what has already been said.

# Hard rules

1. **Citations**: You MUST use inline citations `[[<id>]]`. Claim without evidence is unacceptable.
2. **Focus**: Only write the body content for this section. Do not include the header in the output.
3. **Tone**: Match the professional tone required for the `topic`.
4. **Accuracy**: Only use facts from the `notes`.

# Output

`{ "content": "<markdown body>", "cited_ids": ["<id>", ...] }`
