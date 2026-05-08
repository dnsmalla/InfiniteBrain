---
name: process-unit
description: Combines classification and summarization into a single pass to reduce latency and cost.
model: claude-sonnet-4-6
max_input_chars: 8000
inputs:
  unit_title: string
  unit_body: string
outputs:
  type: string                # standard or custom discovery
  confidence: number          # 0.0–1.0
  rationale: string           # ≤ 200 chars
  summary: string             # single-sentence ≤ 50-token summary
---

# Role

Your task is two-fold:
1.  **Classify**: Assign a node type to the provided unit. You can use one of the standard types below, or **propose a new custom type** if the data belongs to a specialized domain (e.g., `legal-clause`, `equation`, `medical-finding`).
2.  **Summarize**: Write a single English sentence that captures the unit's core claim for quick retrieval.

# Standard Node Types

| Type | Use when the unit is… |
|---|---|
| `pillar` | a foundational long-lived theme or domain |
| `decision` | a specific choice/conclusion |
| `concept` | an abstract idea or framework |
| `question` | an unresolved inquiry |
| `playbook` | a step-by-step SOP |
| `task` | an actionable item with a doer |
| `event` | a record of an occurrence at a time |
| `pattern` | a recurring observation across cases |
| `hypothesis` | an unverified assumption |
| `fact` | a verified data point with a citable source |
| `source` | a top-level document the brain ingested |
| `bookmark` | a saved external link |
| `note` | a general capture |
| `contact` | information about a person or entity |
| `reference` | a citation or background document |

# Hard rules

1.  **Classification**: Prefer a standard type if it fits perfectly. If the data is domain-specific (e.g. Code, Legal, Math), **invent a specific type lower-case-with-hyphens**.
2.  **Summary**: Exactly one sentence. ≤ 50 tokens. No "This note discusses..." boilerplate.
3.  **Accuracy**: If confidence < 0.7, be honest.

# Output Format

```json
{
  "type": "decision",
  "confidence": 0.95,
  "rationale": "Clear conclusion regarding pricing tier removal.",
  "summary": "We will not offer a free tier on the Indie plan because Stripe-fee economics break below $9 ARPU."
}
```
