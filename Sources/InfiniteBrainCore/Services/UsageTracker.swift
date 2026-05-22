import Foundation

public struct UsageMetric: Codable, Sendable {
    public let timestamp: Date
    public let skillName: String
    public let provider: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let latencySeconds: Double
    
    public var estimatedCost: Double {
        // App-specific cost estimation (rough Sonnet 3.5 rates)
        let inputRate = 3.0 / 1_000_000.0  // $3 per M tokens
        let outputRate = 15.0 / 1_000_000.0 // $15 per M tokens
        return (Double(inputTokens) * inputRate) + (Double(outputTokens) * outputRate)
    }
}

/// Tracks and persists local LLM usage metrics.
public actor UsageTracker {
    public static let shared = UsageTracker()
    
    private var metrics: [UsageMetric] = []
    private var persistURL: URL?
    
    private init() {}
    
    public func setPersistURL(_ url: URL) {
        self.persistURL = url
        try? load()
    }
    
    public func record(metric: UsageMetric) {
        metrics.append(metric)
        save()
    }
    
    public func getSummary() -> UsageSummary {
        let cost = metrics.reduce(0.0) { $0 + $1.estimatedCost }
        let tokens = metrics.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
        let inputs = metrics.reduce(0) { $0 + $1.inputTokens }
        let outputs = metrics.reduce(0) { $0 + $1.outputTokens }
        return UsageSummary(totalCost: cost, totalTokens: tokens, totalCalls: metrics.count, inputTokens: inputs, outputTokens: outputs)
    }
    
    private func save() {
        guard let url = persistURL else { return }
        do {
            let data = try JSONEncoder().encode(metrics)
            try data.write(to: url, options: .atomic)
        } catch {
            LogService.shared.error("Failed to save usage metrics", category: .general, error: error)
        }
    }
    
    private func load() throws {
        guard let url = persistURL, FileManager.default.fileExists(atPath: url.path) else { return }
        let data = try Data(contentsOf: url)
        self.metrics = try JSONDecoder().decode([UsageMetric].self, from: data)
    }
}

public struct UsageSummary: Sendable {
    public let totalCost: Double
    public let totalTokens: Int
    public let totalCalls: Int
    public let inputTokens: Int
    public let outputTokens: Int
}
