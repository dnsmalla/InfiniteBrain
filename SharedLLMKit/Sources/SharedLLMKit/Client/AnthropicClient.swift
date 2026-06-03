import Foundation

public enum AnthropicClientError: Error, Equatable {
    case httpStatus(Int, body: String)
    case malformedResponse(String)
}

public struct AnthropicClient: LLMClient {
    public struct RetryPolicy: Sendable {
        public var maxAttempts: Int          // 1 = no retry
        public var baseDelaySeconds: Double  // exponential backoff base; 0 disables sleep (test-friendly)
        public init(maxAttempts: Int = 3, baseDelaySeconds: Double = 0.4) {
            self.maxAttempts = max(1, maxAttempts)
            self.baseDelaySeconds = baseDelaySeconds
        }
    }

    public let retryPolicy: RetryPolicy
    public let gate: LLMGate
    
    public let apiKey: String
    public let model: String
    public let maxTokens: Int
    public let endpoint: URL
    public let session: URLSession

    public init(
        apiKey: String,
        model: String = "claude-sonnet-4-6",
        maxTokens: Int = 8192,
        endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        session: URLSession = .shared,
        retryPolicy: RetryPolicy = .init(),
        gate: LLMGate = NoOpGate()
    ) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.endpoint = endpoint
        self.session = session
        self.retryPolicy = retryPolicy
        self.gate = gate
    }

    public func complete(
        system: String,
        user: String,
        responseSchema: [String: Any]?,
        onUsage: (@Sendable (LLMUsage) -> Void)?
    ) async throws -> String {
        try await gate.withSlot {
            try await performComplete(system: system, user: user, responseSchema: responseSchema, onUsage: onUsage)
        }
    }

    private func performComplete(
        system: String,
        user: String,
        responseSchema: [String: Any]?,
        onUsage: (@Sendable (LLMUsage) -> Void)?
    ) async throws -> String {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 120   // bound a hung connection instead of waiting forever
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        var lastStatus = 0
        var lastBody = ""
        for attempt in 0..<retryPolicy.maxAttempts {
            try Task.checkCancellation()   // stop retrying once the caller cancels
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw AnthropicClientError.malformedResponse("not an HTTPURLResponse")
            }
            lastStatus = http.statusCode
            lastBody = String(data: data, encoding: .utf8) ?? ""

            if (200..<300).contains(http.statusCode) {
                let text = try Self.extractText(from: data)
                if let usage = try? Self.extractUsage(from: data) {
                    onUsage?(usage)
                }
                return text
            }

            // Retry only on 429 and 5xx. Other 4xx are user/auth errors and
            // won't change with retries.
            let retryable = http.statusCode == 429 || (500..<600).contains(http.statusCode)
            if !retryable || attempt == retryPolicy.maxAttempts - 1 { break }

            let serverDelay = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            let backoff = retryPolicy.baseDelaySeconds * pow(2.0, Double(attempt))
            let wait = max(serverDelay ?? 0, backoff)
            if wait > 0 {
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }

        throw AnthropicClientError.httpStatus(lastStatus, body: lastBody)
    }

    private static func extractUsage(from data: Data) throws -> LLMUsage {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = obj["usage"] as? [String: Any],
              let input = usage["input_tokens"] as? Int,
              let output = usage["output_tokens"] as? Int
        else {
            throw AnthropicClientError.malformedResponse("no usage info")
        }
        return LLMUsage(inputTokens: input, outputTokens: output)
    }

    private static func extractText(from data: Data) throws -> String {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]]
        else {
            throw AnthropicClientError.malformedResponse(String(data: data, encoding: .utf8) ?? "<binary>")
        }
        // Concatenate all text blocks. Extended-thinking / tool-use responses can
        // lead with a non-text block or split text across blocks; taking only the
        // first block would throw or truncate.
        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty else {
            throw AnthropicClientError.malformedResponse(String(data: data, encoding: .utf8) ?? "<binary>")
        }
        return text
    }
}
