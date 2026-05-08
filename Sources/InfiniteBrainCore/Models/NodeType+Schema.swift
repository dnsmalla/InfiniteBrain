import Foundation

public extension NodeType {
    /// Plain-language description that explains when this type is the
    /// right classification — surfaced in the app's Schema pane.
    var summary: String {
        switch self {
        case .pillar:    return "Foundational, long-lived theme or domain that organises everything beneath it."
        case .decision:  return "A specific choice or conclusion that was made, often with consequences and a rationale."
        case .concept:   return "An abstract idea, framework, or model that explains how something works."
        case .question:  return "An unresolved inquiry, an open problem, or a point still to be settled."
        case .playbook:  return "A repeatable step-by-step procedure or standard operating procedure."
        case .task:      return "An actionable item with a doer and a definition of done."
        case .event:     return "A record of something that happened at a point in time."
        case .pattern:   return "A recurring observation or theme identified across multiple cases."
        case .hypothesis:return "An unverified assumption or theory that needs evidence to confirm or reject."
        case .fact:      return "A verified data point or measurement, usually with a citable source."
        case .source:    return "An original document the brain ingested — a PDF, web page, or note dump."
        case .bookmark:  return "A pointer to an external resource saved for later reference."
        case .note:      return "A general capture that doesn't yet fit a more specific type."
        case .contact:   return "Information about a person or organisation."
        case .reference: return "A citation or supporting document used as background."
        case .custom:    return "Anything that genuinely doesn't fit one of the other 15. Flagged for review."
        default:         return "A custom knowledge entity discovered by the AI: \(rawValue)"
        }
    }

    /// One concrete example so the user knows when to expect this type.
    var example: String {
        switch self {
        case .pillar:    return "Q3 launch · Coding theory · Personal finance"
        case .decision:  return "“No free tier on the Indie plan”"
        case .concept:   return "Shannon-limit channel capacity"
        case .question:  return "Should we ship a team tier?"
        case .playbook:  return "How to debug a flaky CI job (5 steps)"
        case .task:      return "Migrate user_id column to UUID by Friday"
        case .event:     return "2026-05-07 — kickoff meeting with design"
        case .pattern:   return "Customers churn within 14 days of API rate-limit error"
        case .hypothesis:return "Creators will pay $19/mo for export"
        case .fact:      return "Stripe charges 2.9% + $0.30 per transaction"
        case .source:    return "Coding-Theory-Neubauer.pdf"
        case .bookmark:  return "https://obsidian.md/help/folders"
        case .note:      return "Misc thought captured during a meeting"
        case .contact:   return "Jane Smith, head of growth at AcmeCo"
        case .reference: return "ITU-T G.1010 standard"
        case .custom:    return "Used when the classifier's confidence is below 0.7"
        default:         return "Specific domain entity categorized as '\(rawValue)'"
        }
    }
}

public extension EdgeType {
    var summary: String {
        switch self {
        case .supports:    return "The new note provides evidence for the target."
        case .contradicts: return "The new note conflicts with the target's claim."
        case .dependsOn:   return "The new note presupposes the target. Read the target first."
        case .derivedFrom: return "The new note was extracted from the target — usually a Source."
        case .relatedTo:   return "Generic relation. Use only when nothing more specific fits."
        case .partOf:      return "The new note is a component of the target — typically a Pillar."
        case .precededBy:  return "Temporal: the target happened first."
        case .followedBy:  return "Temporal: the target happens after."
        case .authored:    return "Links a Contact to content they produced."
        case .tagging:     return "Attaches a topical tag — target is a Concept or Pillar."
        }
    }
}
