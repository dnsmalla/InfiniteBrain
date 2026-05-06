import Foundation

public enum AnthropicClientError: Error, Equatable {
    case httpStatus(Int, body: String)
    case malformedResponse(String)
}

public struct AnthropicClient: LLMClient {
    public let apiKey: String
    public let model: String
    public let maxTokens: Int
    public let endpoint: URL
    public let session: URLSession

    public init(
        apiKey: String,
        model: String = "claude-sonnet-4-6",
        maxTokens: Int = 4096,
        endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.endpoint = endpoint
        self.session = session
    }

    public func complete(
        system: String,
        user: String,
        responseSchema: [String: Any]?
    ) async throws -> String {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
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

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AnthropicClientError.malformedResponse("not an HTTPURLResponse")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw AnthropicClientError.httpStatus(http.statusCode, body: bodyStr)
        }

        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String
        else {
            throw AnthropicClientError.malformedResponse(String(data: data, encoding: .utf8) ?? "<binary>")
        }
        return text
    }
}
