import XCTest
@testable import SharedLLMKit

final class AnthropicClientTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testSendsCorrectRequestAndParsesContent() async throws {
        StubURLProtocol.responder = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")

            let body = try XCTUnwrap(request.bodyData)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "claude-sonnet-4-6")
            XCTAssertEqual(json["system"] as? String, "you are helpful")
            let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.first?["role"] as? String, "user")
            XCTAssertEqual(messages.first?["content"] as? String, "hello")

            let response: [String: Any] = [
                "content": [["type": "text", "text": "world"]]
            ]
            return (200, try JSONSerialization.data(withJSONObject: response))
        }

        let client = AnthropicClient(
            apiKey: "test-key",
            model: "claude-sonnet-4-6",
            session: StubURLProtocol.session()
        )
        let result = try await client.complete(system: "you are helpful", user: "hello", responseSchema: nil)
        XCTAssertEqual(result, "world")
    }

    func testThrowsOnNon200() async throws {
        StubURLProtocol.responder = { _ in
            (429, "{\"error\": \"rate limited\"}".data(using: .utf8)!)
        }
        let client = AnthropicClient(
            apiKey: "k",
            session: StubURLProtocol.session()
        )
        do {
            _ = try await client.complete(system: "s", user: "u", responseSchema: nil)
            XCTFail("expected throw")
        } catch AnthropicClientError.httpStatus(let code, _) {
            XCTAssertEqual(code, 429)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}

// MARK: - URLProtocol stub

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) throws -> (Int, Data))?

    static func reset() { responder = nil }

    static func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "StubURLProtocol", code: 0))
            return
        }
        do {
            let (status, data) = try responder(request)
            let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLRequest {
    /// `httpBody` is nil when the body was attached via a stream (the Foundation
    /// URL loading system does this for `URLSession.upload(for:from:)`-style
    /// constructions). Read either source.
    var bodyData: Data? {
        if let b = httpBody { return b }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var out = Data()
        let chunk = 4096
        var buf = [UInt8](repeating: 0, count: chunk)
        while stream.hasBytesAvailable {
            let n = stream.read(&buf, maxLength: chunk)
            if n <= 0 { break }
            out.append(buf, count: n)
        }
        return out
    }
}
