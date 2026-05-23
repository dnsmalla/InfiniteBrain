import Foundation
import SharedLLMKit

/// Manages global concurrency for LLM calls across the entire app.
/// This prevents hitting API rate limits or overwhelming local resources
/// when multiple background tasks (ingest, background sync, research) run at once.
public actor GlobalRateGate: LLMGate {
    public static let shared = GlobalRateGate()
    
    private var maxConcurrent: Int = 2
    private var activeCount: Int = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    private init() {}

    /// Calibrates the gate based on user settings or API tier.
    public func setMaxConcurrent(_ count: Int) {
        let oldMax = maxConcurrent
        maxConcurrent = max(1, count)
        
        // If we increased the limit, wake up pending tasks
        if maxConcurrent > oldMax {
            wakeUp()
        }
    }

    /// Acquires a slot to perform an LLM call. Suspends if the limit is reached.
    public func acquire() async {
        if activeCount < maxConcurrent {
            activeCount += 1
            return
        }
        
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    /// Releases a slot back to the gate.
    public func release() {
        activeCount -= 1
        wakeUp()
    }

    /// Executes the given work within the rate gate.
    public func withSlot<T>(@_inheritActorContext _ work: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await work()
    }

    private func wakeUp() {
        while activeCount < maxConcurrent && !continuations.isEmpty {
            activeCount += 1
            let next = continuations.removeFirst()
            next.resume()
        }
    }
}
