import Foundation

public protocol LLMGate: Sendable {
    func withSlot<T>(@_inheritActorContext _ work: @Sendable () async throws -> T) async rethrows -> T
}

/// A pass-through gate that does no throttling.
public struct NoOpGate: LLMGate {
    public init() {}
    public func withSlot<T>(@_inheritActorContext _ work: @Sendable () async throws -> T) async rethrows -> T {
        try await work()
    }
}
