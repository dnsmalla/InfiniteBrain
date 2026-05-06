import Foundation

public enum ReconcileDecision: Sendable {
    case skip(existingId: String, reason: String)
    case improve(existingId: String, rationale: String)
    case add
}

/// Compares a candidate atomic unit against the embedding index and decides
/// whether to skip (duplicate), improve (rewrite existing in place), or add.
public actor Reconciler {
    public init() {}

    public func decide(candidate: String /* placeholder */) async throws -> ReconcileDecision {
        fatalError("not yet implemented")
    }
}
