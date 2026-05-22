---
name: plan-draft-outline
description: Creates a formal document structure (headers) based on a topic and template.
model: claude-sonnet-4-6
inputs:
  topic: string
  template_name: string
outputs:
  sections: array
---

# Role

Define a professional document outline for the given `topic` following the structural conventions of the `template_name`.

# Templates

- **Scientific Paper**: Abstract, Introduction, Lit Review, Methods, Results, Discussion, Conclusion.
- **Executive Summary**: Overview, Problem, Key Findings, Strategic Impact, Recommendations.
- **Blog Post**: Hook, Background, Main Argument, Case Study, Summary.
- **Project Proposal**: Objectives, Problem Statement, Methodology, Resource Plan, Risk Assessment.

# Output

Return a JSON list of section titles.
`{ "sections": ["Abstract", "Introduction", ...] }`
